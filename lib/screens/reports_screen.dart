import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';
import '../widgets/ui_kit.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  bool _loading = true;
  Map<String, int> _statusCounts = {};
  num _leaveUsed = 0, _leaveTotal = 0;
  int _otMinutes = 0;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final r = await Future.wait([
        ApiService.attendanceList().catchError((_) => <String, dynamic>{}),
        ApiService.myInfo().catchError((_) => <String, dynamic>{}),
        ApiService.otBalance().catchError((_) => <String, dynamic>{}),
        ApiService.leaveApps().catchError((_) => <String, dynamic>{}),
      ]);
      final records = (r[0]['data'] ?? r[0] ?? []) as List;
      final info    = (r[1]['data'] ?? r[1] ?? {}) as Map;
      final otData  = r[2]['data'];
      final ots     = (otData is Map ? otData['ot_attendance_list'] : otData) ?? [];
      final apps    = (r[3]['data'] ?? r[3] ?? []) as List;

      final counts = <String, int>{};
      for (final rec in records) {
        final m = rec as Map;
        var s = (m['day_status'] ?? m['status'] ?? 'Other').toString().trim();
        if (s.isEmpty) s = 'Other';
        s = s[0].toUpperCase() + s.substring(1).toLowerCase();
        if (s == 'Absend') s = 'Absent';
        counts[s] = (counts[s] ?? 0) + 1;
      }

      final total =
          (num.tryParse(info['annual_leave']?.toString() ?? '0') ?? 0) +
          (num.tryParse(info['sick_leave']?.toString() ?? '0') ?? 0) +
          (num.tryParse(info['casual_leave']?.toString() ?? '0') ?? 0);
      num used = 0;
      for (final a in apps) {
        if (((a as Map)['approved_at']?.toString() ?? '').isNotEmpty) used += 1;
      }

      int otMins = 0;
      for (final o in (ots as List)) {
        otMins += int.tryParse((o as Map)['total_overtime']?.toString() ?? '0') ?? 0;
      }

      setState(() {
        _statusCounts = counts;
        _leaveUsed = used; _leaveTotal = total;
        _otMinutes = otMins;
        _loading = false;
      });
    } catch (_) { setState(() => _loading = false); }
  }

  static const _palette = [AppColors.green, AppColors.red, AppColors.blue, AppColors.orange, AppColors.violet, AppColors.blueDeep];

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(backgroundColor: AppColors.surface, body: Center(child: CircularProgressIndicator(color: AppColors.blue)));
    return SheetPage(
      title: 'Reports',
      onRefresh: _load,
      children: [
        const SectionTitle('Attendance breakdown'),
        SoftCard(
          child: _statusCounts.isEmpty
              ? const SizedBox(height: 80, child: Center(child: Text('No attendance data', style: TextStyle(color: AppColors.inkMuted))))
              : SizedBox(height: 200, child: _attendanceBars()),
        ),
        const SizedBox(height: 18),
        const SectionTitle('Leave utilization'),
        SoftCard(child: SizedBox(height: 200, child: _leaveDonut())),
        const SizedBox(height: 18),
        const SectionTitle('Overtime'),
        SoftCard(child: Row(children: [
          Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: AppColors.orangeTint, borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.more_time, color: AppColors.orange)),
          const SizedBox(width: 16),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_otMinutes >= 60 ? '${_otMinutes ~/ 60}h ${_otMinutes % 60}m' : '${_otMinutes}m',
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.ink)),
            const Text('Total overtime logged', style: TextStyle(fontSize: 12, color: AppColors.inkMuted)),
          ]),
        ])),
      ],
    );
  }

  Widget _attendanceBars() {
    final entries = _statusCounts.entries.toList();
    final maxY = entries.map((e) => e.value).reduce((a, b) => a > b ? a : b).toDouble();
    return BarChart(BarChartData(
      maxY: maxY + 1,
      borderData: FlBorderData(show: false),
      gridData: const FlGridData(show: false),
      titlesData: FlTitlesData(
        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(sideTitles: SideTitles(
          showTitles: true, reservedSize: 38,
          getTitlesWidget: (v, _) {
            final i = v.toInt();
            if (i < 0 || i >= entries.length) return const SizedBox();
            return Padding(padding: const EdgeInsets.only(top: 6), child: Text(entries[i].key, style: const TextStyle(color: AppColors.inkSoft, fontSize: 10), textAlign: TextAlign.center));
          },
        )),
      ),
      barGroups: [
        for (int i = 0; i < entries.length; i++)
          BarChartGroupData(x: i, barRods: [
            BarChartRodData(toY: entries[i].value.toDouble(), color: _palette[i % _palette.length], width: 22, borderRadius: BorderRadius.circular(6)),
          ]),
      ],
    ));
  }

  Widget _leaveDonut() {
    final remaining = (_leaveTotal - _leaveUsed).clamp(0, _leaveTotal).toDouble();
    if (_leaveTotal == 0) {
      return const Center(child: Text('No leave data', style: TextStyle(color: AppColors.inkMuted)));
    }
    return Row(children: [
      Expanded(child: PieChart(PieChartData(
        sectionsSpace: 2, centerSpaceRadius: 40,
        sections: [
          PieChartSectionData(value: _leaveUsed.toDouble(), color: AppColors.orange, title: '${_leaveUsed.toInt()}', radius: 45, titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
          PieChartSectionData(value: remaining, color: AppColors.green, title: '${remaining.toInt()}', radius: 45, titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
        ],
      ))),
      const SizedBox(width: 16),
      Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
        _legend(AppColors.orange, 'Used (${_leaveUsed.toInt()})'),
        const SizedBox(height: 8),
        _legend(AppColors.green, 'Remaining (${remaining.toInt()})'),
        const SizedBox(height: 8),
        _legend(const Color(0xFFB6C2DA), 'Total (${_leaveTotal.toInt()})'),
      ]),
    ]);
  }

  Widget _legend(Color c, String t) => Row(children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 8),
        Text(t, style: const TextStyle(color: AppColors.inkSoft, fontSize: 12)),
      ]);
}
