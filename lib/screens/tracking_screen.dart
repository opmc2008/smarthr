import 'package:flutter/foundation.dart' show Factory;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../services/api_service.dart';
import '../services/tracking_service.dart';
import '../theme/app_colors.dart';
import '../widgets/ui_kit.dart';

class TrackingScreen extends StatefulWidget {
  const TrackingScreen({super.key});
  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen> {
  final _service = TrackingService.instance;
  GoogleMapController? _mapController;
  /// Where the camera was last pointed, so it only re-centres on real movement.
  LatLng? _lastCamTarget;
  MapType _mapType = MapType.normal;
  bool _isLoading = true;
  bool _busy = false;

  /// Route as the *server* recorded it today, loaded on demand. Useful when the
  /// phone has been restarted mid-day: the local route only holds this session.
  List<LatLng> _history = [];
  bool _historyLoading = false;
  bool _historyShown = false;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onServiceChanged);
    _prime();
  }

  @override
  void dispose() {
    // Deliberately does NOT stop the session: tracking keeps running in the
    // background until the user presses Stop.
    _service.removeListener(_onServiceChanged);
    super.dispose();
  }

  void _onServiceChanged() {
    if (!mounted) return;
    setState(() {});
    final pos = _service.current;
    if (_service.isTracking && pos != null && _mapController != null) {
      // Only chase the marker once it has actually moved. Re-centring on every
      // fix makes the map twitch while standing still, which reads as bad GPS
      // even when the filter is holding position steady.
      final last = _lastCamTarget;
      final moved = last == null
          ? double.infinity
          : Geolocator.distanceBetween(
              last.latitude, last.longitude, pos.latitude, pos.longitude);
      if (moved >= 8) {
        _lastCamTarget = pos;
        _mapController!.animateCamera(CameraUpdate.newLatLng(pos));
      }
    }
  }

  /// Pulls today's recorded points from the server and shows them as a second,
  /// faded trail. Toggling off keeps them cached so a re-show costs nothing.
  Future<void> _toggleHistory() async {
    if (_historyShown) {
      setState(() => _historyShown = false);
      return;
    }
    if (_history.isNotEmpty) {
      setState(() => _historyShown = true);
      return;
    }
    setState(() => _historyLoading = true);
    try {
      // The user id isn't always stored at login, so fall back to /my_info and
      // cache it for next time.
      var uid = await ApiService.getUserId();
      if (uid.isEmpty) {
        final info = await ApiService.myInfo();
        final data = (info['data'] ?? info) as Map;
        uid = (data['user_id'] ?? data['id'] ?? '').toString();
        if (uid.isNotEmpty) await ApiService.setUserId(uid);
      }
      if (uid.isEmpty) throw Exception('Could not determine your user id.');

      final today = DateTime.now();
      final d = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      final res = await ApiService.locationHistory(uid, start: d, end: d);

      final raw = (res['data'] ?? res['locations'] ?? []) ;
      final list = raw is List ? raw : (raw is Map ? (raw.values.firstWhere((v) => v is List, orElse: () => const [])) : const []);
      final pts = <LatLng>[];
      for (final item in (list as List)) {
        if (item is! Map) continue;
        // Field names for these are unconfirmed against the live server, so
        // accept the spellings the API has plausibly used.
        final lat = double.tryParse((item['lat'] ?? item['latitude'] ?? '').toString());
        final lng = double.tryParse((item['lon'] ?? item['lng'] ?? item['long'] ?? item['longitude'] ?? '').toString());
        if (lat != null && lng != null) pts.add(LatLng(lat, lng));
      }
      if (!mounted) return;
      setState(() {
        _history = pts;
        _historyShown = true;
        _historyLoading = false;
      });
      if (pts.isEmpty) _snack('No recorded points found for today.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _historyLoading = false);
      _snack(e.toString().replaceAll('Exception: ', ''));
    }
  }

  Future<void> _prime() async {
    if (_service.current == null) {
      final enabled = await Geolocator.isLocationServiceEnabled();
      final perm = await Geolocator.checkPermission();
      if (enabled &&
          (perm == LocationPermission.always ||
              perm == LocationPermission.whileInUse)) {
        await _service.refreshCurrentPosition();
      }
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _toggleTracking() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (_service.isTracking) {
        final km = (_service.distanceMeters / 1000).toStringAsFixed(2);
        await _service.stop();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Session ended. Distance: $km km'),
          backgroundColor: AppColors.green,
        ));
      } else {
        final result = await _service.requestPermissions();
        if (!mounted) return;
        switch (result) {
          case TrackingPermission.serviceDisabled:
            await _showGpsDialog();
            return;
          case TrackingPermission.denied:
            _snack('Location permission is required to start a session.');
            return;
          case TrackingPermission.deniedForever:
            await _showSettingsDialog();
            return;
          case TrackingPermission.granted:
          case TrackingPermission.grantedAlways:
            break;
        }
        await _service.refreshCurrentPosition();
        await _service.start();
        if (!mounted) return;
        _snack(
          result == TrackingPermission.grantedAlways
              ? 'Tracking started. It keeps running in the background until you stop it.'
              : 'Tracking started. For the most reliable background tracking, set location access to "Allow all the time".',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _showGpsDialog() => showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Enable GPS'),
          content: const Text(
              'Location services are disabled. Please enable GPS to use tracking.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await Geolocator.openLocationSettings();
              },
              child: const Text('Settings'),
            ),
          ],
        ),
      );

  Future<void> _showSettingsDialog() => showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Location Blocked'),
          content: const Text(
              'Location access is turned off for SmartHR. Open app settings and allow location to track your route.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await Geolocator.openAppSettings();
              },
              child: const Text('Open Settings'),
            ),
          ],
        ),
      );

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(d.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(d.inSeconds.remainder(60));
    return "${twoDigits(d.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
  }

  @override
  Widget build(BuildContext context) {
    final tracking = _service.isTracking;
    final position = _service.current;
    final routePoints = _service.routePoints;
    final pending = _service.pendingCount;

    return SheetPage(
      title: 'Live Tracking',
      showBack: false,
      children: [
        Row(children: [
          Expanded(child: SoftCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: tracking ? AppColors.green : AppColors.inkMuted, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              const Text('Status', style: TextStyle(fontSize: 11, color: AppColors.inkMuted)),
            ]),
            const SizedBox(height: 4),
            Text(tracking ? 'Active Route' : 'Idle', style: TextStyle(fontWeight: FontWeight.w700, color: tracking ? AppColors.green : AppColors.inkSoft)),
            if (_service.lastAccuracy > 0) ...[
              const SizedBox(height: 2),
              // Surfacing the fix radius makes "the map is wrong" diagnosable:
              // a 25m reading is the GPS, not the app.
              Text('±${_service.lastAccuracy.toStringAsFixed(0)} m GPS',
                  style: TextStyle(
                    fontSize: 10,
                    color: _service.lastAccuracy <= 10 ? AppColors.green : AppColors.orange,
                    fontWeight: FontWeight.w600,
                  )),
            ],
          ]))),
          const SizedBox(width: 12),
          Expanded(child: SoftCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Distance / Time', style: TextStyle(fontSize: 11, color: AppColors.inkMuted)),
            const SizedBox(height: 4),
            Text(
              '${(_service.distanceMeters / 1000).toStringAsFixed(2)} km  •  ${_formatDuration(_service.elapsed)}',
              style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.ink, fontSize: 13)
            ),
          ]))),
        ]),
        if (tracking) ...[
          const SizedBox(height: 10),
          SoftCard(child: Row(children: [
            const Icon(Icons.shield_outlined, size: 16, color: AppColors.inkMuted),
            const SizedBox(width: 8),
            Expanded(child: Text(
              pending > 0
                ? 'Running in the background. $pending point(s) waiting to upload.'
                : 'Running in the background — it stays on until you stop it.',
              style: const TextStyle(fontSize: 11, color: AppColors.inkMuted),
            )),
          ])),
        ],
        const SizedBox(height: 14),
        SoftCard(child: Column(children: [
          Container(
            height: 350,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(color: AppColors.blueTint, borderRadius: BorderRadius.circular(12)),
            child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : position == null
                ? const Center(child: Text('Location unavailable', style: TextStyle(color: AppColors.inkMuted)))
                : Stack(
                    children: [
                      GoogleMap(
                        initialCameraPosition: CameraPosition(target: position, zoom: 16.0),
                        onMapCreated: (controller) => _mapController = controller,
                        // The map lives inside a scrolling sheet, which would
                        // otherwise win every vertical drag in the gesture
                        // arena — leaving the map unable to pan or zoom.
                        gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                          Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
                        },
                        myLocationEnabled: true,
                        myLocationButtonEnabled: true,
                        zoomControlsEnabled: true,
                        compassEnabled: true,
                        mapType: _mapType,
                        polylines: {
                          if (_historyShown && _history.length > 1)
                            Polyline(
                              polylineId: const PolylineId('history'),
                              points: _history,
                              color: AppColors.blue.withValues(alpha: 0.55),
                              width: 4,
                              jointType: JointType.round,
                            ),
                          if (routePoints.isNotEmpty)
                            Polyline(
                              polylineId: const PolylineId('route'),
                              points: routePoints,
                              color: AppColors.orange,
                              width: 5,
                              startCap: Cap.roundCap,
                              endCap: Cap.roundCap,
                              jointType: JointType.round,
                            ),
                        },
                        // Shows how confident the fix is, the way Maps does —
                        // a wide circle means the GPS is unsure, not that the
                        // app placed you wrongly.
                        circles: {
                          if (_service.lastAccuracy > 0)
                            Circle(
                              circleId: const CircleId('accuracy'),
                              center: position,
                              radius: _service.lastAccuracy,
                              fillColor: AppColors.blue.withValues(alpha: 0.12),
                              strokeColor: AppColors.blue.withValues(alpha: 0.35),
                              strokeWidth: 1,
                            ),
                        },
                        markers: {
                          if (routePoints.isNotEmpty)
                            Marker(
                              markerId: const MarkerId('start'),
                              position: routePoints.first,
                              icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
                              infoWindow: const InfoWindow(title: 'Session start'),
                            ),
                        },
                      ),
                      Positioned(
                        top: 12,
                        left: 62,
                        child: FloatingActionButton.small(
                          heroTag: 'historyToggle',
                          backgroundColor: _historyShown ? AppColors.blue : Colors.white,
                          onPressed: _historyLoading ? null : _toggleHistory,
                          child: _historyLoading
                              ? const SizedBox(
                                  width: 16, height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.blue))
                              : Icon(Icons.timeline,
                                  color: _historyShown ? Colors.white : AppColors.ink),
                        ),
                      ),
                      Positioned(
                        top: 12,
                        left: 12,
                        child: FloatingActionButton.small(
                          heroTag: 'mapTypeToggle',
                          backgroundColor: Colors.white,
                          onPressed: () {
                            setState(() {
                              _mapType = _mapType == MapType.normal ? MapType.hybrid : MapType.normal;
                            });
                          },
                          child: Icon(
                            _mapType == MapType.normal ? Icons.satellite_alt : Icons.map,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, child: ElevatedButton.icon(
            onPressed: _busy ? null : _toggleTracking,
            icon: Icon(tracking ? Icons.stop_circle : Icons.play_circle, size: 20),
            label: Text(tracking ? 'Stop Tracking' : 'Start Tracking Session'),
            style: ElevatedButton.styleFrom(
              backgroundColor: tracking ? AppColors.red : AppColors.orange,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
            ),
          )),
        ])),
      ],
    );
  }
}
