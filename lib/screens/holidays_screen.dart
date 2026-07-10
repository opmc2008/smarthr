import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';
import '../widgets/ui_kit.dart';

class HolidaysScreen extends StatefulWidget {
  const HolidaysScreen({super.key});
  @override
  State<HolidaysScreen> createState() => _HolidaysScreenState();
}

class _HolidaysScreenState extends State<HolidaysScreen> {
  List _holidays = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try { final r = await ApiService.holidays(); setState(() { _holidays = r['data'] ?? r ?? []; _loading = false; }); }
    catch (_) { setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(backgroundColor: AppColors.surface, body: Center(child: CircularProgressIndicator(color: AppColors.blue)));
    return SheetPage(
      title: 'Holidays',
      onRefresh: _load,
      children: _holidays.isEmpty
          ? [const Padding(padding: EdgeInsets.only(top: 60), child: Center(child: Text('No holidays', style: TextStyle(color: AppColors.inkMuted))))]
          : _holidays.map((e) {
              final h = e as Map;
              final type = h['type']?.toString() ?? h['category']?.toString() ?? '';
              return SoftCard(
                margin: const EdgeInsets.only(bottom: 10),
                child: Row(children: [
                  Container(width: 44, height: 44, decoration: BoxDecoration(color: AppColors.orangeTint, borderRadius: BorderRadius.circular(13)), child: const Icon(Icons.celebration, color: AppColors.orange, size: 22)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(h['name']?.toString() ?? h['title']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.ink)),
                    const SizedBox(height: 3),
                    Text(h['date']?.toString() ?? h['holiday_date']?.toString() ?? '', style: const TextStyle(fontSize: 12, color: AppColors.inkMuted)),
                  ])),
                  if (type.isNotEmpty) SoftPill(type, AppColors.violet),
                ]),
              );
            }).toList(),
    );
  }
}
