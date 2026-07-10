import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';
import '../widgets/ui_kit.dart';
import 'notice_detail_screen.dart';

class NoticeboardScreen extends StatefulWidget {
  const NoticeboardScreen({super.key});
  @override
  State<NoticeboardScreen> createState() => _NoticeboardScreenState();
}

class _NoticeboardScreenState extends State<NoticeboardScreen> {
  List _notices = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try { final r = await ApiService.notices(); setState(() { _notices = r['data'] ?? r ?? []; _loading = false; }); }
    catch (_) { setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(backgroundColor: AppColors.surface, body: Center(child: CircularProgressIndicator(color: AppColors.blue)));
    return SheetPage(
      title: 'Notice Board',
      onRefresh: _load,
      children: _notices.isEmpty
          ? [const Padding(padding: EdgeInsets.only(top: 60), child: Center(child: Text('No notices', style: TextStyle(color: AppColors.inkMuted))))]
          : _notices.map((e) {
              final n = e as Map;
              final id = int.tryParse(n['id']?.toString() ?? '');
              final date = (n['date']?.toString() ?? n['created_at']?.toString() ?? '').split('T').first;
              final body = n['notice']?.toString() ?? n['short_desc']?.toString() ?? n['description']?.toString() ?? '';
              return SoftCard(
                margin: const EdgeInsets.only(bottom: 12),
                onTap: id == null ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) => NoticeDetailScreen(id: id, summary: n))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(width: 38, height: 38, decoration: BoxDecoration(color: AppColors.blueTint, borderRadius: BorderRadius.circular(11)), child: const Icon(Icons.campaign, color: AppColors.blue, size: 20)),
                    const SizedBox(width: 10),
                    Expanded(child: Text(n['hedding']?.toString() ?? n['title']?.toString() ?? n['subject']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.ink))),
                    if (id != null) const Icon(Icons.chevron_right, size: 18, color: Color(0xFFB6C2DA)),
                  ]),
                  if (date.isNotEmpty)
                    Padding(padding: const EdgeInsets.only(top: 6), child: Text(date, style: const TextStyle(fontSize: 12, color: AppColors.inkMuted))),
                  if (body.isNotEmpty)
                    Padding(padding: const EdgeInsets.only(top: 8), child: Text(body.length > 120 ? '${body.substring(0, 120)}…' : body, style: const TextStyle(fontSize: 13, color: AppColors.inkSoft))),
                ]),
              );
            }).toList(),
    );
  }
}
