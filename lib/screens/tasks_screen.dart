import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';
import '../widgets/ui_kit.dart';

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});
  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  List _tasks = [];
  bool _loading = true;
  String _filter = '';

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try { final r = await ApiService.tasks(filter: _filter); setState(() { _tasks = r['data'] ?? r ?? []; _loading = false; }); }
    catch (_) { setState(() => _loading = false); }
  }

  String _d(dynamic v) => (v?.toString() ?? '').split(' ').first.split('T').first;

  void _snack(String m, {bool err = false}) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), backgroundColor: err ? AppColors.red : AppColors.green, behavior: SnackBarBehavior.floating));

  Future<void> _complete(Map t) async {
    final noteCtrl = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: Colors.white,
      title: const Text('Complete task', style: TextStyle(fontSize: 16, color: AppColors.ink)),
      content: TextField(controller: noteCtrl, maxLines: 2, decoration: const InputDecoration(hintText: 'Completion note (optional)')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: AppColors.green, foregroundColor: Colors.white), onPressed: () => Navigator.pop(ctx, true), child: const Text('Complete')),
      ],
    ));
    if (ok != true) return;
    try { await ApiService.taskComplete(t['id'].toString(), noteCtrl.text); _snack('Task completed'); _load(); }
    catch (e) { _snack(e.toString().replaceAll('Exception: ', ''), err: true); }
  }

  Future<void> _uncomplete(Map t) async {
    try { await ApiService.taskUncomplete(t['id'].toString()); _snack('Task reopened'); _load(); }
    catch (e) { _snack(e.toString().replaceAll('Exception: ', ''), err: true); }
  }

  Future<void> _delete(Map t) async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: Colors.white,
      title: const Text('Delete task?', style: TextStyle(fontSize: 16, color: AppColors.ink)),
      content: Text('Task ${t['sku'] ?? ''} will be permanently deleted.', style: const TextStyle(fontSize: 13, color: AppColors.inkSoft)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: AppColors.red, foregroundColor: Colors.white), onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
      ],
    ));
    if (ok != true) return;
    try { await ApiService.taskDelete(t['id'].toString()); _snack('Task deleted'); _load(); }
    catch (e) { _snack(e.toString().replaceAll('Exception: ', ''), err: true); }
  }

  @override
  Widget build(BuildContext context) {
    return SheetPage(
      title: 'Tasks',
      onRefresh: _load,
      headerTrailing: GestureDetector(
        onTap: () async {
          final created = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const TaskFormScreen()));
          if (created == true) _load();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: AppColors.orange, borderRadius: BorderRadius.circular(11)),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.add, color: Colors.white, size: 16), SizedBox(width: 4),
            Text('New', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
      headerChild: Row(children: [
        _filterPill('All', ''),
        const SizedBox(width: 8),
        _filterPill('Pending', 'pending'),
        const SizedBox(width: 8),
        _filterPill('Complete', 'complete'),
        const SizedBox(width: 8),
        _filterPill('Mine', 'self_task'),
      ]),
      children: _loading
          ? [const Padding(padding: EdgeInsets.only(top: 60), child: Center(child: CircularProgressIndicator(color: AppColors.blue)))]
          : _tasks.isEmpty
              ? [const Padding(padding: EdgeInsets.only(top: 60), child: Center(child: Text('No tasks', style: TextStyle(color: AppColors.inkMuted))))]
              : _tasks.map((e) => _taskCard(e as Map)).toList(),
    );
  }

  Widget _filterPill(String label, String value) {
    final sel = _filter == value;
    return Expanded(child: GestureDetector(
      onTap: () { setState(() => _filter = value); _load(); },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(color: sel ? Colors.white : Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(11)),
        child: Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: sel ? AppColors.blueDeep : Colors.white)),
      ),
    ));
  }

  Widget _taskCard(Map t) {
    final done = (t['completed_at']?.toString() ?? '').isNotEmpty;
    return SoftCard(
      margin: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 38, height: 38,
              decoration: BoxDecoration(color: done ? AppColors.greenTint : AppColors.orangeTint, borderRadius: BorderRadius.circular(11)),
              child: Icon(done ? Icons.task_alt : Icons.pending_actions, color: done ? AppColors.green : AppColors.orange, size: 20)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${t['type'] ?? 'Task'} · #${t['sku'] ?? t['id']}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.ink)),
            Text(_d(t['task_date']), style: const TextStyle(fontSize: 11, color: AppColors.inkMuted)),
          ])),
          SoftPill(done ? 'Complete' : 'Pending', done ? AppColors.green : AppColors.orange),
        ]),
        if ((t['task']?.toString() ?? '').isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 8), child: Text(t['task'].toString(), style: const TextStyle(fontSize: 13, color: AppColors.inkSoft))),
        if (done && (t['note']?.toString() ?? '').isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 4), child: Text('Note: ${t['note']}', style: const TextStyle(fontSize: 12, color: AppColors.inkMuted))),
        const SizedBox(height: 10),
        Row(children: [
          if (!done) _action('Complete', Icons.check, AppColors.green, () => _complete(t)),
          if (done) _action('Reopen', Icons.replay, AppColors.blue, () => _uncomplete(t)),
          const SizedBox(width: 8),
          _action('Delete', Icons.delete_outline, AppColors.red, () => _delete(t)),
        ]),
      ]),
    );
  }

  Widget _action(String label, IconData icon, Color c, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(color: c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(9), border: Border.all(color: c.withValues(alpha: 0.3))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 14, color: c), const SizedBox(width: 5),
            Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c)),
          ]),
        ),
      );
}

