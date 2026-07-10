import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';
import '../widgets/liquid_dial.dart';
import '../widgets/ui_kit.dart';
import 'login_screen.dart';
import 'leaves_screen.dart';
import 'overtime_screen.dart';
import 'payroll_screen.dart';
import 'tracking_screen.dart';
import 'holidays_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, dynamic> _info = {};
  Map<String, dynamic> _schedule = {};
  bool _loading = true;
  bool _clockedIn = false;
  int _leaveRemaining = 0;
  int _otMinutes = 0;

  Timer? _clock;
  DateTime? _localStartTime;

  @override
  void initState() {
    super.initState();
    _load();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) { if (mounted) setState(() {}); });
  }

  @override
  void dispose() { _clock?.cancel(); super.dispose(); }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        ApiService.myInfo(),
        ApiService.todaySchedule().catchError((_) => <String, dynamic>{}),
        ApiService.otBalance().catchError((_) => <String, dynamic>{}),
      ]);
      final info   = (results[0]['data'] ?? results[0]) as Map;
      final otData = results[2]['data'] ?? results[2];
      final otList = ((otData is Map ? otData['ot_attendance_list'] : otData) ?? []) as List;

      final leaveRem =
          (num.tryParse(info['annual_leave']?.toString() ?? '0') ?? 0) +
          (num.tryParse(info['sick_leave']?.toString() ?? '0') ?? 0) +
          (num.tryParse(info['casual_leave']?.toString() ?? '0') ?? 0);

      int otMins = 0;
      for (final o in otList) {
        otMins += int.tryParse((o as Map)['total_overtime']?.toString() ?? '0') ?? 0;
      }

      final schedData = (results[1]['data'] ?? results[1] ?? {}) as Map;
      final schedules = (schedData['schedules'] ?? {}) as Map;
      final shifts = <Map<String, dynamic>>[];
      for (final key in ['schedule1', 'schedule2', 'schedule3']) {
        final s = schedules[key];
        if (s is Map && (s['start_time']?.toString() ?? '').isNotEmpty) {
          shifts.add(Map<String, dynamic>.from(s));
        }
      }
      final alreadyIn = schedData['is_login_today']?.toString() == 'yes';

      final prefs = await SharedPreferences.getInstance();
      final localStartStr = prefs.getString('shift_start_time');
      if (localStartStr != null) {
        _localStartTime = DateTime.tryParse(localStartStr);
      }

      setState(() {
        _info = Map<String, dynamic>.from(info);
        _schedule = shifts.isNotEmpty ? shifts.first : {};
        _clockedIn = alreadyIn || _localStartTime != null;
        _leaveRemaining = leaveRem.toInt();
        _otMinutes = otMins;
        _loading = false;
      });
    } catch (_) { setState(() => _loading = false); }
  }

  Future<void> _clockIn() async {
    try {
      final s = _schedule;
      await ApiService.clockIn({
        'start_time': s['start_time']?.toString() ?? '',
        'end_time': s['end_time']?.toString() ?? '',
        'total_office_hour': s['total_office_hour']?.toString() ?? '',
        'late_in_consider_time': s['late_in_consider_time']?.toString() ?? '',
        'early_out_consider_time': s['early_out_consider_time']?.toString() ?? '',
        'office_shifts': s['office_shifts']?.toString() ?? '',
      });
      
      final now = DateTime.now();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('shift_start_time', now.toIso8601String());

      setState(() {
        _clockedIn = true;
        _localStartTime = now;
      });
      if (mounted) _toast('Clocked in! Have a great shift');
    } catch (e) { if (mounted) _toast(e.toString().replaceAll('Exception: ', ''), error: true); }
  }

  Future<void> _clockOut() async {
    try {
      await ApiService.clockOut();
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('shift_start_time');
      
      setState(() {
        _clockedIn = false;
        _localStartTime = null;
      });
      if (mounted) _toast('Clocked out');
    } catch (e) { if (mounted) _toast(e.toString().replaceAll('Exception: ', ''), error: true); }
  }

  void _toast(String msg, {bool error = false}) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg), backgroundColor: error ? AppColors.red : AppColors.green,
        behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));

  Future<void> _logout() async {
    try { await ApiService.logout(); } catch (_) {}
    await ApiService.clearAll();
    if (mounted) Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
  }

  void _push(Widget s) => Navigator.push(context, MaterialPageRoute(builder: (_) => s));

  int _toMin(String? hhmm) {
    if (hhmm == null || hhmm.isEmpty) return -1;
    final p = hhmm.split(':');
    if (p.length < 2) return -1;
    return (int.tryParse(p[0]) ?? 0) * 60 + (int.tryParse(p[1]) ?? 0);
  }

  // Fraction of today's shift elapsed (max 12 hours).
  double get _shiftProgress {
    if (!_clockedIn) return 0;
    
    // If we have a rigid API schedule, use that
    final startMin = _toMin(_schedule['start_time']?.toString());
    final endMin = _toMin(_schedule['end_time']?.toString());
    
    if (startMin >= 0 && endMin > startMin) {
      final now = TimeOfDay.now();
      final cur = now.hour * 60 + now.minute;
      return ((cur - startMin) / (endMin - startMin)).clamp(0.0, 1.0);
    }
    
    // Otherwise, use 12-hour local tracking (720 minutes max)
    if (_localStartTime != null) {
      final diffMins = DateTime.now().difference(_localStartTime!).inMinutes;
      return (diffMins / 720.0).clamp(0.0, 1.0);
    }
    
    return 0.0;
  }

  String _workedLabel() {
    if (!_clockedIn) return 'Not started';
    
    int mins = 0;
    final startMin = _toMin(_schedule['start_time']?.toString());
    
    if (startMin >= 0) {
      final now = TimeOfDay.now();
      mins = (now.hour * 60 + now.minute) - startMin;
    } else if (_localStartTime != null) {
      mins = DateTime.now().difference(_localStartTime!).inMinutes;
    }
    
    if (mins < 0) mins = 0;
    return '${mins ~/ 60}h ${(mins % 60).toString().padLeft(2, '0')}m';
  }

  @override
  Widget build(BuildContext context) {
    final name = (_info['name'] ?? 'Employee').toString().split(' ').first;
    final salary = _info['salary']?.toString() ?? '—';
    final pct = (_shiftProgress * 100).round();

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.blue))
          : RefreshIndicator(
              color: AppColors.orange,
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                children: [
                  _hero(name, pct),
                  Transform.translate(
                    offset: const Offset(0, -52),
                    child: Container(
                      decoration: const BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
                      ),
                      padding: const EdgeInsets.fromLTRB(14, 18, 14, 30),
                      child: Column(children: [
                        _statChips(salary),
                        const SizedBox(height: 18),
                        _sectionRow('Quick actions'),
                        const SizedBox(height: 10),
                        _quickActions(),
                        const SizedBox(height: 18),
                        _payslipCard(),
                        const SizedBox(height: 16),
                        Align(alignment: Alignment.centerLeft, child: _sectionRow('Recent activity')),
                        const SizedBox(height: 10),
                        _activity(),
                        const SizedBox(height: 14),
                        _logoutBtn(),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  // ── Hero ──────────────────────────────────────────────────────────────────
  Widget _hero(String name, int pct) {
    final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final now = DateTime.now();
    final days = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
    final shiftLbl = _schedule['office_shifts']?.toString() ?? '';
    final start = _schedule['start_time']?.toString() ?? '';

    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    final ss = now.second.toString().padLeft(2, '0');

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.blueHeaderTop, AppColors.blue, AppColors.blueDeep],
          stops: [0.0, 0.55, 1.0],
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(34)),
        boxShadow: [BoxShadow(color: AppColors.blueDeep.withValues(alpha: 0.35), blurRadius: 30, offset: const Offset(0, 14))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(children: [
        const Positioned.fill(child: MeshBlobs()),
        const Positioned.fill(child: HeaderSheen()),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 56, 18, 72),
          child: Column(children: [
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _shiftChip(),
              const SizedBox(height: 8),
              Text('Hi, $name 👋', style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: Colors.white)),
              Text('${days[now.weekday - 1]}, ${now.day} ${months[now.month - 1]} · $hh:$mm:$ss',
                  style: const TextStyle(fontSize: 12, color: Color(0xFFC9DAFF))),
            ])),
            ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: Container(
                  width: 38, height: 38,
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(11)),
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.power_settings_new, color: AppColors.orange, size: 18),
                    onPressed: _logout, tooltip: 'Logout',
                  ),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 18),
          Row(children: [
            LiquidDial(
              size: 122,
              progress: _shiftProgress,
              center: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('$pct%', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Colors.white)),
                Text('of shift', style: TextStyle(fontSize: 9, color: Colors.white.withValues(alpha: 0.7))),
              ]),
            ),
            const SizedBox(width: 16),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(width: 7, height: 7, decoration: BoxDecoration(color: _clockedIn ? AppColors.green : AppColors.orange, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text(_clockedIn ? 'Working' : 'Not clocked in', style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.75))),
              ]),
              const SizedBox(height: 3),
              Text(_clockedIn ? _workedLabel() : (shiftLbl.isEmpty ? 'Ready' : '$shiftLbl · $start'),
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white)),
              const SizedBox(height: 10),
              _clockBtn(),
            ])),
          ]),
        ]),
        ),
      ]),
    );
  }

  /// Orange status chip with a breathing dot — "On shift" / "Off shift".
  Widget _shiftChip() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.orange.withValues(alpha: _clockedIn ? 0.92 : 0.35),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          TweenAnimationBuilder<double>(
            key: ValueKey(DateTime.now().second.isEven),
            tween: Tween(begin: 0.3, end: 1),
            duration: const Duration(milliseconds: 900),
            builder: (_, a, __) => Container(
              width: 6, height: 6,
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: a), shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: 5),
          Text(_clockedIn ? 'On shift' : 'Off shift',
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
        ]),
      );

  Widget _clockBtn() {
    final inMode = !_clockedIn;
    return GestureDetector(
      onTap: inMode ? _clockIn : _clockOut,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.orange,
          borderRadius: BorderRadius.circular(13),
          boxShadow: [BoxShadow(color: AppColors.orange.withValues(alpha: 0.4), blurRadius: 18, offset: const Offset(0, 6))],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(inMode ? Icons.fingerprint : Icons.logout, color: Colors.white, size: 16),
          const SizedBox(width: 7),
          Text(inMode ? 'Clock in' : 'Clock out', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
        ]),
      ),
    );
  }

  // ── Content sheet pieces ────────────────────────────────────────────────
  Widget _statChips(String salary) => Row(children: [
        Expanded(child: _chip(Icons.calendar_month, AppColors.blue, AppColors.blueTint, '$_leaveRemaining', 'Leave left', (_leaveRemaining / 15).clamp(0.05, 1.0))),
        const SizedBox(width: 9),
        Expanded(child: _chip(Icons.hourglass_top, AppColors.orange, AppColors.orangeTint, '$_otMinutes', 'OT mins', (_otMinutes / 600).clamp(0.05, 1.0))),
        const SizedBox(width: 9),
        Expanded(child: _chip(Icons.payments, AppColors.green, AppColors.greenTint, '৳$salary', 'Salary', 1.0)),
      ]);

  Widget _chip(IconData icon, Color c, Color tint, String value, String label, double frac) => _card(
        padding: const EdgeInsets.all(12),
        spine: c,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(width: 32, height: 32, decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: c, size: 17)),
          const SizedBox(height: 8),
          _Counter(value: value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink)),
          Text(label, style: const TextStyle(fontSize: 10, color: AppColors.inkMuted)),
          const SizedBox(height: 8),
          // Animated meter — fills to frac on load
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: SizedBox(height: 4, child: LayoutBuilder(builder: (_, box) => Stack(children: [
              Container(color: const Color(0xFFEAF0FC)),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: frac),
                duration: const Duration(milliseconds: 1400),
                curve: Curves.easeOutCubic,
                builder: (_, f, __) => Container(
                  width: box.maxWidth * f,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [c.withValues(alpha: 0.55), c]),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ]))),
          ),
        ]),
      );

  Widget _quickActions() => Row(children: [
        _qa(Icons.event_available, 'Leave', () => _push(const LeavesScreen(initialTab: 2))),
        _qa(Icons.hourglass_bottom, 'OT', () => _push(const OvertimeScreen(initialTab: 2))),
        _qa(Icons.receipt_long, 'Payslip', () => _push(const PayrollScreen())),
        _qa(Icons.celebration, 'Holidays', () => _push(const HolidaysScreen())),
      ]);

  Widget _qa(IconData icon, String label, VoidCallback onTap) => Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.5),
          child: GestureDetector(
            onTap: onTap,
            child: _card(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Column(children: [
                Icon(icon, color: AppColors.blue, size: 20),
                const SizedBox(height: 5),
                Text(label, style: const TextStyle(fontSize: 10, color: AppColors.inkSoft)),
              ]),
            ),
          ),
        ),
      );

  Widget _payslipCard() => GestureDetector(
        onTap: () => _push(const PayrollScreen()),
        child: _card(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Container(width: 38, height: 38, decoration: BoxDecoration(color: AppColors.greenTint, borderRadius: BorderRadius.circular(11)), child: const Icon(Icons.account_balance_wallet, color: AppColors.green, size: 19)),
            const SizedBox(width: 12),
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('View latest payslip', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.ink)),
              Text('Monthly earnings & breakdown', style: TextStyle(fontSize: 11, color: AppColors.inkMuted)),
            ])),
            const Icon(Icons.chevron_right, color: Color(0xFFB6C2DA), size: 18),
          ]),
        ),
      );

  Widget _activity() => _card(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Column(children: [
          _activityRow(Icons.login, AppColors.green, AppColors.greenTint, _clockedIn ? 'Clocked in' : 'Last shift', _clockedIn ? 'Today' : 'Yesterday', _clockedIn ? 'Active' : '—', AppColors.green),
          _div(),
          _activityRow(Icons.hourglass_top, AppColors.orange, AppColors.orangeTint, 'Overtime logged', 'This month', '$_otMinutes min', AppColors.orange),
          _div(),
          _activityRow(Icons.event_available, AppColors.blue, AppColors.blueTint, 'Leave balance', 'Available', '$_leaveRemaining days', AppColors.blue, last: true),
        ]),
      );

  Widget _activityRow(IconData icon, Color c, Color tint, String title, String sub, String trail, Color trailC, {bool last = false}) => Padding(
        padding: EdgeInsets.symmetric(vertical: last ? 12 : 11),
        child: Row(children: [
          Container(width: 32, height: 32, decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: c, size: 16)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.ink)),
            Text(sub, style: const TextStyle(fontSize: 10, color: AppColors.inkMuted)),
          ])),
          Text(trail, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: trailC)),
        ]),
      );

  Widget _div() => const Divider(height: 1, color: Color(0xFFF0F3FA));

  Widget _logoutBtn() => SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          icon: const Icon(Icons.logout, color: AppColors.red, size: 18),
          label: const Text('Log out', style: TextStyle(color: AppColors.red)),
          style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0x33DC2626)), padding: const EdgeInsets.symmetric(vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          onPressed: _logout,
        ),
      );

  Widget _sectionRow(String t) => Row(children: [
        Container(width: 3, height: 14, decoration: BoxDecoration(color: AppColors.orange, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        Text(t, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.ink)),
      ]);

  Widget _card({required Widget child, EdgeInsets? padding, Color? spine}) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: spine == null ? null : Border(top: BorderSide(color: spine, width: 3)),
          boxShadow: const [BoxShadow(color: AppColors.softShadow, blurRadius: 16, offset: Offset(0, 6))],
        ),
        child: child,
      );
}

/// Counts up to a numeric value (keeps any ৳ / non-digit prefix).
class _Counter extends StatelessWidget {
  final String value;
  final TextStyle style;
  const _Counter({required this.value, required this.style});

  @override
  Widget build(BuildContext context) {
    final match = RegExp(r'(\d[\d,]*)').firstMatch(value);
    if (match == null) return Text(value, style: style);
    final prefix = value.substring(0, match.start);
    final target = int.tryParse(match.group(1)!.replaceAll(',', '')) ?? 0;
    final suffix = value.substring(match.end);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 1000),
      curve: Curves.easeOutCubic,
      builder: (_, t, __) => Text('$prefix${(target * t).round()}$suffix', style: style),
    );
  }
}
