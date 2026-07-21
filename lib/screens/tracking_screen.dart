import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
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
  MapType _mapType = MapType.normal;
  bool _isLoading = true;
  bool _busy = false;

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
      _mapController!.animateCamera(CameraUpdate.newLatLng(pos));
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
                        myLocationEnabled: true,
                        myLocationButtonEnabled: true,
                        zoomControlsEnabled: true,
                        compassEnabled: true,
                        mapType: _mapType,
                        polylines: {
                          if (routePoints.isNotEmpty)
                            Polyline(
                              polylineId: const PolylineId('route'),
                              points: routePoints,
                              color: AppColors.orange,
                              width: 5,
                            ),
                        },
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
