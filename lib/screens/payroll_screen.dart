import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../widgets/ui_kit.dart';
import '../services/api_service.dart';

class PayrollScreen extends StatefulWidget {
  const PayrollScreen({super.key});
  @override
  State<PayrollScreen> createState() => _PayrollScreenState();
}

class _PayrollScreenState extends State<PayrollScreen> with SingleTickerProviderStateMixin {
  late TabController _tab;
  List _all = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _tab.addListener(() { if (mounted) setState(() {}); });
    _load();
  }
  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  Future<void> _load() async {
    try {
      final r = await ApiService.payrollList();
      setState(() { _all = r['data'] ?? r ?? []; _loading = false; });
    } catch (_) { setState(() => _loading = false); }
  }

  String _fmt(num v) => '৳${v.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}';
  num _n(Map p, String k) => num.tryParse(p[k]?.toString() ?? '0') ?? 0;
  String _month(Map p) => '${p['month'] ?? ''} ${p['year'] ?? ''}'.trim();
  String _payStatus(Map p) => (p['status']?.toString() == '1') ? 'Paid' : 'Pending';
  num _net(Map p) =>
      _n(p, 'salary') + _n(p, 'commission') + _n(p, 'extra_day_amount') +
      _n(p, 'eid_bonus') + _n(p, 'over_time_amount') + _n(p, 'night_shift') +
      _n(p, 'mobile_recharge') + _n(p, 'adjustment');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.blue))
          : ListView(padding: EdgeInsets.zero, children: [
              GradientHeader(
                title: 'Payroll',
                bottomPad: 66,
                child: Container(
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(14)),
                  child: TabBar(
                    controller: _tab,
                    indicator: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                    indicatorSize: TabBarIndicatorSize.tab,
                    dividerColor: Colors.transparent,
                    labelColor: AppColors.blueDeep,
                    unselectedLabelColor: Colors.white,
                    labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                    tabs: const [Tab(text: 'Current'), Tab(text: 'Last'), Tab(text: 'All')],
                  ),
                ),
              ),
              Transform.translate(
                offset: const Offset(0, -46),
                child: Container(
                  decoration: const BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
                  constraints: const BoxConstraints(minHeight: 460),
                  padding: const EdgeInsets.fromLTRB(14, 18, 14, 30),
                  child: [
                    _slip(_all.isNotEmpty ? _all[0] as Map : null),
                    _slip(_all.length > 1 ? _all[1] as Map : null),
                    _allList(),
                  ][_tab.index],
                ),
              ),
            ]),
    );
  }

  Widget _slip(Map? p) {
    if (p == null) return const Padding(padding: EdgeInsets.only(top: 60), child: Center(child: Text('No data', style: TextStyle(color: AppColors.inkMuted))));
    final adj = _n(p, 'adjustment');
    return Column(children: [
      SoftCard(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Net pay', style: TextStyle(fontSize: 12, color: AppColors.inkMuted)),
              Text(_month(p), style: const TextStyle(fontSize: 12, color: AppColors.inkSoft)),
            ]),
            SoftPill(_payStatus(p), SoftPill.forStatus(_payStatus(p))),
          ]),
          const SizedBox(height: 8),
          Text(_fmt(_net(p)), style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: AppColors.ink)),
        ]),
      ),
      const SizedBox(height: 14),
      const Align(alignment: Alignment.centerLeft, child: SectionTitle('Breakdown')),
      SoftCard(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(children: [
          _row('Basic salary', _fmt(_n(p, 'salary'))),
          if (_n(p, 'over_time_amount') != 0) _row('Over time', '+${_fmt(_n(p, 'over_time_amount'))}', AppColors.green),
          if (_n(p, 'commission') != 0) _row('Commission', '+${_fmt(_n(p, 'commission'))}', AppColors.green),
          if (_n(p, 'extra_day_amount') != 0) _row('Extra days', '+${_fmt(_n(p, 'extra_day_amount'))}', AppColors.green),
          if (_n(p, 'eid_bonus') != 0) _row('Eid bonus', '+${_fmt(_n(p, 'eid_bonus'))}', AppColors.green),
          if (_n(p, 'night_shift') != 0) _row('Night shift', '+${_fmt(_n(p, 'night_shift'))}', AppColors.green),
          if (_n(p, 'mobile_recharge') != 0) _row('Mobile recharge', '+${_fmt(_n(p, 'mobile_recharge'))}', AppColors.green),
          if (adj != 0) _row('Adjustment', '${adj < 0 ? '-' : '+'}${_fmt(adj.abs())}', adj < 0 ? AppColors.red : AppColors.green, true),
        ]),
      ),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(16)),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Take-home', style: TextStyle(color: Color(0xFFAFC1E6), fontSize: 14)),
          Text(_fmt(_net(p)), style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
        ]),
      ),
    ]);
  }

  Widget _allList() {
    if (_all.isEmpty) return const Padding(padding: EdgeInsets.only(top: 60), child: Center(child: Text('No records', style: TextStyle(color: AppColors.inkMuted))));
    return Column(children: _all.map((e) {
      final p = e as Map;
      return SoftCard(
        margin: const EdgeInsets.only(bottom: 10),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(
          backgroundColor: AppColors.surface,
          appBar: AppBar(backgroundColor: AppColors.blue, foregroundColor: Colors.white, title: Text(_month(p).isEmpty ? 'Pay Slip' : _month(p))),
          body: ListView(padding: const EdgeInsets.all(14), children: [_slip(p)]),
        ))),
        child: Row(children: [
          Container(width: 40, height: 40, decoration: BoxDecoration(color: AppColors.greenTint, borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.receipt_long, color: AppColors.green, size: 20)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_month(p), style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.ink)),
            Text(_fmt(_net(p)), style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.green, fontSize: 13)),
          ])),
          SoftPill(_payStatus(p), SoftPill.forStatus(_payStatus(p))),
          const Icon(Icons.chevron_right, size: 18, color: Color(0xFFB6C2DA)),
        ]),
      );
    }).toList());
  }

  Widget _row(String label, String value, [Color? color, bool last = false]) => Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(border: last ? null : const Border(bottom: BorderSide(color: Color(0xFFF0F3FA)))),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: const TextStyle(fontSize: 13, color: AppColors.inkSoft)),
          Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color ?? AppColors.ink)),
        ]),
      );
}
