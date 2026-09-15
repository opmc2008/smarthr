import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';

/// Preference keys shared between the UI and the engine.
///
/// Ownership is split so the two isolates never write the same key: the UI
/// owns [active], [batch] and [start]; the engine owns [distance], [points] and
/// [pending] once a session is running.
class TrackingKeys {
  static const active = 'tracking_active';
  static const batch = 'tracking_batch_id';
  static const start = 'tracking_started_ms';
  static const distance = 'tracking_distance_m';
  static const points = 'tracking_points';
  static const pending = 'tracking_pending';

  /// Most points kept on disk and in memory; the server holds the full history.
  static const maxStoredPoints = 2000;

  static String encode(List<LatLng> pts) =>
      pts.map((p) => '${p.latitude},${p.longitude}').join(';');

  static List<LatLng> decode(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    final out = <LatLng>[];
    for (final chunk in raw.split(';')) {
      final parts = chunk.split(',');
      if (parts.length != 2) continue;
      final lat = double.tryParse(parts[0]);
      final lon = double.tryParse(parts[1]);
      if (lat != null && lon != null) out.add(LatLng(lat, lon));
    }
    return out;
  }
}

/// Entry point of the Android background service.
///
/// Runs in its own Dart isolate inside a `location` foreground service, so the
/// session survives the app being backgrounded, swiped out of recents, or the
/// activity being destroyed to reclaim memory.
@pragma('vm:entry-point')
Future<void> trackingServiceMain(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  var lastNotified = DateTime.fromMillisecondsSinceEpoch(0);
  final engine = TrackingEngine(onUpdate: (update) {
    service.invoke('update', update);
    final now = DateTime.now();
    if (service is AndroidServiceInstance &&
        now.difference(lastNotified).inSeconds >= 30) {
      lastNotified = now;
      final km = ((update['distance'] as num? ?? 0) / 1000).toStringAsFixed(2);
      service.setForegroundNotificationInfo(
        title: 'SmartHR tracking active',
        content: 'Recording your route for this work session · $km km',
      );
    }
  });

  // The UI flips its own flag first, then asks us to wind down.
  service.on('stop').listen((_) async {
    await engine.stop();
    // A new session may have started while the final upload was in flight.
    if (!engine.isRunning) await service.stopSelf();
  });
  service.on('resume').listen((_) => engine.resume());

  // Nothing to resume (e.g. boot restart after the user already stopped).
  if (!await engine.resume()) await service.stopSelf();
}

/// Records the route: GPS stream, fix filtering, persistence and upload.
///
/// Host-agnostic. On Android it lives in the background service isolate; on
/// iOS it runs in the app isolate, which the `location` background mode keeps
/// alive while updates flow.
class TrackingEngine {
  TrackingEngine({required this.onUpdate});

  /// Receives a JSON-safe snapshot after every accepted fix or upload.
  final void Function(Map<String, dynamic> update) onUpdate;

  StreamSubscription<Position>? _positionStream;
  Timer? _retryTimer;
  SharedPreferences? _prefs;

  bool _running = false;
  String _batchId = '';
  final List<LatLng> _routePoints = [];
  double _distanceMeters = 0;
  DateTime _lastSync = DateTime.fromMillisecondsSinceEpoch(0);

  /// Points captured but not yet accepted by the server (offline buffer).
  final List<LatLng> _pending = [];

  /// True while a flush is in flight, so concurrent callers don't double-send.
  bool _flushing = false;

  bool get isRunning => _running;

  // ── Fix quality ────────────────────────────────────────────────────────────
  // Raw GPS is noisy: cell/Wi-Fi fixes land hundreds of metres out, and the
  // receiver jitters several metres while standing still. Everything below
  // exists to keep those out of the recorded route.

  /// Reject fixes less precise than this (metres). Wi-Fi/cell fixes are the
  /// main source of "the map shows me in the wrong place".
  static const double _maxAccuracyMetres = 30;

  /// Reject fixes implying a speed no vehicle would hit — a teleport is a bad
  /// fix, not travel, and it also corrupts the distance total.
  static const double _maxPlausibleSpeed = 55; // m/s ≈ 198 km/h

