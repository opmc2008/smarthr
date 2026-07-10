import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';
import '../widgets/ui_kit.dart';

class NoticeDetailScreen extends StatefulWidget {
  final int id;
  final Map summary;
  const NoticeDetailScreen({super.key, required this.id, this.summary = const {}});
  @override
  State<NoticeDetailScreen> createState() => _NoticeDetailScreenState();
}

class _NoticeDetailScreenState extends State<NoticeDetailScreen> {
  Map _notice = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _notice = Map.from(widget.summary);
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await ApiService.noticeDetail(widget.id);
      setState(() { _notice = (r['data'] ?? r) as Map; _loading = false; });
    } catch (_) { setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    final title = _notice['hedding']?.toString() ?? _notice['title']?.toString() ?? _notice['subject']?.toString() ?? 'Notice';
    final date  = (_notice['date']?.toString() ?? _notice['created_at']?.toString() ?? '').split('T').first;
    final body  = _notice['notice']?.toString() ?? _notice['description']?.toString() ?? _notice['details']?.toString() ?? _notice['short_desc']?.toString() ?? _notice['body']?.toString() ?? '';

    if (_loading && body.isEmpty) return const Scaffold(backgroundColor: AppColors.surface, body: Center(child: CircularProgressIndicator(color: AppColors.blue)));
    return SheetPage(
      title: 'Notice',
      children: [
        SoftCard(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink)),
            if (date.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(children: [
                const Icon(Icons.calendar_today, size: 12, color: AppColors.inkMuted),
                const SizedBox(width: 6),
                Text(date, style: const TextStyle(fontSize: 12, color: AppColors.inkMuted)),
              ]),
            ],
            const SizedBox(height: 16),
            Text(body.isEmpty ? 'No further details.' : body, style: const TextStyle(fontSize: 14, height: 1.6, color: AppColors.inkSoft)),
          ]),
        ),
      ],
    );
  }
}
