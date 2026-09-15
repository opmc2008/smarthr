import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'tracking_engine.dart';

/// Outcome of asking the OS for location access.
enum TrackingPermission {
  granted,          // fine location while-in-use (enough for a foreground service)
  grantedAlways,    // fine location "all the time"
  denied,           // user said no this time
  deniedForever,    // user said "don't ask again" -> must go to app settings
  serviceDisabled,  // GPS master switch is off
}

/// The app's handle on the tracking session.
///
/// The recording itself happens in [TrackingEngine]. On Android that engine
/// runs inside a separate background service, so it keeps going when the app
/// is backgrounded, swiped away, or its UI is torn down; this class starts and
/// stops it and mirrors its state for the screens. On iOS the engine runs
/// in-process under the `location` background mode.
///
/// A session ends only when [stop] is called, i.e. when the user turns it off.
class TrackingService extends ChangeNotifier with WidgetsBindingObserver {
  TrackingService._();
  static final TrackingService instance = TrackingService._();

  static const _kBatteryAsked = 'tracking_battery_asked';
  static const _channel = MethodChannel('smarthr/background');

  final _bg = FlutterBackgroundService();
  TrackingEngine? _inProcess;
  StreamSubscription<Map<String, dynamic>?>? _updates;
  Future<void>? _setup;
  Timer? _ticker;
  Timer? _retryTimer;
  SharedPreferences? _prefs;

  bool _isTracking = false;
  LatLng? _current;
  final List<LatLng> _routePoints = [];
  double _distanceMeters = 0;
  DateTime? _startedAt;
  int _pendingCount = 0;
  double _lastAccuracy = 0;

  static bool get _useService =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  bool get isTracking => _isTracking;
  LatLng? get current => _current;
  List<LatLng> get routePoints => List.unmodifiable(_routePoints);
  double get distanceMeters => _distanceMeters;
  int get pendingCount => _pendingCount;

  /// Accuracy of the most recent accepted fix, in metres — for the UI.
  double get lastAccuracy => _lastAccuracy;

  Duration get elapsed =>
      _startedAt == null ? Duration.zero : DateTime.now().difference(_startedAt!);

  // ---------------------------------------------------------------- lifecycle

  /// One-time wiring; runs lazily so a user who logs in mid-launch still gets it.
  Future<void> _ensureSetup() => _setup ??= () async {
        _prefs = await SharedPreferences.getInstance();
        WidgetsBinding.instance.addObserver(this);
        if (!_useService) return;
        await _bg.configure(
          androidConfiguration: AndroidConfiguration(
            onStart: trackingServiceMain,
            autoStart: false,
            // Picks the session back up after a reboot; the engine stops
            // itself straight away if the user had already turned it off.
            autoStartOnBoot: true,
            isForegroundMode: true,
            foregroundServiceTypes: [AndroidForegroundType.location],
            initialNotificationTitle: 'SmartHR tracking active',
            initialNotificationContent:
                'Recording your route for this work session.',
            foregroundServiceNotificationId: 7401,
          ),
          // Unused: iOS runs the engine in-process instead.
          iosConfiguration: IosConfiguration(autoStart: false),
        );
        _updates = _bg.on('update').listen(_onUpdate);
      }();

  /// Call once from `main()`. Re-attaches to a session the user never stopped.
  Future<void> restore() async {
    await _ensureSetup();
    final p = _prefs!;
    await p.reload();
    _pendingCount = TrackingKeys.decode(p.getString(TrackingKeys.pending)).length;
    if (!(p.getBool(TrackingKeys.active) ?? false)) return;

    _startedAt = DateTime.fromMillisecondsSinceEpoch(
        p.getInt(TrackingKeys.start) ?? DateTime.now().millisecondsSinceEpoch);
    _loadRoute(p);
    _isTracking = true;
    _startTicker();
    notifyListeners();
    await _ensureRunning();
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
      try {
        perm = await Geolocator.requestPermission();
      } catch (e) {
        debugPrint('TrackingService: permission request failed: $e');
        return TrackingPermission.denied;
      }
    }
    if (perm == LocationPermission.denied) return TrackingPermission.denied;
    if (perm == LocationPermission.deniedForever) {
      return TrackingPermission.deniedForever;
    }

    var result = TrackingPermission.grantedAlways;
    if (perm != LocationPermission.always) {
      // whileInUse: a second request escalates to the "Allow all the time"
      // prompt on Android 11+/iOS. Declining is fine — the foreground service
      // still keeps us alive — so we don't treat it as a failure.
      try {
        final escalated = await Geolocator.requestPermission();
        result = escalated == LocationPermission.always
            ? TrackingPermission.grantedAlways
            : TrackingPermission.granted;
      } catch (e) {
        debugPrint('TrackingService: permission escalation failed: $e');
        result = TrackingPermission.granted;
      }
    }

