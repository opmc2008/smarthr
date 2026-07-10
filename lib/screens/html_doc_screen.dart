import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../widgets/ui_kit.dart';

/// Generic viewer for single-record HTML content endpoints
/// (Document `/document` and Tutorial `/tutorial` — both return { text }).
class HtmlDocScreen extends StatefulWidget {
  final String title;
  final Future<Map<String, dynamic>> Function() fetch;
  const HtmlDocScreen({super.key, required this.title, required this.fetch});

  @override
  State<HtmlDocScreen> createState() => _HtmlDocScreenState();
}

class _HtmlDocScreenState extends State<HtmlDocScreen> {
  String _text = '';
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final r = await widget.fetch();
      final d = r['data'];
      setState(() {
        _text = d is Map ? _stripHtml(d['text']?.toString() ?? d['description']?.toString() ?? '') : '';
        _loading = false;
      });
    } catch (_) { setState(() => _loading = false); }
  }

  String _stripHtml(String html) => html
      .replaceAll(RegExp(r'</p>|<br\s*/?>|</li>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&nbsp;', ' ').replaceAll('&amp;', '&').replaceAll('&lt;', '<').replaceAll('&gt;', '>')
      .replaceAll(RegExp(r'\n\s*\n+'), '\n\n').trim();

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(backgroundColor: AppColors.surface, body: Center(child: CircularProgressIndicator(color: AppColors.blue)));
    return SheetPage(
      title: widget.title,
      children: _text.isEmpty
          ? [Padding(padding: const EdgeInsets.only(top: 60), child: Center(child: Text('No ${widget.title.toLowerCase()} found', style: const TextStyle(color: AppColors.inkMuted))))]
          : [SoftCard(child: Text(_text, style: const TextStyle(fontSize: 14, color: AppColors.inkSoft, height: 1.6)))],
    );
  }
}