/// New-task form: type (from tasktype lookup), client, date, details.
class TaskFormScreen extends StatefulWidget {
  const TaskFormScreen({super.key});
  @override
  State<TaskFormScreen> createState() => _TaskFormScreenState();
}

class _TaskFormScreenState extends State<TaskFormScreen> {
  List _types = [], _clients = [];
  String? _type;
  String? _clientId;
  DateTime _date = DateTime.now();
  final _taskCtrl = TextEditingController();
  bool _submitting = false;
  String _msg = '';

  @override
  void initState() { super.initState(); _loadLookups(); }

  @override
  void dispose() { _taskCtrl.dispose(); super.dispose(); }

  Future<void> _loadLookups() async {
    try {
      final r = await Future.wait([
        ApiService.taskTypes().catchError((_) => <String, dynamic>{}),
        ApiService.clients().catchError((_) => <String, dynamic>{}),
      ]);
      setState(() {
        _types = r[0]['data'] ?? [];
        _clients = r[1]['data'] ?? [];
      });
    } catch (_) {}
  }

  String _iso(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _submit() async {
    if (_type == null || _clientId == null || _taskCtrl.text.trim().isEmpty) {
      setState(() => _msg = 'Fill in type, client and task details.');
      return;
    }
    setState(() { _submitting = true; _msg = ''; });
    try {
      final uid = await ApiService.getUserId();
      await ApiService.taskCreate({
        'type': _type!,
        'task_date': _iso(_date),
        'client_id': _clientId!,
        'issue_for': uid,
        'task': _taskCtrl.text.trim(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() { _msg = e.toString().replaceAll('Exception: ', ''); _submitting = false; });
    }
  }

  @override
  Widget build(BuildContext context) => SheetPage(
        title: 'New Task',
        children: [
          SoftCard(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _label('Task type'),
              _dropdown(_types.map((t) => (t as Map)['name']?.toString() ?? '').where((s) => s.isNotEmpty).toList(), _type, (v) => setState(() => _type = v)),
              const SizedBox(height: 14),
              _label('Client'),
              DropdownButtonFormField<String>(
                initialValue: _clientId,
                isExpanded: true,
                decoration: _dec(),
                items: _clients.map((c) {
                  final m = c as Map;
                  return DropdownMenuItem(value: m['id'].toString(), child: Text('${m['name'] ?? ''} — ${m['company_name'] ?? ''}', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)));
                }).toList(),
                onChanged: (v) => setState(() => _clientId = v),
              ),
              const SizedBox(height: 14),
              _label('Task date'),
              OutlinedButton(
                onPressed: () async {
                  final d = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(2020), lastDate: DateTime(2030));
                  if (d != null) setState(() => _date = d);
                },
                style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 46), alignment: Alignment.centerLeft, side: const BorderSide(color: Color(0xFFE0E7F5))),
                child: Text(_iso(_date), style: const TextStyle(color: AppColors.ink, fontSize: 13)),
              ),
              const SizedBox(height: 14),
              _label('Task details'),
              TextField(controller: _taskCtrl, maxLines: 3, decoration: _dec(hint: 'Describe the task...')),
              if (_msg.isNotEmpty) ...[const SizedBox(height: 10), Text(_msg, style: const TextStyle(fontSize: 13, color: AppColors.red))],
              const SizedBox(height: 18),
              SizedBox(width: double.infinity, child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.blue, foregroundColor: Colors.white, elevation: 0, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: Text(_submitting ? 'Creating…' : 'Create task', style: const TextStyle(fontWeight: FontWeight.w600)),
              )),
            ]),
          ),
        ],
      );

  Widget _label(String t) => Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(t, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.inkMuted, letterSpacing: 0.5)));

  Widget _dropdown(List<String> items, String? value, ValueChanged<String?> onChanged) => DropdownButtonFormField<String>(
        initialValue: value,
        isExpanded: true,
        decoration: _dec(),
        items: items.map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(fontSize: 13)))).toList(),
        onChanged: onChanged,
      );

  InputDecoration _dec({String? hint}) => InputDecoration(
        hintText: hint, hintStyle: const TextStyle(color: AppColors.inkMuted),
        filled: true, fillColor: AppColors.surface, isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE0E7F5))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE0E7F5))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.blue)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      );
}
