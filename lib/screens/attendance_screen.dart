import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';
import '../widgets/ui_kit.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});
  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> with SingleTickerProviderStateMixin {
  late TabController _tab;
  List _records = [], _apps = [];
  bool _loading = true;
  DateTime? _start, _end;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _tab.addListener(() { if (mounted) setState(() {}); });
    _load();
  }

  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  String _iso(DateTime? d) => d == null ? '' : '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await Future.wait([
        ApiService.attendanceList(start: _iso(_start), end: _iso(_end)),
        ApiService.attendanceApps(start: _iso(_start), end: _iso(_end)),
      ]);
      setState(() {
        _records = r[0]['data'] ?? r[0] ?? [];
        _apps = r[1]['data'] ?? r[1] ?? [];
        _loading = false;
      });
    } catch (_) { setState(() => _loading = false); }
  }

  String _v(Map r, List<String> keys, [String fallback = '']) {
    for (final k in keys) {
      final val = r[k];
      if (val != null && val.toString().trim().isNotEmpty) return val.toString();
    }
    return fallback;
  }

  bool _flag(Map r, List<String> keys) {
    final v = _v(r, keys).toLowerCase().trim();
    return v == 'yes' || v == '1' || v == 'true';
  }

  String _appStatus(Map r) {
    if ((r['rejected_at']?.toString() ?? '').isNotEmpty) return 'Rejected';
    if ((r['approved_at']?.toString() ?? '').isNotEmpty) return 'Approved';
    return 'Pending';
  }

  String _fmt(String? d) {
    if (d == null || d.isEmpty) return '—';
    try { final dt = DateTime.parse(d); return '${dt.day} ${['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][dt.month-1]} ${dt.year}'; }
    catch (_) { return d.length > 10 ? d.substring(0, 10) : d; }
  }

  @override
  Widget build(BuildContext context) {
    final present = _records.where((r) => _v(r as Map, ['day_status','status']).toLowerCase() == 'present').length;
    final lateIn = _records.where((r) => _flag(r as Map, ['is_late_in', 'late_in'])).length;
    final absent = _records.where((r) => _v(r as Map, ['day_status','status']).toLowerCase().contains('absen')).length;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.blue))
          : ListView(padding: EdgeInsets.zero, children: [
              GradientHeader(
                title: 'Attendance', showBack: false, bottomPad: 64,
                child: Column(children: [
                  Row(children: [
                    _headStat('$present', 'Present', false),
                    const SizedBox(width: 10),
                    _headStat('$lateIn', 'Late in', false),
                    const SizedBox(width: 10),
                    _headStat('$absent', 'Absent', true),
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
                      tabs: const [Tab(text: 'My Attendance'), Tab(text: 'Applications')],
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
                  child: _tab.index == 0 ? _records0() : _apps0(),
                ),
              ),
            ]),
    );
  }

  Widget _headStat(String value, String label, bool accent) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 12),
          decoration: BoxDecoration(color: accent ? AppColors.orange : Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(14)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700, color: Colors.white)),
            Text(label, style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.85))),
          ]),
        ),
      );

  Widget _records0() {
    return Column(children: [
      if (_records.length >= 3) ...[_weekBars(), const SizedBox(height: 14)],
      _dateFilter(),
      const SizedBox(height: 14),
      if (_records.isEmpty)
        const Padding(padding: EdgeInsets.only(top: 40), child: Center(child: Text('No records', style: TextStyle(color: AppColors.inkMuted))))
      else
        ..._records.map((rec) => _recordCard(rec as Map)),
    ]);
  }

  /// "Weekly hours" bar chart from the most recent records — blue full days,
  /// orange short/late days, greyed absents; weekday labels below.
  Widget _weekBars() {
    final recent = _records.take(7).toList().reversed.toList();
    const wd = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];

    double heightFor(Map r) {
      final s = _v(r, ['day_status', 'status']).toLowerCase();
      if (s.contains('absen')) return 0.12;
      if (_flag(r, ['is_half_day'])) return 0.5;
      if (_flag(r, ['is_late_in', 'late_in']) || _flag(r, ['is_early_out', 'early_out'])) return 0.65;
      if (s.contains('present')) return 0.95;
      return 0.35;
    }

    Color colorFor(Map r) {
      final s = _v(r, ['day_status', 'status']).toLowerCase();
      if (s.contains('absen')) return const Color(0xFFD5DEF2);
      if (_flag(r, ['is_half_day']) || _flag(r, ['is_late_in', 'late_in']) || _flag(r, ['is_early_out', 'early_out'])) return AppColors.orange;
      return AppColors.blue;
    }

    String labelFor(Map r) {
      final d = _v(r, ['date', 'attendance_date', 'created_at']);
      try { return wd[DateTime.parse(d).weekday - 1]; } catch (_) { return ''; }
    }

    return SoftCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Weekly hours', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.ink)),
          Row(children: [
            _legendDot(AppColors.blue, 'Full day'),
            const SizedBox(width: 10),
            _legendDot(AppColors.orange, 'Short'),
          ]),
        ]),
        const SizedBox(height: 10),
        SizedBox(
          height: 66,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < recent.length; i++) ...[
                if (i > 0) const SizedBox(width: 7),
                Expanded(child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: heightFor(recent[i] as Map)),
                  duration: Duration(milliseconds: 600 + i * 100),
                  curve: Curves.easeOutBack,
                  builder: (_, h, __) => Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      height: 66 * h.clamp(0.0, 1.0),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter, end: Alignment.bottomCenter,
                          colors: [colorFor(recent[i] as Map).withValues(alpha: 0.75), colorFor(recent[i] as Map)],
                        ),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(6), bottom: Radius.circular(3)),
                      ),
                      width: double.infinity,
                    ),
                  ),
                )),
              ],
            ],
          ),
        ),
        const SizedBox(height: 6),
        Row(children: [
          for (var i = 0; i < recent.length; i++) ...[
            if (i > 0) const SizedBox(width: 7),
            Expanded(child: Text(labelFor(recent[i] as Map), textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 9, color: Color(0xFF9DAEDA), fontWeight: FontWeight.w600))),
          ],
        ]),
      ]),
    );
  }

  Widget _legendDot(Color c, String t) => Row(children: [
        Container(width: 7, height: 7, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 4),
        Text(t, style: const TextStyle(fontSize: 9, color: AppColors.inkMuted)),
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
            if (d != null) setState(() { if (isStart) { _start = d; } else { _end = d; } });
          },
          style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 44), alignment: Alignment.centerLeft, backgroundColor: AppColors.surface, side: const BorderSide(color: Color(0xFFE0E7F5)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
          child: Text(value == null ? 'mm/dd/yyyy' : _iso(value), style: TextStyle(color: value == null ? AppColors.inkMuted : AppColors.ink, fontSize: 13)),
        ),
      ]);

  Widget _recordCard(Map r) {
    final rawId     = _v(r, ['my_att_id', 'att_id', 'attendance_id', 'id']);
    final id        = rawId.isEmpty ? '' : rawId.padLeft(6, '0');
    final date      = _v(r, ['date', 'attendance_date', 'created_at']);
    final inTime    = _v(r, ['time_in', 'in_time', 'clock_in'], '—');
    final outTime   = _v(r, ['time_out', 'out_time', 'clock_out'], '—');
    final dayStatus = _v(r, ['day_status', 'status'], '—');
    final isHalf    = _flag(r, ['is_half_day']);
    final isWeekend = _flag(r, ['is_weekend', 'weekend']);
    final isHoliday = _flag(r, ['is_holiday']);
    final isLeave   = _flag(r, ['is_leave', 'leave']);
    final holidayNm = _v(r, ['holiday']);
    final leaveType = _v(r, ['leave_type']);
    final isLateIn  = _flag(r, ['is_late_in', 'late_in']);
    final isEarlyOut= _flag(r, ['is_early_out', 'early_out']);
    final officeHr  = _v(r, ['total_office_hour']);
    final statusColor = SoftPill.forStatus(dayStatus);

    return SoftCard(
      margin: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 46, height: 46, decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(13)), child: Icon(_iconFor(dayStatus), color: statusColor, size: 22)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_fmt(date), style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink, fontSize: 14)),
            if (id.isNotEmpty) Text('ID #$id', style: const TextStyle(fontSize: 11, color: AppColors.inkMuted)),
          ])),
          SoftPill(dayStatus, statusColor),
          if (rawId.isNotEmpty && !isWeekend && !isHoliday) ...[
            const SizedBox(width: 2),
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              icon: const Icon(Icons.more_horiz, size: 20, color: AppColors.inkMuted),
              tooltip: 'Request correction',
              onPressed: () => _showActions(rawId),
            ),
          ],
        ]),
        if (inTime != '—' || outTime != '—') ...[
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _timeChip(Icons.login, 'In', inTime, AppColors.green)),
            const SizedBox(width: 8),
            Expanded(child: _timeChip(Icons.logout, 'Out', outTime, AppColors.orange)),
          ]),
        ],
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: [
          _tag(isHalf ? 'Half Day' : 'Full Day', AppColors.blue),
          if (officeHr.isNotEmpty && officeHr != '0') _tag('${officeHr}h', AppColors.blueDeep),
          if (isWeekend) _tag('Weekend', AppColors.violet),
          if (isHoliday) _tag(holidayNm.isNotEmpty ? 'Holiday: $holidayNm' : 'Holiday', AppColors.violet),
          if (isLeave) _tag(leaveType.isNotEmpty ? leaveType : 'Leave', AppColors.orange),
          if (isLateIn) _tag('Late In', AppColors.red),
          if (isEarlyOut) _tag('Early Out', AppColors.violet),
        ]),
      ]),
    );
  }

  IconData _iconFor(String status) {
    final s = status.toLowerCase();
    if (s.contains('absen')) return Icons.event_busy;
    if (s.contains('present')) return Icons.check_circle_outline;
    if (s.contains('weekend') || s.contains('holiday')) return Icons.weekend;
    return Icons.calendar_today;
  }

  Widget _timeChip(IconData icon, String label, String value, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text('$label  ', style: const TextStyle(fontSize: 11, color: AppColors.inkMuted)),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink)),
        ]),
      );

  Widget _tag(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
        child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
      );

  // ── Correction requests ──────────────────────────────────────────────────
  void _showActions(String attId) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 12),
        Container(width: 40, height: 4, decoration: BoxDecoration(color: const Color(0xFFE0E7F5), borderRadius: BorderRadius.circular(2))),
        const Padding(padding: EdgeInsets.all(16), child: Text('Request Correction', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.ink))),
        _actionTile(Icons.login, 'Modify In Time', AppColors.green, () { Navigator.pop(context); _timeModifyForm(attId, 'In Time Modify'); }),
        _actionTile(Icons.logout, 'Modify Out Time', AppColors.orange, () { Navigator.pop(context); _timeModifyForm(attId, 'Out Time Modify'); }),
        _actionTile(Icons.schedule, 'Late In Excuse', AppColors.red, () { Navigator.pop(context); _excuseForm(attId, 'Late In'); }),
        _actionTile(Icons.run_circle_outlined, 'Early Out Excuse', AppColors.violet, () { Navigator.pop(context); _excuseForm(attId, 'Early Out'); }),
        const SizedBox(height: 12),
      ])),
    );
  }

  Widget _actionTile(IconData icon, String label, Color color, VoidCallback onTap) => ListTile(
        leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: color, size: 20)),
        title: Text(label, style: const TextStyle(color: AppColors.ink, fontSize: 14)),
        onTap: onTap,
      );

  Future<void> _timeModifyForm(String attId, String type) async {
    final timeNotifier = ValueNotifier<TimeOfDay?>(null);
    final detailsCtrl = TextEditingController();
    await _requestDialog(
      title: type,
      fields: [_timeField('New Time', timeNotifier), _dialogField('Reason', detailsCtrl, hint: 'Why the correction?', lines: 2)],
      onSubmit: () async {
        if (timeNotifier.value == null) throw Exception('Select a time.');
        await ApiService.applyTimeModify(attId, type, '${_fmtTime(timeNotifier.value)}:00', detailsCtrl.text.trim());
      },
    );
    timeNotifier.dispose();
  }

  Future<void> _excuseForm(String attId, String type) async {
    final detailsCtrl = TextEditingController();
    await _requestDialog(
      title: '$type Excuse',
      fields: [_dialogField('Reason', detailsCtrl, hint: 'Explain the reason...', lines: 3)],
      onSubmit: () => ApiService.applyLateInEarlyOut(attId, type, detailsCtrl.text.trim()),
    );
  }

  Widget _dialogField(String label, TextEditingController ctrl, {String? hint, int lines = 1}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.inkMuted, letterSpacing: 0.5)),
          const SizedBox(height: 6),
          TextField(controller: ctrl, maxLines: lines, style: const TextStyle(color: AppColors.ink),
            decoration: InputDecoration(hintText: hint, hintStyle: const TextStyle(color: AppColors.inkMuted), isDense: true, filled: true, fillColor: AppColors.surface,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE0E7F5))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE0E7F5))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.blue)))),
        ]),
      );

  Widget _timeField(String label, ValueNotifier<TimeOfDay?> timeNotifier) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.inkMuted, letterSpacing: 0.5)),
          const SizedBox(height: 6),
          ValueListenableBuilder<TimeOfDay?>(
            valueListenable: timeNotifier,
            builder: (context, time, _) => OutlinedButton.icon(
              onPressed: () async {
                final t = await showTimePicker(context: context, initialTime: time ?? TimeOfDay.now());
                if (t != null) timeNotifier.value = t;
              },
              icon: const Icon(Icons.schedule, size: 15, color: AppColors.blue),
              label: Text(_fmtTime(time), style: const TextStyle(color: AppColors.ink)),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 44), alignment: Alignment.centerLeft,
                backgroundColor: AppColors.surface, side: const BorderSide(color: Color(0xFFE0E7F5)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ]),
      );

  String _fmtTime(TimeOfDay? t) {
    if (t == null) return 'Select time';
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _requestDialog({required String title, required List<Widget> fields, required Future<void> Function() onSubmit}) async {
    bool submitting = false;
    String err = '';
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSt) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text(title, style: const TextStyle(color: AppColors.ink, fontSize: 16)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          ...fields,
          if (err.isNotEmpty) Text(err, style: const TextStyle(color: AppColors.red, fontSize: 12)),
        ]),
        actions: [
          TextButton(onPressed: submitting ? null : () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: AppColors.inkMuted))),
          ElevatedButton(
            onPressed: submitting ? null : () async {
              setSt(() { submitting = true; err = ''; });
              try {
                await onSubmit();
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Request submitted'), backgroundColor: AppColors.green));
                  _load();
                }
              } catch (e) {
                setSt(() { submitting = false; err = e.toString().replaceAll('Exception: ', ''); });
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.blue, foregroundColor: Colors.white, elevation: 0),
            child: Text(submitting ? 'Submitting…' : 'Submit'),
          ),
        ],
      )),
    );
  }

  Widget _apps0() {
    if (_apps.isEmpty) return const Padding(padding: EdgeInsets.only(top: 60), child: Center(child: Text('No applications', style: TextStyle(color: AppColors.inkMuted))));
    return Column(children: _apps.map((e) {
      final r = e as Map;
      final st = _appStatus(r);
      return SoftCard(
        margin: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(r['type']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.ink)),
            const SizedBox(height: 4),
            Text(_fmt(r['date']?.toString()), style: const TextStyle(fontSize: 12, color: AppColors.inkMuted)),
            if ((r['details']?.toString() ?? '').isNotEmpty) Text(r['details'].toString(), style: const TextStyle(fontSize: 12, color: AppColors.inkMuted)),
          ])),
          SoftPill(st, SoftPill.forStatus(st)),
        ]),
      );
    }).toList());
  }
}
