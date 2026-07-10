import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';
import '../widgets/ui_kit.dart';

class RulesScreen extends StatefulWidget {
  const RulesScreen({super.key});
  @override
  State<RulesScreen> createState() => _RulesScreenState();
}

class _RulesScreenState extends State<RulesScreen> {
  String _text = '';
  List _rules = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final r = await ApiService.rules();
      final d = r['data'];
      setState(() {
        if (d is Map) {
          _text = _stripHtml(d['text']?.toString() ?? d['description']?.toString() ?? '');
        } else if (d is List) {
          _rules = d;
        }
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
    final hasContent = _text.isNotEmpty || _rules.isNotEmpty;
    return SheetPage(
      title: 'Company Rules',
      children: !hasContent
          ? [const Padding(padding: EdgeInsets.only(top: 60), child: Center(child: Text('No rules found', style: TextStyle(color: AppColors.inkMuted))))]
          : [
              if (_text.isNotEmpty)
                SoftCard(child: Text(_text, style: const TextStyle(fontSize: 14, color: AppColors.inkSoft, height: 1.6))),
              for (final raw in _rules)
                SoftCard(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text((raw as Map)['title']?.toString() ?? raw['name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.ink)),
                    if (raw['description'] != null || raw['details'] != null) ...[
                      const SizedBox(height: 8),
                      Text(_stripHtml(raw['description']?.toString() ?? raw['details']?.toString() ?? ''), style: const TextStyle(fontSize: 13, color: AppColors.inkSoft, height: 1.5)),
                    ],
                  ]),
                ),
            ],
    );
  }
}
