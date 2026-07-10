import 'package:flutter/material.dart';
import 'dashboard_screen.dart';
import 'attendance_screen.dart';
import 'leaves_screen.dart';
import 'payroll_screen.dart';
import 'more_screen.dart';
import 'tracking_screen.dart';
import 'admin_dashboard_screen.dart';
import '../services/api_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _loadRole();
  }

  Future<void> _loadRole() async {
    final role = await ApiService.getRole();
    if (mounted) {
      setState(() {
        _isAdmin = role == 'super_admin' || role == 'admin' || role == 'manager' || role == '1';
      });
    }
  }

  List<Widget> get _screens => [
    const DashboardScreen(),
    const AttendanceScreen(),
    const LeavesScreen(),
    const PayrollScreen(),
    if (_isAdmin) const AdminDashboardScreen(),
    const MoreScreen(),
    const TrackingScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_index],
      extendBody: true,
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0A1F4E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          boxShadow: [BoxShadow(color: Color(0x660A1F4E), blurRadius: 26, offset: Offset(0, -6))],
        ),
        clipBehavior: Clip.antiAlias,
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          backgroundColor: Colors.transparent,
          indicatorColor: const Color(0xFFFF7A1A).withOpacity(0.22),
          elevation: 0,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: [
            const NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Home'),
            const NavigationDestination(icon: Icon(Icons.fingerprint_outlined), selectedIcon: Icon(Icons.fingerprint), label: 'Attendance'),
            const NavigationDestination(icon: Icon(Icons.event_busy_outlined), selectedIcon: Icon(Icons.event_busy), label: 'Leaves'),
            const NavigationDestination(icon: Icon(Icons.payments_outlined), selectedIcon: Icon(Icons.payments), label: 'Payroll'),
            if (_isAdmin) const NavigationDestination(icon: Icon(Icons.group_outlined), selectedIcon: Icon(Icons.group), label: 'Team'),
            const NavigationDestination(icon: Icon(Icons.grid_view_outlined), selectedIcon: Icon(Icons.grid_view), label: 'More'),
            const NavigationDestination(icon: Icon(Icons.location_on_outlined), selectedIcon: Icon(Icons.location_on), label: 'Tracking'),
          ],
        ),
      ),
    );
  }
}
