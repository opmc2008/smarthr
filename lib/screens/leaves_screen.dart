import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';
import '../widgets/ui_kit.dart';

class LeavesScreen extends StatefulWidget {
  final int initialTab;
  const LeavesScreen({super.key, this.initialTab = 0});
  @override
  State<LeavesScreen> createState() => _LeavesScreenState();
}

class _LeavesScreenState extends State<LeavesScreen> with SingleTickerProviderStateMixin {
  late TabController _tab;
  Map _info = {};
  List _apps = [];
  bool _loading = true;

  final List<String> _leaveTypes = ['Annual Leave', 'Casual Leave', 'Sick Leave', 'Leave Without Pay'];
  String _leaveType = 'Annual Leave';
  DateTime? _fromDate, _toDate;
  final _reasonCtrl = TextEditingController();
  bool _submitting = false;
  String _msg = '';

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this, initialIndex: widget.initialTab);
    _tab.addListener(() { if (mounted) setState(() {}); });
    _load();
  }

  @override
  void dispose() { _tab.dispose(); _reasonCtrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    try {
      final r = await Future.wait([ApiService.myInfo(), ApiService.leaveApps()]);
      setState(() {
        _info = (r[0]['data'] ?? r[0]) as Map;
        _apps = r[1]['data'] ?? r[1] ?? [];
        _loading = false;
      });
    } catch (_) { setState(() => _loading = false); }
  }

  String _appStatus(Map r) {
    if ((r['rejected_at']?.toString() ?? '').isNotEmpty) return 'Rejected';
    if ((r['approved_at']?.toString() ?? '').isNotEmpty) return 'Approved';
    return 'Pending';
  }

  Future<void> _submit() async {
    if (_fromDate == null) { setState(() => _msg = 'Select a from date.'); return; }
    setState(() { _submitting = true; _msg = ''; });
    final dates = <String>[];
    final end = _toDate ?? _fromDate!;
    var cur = _fromDate!;
    while (!cur.isAfter(end)) {
      dates.add('${cur.year}-${cur.month.toString().padLeft(2,'0')}-${cur.day.toString().padLeft(2,'0')}');
      cur = cur.add(const Duration(days: 1));
    }
    try {
      await ApiService.applyLeave(_leaveType, dates, _reasonCtrl.text.trim());
      setState(() { _msg = '✓ Leave application submitted.'; _submitting = false; });
    } catch (e) {
      setState(() { _msg = e.toString().replaceAll('Exception: ', ''); _submitting = false; });
    }
  }

  String _fmtDate(DateTime? d) => d == null ? 'Select' : '${d.day}/${d.month}/${d.year}';

  String _datesOf(Map r) {
    final dl = r['date_list'] ?? r['dates'];
    if (dl is List && dl.isNotEmpty) {
      final ds = dl.map((e) => e is Map ? (e['date']?.toString() ?? '') : e.toString()).where((s) => s.isNotEmpty).toList();
      if (ds.isEmpty) return '';
      return ds.length == 1 ? ds.first : '${ds.first} → ${ds.last} (${ds.length}d)';
    }
    final from = r['from_date']?.toString() ?? r['start_date']?.toString();
    final to   = r['to_date']?.toString() ?? r['end_date']?.toString();
    if (from != null && from.isNotEmpty) return (to != null && to.isNotEmpty && to != from) ? '$from → $to' : from;
    return r['date']?.toString() ?? '';
  }

  Future<void> _pickDate(bool isFrom) async {
    final d = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2030));
    if (d != null) setState(() { if (isFrom) { _fromDate = d; } else { _toDate = d; } });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.blue))
          : ListView(padding: EdgeInsets.zero, children: [
              GradientHeader(
                title: 'Leaves', bottomPad: 66,
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
                    tabs: const [Tab(text: 'Balance'), Tab(text: 'History'), Tab(text: 'Apply')],
                  ),
                ),
              ),
              Transform.translate(
                offset: const Offset(0, -46),
                child: Container(
                  decoration: const BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
                  constraints: const BoxConstraints(minHeight: 460),
                  padding: const EdgeInsets.fromLTRB(14, 18, 14, 30),
                  child: [_balance(), _history(), _apply()][_tab.index],
                ),
              ),
            ]),
    );
  }

  Widget _balance() {
    final types = [
      ('Annual Leave', num.tryParse(_info['annual_leave']?.toString() ?? '0') ?? 0, AppColors.blue, AppColors.blueTint, Icons.beach_access),
      ('Sick Leave',   num.tryParse(_info['sick_leave']?.toString() ?? '0') ?? 0,   AppColors.red, const Color(0xFFFDE8E8), Icons.healing),
      ('Casual Leave', num.tryParse(_info['casual_leave']?.toString() ?? '0') ?? 0, AppColors.orange, AppColors.orangeTint, Icons.wb_sunny),
    ];
    final usedByType = <String, int>{};
    for (final a in _apps) {
      if (_appStatus(a as Map) == 'Approved') {
        final t = a['type']?.toString() ?? '';
        usedByType[t] = (usedByType[t] ?? 0) + 1;
      }
    }
    return Column(children: [
      for (final (name, available, color, tint, icon) in types)
        SoftCard(
          margin: const EdgeInsets.only(bottom: 12),
          child: Row(children: [
            Container(width: 44, height: 44, decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(13)), child: Icon(icon, color: color, size: 22)),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.ink, fontSize: 14)),
              if ((usedByType[name] ?? 0) > 0)
                Text('${usedByType[name]} taken this period', style: const TextStyle(fontSize: 12, color: AppColors.inkMuted)),
            ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('${available.toInt()}', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: color)),
              const Text('days', style: TextStyle(fontSize: 11, color: AppColors.inkMuted)),
            ]),
          ]),
        ),
    ]);
  }

  Widget _history() {
    if (_apps.isEmpty) return const Padding(padding: EdgeInsets.only(top: 60), child: Center(child: Text('No applications', style: TextStyle(color: AppColors.inkMuted))));
    return Column(children: _apps.map((e) {
      final r = e as Map;
      final dates = _datesOf(r);
      final st = _appStatus(r);
      return SoftCard(
        margin: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(r['type']?.toString() ?? r['leave_type']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.ink)),
            if (dates.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(children: [
                const Icon(Icons.calendar_today, size: 11, color: AppColors.inkMuted),
                const SizedBox(width: 4),
                Expanded(child: Text(dates, style: const TextStyle(fontSize: 12, color: AppColors.blue, fontWeight: FontWeight.w500))),
              ]),
            ],
            if ((r['details']?.toString() ?? r['reason']?.toString() ?? '').isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(r['details']?.toString() ?? r['reason']?.toString() ?? '', style: const TextStyle(fontSize: 12, color: AppColors.inkMuted)),
            ],
          ])),
          SoftPill(st, SoftPill.forStatus(st)),
        ]),
      );
    }).toList());
  }

  Widget _apply() {
    return SoftCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SectionTitle('Leave application'),
        const SizedBox(height: 6),
        _label('Leave type'),
        DropdownButtonFormField<String>(
          initialValue: _leaveType,
          style: const TextStyle(color: AppColors.ink),
          decoration: _dec(),
          items: _leaveTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
          onChanged: (v) => setState(() => _leaveType = v!),
        ),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _label('From'),
            OutlinedButton.icon(onPressed: () => _pickDate(true), icon: const Icon(Icons.calendar_today, size: 15, color: AppColors.blue), label: Text(_fmtDate(_fromDate), style: const TextStyle(color: AppColors.ink)), style: _dateBtn()),
          ])),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _label('To'),
            OutlinedButton.icon(onPressed: () => _pickDate(false), icon: const Icon(Icons.calendar_today, size: 15, color: AppColors.blue), label: Text(_fmtDate(_toDate), style: const TextStyle(color: AppColors.ink)), style: _dateBtn()),
          ])),
        ]),
        const SizedBox(height: 14),
        _label('Reason'),
        TextField(controller: _reasonCtrl, maxLines: 3, style: const TextStyle(color: AppColors.ink), decoration: _dec(hint: 'Describe your reason...')),
        if (_msg.isNotEmpty) ...[const SizedBox(height: 12), Text(_msg, style: TextStyle(fontSize: 13, color: _msg.startsWith('✓') ? AppColors.green : AppColors.red))],
        const SizedBox(height: 18),
        SizedBox(width: double.infinity, child: ElevatedButton(
          onPressed: _submitting ? null : _submit,
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.blue, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0),
          child: Text(_submitting ? 'Submitting…' : 'Submit application', style: const TextStyle(fontWeight: FontWeight.w600)),
        )),
      ]),
    );
  }

  Widget _label(String t) => Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(t, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.inkMuted, letterSpacing: 0.5)));

  InputDecoration _dec({String? hint}) => InputDecoration(
        hintText: hint, hintStyle: const TextStyle(color: AppColors.inkMuted),
        filled: true, fillColor: AppColors.surface, isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE0E7F5))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE0E7F5))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.blue)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      );

  ButtonStyle _dateBtn() => OutlinedButton.styleFrom(
        minimumSize: const Size(double.infinity, 48), alignment: Alignment.centerLeft,
        backgroundColor: AppColors.surface, side: const BorderSide(color: Color(0xFFE0E7F5)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      );
}
