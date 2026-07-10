import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';
import '../widgets/ui_kit.dart';

class AdvanceSalaryScreen extends StatefulWidget {
  const AdvanceSalaryScreen({super.key});
  @override
  State<AdvanceSalaryScreen> createState() => _AdvanceSalaryScreenState();
}

class _AdvanceSalaryScreenState extends State<AdvanceSalaryScreen> {
  List _items = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final r = await ApiService.advanceSalary();
      setState(() { _items = r['data'] ?? r ?? []; _loading = false; });
    } catch (_) { setState(() => _loading = false); }
  }

  String _fmt(num v) => '৳${v.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}';
  num _n(Map m, String k) => num.tryParse(m[k]?.toString() ?? '0') ?? 0;
  String _date(dynamic v) => (v?.toString() ?? '').split(' ').first.split('T').first;

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(backgroundColor: AppColors.surface, body: Center(child: CircularProgressIndicator(color: AppColors.blue)));
    return SheetPage(
      title: 'Advance Salary',
      onRefresh: _load,
      children: _items.isEmpty
          ? [const Padding(padding: EdgeInsets.only(top: 60), child: Center(child: Text('No advance salary records', style: TextStyle(color: AppColors.inkMuted))))]
          : _items.map((e) {
              final m = e as Map;
              final paid = m['status']?.toString() == '1' || m['status']?.toString().toLowerCase() == 'paid';
              return SoftCard(
                margin: const EdgeInsets.only(bottom: 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text(_fmt(_n(m, 'amount')), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.green)),
                    SoftPill(paid ? 'Paid' : 'Pending', paid ? AppColors.green : AppColors.orange),
                  ]),
                  const SizedBox(height: 8),
                  if (_date(m['payment_date']).isNotEmpty) _row('Payment date', _date(m['payment_date'])),
                  if (_date(m['created_at']).isNotEmpty) _row('Requested', _date(m['created_at'])),
                  if ((m['details']?.toString() ?? '').isNotEmpty)
                    Padding(padding: const EdgeInsets.only(top: 6), child: Text(m['details'].toString(), style: const TextStyle(fontSize: 13, color: AppColors.inkSoft))),
                ]),
              );
            }).toList(),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.inkMuted)),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.ink)),
        ]),
      );
}
