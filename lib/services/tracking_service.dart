import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';

/// Outcome of asking the OS for location access.
enum TrackingPermission {
  granted,          // fine location while-in-use (enough for a foreground service)
  grantedAlways,    // fine location "all the time"
  denied,           // user said no this time
  deniedForever,    // user said "don't ask again" -> must go to app settings
  serviceDisabled,  // GPS master switch is off
}

/// Owns the location session for the whole app.
///
/// Lives outside the widget tree so a session keeps running when the tracking
/// screen is popped, when the app is backgrounded, and across app restarts.
/// A session ends only when [stop] is called, i.e. when the user turns it off.
class TrackingService extends ChangeNotifier {
  TrackingService._();
  static final TrackingService instance = TrackingService._();

  static const _kActive = 'tracking_active';
  static const _kBatch = 'tracking_batch_id';
  static const _kStart = 'tracking_started_ms';
  static const _kDistance = 'tracking_distance_m';
  static const _kPoints = 'tracking_points';
  static const _kPending = 'tracking_pending';

  StreamSubscription<Position>? _positionStream;
  Timer? _ticker;
  Timer? _retryTimer;
  SharedPreferences? _prefs;

  bool _isTracking = false;
  LatLng? _current;
  final List<LatLng> _routePoints = [];
  double _distanceMeters = 0;
  DateTime? _startedAt;
  String _batchId = '';
  DateTime _lastSync = DateTime.fromMillisecondsSinceEpoch(0);

  /// Points captured but not yet accepted by the server (offline buffer).
  final List<LatLng> _pending = [];

  bool get isTracking => _isTracking;
  LatLng? get current => _current;
  List<LatLng> get routePoints => List.unmodifiable(_routePoints);
  double get distanceMeters => _distanceMeters;
  int get pendingCount => _pending.length;
  Duration get elapsed =>
      _startedAt == null ? Duration.zero : DateTime.now().difference(_startedAt!);

  // ---------------------------------------------------------------- lifecycle

  /// Call once from `main()`. Re-attaches to a session the user never stopped.
  Future<void> restore() async {
    _prefs = await SharedPreferences.getInstance();
    final p = _prefs!;
    _pending
      ..clear()
      ..addAll(_decodePoints(p.getString(_kPending) ?? ''));

    if (!(p.getBool(_kActive) ?? false)) return;

    _batchId = p.getString(_kBatch) ?? _newBatchId();
    final startMs = p.getInt(_kStart) ?? DateTime.now().millisecondsSinceEpoch;
    _startedAt = DateTime.fromMillisecondsSinceEpoch(startMs);
    _distanceMeters = p.getDouble(_kDistance) ?? 0;
    _routePoints
      ..clear()
      ..addAll(_decodePoints(p.getString(_kPoints) ?? ''));
    if (_routePoints.isNotEmpty) _current = _routePoints.last;

    // The user never turned it off, so resume — but only if the OS still lets
    // us. If permission was revoked we keep the session flagged active and the
    // screen will surface the problem instead of silently dropping it.
    final perm = await Geolocator.checkPermission();
    final serviceOn = await Geolocator.isLocationServiceEnabled();
    if (!serviceOn ||
        perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      _isTracking = true;
      notifyListeners();
      _scheduleRetry();
      return;
    }

    _isTracking = true;
    _startTicker();
    _subscribe();
    notifyListeners();
  }

