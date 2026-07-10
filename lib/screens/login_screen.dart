import 'dart:ui';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'home_screen.dart';

enum _Stage { roleSelect, adminLogin, employeeEmailCheck, employeePassword, otp }

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  _Stage _stage = _Stage.roleSelect;
  bool _isAdminFlow = false;

  final _emailCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();
  final _otpCtrls  = List.generate(6, (_) => TextEditingController());
  final _otpFocuses = List.generate(6, (_) => FocusNode());

  bool _loading = false;
  String _error = '';
  String _pendingUserId = '';

  late AnimationController _pulse;

  static const _orange  = Color(0xFFFF7A1A);
  static const _blueLt  = Color(0xFF4C82FF);
  static const _blueDeep = Color(0xFF0F3FB8);

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    _emailCtrl.dispose(); _passCtrl.dispose();
    for (final c in _otpCtrls) c.dispose();
    for (final f in _otpFocuses) f.dispose();
    super.dispose();
  }

  // ── Super Admin Login ──────────────────────────────────────────────────────
  Future<void> _doAdminLogin() async {
    final email = _emailCtrl.text.trim();
    final pass  = _passCtrl.text;
    if (email.isEmpty || pass.isEmpty) {
      setState(() => _error = 'Enter your email and password.');
      return;
    }
    setState(() { _loading = true; _error = ''; });
    try {
      final res  = await ApiService.login(email, pass);
      final data = res['data'] is Map ? res['data'] as Map : null;
      final token = res['token'] ?? res['access_token'] ?? data?['token'] ?? data?['access_token'] ?? '';
      final uid   = (res['user_id'] ?? data?['user_id'] ?? res['id'] ?? data?['id'] ?? '').toString();
      final role  = (res['role'] ?? data?['role'] ?? res['user_type'] ?? data?['user_type'] ?? '').toString().toLowerCase();

      // Guard: if backend says this is NOT an admin, block access
      final isAdmin = role == 'super_admin' || role == 'admin' || role == 'manager' || role == '1';
      if (token.toString().isNotEmpty && !isAdmin && role.isNotEmpty) {
        setState(() {
          _loading = false;
          _error = 'This is an Employee account. Please use Employee login.';
        });
        return;
      }

      if (token.toString().isNotEmpty) {
        await ApiService.setToken(token.toString());
        if (uid.isNotEmpty) await ApiService.setUserId(uid);
        await ApiService.setRole(isAdmin ? 'super_admin' : 'super_admin'); // Admin flow → always admin
        _enterApp();
        return;
      }
      // OTP required
      _pendingUserId = uid;
      setState(() { _stage = _Stage.otp; _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString().replaceAll('Exception: ', ''); _loading = false; });
    }
  }

  // ── Employee: Step 1 — verify email ───────────────────────────────────────
  Future<void> _doEmployeeEmailCheck() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Enter your employee email address.');
      return;
    }
    setState(() { _loading = true; _error = ''; });
    try {
      final res = await ApiService.checkUser(email);
      // If server returns a role and it's an admin, block it
      final data = res['data'] is Map ? res['data'] as Map : null;
      final role = (res['role'] ?? data?['role'] ?? res['user_type'] ?? data?['user_type'] ?? '').toString().toLowerCase();
      final isAdmin = role == 'super_admin' || role == 'admin' || role == 'manager' || role == '1';
      if (isAdmin) {
        setState(() {
          _loading = false;
          _error = 'This is a Super Admin account. Please use Super Admin login.';
        });
        return;
      }
      setState(() { _stage = _Stage.employeePassword; _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString().replaceAll('Exception: ', ''); _loading = false; });
    }
  }

  // ── Employee: Step 2 — login with password ────────────────────────────────
  Future<void> _doEmployeeLogin() async {
    final email = _emailCtrl.text.trim();
    final pass  = _passCtrl.text;
    if (pass.isEmpty) {
      setState(() => _error = 'Enter your password.');
      return;
    }
    setState(() { _loading = true; _error = ''; });
    try {
      final res  = await ApiService.login(email, pass);
      final data = res['data'] is Map ? res['data'] as Map : null;
      final token = res['token'] ?? res['access_token'] ?? data?['token'] ?? data?['access_token'] ?? '';
      final uid   = (res['user_id'] ?? data?['user_id'] ?? res['id'] ?? data?['id'] ?? '').toString();
      final role  = (res['role'] ?? data?['role'] ?? res['user_type'] ?? data?['user_type'] ?? 'employee').toString().toLowerCase();

      // Guard: if backend says this is an admin, block employee path
      final isAdmin = role == 'super_admin' || role == 'admin' || role == 'manager' || role == '1';
      if (isAdmin && role.isNotEmpty) {
        setState(() {
          _loading = false;
          _error = 'Super Admin accounts cannot log in as Employee.';
        });
        return;
      }

      if (token.toString().isNotEmpty) {
        await ApiService.setToken(token.toString());
        if (uid.isNotEmpty) await ApiService.setUserId(uid);
        await ApiService.setRole('employee');
        _enterApp();
        return;
      }
      // OTP required
      _pendingUserId = uid;
      setState(() { _stage = _Stage.otp; _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString().replaceAll('Exception: ', ''); _loading = false; });
    }
  }

  // ── OTP Verify ────────────────────────────────────────────────────────────
  Future<void> _doVerifyOtp() async {
    final otp = _otpCtrls.map((c) => c.text).join();
    if (otp.length < 4) { setState(() => _error = 'Enter the complete OTP.'); return; }
    setState(() { _loading = true; _error = ''; });
    try {
      final res   = await ApiService.verifyOtp(_pendingUserId, otp);
      final data2 = res['data'] is Map ? res['data'] as Map : null;
      final token = res['token'] ?? res['access_token'] ?? data2?['token'] ?? data2?['access_token'] ?? '';
      final uid   = (res['user_id'] ?? data2?['user_id'] ?? res['id'] ?? data2?['id'] ?? _pendingUserId).toString();
      if (token.toString().isNotEmpty) await ApiService.setToken(token.toString());
      if (uid.isNotEmpty) await ApiService.setUserId(uid);
      await ApiService.setRole(_isAdminFlow ? 'super_admin' : 'employee');
      _enterApp();
    } catch (e) {
      setState(() { _error = e.toString().replaceAll('Exception: ', ''); _loading = false; });
    }
  }

  void _enterApp() => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const HomeScreen()));

  void _goBack() {
    setState(() {
      _error = '';
      _passCtrl.clear();
      switch (_stage) {
        case _Stage.adminLogin:
        case _Stage.employeeEmailCheck:
          _emailCtrl.clear();
          _stage = _Stage.roleSelect;
          break;
        case _Stage.employeePassword:
          _stage = _Stage.employeeEmailCheck;
          break;
        case _Stage.otp:
          _stage = _isAdminFlow ? _Stage.adminLogin : _Stage.employeePassword;
          break;
        case _Stage.roleSelect:
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(children: [
              // Logo
              AnimatedBuilder(
                animation: _pulse,
                builder: (_, child) => Container(
                  width: 92, height: 92,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    color: Colors.white.withOpacity(0.10),
                    border: Border.all(color: Colors.white.withOpacity(0.22 + _pulse.value * 0.12), width: 1.5),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 30, offset: const Offset(0, 14)),
                      BoxShadow(color: _orange.withOpacity(0.12 + _pulse.value * 0.12), blurRadius: 50),
                    ],
                  ),
                  padding: const EdgeInsets.all(14),
                  child: Image.asset('assets/logo.png', fit: BoxFit.contain),
                ),
              ),
              const SizedBox(height: 22),
              RichText(
                text: const TextSpan(
                  style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5, fontFamily: 'Inter'),
                  children: [
                    TextSpan(text: 'Smart'),
                    TextSpan(text: 'HR', style: TextStyle(color: _orange)),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 52),
                duration: const Duration(milliseconds: 1200),
                curve: Curves.easeOutCubic,
                builder: (_, w, __) => Container(
                  width: w, height: 5,
                  decoration: BoxDecoration(color: _orange, borderRadius: BorderRadius.circular(3)),
                ),
              ),
              const SizedBox(height: 10),
              Text('Your team, in motion', style: TextStyle(color: const Color(0xFFC9DAFF).withOpacity(0.9), fontSize: 13)),
              const SizedBox(height: 30),

              // Card
              ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white.withOpacity(0.12)),
                    ),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 320),
                      transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: SlideTransition(
                        position: Tween<Offset>(begin: const Offset(0.05, 0), end: Offset.zero).animate(anim),
                        child: child,
                      )),
                      child: _buildCurrentStage(),
                    ),
                  ),
                ),
              ),

              if (_error.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.withOpacity(0.3)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.error_outline, color: Color(0xFFFCA5A5), size: 16),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_error, style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 13))),
                  ]),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentStage() {
    switch (_stage) {
      case _Stage.roleSelect:        return _buildRoleSelect();
      case _Stage.adminLogin:        return _buildAdminLogin();
      case _Stage.employeeEmailCheck: return _buildEmployeeEmailCheck();
      case _Stage.employeePassword:  return _buildEmployeePassword();
      case _Stage.otp:               return _buildOtpForm();
    }
  }

  // ── Role Selection ─────────────────────────────────────────────────────────
  Widget _buildRoleSelect() => Column(key: const ValueKey('role'), children: [
    const Text('Who are you?', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white)),
    const SizedBox(height: 6),
    Text('Select your account type to continue', style: TextStyle(color: Colors.white.withOpacity(0.45), fontSize: 13)),
    const SizedBox(height: 28),
    _roleCard(
      icon: Icons.shield_outlined,
      title: 'Super Admin',
      subtitle: 'Manage employees & monitor tracking',
      gradient: const LinearGradient(colors: [Color(0xFF1B5CFF), Color(0xFF0F3FB8)]),
      onTap: () => setState(() { _isAdminFlow = true; _stage = _Stage.adminLogin; _error = ''; }),
    ),
    const SizedBox(height: 14),
    _roleCard(
      icon: Icons.badge_outlined,
      title: 'Employee',
      subtitle: 'Access your HR dashboard & attendance',
      gradient: const LinearGradient(colors: [Color(0xFFFF7A1A), Color(0xFFE05F00)]),
      onTap: () => setState(() { _isAdminFlow = false; _stage = _Stage.employeeEmailCheck; _error = ''; }),
    ),
  ]);

  Widget _roleCard({required IconData icon, required String title, required String subtitle, required Gradient gradient, required VoidCallback onTap}) =>
    Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 6))],
          ),
          child: Row(children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: Colors.white, size: 26),
            ),
            const SizedBox(width: 16),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Colors.white)),
              const SizedBox(height: 3),
              Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.75))),
            ])),
            const Icon(Icons.arrow_forward_ios, color: Colors.white60, size: 16),
          ]),
        ),
      ),
    );

  // ── Admin Login ────────────────────────────────────────────────────────────
  Widget _buildAdminLogin() => Column(key: const ValueKey('admin'), crossAxisAlignment: CrossAxisAlignment.start, children: [
    _backButton(),
    const SizedBox(height: 20),
    Row(children: [
      Container(width: 32, height: 32, decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF1B5CFF), Color(0xFF0F3FB8)]), borderRadius: BorderRadius.circular(8)),
        child: const Icon(Icons.shield, color: Colors.white, size: 18)),
      const SizedBox(width: 10),
      const Text('Super Admin Login', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
    ]),
    const SizedBox(height: 4),
    Padding(padding: const EdgeInsets.only(left: 42),
      child: Text('Sign in with your admin credentials', style: TextStyle(color: Colors.white.withOpacity(0.45), fontSize: 13))),
    const SizedBox(height: 24),
    _label('EMAIL'),
    _input(controller: _emailCtrl, hint: 'admin@company.com', icon: Icons.email_outlined, type: TextInputType.emailAddress),
    const SizedBox(height: 16),
    _label('PASSWORD'),
    _input(controller: _passCtrl, hint: '••••••••', icon: Icons.lock_outline, obscure: true),
    const SizedBox(height: 28),
    _btn(_loading ? 'Signing in…' : 'Sign In as Admin', _loading ? null : _doAdminLogin, Icons.arrow_forward,
      const LinearGradient(colors: [Color(0xFF1B5CFF), Color(0xFF0F3FB8)])),
  ]);

  // ── Employee: Step 1 Email ─────────────────────────────────────────────────
  Widget _buildEmployeeEmailCheck() => Column(key: const ValueKey('empEmail'), crossAxisAlignment: CrossAxisAlignment.start, children: [
    _backButton(),
    const SizedBox(height: 20),
    Row(children: [
      Container(width: 32, height: 32, decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFFF7A1A), Color(0xFFE05F00)]), borderRadius: BorderRadius.circular(8)),
        child: const Icon(Icons.badge, color: Colors.white, size: 18)),
      const SizedBox(width: 10),
      const Text('Employee Login', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
    ]),
    const SizedBox(height: 4),
    Padding(padding: const EdgeInsets.only(left: 42),
      child: Text('Step 1 of 2 — Verify your employee email', style: TextStyle(color: Colors.white.withOpacity(0.45), fontSize: 13))),
    const SizedBox(height: 24),
    _label('EMPLOYEE EMAIL'),
    _input(controller: _emailCtrl, hint: 'you@company.com', icon: Icons.email_outlined, type: TextInputType.emailAddress),
    const SizedBox(height: 8),
    // Security note
    Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Row(children: [
        const Icon(Icons.verified_user_outlined, color: Color(0xFF4C82FF), size: 16),
        const SizedBox(width: 8),
        Expanded(child: Text("Your email will be verified against your Super Admin's registered employee list.",
          style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 11))),
      ]),
    ),
    const SizedBox(height: 24),
    _btn(_loading ? 'Verifying…' : 'Verify Email', _loading ? null : _doEmployeeEmailCheck, Icons.arrow_forward,
      const LinearGradient(colors: [Color(0xFFFF7A1A), Color(0xFFE05F00)])),
  ]);

  // ── Employee: Step 2 Password ──────────────────────────────────────────────
  Widget _buildEmployeePassword() => Column(key: const ValueKey('empPass'), crossAxisAlignment: CrossAxisAlignment.start, children: [
    _backButton(),
    const SizedBox(height: 20),
    Row(children: [
      Container(width: 32, height: 32, decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFFF7A1A), Color(0xFFE05F00)]), borderRadius: BorderRadius.circular(8)),
        child: const Icon(Icons.badge, color: Colors.white, size: 18)),
      const SizedBox(width: 10),
      const Text('Employee Login', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
    ]),
    const SizedBox(height: 4),
    Padding(padding: const EdgeInsets.only(left: 42),
      child: Text('Step 2 of 2 — Enter your password', style: TextStyle(color: Colors.white.withOpacity(0.45), fontSize: 13))),
    const SizedBox(height: 6),
    // Show verified email
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.green.withOpacity(0.25))),
      child: Row(children: [
        const Icon(Icons.check_circle_outline, color: Color(0xFF4ADE80), size: 15),
        const SizedBox(width: 8),
        Expanded(child: Text(_emailCtrl.text, style: const TextStyle(color: Color(0xFF4ADE80), fontSize: 13, fontWeight: FontWeight.w600))),
      ]),
    ),
    const SizedBox(height: 20),
    _label('PASSWORD'),
    _input(controller: _passCtrl, hint: '••••••••', icon: Icons.lock_outline, obscure: true),
    const SizedBox(height: 28),
    _btn(_loading ? 'Signing in…' : 'Sign In', _loading ? null : _doEmployeeLogin, Icons.arrow_forward,
      const LinearGradient(colors: [Color(0xFFFF7A1A), Color(0xFFE05F00)])),
  ]);

  // ── OTP ────────────────────────────────────────────────────────────────────
  Widget _buildOtpForm() => Column(key: const ValueKey('otp'), crossAxisAlignment: CrossAxisAlignment.start, children: [
    _backButton(),
    const SizedBox(height: 20),
    const Text('Verify OTP', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
    const SizedBox(height: 4),
    Text('Enter the 6-digit code sent to you', style: TextStyle(color: Colors.white.withOpacity(0.45), fontSize: 13)),
    const SizedBox(height: 24),
    Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: List.generate(6, (i) => SizedBox(
      width: 44, height: 54,
      child: TextField(
        controller: _otpCtrls[i], focusNode: _otpFocuses[i],
        maxLength: 1, textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white),
        decoration: InputDecoration(
          counterText: '',
          filled: true,
          fillColor: Colors.white.withOpacity(0.07),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withOpacity(0.15))),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withOpacity(0.15))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _isAdminFlow ? _blueLt : _orange, width: 2)),
        ),
        onChanged: (v) {
          if (v.isNotEmpty && i < 5) _otpFocuses[i + 1].requestFocus();
          if (v.isEmpty && i > 0) _otpFocuses[i - 1].requestFocus();
        },
      ),
    ))),
    const SizedBox(height: 28),
    _btn(_loading ? 'Verifying…' : 'Verify & Login', _loading ? null : _doVerifyOtp, Icons.verified_outlined,
      _isAdminFlow
        ? const LinearGradient(colors: [Color(0xFF1B5CFF), Color(0xFF0F3FB8)])
        : const LinearGradient(colors: [Color(0xFFFF7A1A), Color(0xFFE05F00)])),
  ]);

  // ── Helpers ────────────────────────────────────────────────────────────────
  Widget _backButton() => GestureDetector(
    onTap: _goBack,
    child: Row(children: [
      Container(padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.08), shape: BoxShape.circle),
        child: const Icon(Icons.arrow_back, size: 14, color: Colors.white70)),
      const SizedBox(width: 8),
      Text('Back', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13)),
    ]),
  );

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white.withOpacity(0.4), letterSpacing: 1.2)),
  );

  Widget _input({required TextEditingController controller, required String hint, required IconData icon, bool obscure = false, TextInputType type = TextInputType.text}) =>
    TextField(
      controller: controller, obscureText: obscure, keyboardType: type,
      style: const TextStyle(color: Colors.white, fontSize: 15),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.white.withOpacity(0.25)),
        prefixIcon: Icon(icon, color: Colors.white.withOpacity(0.35), size: 18),
        filled: true,
        fillColor: Colors.white.withOpacity(0.06),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _isAdminFlow ? _blueLt : _orange, width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );

  Widget _btn(String label, VoidCallback? onTap, IconData icon, Gradient gradient) => Container(
    width: double.infinity,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(14),
      gradient: onTap != null ? gradient : null,
      color: onTap == null ? Colors.white12 : null,
      boxShadow: onTap != null ? [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 4))] : null,
    ),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 15),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (_loading)
              const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            else ...[
              Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
              const SizedBox(width: 8),
              Icon(icon, size: 18, color: Colors.white),
            ],
          ]),
        ),
      ),
    ),
  );
}