    await _requestAndroidExtras();
    return result;
  }

  /// Notification permission (so the ongoing notification is visible on
  /// Android 13+) and a one-time battery-optimisation exemption, without which
  /// many OEM builds kill background services within minutes.
  Future<void> _requestAndroidExtras() async {
    if (!_useService) return;
    try {
      await _channel.invokeMethod('requestNotificationPermission');
      final p = _prefs ??= await SharedPreferences.getInstance();
      if (!(p.getBool(_kBatteryAsked) ?? false)) {
        await p.setBool(_kBatteryAsked, true);
        await _channel.invokeMethod('requestIgnoreBatteryOptimizations');
      }
    } catch (e) {
      debugPrint('TrackingService: background extras failed: $e');
    }
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
    await _ensureSetup();
    final p = _prefs!;

    _isTracking = true;
    _routePoints.clear();
    if (_current != null) _routePoints.add(_current!);
    _distanceMeters = 0;
    _lastAccuracy = 0;
    _startedAt = DateTime.now();

    // Hand the new session to the engine through prefs before starting it.
    await p.setString(
        TrackingKeys.batch, 'b${_startedAt!.millisecondsSinceEpoch}');
    await p.setInt(TrackingKeys.start, _startedAt!.millisecondsSinceEpoch);
    await p.setDouble(TrackingKeys.distance, 0);
    await p.setString(TrackingKeys.points, TrackingKeys.encode(_routePoints));
    await p.setBool(TrackingKeys.active, true);

    _startTicker();
    notifyListeners();
    await _ensureRunning();
  }

  /// The only way a session ends.
  Future<void> stop() async {
    if (!_isTracking) return;
    _isTracking = false;
    _ticker?.cancel();
    _ticker = null;
    _retryTimer?.cancel();
    _retryTimer = null;

    final p = _prefs ??= await SharedPreferences.getInstance();
    await p.setBool(TrackingKeys.active, false);
    if (_useService) {
      _bg.invoke('stop');
    } else {
      await _inProcess?.stop();
    }
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !_isTracking) return;
    // Catch up on fixes recorded while no UI was listening, and restart the
    // service if the OS stopped it while we were away.
    unawaited(() async {
      final p = _prefs!;
      await p.reload();
      _loadRoute(p);
      notifyListeners();
      await _ensureRunning();
    }());
  }

  // ----------------------------------------------------------------- engine

  /// Starts the engine if the OS allows it, otherwise keeps retrying.
  Future<void> _ensureRunning() async {
    if (!_isTracking) return;
    final serviceOn = await Geolocator.isLocationServiceEnabled();
    final perm = await Geolocator.checkPermission();
    // If permission was revoked we keep the session flagged active and the
    // screen surfaces the problem instead of silently dropping it.
    if (!serviceOn ||
        perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      _scheduleRetry();
      return;
    }

    try {
      if (_useService) {
        if (await _bg.isRunning()) {
          _bg.invoke('resume'); // no-op if it is already recording
        } else {
          await _bg.startService();
        }
      } else {
        await (_inProcess ??= TrackingEngine(onUpdate: _onUpdate)).resume();
      }
    } catch (e) {
      // Android 12+ refuses to start a foreground service from the background;
      // the next retry or app resume will get it going.
      debugPrint('TrackingService: could not start engine: $e');
      _scheduleRetry();
    }
  }

  void _scheduleRetry() {
    if (!_isTracking) return;
    _retryTimer?.cancel();
    _retryTimer = Timer(const Duration(seconds: 15), _ensureRunning);
  }

  void _onUpdate(Map<String, dynamic>? e) {
    if (e == null) return;
    _pendingCount = (e['pending'] as num?)?.toInt() ?? _pendingCount;

    final lat = (e['lat'] as num?)?.toDouble();
    final lng = (e['lng'] as num?)?.toDouble();
    if (lat != null && lng != null && _isTracking) {
      _current = LatLng(lat, lng);
      _lastAccuracy = (e['accuracy'] as num?)?.toDouble() ?? _lastAccuracy;
      _distanceMeters = (e['distance'] as num?)?.toDouble() ?? _distanceMeters;
      _routePoints.add(_current!);
      if (_routePoints.length > TrackingKeys.maxStoredPoints) {
        _routePoints.removeRange(
            0, _routePoints.length - TrackingKeys.maxStoredPoints);
      }
      // Out of step (missed events while detached): resync from disk.
      final count = (e['count'] as num?)?.toInt();
      if (count != null && count != _routePoints.length) {
        unawaited(() async {
          final p = _prefs!;
          await p.reload();
          _loadRoute(p);
          notifyListeners();
        }());
      }
    }
    notifyListeners();
  }

  void _loadRoute(SharedPreferences p) {
    _distanceMeters = p.getDouble(TrackingKeys.distance) ?? 0;
    _routePoints
      ..clear()
      ..addAll(TrackingKeys.decode(p.getString(TrackingKeys.points)));
    if (_routePoints.isNotEmpty) _current = _routePoints.last;
  }

  void _startTicker() {
    _ticker?.cancel();
    // Drives the elapsed-time readout while a screen is watching.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_isTracking) notifyListeners();
    });
  }

  @override
  void dispose() {
    _updates?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