  /// Ask for everything a background session needs.
  ///
  /// Requests while-in-use first, then escalates to "allow all the time" so the
  /// session survives the app being swept out of the foreground.
  Future<TrackingPermission> requestPermissions() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return TrackingPermission.serviceDisabled;
    }

    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied) return TrackingPermission.denied;
    if (perm == LocationPermission.deniedForever) {
      return TrackingPermission.deniedForever;
    }
    if (perm == LocationPermission.always) return TrackingPermission.grantedAlways;

    // whileInUse: a second request escalates to the "Allow all the time" prompt
    // on Android 11+/iOS. Declining is fine — the foreground service still
    // keeps us alive — so we don't treat it as a failure.
    final escalated = await Geolocator.requestPermission();
    return escalated == LocationPermission.always
        ? TrackingPermission.grantedAlways
        : TrackingPermission.granted;
  }

  /// One-off fix so the map has something to show before a session starts.
  Future<void> refreshCurrentPosition() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      _current = LatLng(pos.latitude, pos.longitude);
      notifyListeners();
    } catch (e) {
      debugPrint('TrackingService: current position failed: $e');
    }
  }

  Future<void> start() async {
    if (_isTracking) return;
    _prefs ??= await SharedPreferences.getInstance();

    _isTracking = true;
    _routePoints.clear();
    _distanceMeters = 0;
    _startedAt = DateTime.now();
    _batchId = _newBatchId();
    _lastSync = DateTime.fromMillisecondsSinceEpoch(0);

    if (_current != null) {
      _routePoints.add(_current!);
      _queue(_current!);
    }

    await _persist();
    _startTicker();
    _subscribe();
    notifyListeners();
    unawaited(_flushPending());
  }

  /// The only way a session ends.
  Future<void> stop() async {
    if (!_isTracking) return;
    _isTracking = false;
    await _positionStream?.cancel();
    _positionStream = null;
    _ticker?.cancel();
    _ticker = null;
    _retryTimer?.cancel();
    _retryTimer = null;

    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setBool(_kActive, false);
    notifyListeners();
    unawaited(_flushPending());
  }

  // ------------------------------------------------------------------ stream

  void _subscribe() {
    _positionStream?.cancel();
    _positionStream = Geolocator.getPositionStream(
      locationSettings: _backgroundSettings(),
    ).listen(
      _onPosition,
      onError: (Object e) {
        debugPrint('TrackingService: stream error: $e');
        // Never end the session on our own — retry until the user stops it.
        _scheduleRetry();
      },
      cancelOnError: true,
    );
  }

  LocationSettings _backgroundSettings() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
        intervalDuration: const Duration(seconds: 5),
        // Promotes the location service to a foreground service: Android keeps
        // delivering fixes with the app backgrounded or the screen off, and the
        // user always sees an ongoing notification while we track them.
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'SmartHR tracking active',
          notificationText: 'Recording your route for this work session.',
          notificationIcon: AndroidResource(name: 'ic_launcher', defType: 'mipmap'),
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    }
    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
        activityType: ActivityType.otherNavigation,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
        allowBackgroundLocationUpdates: true,
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
    );
  }

  void _scheduleRetry() {
    if (!_isTracking) return;
    _retryTimer?.cancel();
    _retryTimer = Timer(const Duration(seconds: 15), () async {
      if (!_isTracking) return;
      final serviceOn = await Geolocator.isLocationServiceEnabled();
      final perm = await Geolocator.checkPermission();
      if (serviceOn &&
          (perm == LocationPermission.always ||
              perm == LocationPermission.whileInUse)) {
        _startTicker();
        _subscribe();
        notifyListeners();
      } else {
        _scheduleRetry();
      }
    });
  }

  void _onPosition(Position position) {
    final next = LatLng(position.latitude, position.longitude);
    _current = next;

    if (_isTracking) {
      if (_routePoints.isNotEmpty) {
        final last = _routePoints.last;
        _distanceMeters += Geolocator.distanceBetween(
          last.latitude,
          last.longitude,
          next.latitude,
          next.longitude,
        );
      }
      _routePoints.add(next);

      final now = DateTime.now();
      if (now.difference(_lastSync).inSeconds > 10) {
        _lastSync = now;
        _queue(next);
        unawaited(_flushPending());
      }
      unawaited(_persist());
    }
    notifyListeners();
  }

  void _startTicker() {
    _ticker?.cancel();
    // Drives the elapsed-time readout while a screen is watching.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_isTracking) notifyListeners();
    });
  }

  // ------------------------------------------------------------------ upload

  void _queue(LatLng p) {
    _pending.add(p);
    // Bound the buffer so a long offline stretch can't grow without limit.
    if (_pending.length > 500) _pending.removeRange(0, _pending.length - 500);
  }

  Future<void> _flushPending() async {
    if (_pending.isEmpty) return;
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
        debugPrint('TrackingService: sync failed, will retry: $e');
        break; // keep the point buffered for the next flush
      }
    }
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_kPending, _encodePoints(_pending));
    notifyListeners();
  }

  // ----------------------------------------------------------- persistence

  Future<void> _persist() async {
    _prefs ??= await SharedPreferences.getInstance();
    final p = _prefs!;
    await p.setBool(_kActive, _isTracking);
    await p.setString(_kBatch, _batchId);
    await p.setInt(_kStart, _startedAt?.millisecondsSinceEpoch ?? 0);
    await p.setDouble(_kDistance, _distanceMeters);
    // Cap the stored polyline; the server holds the authoritative history.
    final tail = _routePoints.length > 2000
        ? _routePoints.sublist(_routePoints.length - 2000)
        : _routePoints;
    await p.setString(_kPoints, _encodePoints(tail));
  }

  String _newBatchId() => 'b${DateTime.now().millisecondsSinceEpoch}';

  static String _encodePoints(List<LatLng> pts) =>
      pts.map((p) => '${p.latitude},${p.longitude}').join(';');

  static List<LatLng> _decodePoints(String raw) {
    if (raw.isEmpty) return const [];
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