  DateTime? _lastFixAt;
  double _lastAccuracy = 0;

  // Kalman state (position in degrees, variance in metres²).
  double? _kLat, _kLng;
  double _kVariance = 0;

  void _resetFilter() {
    _kLat = null;
    _kLng = null;
    _kVariance = 0;
    _lastFixAt = null;
    _lastAccuracy = 0;
  }

  /// Drop fixes that are too imprecise or physically impossible.
  bool _isUsable(Position p) {
    if (p.accuracy <= 0 || p.accuracy > _maxAccuracyMetres) return false;
    final last = _routePoints.isNotEmpty ? _routePoints.last : null;
    if (last != null && _lastFixAt != null) {
      final dt = p.timestamp.difference(_lastFixAt!).inMilliseconds / 1000.0;
      if (dt > 0) {
        final d = Geolocator.distanceBetween(
            last.latitude, last.longitude, p.latitude, p.longitude);
        if (d / dt > _maxPlausibleSpeed) return false;
      }
    }
    return true;
  }

  /// Standard GPS Kalman filter: trusts a fix in proportion to its accuracy,
  /// so a tight fix moves the estimate a lot and a loose one barely at all.
  LatLng _smooth(Position p) {
    const processNoise = 3.0; // m/s of assumed movement between fixes
    final accuracy = math.max(p.accuracy, 1.0);
    if (_kLat == null) {
      _kLat = p.latitude;
      _kLng = p.longitude;
      _kVariance = accuracy * accuracy;
    } else {
      final dt = _lastFixAt == null
          ? 0.0
          : p.timestamp.difference(_lastFixAt!).inMilliseconds / 1000.0;
      if (dt > 0) _kVariance += dt * processNoise * processNoise;
      final gain = _kVariance / (_kVariance + accuracy * accuracy);
      _kLat = _kLat! + gain * (p.latitude - _kLat!);
      _kLng = _kLng! + gain * (p.longitude - _kLng!);
      _kVariance = (1 - gain) * _kVariance;
    }
    return LatLng(_kLat!, _kLng!);
  }

  // ---------------------------------------------------------------- lifecycle

  /// Attaches to the session the UI flagged active. Returns false if none.
  /// Safe to call repeatedly.
  Future<bool> resume() async {
    if (_running) return true;
    final p = _prefs ??= await SharedPreferences.getInstance();
    // The other isolate may have written since our cache was loaded.
    await p.reload();
    _pending
      ..clear()
      ..addAll(TrackingKeys.decode(p.getString(TrackingKeys.pending)));

    if (!(p.getBool(TrackingKeys.active) ?? false)) {
      await _flushPending();
      return false;
    }

    _running = true;
    _batchId = p.getString(TrackingKeys.batch) ??
        'b${DateTime.now().millisecondsSinceEpoch}';
    _distanceMeters = p.getDouble(TrackingKeys.distance) ?? 0;
    _routePoints
      ..clear()
      ..addAll(TrackingKeys.decode(p.getString(TrackingKeys.points)));
    _lastSync = DateTime.fromMillisecondsSinceEpoch(0);
    // Start from a clean estimate — stale filter state would drag the first
    // fixes toward wherever tracking last left off.
    _resetFilter();

    _subscribe();
    _emit();
    unawaited(_flushPending());
    return true;
  }

