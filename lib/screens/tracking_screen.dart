import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';
import '../widgets/ui_kit.dart';

class TrackingScreen extends StatefulWidget {
  const TrackingScreen({super.key});
  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen> {
  GoogleMapController? _mapController;
  LatLng? _currentPosition;
  bool _isLoading = true;
  MapType _mapType = MapType.normal;
  
  // Tracking Session State
  bool _isTracking = false;
  final List<LatLng> _routePoints = [];
  double _totalDistanceMeters = 0.0;
  DateTime? _sessionStartTime;
  Timer? _durationTimer;
  Duration _sessionDuration = Duration.zero;

  StreamSubscription<Position>? _positionStream;
  DateTime _lastApiSyncTime = DateTime.fromMillisecondsSinceEpoch(0);
  String _batchId = '';

  @override
  void initState() {
    super.initState();
    _determinePosition();
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _durationTimer?.cancel();
    super.dispose();
  }

  Future<void> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Enable GPS'),
            content: const Text('Location services are disabled. Please enable GPS to use tracking.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
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
        setState(() => _isLoading = false);
      }
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      if (mounted) {
        bool? allow = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Location Required'),
            content: const Text('SmartHR needs your location to track your route during a session. Please allow location access.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Continue')),
            ],
          ),
        );
        if (allow != true) {
          setState(() => _isLoading = false);
          return;
        }
      }
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high);
    
    if (mounted) {
      setState(() {
        _currentPosition = LatLng(position.latitude, position.longitude);
        _isLoading = false;
      });
    }

    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5, // Update every 5 meters
      ),
    ).listen((Position position) {
      _handleNewPosition(position);
    });
  }

  void _handleNewPosition(Position position) {
    LatLng newPos = LatLng(position.latitude, position.longitude);
    
    if (mounted) {
      setState(() {
        _currentPosition = newPos;
        
        if (_isTracking) {
          if (_routePoints.isNotEmpty) {
            final lastPos = _routePoints.last;
            _totalDistanceMeters += Geolocator.distanceBetween(
              lastPos.latitude, lastPos.longitude,
              newPos.latitude, newPos.longitude,
            );
          }
          _routePoints.add(newPos);
          
          // Throttled API sync (max once every 10 seconds)
          final now = DateTime.now();
          if (now.difference(_lastApiSyncTime).inSeconds > 10) {
            _lastApiSyncTime = now;
            _syncLocationToApi(newPos);
          }
        }
      });
    }
    
    // Auto-pan camera if tracking
    if (_isTracking && _mapController != null) {
      _mapController!.animateCamera(CameraUpdate.newLatLng(newPos));
    }
  }

  Future<void> _syncLocationToApi(LatLng pos) async {
    try {
      final lat = pos.latitude.toStringAsFixed(6);
      final lon = pos.longitude.toStringAsFixed(6);
      await ApiService.locationCreate(_batchId, lat, lon);
    } catch (e) {
      debugPrint("API Sync failed: $e");
    }
  }

  void _toggleTracking() {
    setState(() {
      if (_isTracking) {
        // Stop Tracking
        _isTracking = false;
        _durationTimer?.cancel();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Session Ended. Distance: ${(_totalDistanceMeters / 1000).toStringAsFixed(2)} km'), 
            backgroundColor: AppColors.green
          )
        );
      } else {
        // Start Tracking
        _isTracking = true;
        _routePoints.clear();
        _totalDistanceMeters = 0.0;
        _sessionStartTime = DateTime.now();
        _sessionDuration = Duration.zero;
        _batchId = 'b${DateTime.now().millisecondsSinceEpoch}';
        
        if (_currentPosition != null) {
          _routePoints.add(_currentPosition!);
          _syncLocationToApi(_currentPosition!);
        }

        _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (mounted) {
            setState(() {
              _sessionDuration = DateTime.now().difference(_sessionStartTime!);
            });
          }
        });
      }
    });
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(d.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(d.inSeconds.remainder(60));
    return "${twoDigits(d.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
  }

  @override
  Widget build(BuildContext context) {
    return SheetPage(
      title: 'Live Tracking',
      showBack: false,
      children: [
        Row(children: [
          Expanded(child: SoftCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: _isTracking ? AppColors.green : AppColors.inkMuted, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              const Text('Status', style: TextStyle(fontSize: 11, color: AppColors.inkMuted)),
            ]),
            const SizedBox(height: 4),
            Text(_isTracking ? 'Active Route' : 'Idle', style: TextStyle(fontWeight: FontWeight.w700, color: _isTracking ? AppColors.green : AppColors.inkSoft)),
          ]))),
          const SizedBox(width: 12),
          Expanded(child: SoftCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Distance / Time', style: TextStyle(fontSize: 11, color: AppColors.inkMuted)),
            const SizedBox(height: 4),
            Text(
              '${(_totalDistanceMeters / 1000).toStringAsFixed(2)} km  •  ${_formatDuration(_sessionDuration)}', 
              style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.ink, fontSize: 13)
            ),
          ]))),
        ]),
        const SizedBox(height: 14),
        SoftCard(child: Column(children: [
          Container(
            height: 350,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(color: AppColors.blueTint, borderRadius: BorderRadius.circular(12)),
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator())
              : _currentPosition == null 
                ? const Center(child: Text('Location unavailable', style: TextStyle(color: AppColors.inkMuted)))
                : Stack(
                    children: [
                      GoogleMap(
                        initialCameraPosition: CameraPosition(target: _currentPosition!, zoom: 16.0),
                        onMapCreated: (controller) => _mapController = controller,
                        myLocationEnabled: true,
                        myLocationButtonEnabled: true,
                        zoomControlsEnabled: true,
                        compassEnabled: true,
                        mapType: _mapType,
                        polylines: {
                          if (_routePoints.isNotEmpty)
                            Polyline(
                              polylineId: const PolylineId('route'),
                              points: _routePoints,
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
            onPressed: _currentPosition == null ? null : _toggleTracking,
            icon: Icon(_isTracking ? Icons.stop_circle : Icons.play_circle, size: 20),
            label: Text(_isTracking ? 'Stop Tracking' : 'Start Tracking Session'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _isTracking ? AppColors.red : AppColors.orange, 
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
