import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'services/tracking_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('smarthr_token') ?? '';
  // Resume a tracking session the user never turned off (app killed, reboot...).
  if (token.isNotEmpty) await TrackingService.instance.restore();
  runApp(SmartHRApp(isLoggedIn: token.isNotEmpty));
}

class SmartHRApp extends StatelessWidget {
  final bool isLoggedIn;
  const SmartHRApp({super.key, required this.isLoggedIn});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SmartHR',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1B5CFF),
          brightness: Brightness.dark,
          surface: const Color(0xFF0B2668),
        ),
        scaffoldBackgroundColor: Colors.transparent,
        useMaterial3: true,
        fontFamily: 'Inter',
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0,
          titleTextStyle: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800, fontFamily: 'Inter'),
        ),
        tabBarTheme: TabBarThemeData(
          labelColor: const Color(0xFFFF7A1A),
          unselectedLabelColor: Colors.white.withOpacity(0.4),
          indicatorColor: const Color(0xFFFF7A1A),
          dividerColor: Colors.white.withOpacity(0.08),
        ),
        navigationBarTheme: NavigationBarThemeData(
          iconTheme: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return const IconThemeData(color: Color(0xFFFF7A1A));
            return const IconThemeData(color: Color(0xFF8FA6DE));
          }),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return const TextStyle(color: Color(0xFFFF7A1A), fontWeight: FontWeight.w700, fontSize: 11);
            return const TextStyle(color: Color(0xFF8FA6DE), fontSize: 11);
          }),
        ),
      ),
      builder: (context, child) => Stack(children: [
        const Positioned.fill(child: _AmbientBg()),
        child!,
      ]),
      home: AppShell(isLoggedIn: isLoggedIn),
    );
  }
}

class AppShell extends StatelessWidget {
  final bool isLoggedIn;
  const AppShell({super.key, required this.isLoggedIn});

  @override
  Widget build(BuildContext context) =>
      isLoggedIn ? const HomeScreen() : const LoginScreen();
}

class _AmbientBg extends StatefulWidget {
  const _AmbientBg();
  @override
  State<_AmbientBg> createState() => _AmbientBgState();
}

class _AmbientBgState extends State<_AmbientBg> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 8))..repeat(reverse: true);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final t = Curves.easeInOut.transform(_ctrl.value);
        return Container(
          decoration: const BoxDecoration(
            // Variant A "carved geometry" royal canvas
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF2B67F0), Color(0xFF123B9E), Color(0xFF0B2668)],
              stops: [0.0, 0.55, 1.0],
            ),
          ),
          child: Stack(children: [
            // Big carved ring, top right
            Positioned(
              top: -110, right: -110,
              child: Container(
                width: 340, height: 340,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withOpacity(0.08), width: 52),
                ),
              ),
            ),
            // Rotated plate, left
            Positioned(
              top: 190, left: -80,
              child: Transform.rotate(
                angle: 28 * math.pi / 180,
                child: Container(
                  width: 200, height: 200,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(56),
                  ),
                ),
              ),
            ),
            // Bobbing orange ring, bottom right
            Positioned(
              bottom: 130 + t * 26, right: -50,
              child: Container(
                width: 170, height: 170,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFFF7A1A).withOpacity(0.4), width: 26),
                ),
              ),
            ),
            // Small carved square, bottom left
            Positioned(
              bottom: -30, left: 30,
              child: Transform.rotate(
                angle: -0.3,
                child: Container(
                  width: 110, height: 110,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white.withOpacity(0.12), width: 2),
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
              ),
            ),
          ]),
        );
      },
    );
  }
}