  /// Stops recording and makes a last attempt to upload buffered points.
  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    await _positionStream?.cancel();
    _positionStream = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    await _flushPending();
  }

  // ------------------------------------------------------------------ stream

  void _subscribe() {
    _positionStream?.cancel();
    // Opening the stream can throw synchronously (permission revoked between
    // our check and the call, service unavailable). Swallow it and retry: the
    // session ends only when the user says so.
    try {
      _positionStream = Geolocator.getPositionStream(
        locationSettings: _backgroundSettings(),
      ).listen(
        _onPosition,
        onError: (Object e) {
          debugPrint('TrackingEngine: stream error: $e');
          _scheduleRetry();
        },
        cancelOnError: true,
      );
    } catch (e) {
      debugPrint('TrackingEngine: could not open position stream: $e');
      _positionStream = null;
      _scheduleRetry();
    }
  }

  LocationSettings _backgroundSettings() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      // No foregroundNotificationConfig: the hosting background service is
      // already a `location` foreground service with its own notification.
      return AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5,
        intervalDuration: const Duration(seconds: 5),
      );
    }
    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5,
        activityType: ActivityType.otherNavigation,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
        allowBackgroundLocationUpdates: true,
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 5,
    );
  }

  void _scheduleRetry() {
    if (!_running) return;
    _retryTimer?.cancel();
    _retryTimer = Timer(const Duration(seconds: 15), () async {
      if (!_running) return;
      final serviceOn = await Geolocator.isLocationServiceEnabled();
      final perm = await Geolocator.checkPermission();
      if (serviceOn &&
          (perm == LocationPermission.always ||
              perm == LocationPermission.whileInUse)) {
        _subscribe();
      } else {
        _scheduleRetry();
      }
    });
  }

  Future<void> _onPosition(Position position) async {
    if (!_running) return;
    // Bad fixes are worse than no fix: they move the marker somewhere the user
    // never was and inflate the distance total. Drop them before anything else.
    if (!_isUsable(position)) {
      debugPrint('TrackingEngine: dropped fix '
          '(accuracy ${position.accuracy.toStringAsFixed(1)}m)');
      return;
    }

    final next = _smooth(position);
    _lastFixAt = position.timestamp;
    _lastAccuracy = position.accuracy;

    if (_routePoints.isNotEmpty) {
      final last = _routePoints.last;
      final step = Geolocator.distanceBetween(
          last.latitude, last.longitude, next.latitude, next.longitude);
      // Ignore sub-metre drift so standing still doesn't accumulate distance.
      if (step >= 1.0) _distanceMeters += step;
    }
    _routePoints.add(next);
    if (_routePoints.length > TrackingKeys.maxStoredPoints) {
      _routePoints.removeRange(
          0, _routePoints.length - TrackingKeys.maxStoredPoints);
    }

    final now = DateTime.now();
    if (now.difference(_lastSync).inSeconds > 10) {
      _lastSync = now;
      _queue(next);
      unawaited(_flushPending());
    }
    // Persist before emitting so a UI that reloads on mismatch sees this fix.
    await _persist();
    _emit(position: next);
  }

  void _emit({LatLng? position}) {
    onUpdate({
      if (position != null) 'lat': position.latitude,
      if (position != null) 'lng': position.longitude,
      if (position != null) 'accuracy': _lastAccuracy,
      'distance': _distanceMeters,
      'pending': _pending.length,
      'count': _routePoints.length,
    });
  }

  // ------------------------------------------------------------------ upload

  void _queue(LatLng p) {
    _pending.add(p);
    // Bound the buffer so a long offline stretch can't grow without limit.
    if (_pending.length > 500) _pending.removeRange(0, _pending.length - 500);
  }

  Future<void> _flushPending() async {
    // Guard against overlapping flushes: two runs would read the same
    // _pending.first, upload it twice, then drop a point that never went up.
    if (_flushing || _pending.isEmpty) return;
    _flushing = true;
    try {
      await _drainPending();
    } finally {
      _flushing = false;
    }
  }

  Future<void> _drainPending() async {
    while (_pending.isNotEmpty) {
      final p = _pending.first;
      try {
        await ApiService.locationCreate(
          _batchId,
          p.latitude.toStringAsFixed(6),
          p.longitude.toStringAsFixed(6),
        );
        _pending.removeAt(0);
      } catch (e) {
        debugPrint('TrackingEngine: sync failed, will retry: $e');
        break; // keep the point buffered for the next flush
      }
    }
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    await prefs.setString(TrackingKeys.pending, TrackingKeys.encode(_pending));
    _emit();
  }

  // ----------------------------------------------------------- persistence

  Future<void> _persist() async {
    final p = _prefs ??= await SharedPreferences.getInstance();
    await p.setDouble(TrackingKeys.distance, _distanceMeters);
    await p.setString(TrackingKeys.points, TrackingKeys.encode(_routePoints));
  }
}
