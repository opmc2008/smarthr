import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';
import '../widgets/ui_kit.dart';

class OvertimeScreen extends StatefulWidget {
  final int initialTab;
  const OvertimeScreen({super.key, this.initialTab = 0});
  @override
  State<OvertimeScreen> createState() => _OvertimeScreenState();
}

class _OvertimeScreenState extends State<OvertimeScreen> with SingleTickerProviderStateMixin {
  late TabController _tab;
  List _otList = [];
  Map _count = {};
  List _apps = [];
  bool _loading = true;
  DateTime? _start, _end;

  String _otType = 'Extra OT';
  String? _selectedAttId;
  TimeOfDay? _startTimePicker, _endTimePicker;
  final _minutesCtrl = TextEditingController();
  final _detailsCtrl = TextEditingController();
  bool _submitting = false;
  String _msg = '';
  List _attRecords = [];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this, initialIndex: widget.initialTab);
    _tab.addListener(() { if (mounted) setState(() {}); });
    _load();
  }

  @override
  void dispose() {
    _tab.dispose(); _minutesCtrl.dispose(); _detailsCtrl.dispose();
    super.dispose();
  }

  String _iso(DateTime? d) => d == null ? '' : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await Future.wait([
        ApiService.otBalance(start: _iso(_start), end: _iso(_end)),
        ApiService.otApps(start: _iso(_start), end: _iso(_end)),
        ApiService.attendanceList(),
      ]);
      final d = r[0]['data'];
      setState(() {
        _otList = (d is Map ? d['ot_attendance_list'] : d) ?? [];
        _count = (d is Map ? d['count'] : null) ?? {};
        _apps = r[1]['data'] ?? r[1] ?? [];
        _attRecords = r[2]['data'] ?? r[2] ?? [];
        _loading = false;
      });
    } catch (_) { setState(() => _loading = false); }
  }

  Future<void> _submit() async {
    if (_selectedAttId == null || _selectedAttId!.isEmpty) { setState(() => _msg = 'Select an attendance date.'); return; }
    if (_startTimePicker == null || _endTimePicker == null) { setState(() => _msg = 'Select start and end times.'); return; }
    setState(() { _submitting = true; _msg = ''; });
    try {
      await ApiService.applyOt(_selectedAttId!, {
        'type': _otType,
        'over_time_minute': _minutesCtrl.text,
        'start_time': '${_fmtTime(_startTimePicker)}:00',
        'end_time': '${_fmtTime(_endTimePicker)}:00',
        'details': _detailsCtrl.text,
      });
      setState(() { _msg = '✓ OT request submitted.'; _submitting = false; });
    } catch (e) {
      setState(() { _msg = e.toString().replaceAll('Exception: ', ''); _submitting = false; });
    }
  }

  String _status(Map r) {
    if ((r['rejected_at']?.toString() ?? '').isNotEmpty) return 'Rejected';
    if ((r['approved_at']?.toString() ?? '').isNotEmpty) return 'Approved';
    return 'Pending';
  }

  String _date(dynamic v) => (v?.toString() ?? '').split(' ').first.split('T').first;

  bool _flag(Map r, String key) {
    final v = r[key]?.toString().trim().toLowerCase() ?? '';
    return v == '1' || v == 'true' || v == 'yes';
  }

  num _n(Map r, String k) => num.tryParse(r[k]?.toString() ?? '0') ?? 0;

  int get _totalMins => _otList.fold(0, (sum, o) => sum + _n(o as Map, 'total_overtime').toInt());

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(backgroundColor: AppColors.surface, body: Center(child: CircularProgressIndicator(color: AppColors.blue)));
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: ListView(padding: EdgeInsets.zero, children: [
        GradientHeader(
          title: 'Over Time', bottomPad: 64,
          child: Column(children: [
            Row(children: [
              _headStat('${_n(_count, 'Early In OT').toInt()}', 'Early In'),
              const SizedBox(width: 8),
              _headStat('${_n(_count, 'Late Out OT').toInt()}', 'Late Out'),
              const SizedBox(width: 8),
              _headStat('${_n(_count, 'Extra OT').toInt()}', 'Extra'),
              const SizedBox(width: 8),
              _headStat('$_totalMins', 'Total min', accent: true),
            ]),
            const SizedBox(height: 14),
            Container(
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(14)),
              child: TabBar(
                controller: _tab,
                indicator: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                labelColor: AppColors.blueDeep,
                unselectedLabelColor: Colors.white,
                labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                tabs: const [Tab(text: 'My OT'), Tab(text: 'History'), Tab(text: 'Apply')],
              ),
            ),
          ]),
        ),
        Transform.translate(
          offset: const Offset(0, -46),
          child: Container(
            decoration: const BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
            constraints: const BoxConstraints(minHeight: 440),
            padding: const EdgeInsets.fromLTRB(14, 18, 14, 30),
            child: [_balance(), _history(), _apply()][_tab.index],
          ),
        ),
      ]),
    );
  }

  Widget _headStat(String value, String label, {bool accent = false}) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(color: accent ? AppColors.orange : Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(13)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
            Text(label, style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.85))),
          ]),
        ),
      );

  Widget _balance() => Column(children: [
        _dateFilter(),
        const SizedBox(height: 14),
        if (_otList.isEmpty)
          const Padding(padding: EdgeInsets.only(top: 40), child: Center(child: Text('No OT records', style: TextStyle(color: AppColors.inkMuted))))
        else
          ..._otList.map((o) => _otCard(o as Map)),
      ]);

  Widget _otCard(Map r) {
    final isWeekend = _flag(r, 'is_weekend');
    final isHoliday = _flag(r, 'is_holiday');
    final isLeave   = _flag(r, 'is_leave');
    final isHalf    = _flag(r, 'is_half_day');
    final dayStatus = r['day_status']?.toString() ?? '—';
    final otMins    = _n(r, 'total_overtime').toInt();
    final otAmt     = _n(r, 'overtime_amount');
    final holidayNm = r['holiday']?.toString() ?? '';
    final leaveType = r['leave_type']?.toString() ?? '';

    return SoftCard(
      margin: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 42, height: 42, decoration: BoxDecoration(color: AppColors.orangeTint, borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.hourglass_top, color: AppColors.orange, size: 20)),
          const SizedBox(width: 12),
          Expanded(child: Text(_date(r['date'] ?? r['created_at']), style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink, fontSize: 14))),
          SoftPill(dayStatus, SoftPill.forStatus(dayStatus)),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: [
          _tag(isHalf ? 'Half Day' : 'Full Day', AppColors.blue),
          if (isWeekend) _tag('Weekend', AppColors.violet),
          if (isHoliday) _tag(holidayNm.isNotEmpty ? 'Holiday: $holidayNm' : 'Holiday', AppColors.violet),
          if (isLeave) _tag(leaveType.isNotEmpty ? leaveType : 'Leave', AppColors.orange),
          if (otMins > 0) _tag('$otMins min OT', AppColors.orange),
          if (otAmt > 0) _tag('৳${otAmt.toStringAsFixed(0)}', AppColors.green),
        ]),
      ]),
    );
  }

  Widget _history() => Column(children: [
        _dateFilter(),
        const SizedBox(height: 14),
        if (_apps.isEmpty)
          const Padding(padding: EdgeInsets.only(top: 40), child: Center(child: Text('No applications', style: TextStyle(color: AppColors.inkMuted))))
        else
          ..._apps.map((e) {
            final r = e as Map;
            final st = _status(r);
            return SoftCard(
              margin: const EdgeInsets.only(bottom: 10),
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(r['type']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.ink)),
                  const SizedBox(height: 2),
                  Text('${r['over_time_minute'] ?? '—'} min  •  ${_date(r['date'])}', style: const TextStyle(fontSize: 12, color: AppColors.inkMuted)),
                  if ((r['details']?.toString() ?? '').isNotEmpty)
                    Text(r['details'].toString(), style: const TextStyle(fontSize: 12, color: AppColors.inkMuted)),
                ])),
                SoftPill(st, SoftPill.forStatus(st)),
              ]),
            );
          }),
      ]);

  Widget _dateFilter() => SoftCard(
        child: Column(children: [
          Row(children: [
            Expanded(child: _dateBox('Start Date', _start, true)),
            const SizedBox(width: 10),
            Expanded(child: _dateBox('End Date', _end, false)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: ElevatedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.search, size: 16),
              label: const Text('Search'),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.blue, foregroundColor: Colors.white, elevation: 0, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            )),
            const SizedBox(width: 10),
            Expanded(child: OutlinedButton.icon(
              onPressed: () { setState(() { _start = null; _end = null; }); _load(); },
              icon: const Icon(Icons.clear, size: 16, color: AppColors.inkSoft),
              label: const Text('Clear', style: TextStyle(color: AppColors.inkSoft)),
              style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFFE0E7F5)), padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            )),
          ]),
        ]),
      );

  Widget _dateBox(String label, DateTime? value, bool isStart) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.inkMuted, letterSpacing: 0.5)),
        const SizedBox(height: 6),
        OutlinedButton(
          onPressed: () async {
            final d = await showDatePicker(context: context, initialDate: value ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2030));
            if (d != null) {
              setState(() {
                if (isStart) { _start = d; } else { _end = d; }
              });
            }
          },
          style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 44), alignment: Alignment.centerLeft, backgroundColor: AppColors.surface, side: const BorderSide(color: Color(0xFFE0E7F5)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
          child: Text(value == null ? 'mm/dd/yyyy' : _iso(value), style: TextStyle(color: value == null ? AppColors.inkMuted : AppColors.ink, fontSize: 13)),
        ),
      ]);

  Widget _apply() => SoftCard(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SectionTitle('OT application'),
          const SizedBox(height: 6),
          _label('OT type'),
          DropdownButtonFormField<String>(
            initialValue: _otType,
            style: const TextStyle(color: AppColors.ink),
            decoration: _dec(),
            items: ['Early In OT', 'Late Out OT', 'Extra OT'].map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
            onChanged: (v) => setState(() => _otType = v!),
          ),
          const SizedBox(height: 14),
          _label('Attendance Date'),
          DropdownButtonFormField<String>(
            value: _selectedAttId,
            style: const TextStyle(color: AppColors.ink),
            decoration: _dec(hint: 'Select a date you worked'),
            items: _attRecords.map((r) {
              final m = r as Map;
              final id = m['my_att_id']?.toString() ?? m['att_id']?.toString() ?? m['attendance_id']?.toString() ?? m['id']?.toString() ?? '';
              final date = _date(m['date'] ?? m['attendance_date'] ?? m['created_at']);
              return DropdownMenuItem(value: id, child: Text(date.isEmpty ? 'ID #$id' : '$date (ID #$id)'));
            }).where((item) => item.value != null && item.value!.isNotEmpty).toList(),
            onChanged: (v) => setState(() => _selectedAttId = v),
          ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _label('Start time'),
              OutlinedButton.icon(
                onPressed: () => _pickTime(true), 
                icon: const Icon(Icons.schedule, size: 15, color: AppColors.blue), 
                label: Text(_fmtTime(_startTimePicker), style: const TextStyle(color: AppColors.ink)), 
                style: _btnStyle()
              ),
            ])),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _label('End time'),
              OutlinedButton.icon(
                onPressed: () => _pickTime(false), 
                icon: const Icon(Icons.schedule, size: 15, color: AppColors.blue), 
                label: Text(_fmtTime(_endTimePicker), style: const TextStyle(color: AppColors.ink)), 
                style: _btnStyle()
              ),
            ])),
          ]),
          const SizedBox(height: 14),
          _label('OT minutes'),
          TextField(controller: _minutesCtrl, keyboardType: TextInputType.number, style: const TextStyle(color: AppColors.ink), decoration: _dec(hint: 'e.g. 60')),
          const SizedBox(height: 14),
          _label('Details'),
          TextField(controller: _detailsCtrl, maxLines: 3, style: const TextStyle(color: AppColors.ink), decoration: _dec(hint: 'Describe the work done...')),
          if (_msg.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(_msg, style: TextStyle(fontSize: 13, color: _msg.startsWith('✓') ? AppColors.green : AppColors.red)),
          ],
          const SizedBox(height: 18),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: _submitting ? null : _submit,
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.orange, foregroundColor: Colors.white, elevation: 0, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: Text(_submitting ? 'Submitting…' : 'Submit OT request', style: const TextStyle(fontWeight: FontWeight.w600)),
          )),
        ]),
      );

  Widget _tag(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
        child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
      );

  Widget _label(String t) => Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(t, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.inkMuted, letterSpacing: 0.5)));

  InputDecoration _dec({String? hint}) => InputDecoration(
        hintText: hint, hintStyle: const TextStyle(color: AppColors.inkMuted),
        filled: true, fillColor: AppColors.surface, isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE0E7F5))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE0E7F5))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.blue)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      );

  String _fmtTime(TimeOfDay? t) {
    if (t == null) return 'HH:MM';
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }
  
  Future<void> _pickTime(bool isStart) async {
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (t != null) setState(() { if (isStart) { _startTimePicker = t; } else { _endTimePicker = t; } });
  }
  
  ButtonStyle _btnStyle() => OutlinedButton.styleFrom(
    minimumSize: const Size(double.infinity, 48), alignment: Alignment.centerLeft,
    backgroundColor: AppColors.surface, side: const BorderSide(color: Color(0xFFE0E7F5)),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
  );
}
