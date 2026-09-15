import 'dart:async';
import 'package:flutter/foundation.dart' show Factory;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';
import '../widgets/ui_kit.dart';

class AdminEmployeeTrackingScreen extends StatefulWidget {
  final String employeeUserId;
  final String employeeName;

  const AdminEmployeeTrackingScreen({
    super.key,
    required this.employeeUserId,
    required this.employeeName,
  });

  @override
  State<AdminEmployeeTrackingScreen> createState() => _AdminEmployeeTrackingScreenState();
}

class _AdminEmployeeTrackingScreenState extends State<AdminEmployeeTrackingScreen> {
  GoogleMapController? _mapController;
  LatLng? _currentPosition;
  bool _isLoading = true;
  String _error = '';
  MapType _mapType = MapType.normal;
  Timer? _refreshTimer;
  String _lastUpdate = '';
  String _speed = '--';

  @override
  void initState() {
    super.initState();
    _fetchLastLocation();
    // Auto-refresh every 30 seconds
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) => _fetchLastLocation());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchLastLocation() async {
    try {
      final res = await ApiService.teamLastLocation(widget.employeeUserId);
      final data = res['data'];
      if (data != null && data['lat'] != null && data['lon'] != null) {
        final lat = double.tryParse(data['lat'].toString());
        final lon = double.tryParse(data['lon'].toString());
        if (lat != null && lon != null && mounted) {
          final newPos = LatLng(lat, lon);
          setState(() {
            _currentPosition = newPos;
            _isLoading = false;
            _error = '';
            // Format the last update time
            final createdAt = data['created_at']?.toString() ?? '';
            _lastUpdate = createdAt.isNotEmpty ? _formatTime(createdAt) : 'Just now';
          });
          _mapController?.animateCamera(CameraUpdate.newLatLng(newPos));
        }
      } else {
        if (mounted) setState(() { _isLoading = false; _error = 'No location data available yet.'; });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceAll('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  String _formatTime(String raw) {
    try {
      final dt = DateTime.parse(raw).toLocal();
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      return '${dt.day}/${dt.month} ${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
    } catch (_) {
      return raw;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SheetPage(
      title: widget.employeeName,
      showBack: true,
      children: [
        // Status row
        Row(children: [
          Expanded(child: SoftCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [
              Icon(Icons.access_time, size: 14, color: AppColors.inkMuted),
              SizedBox(width: 6),
              Text('Last Update', style: TextStyle(fontSize: 11, color: AppColors.inkMuted)),
            ]),
            const SizedBox(height: 4),
            Text(_lastUpdate.isEmpty ? '--' : _lastUpdate,
              style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
          ]))),
          const SizedBox(width: 12),
          Expanded(child: SoftCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [
              Icon(Icons.location_on, size: 14, color: AppColors.inkMuted),
              SizedBox(width: 6),
              Text('Coordinates', style: TextStyle(fontSize: 11, color: AppColors.inkMuted)),
            ]),
            const SizedBox(height: 4),
            Text(
              _currentPosition != null
                ? '${_currentPosition!.latitude.toStringAsFixed(4)}, ${_currentPosition!.longitude.toStringAsFixed(4)}'
                : '--',
              style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.inkSoft, fontSize: 12),
            ),
          ]))),
        ]),
        const SizedBox(height: 14),

        // Map
        SoftCard(child: Container(
          height: 460,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(color: AppColors.blueTint, borderRadius: BorderRadius.circular(12)),
          child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _error.isNotEmpty
              ? Center(child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.location_off, color: AppColors.red, size: 40),
                    const SizedBox(height: 12),
                    Text(_error, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.inkMuted)),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () { setState(() => _isLoading = true); _fetchLastLocation(); },
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.orange, foregroundColor: Colors.white),
                    ),
                  ]),
                ))
              : Stack(children: [
                  GoogleMap(
                    initialCameraPosition: CameraPosition(target: _currentPosition!, zoom: 16.0),
                    onMapCreated: (controller) => _mapController = controller,
                    // Same gesture-arena fix as the employee map: without this
                    // the surrounding scroll view eats every pan and pinch.
                    gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                      Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
                    },
                    myLocationEnabled: false,
                    myLocationButtonEnabled: false,
                    zoomControlsEnabled: true,
                    compassEnabled: true,
                    mapType: _mapType,
                    markers: {
                      Marker(
                        markerId: const MarkerId('employee'),
                        position: _currentPosition!,
                        infoWindow: InfoWindow(
                          title: widget.employeeName,
                          snippet: _lastUpdate.isEmpty ? 'Live location' : 'Updated: $_lastUpdate',
                        ),
                      ),
                    },
                  ),
                  // Map type toggle
                  Positioned(
                    top: 12, left: 12,
                    child: FloatingActionButton.small(
                      heroTag: 'mapTypeToggleAdmin',
                      backgroundColor: Colors.white,
                      onPressed: () => setState(() {
                        _mapType = _mapType == MapType.normal ? MapType.hybrid : MapType.normal;
                      }),
                      child: Icon(_mapType == MapType.normal ? Icons.satellite_alt : Icons.map, color: AppColors.ink),
                    ),
                  ),
                  // Refresh button
                  Positioned(
                    top: 12, right: 12,
                    child: FloatingActionButton.small(
                      heroTag: 'refreshLoc',
                      backgroundColor: AppColors.blueLight,
                      onPressed: () { setState(() => _isLoading = true); _fetchLastLocation(); },
                      child: const Icon(Icons.refresh, color: Colors.white),
                    ),
                  ),
                  // Live badge
                  Positioned(
                    bottom: 12, left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.65),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Container(width: 7, height: 7, decoration: const BoxDecoration(color: Color(0xFF4ADE80), shape: BoxShape.circle)),
                        const SizedBox(width: 6),
                        const Text('Live Tracking', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  ),
                ]),
        )),
      ],
    );
  }
}
