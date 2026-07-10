import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';
import '../widgets/ui_kit.dart';

class ClientsScreen extends StatefulWidget {
  const ClientsScreen({super.key});
  @override
  State<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends State<ClientsScreen> {
  List _clients = [];
  bool _loading = true;
  String _search = '';

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try { final r = await ApiService.clients(); setState(() { _clients = r['data'] ?? r ?? []; _loading = false; }); }
    catch (_) { setState(() => _loading = false); }
  }

  void _snack(String m, {bool err = false}) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), backgroundColor: err ? AppColors.red : AppColors.green, behavior: SnackBarBehavior.floating));

  Future<void> _delete(Map c) async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: Colors.white,
      title: const Text('Delete client?', style: TextStyle(fontSize: 16, color: AppColors.ink)),
      content: Text('${c['name'] ?? 'Client'} will be permanently deleted.', style: const TextStyle(fontSize: 13, color: AppColors.inkSoft)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: AppColors.red, foregroundColor: Colors.white), onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
      ],
    ));
    if (ok != true) return;
    try { await ApiService.clientDelete(c['id'].toString()); _snack('Client deleted'); _load(); }
    catch (e) { _snack(e.toString().replaceAll('Exception: ', ''), err: true); }
  }

  @override
  Widget build(BuildContext context) {
    final list = _search.isEmpty
        ? _clients
        : _clients.where((c) {
            final m = c as Map;
            final hay = '${m['name'] ?? ''} ${m['company_name'] ?? ''} ${m['number'] ?? ''}'.toLowerCase();
            return hay.contains(_search.toLowerCase());
          }).toList();

    return SheetPage(
      title: 'Clients',
      onRefresh: _load,
      headerTrailing: GestureDetector(
        onTap: () async {
          final created = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const ClientFormScreen()));
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
      headerChild: Container(
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(12)),
        child: TextField(
          onChanged: (v) => setState(() => _search = v),
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Search name, company, number…',
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13),
            prefixIcon: Icon(Icons.search, color: Colors.white.withValues(alpha: 0.7), size: 18),
            border: InputBorder.none, isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
      ),
      children: _loading
          ? [const Padding(padding: EdgeInsets.only(top: 60), child: Center(child: CircularProgressIndicator(color: AppColors.blue)))]
          : list.isEmpty
              ? [const Padding(padding: EdgeInsets.only(top: 60), child: Center(child: Text('No clients', style: TextStyle(color: AppColors.inkMuted))))]
              : list.map((e) => _clientCard(e as Map)).toList(),
    );
  }

  Widget _clientCard(Map c) => SoftCard(
        margin: const EdgeInsets.only(bottom: 10),
        onTap: () async {
          final changed = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => ClientFormScreen(client: c)));
          if (changed == true) _load();
        },
        child: Row(children: [
          Container(width: 44, height: 44,
              decoration: BoxDecoration(color: AppColors.blueTint, borderRadius: BorderRadius.circular(13)),
              child: Center(child: Text((c['name']?.toString() ?? '?').isNotEmpty ? c['name'].toString()[0].toUpperCase() : '?',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.blueDeep)))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(c['name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.ink)),
            if ((c['company_name']?.toString() ?? '').isNotEmpty)
              Text(c['company_name'].toString(), style: const TextStyle(fontSize: 12, color: AppColors.inkSoft)),
            if ((c['number']?.toString() ?? '').isNotEmpty)
              Text(c['number'].toString(), style: const TextStyle(fontSize: 11, color: AppColors.inkMuted)),
          ])),
          IconButton(icon: const Icon(Icons.delete_outline, color: AppColors.red, size: 19), onPressed: () => _delete(c)),
          const Icon(Icons.chevron_right, color: Color(0xFFB6C2DA), size: 18),
        ]),
      );
}

/// Create/edit client — mirrors the website's client form fields.
class ClientFormScreen extends StatefulWidget {
  final Map? client;
  const ClientFormScreen({super.key, this.client});
  @override
  State<ClientFormScreen> createState() => _ClientFormScreenState();
}

class _ClientFormScreenState extends State<ClientFormScreen> {
  late final Map<String, TextEditingController> _c;
  List _districts = [], _zones = [], _areas = [], _statuses = [];
  String? _districtId, _zoneId, _areaId, _statusId;
  bool _submitting = false;
  String _msg = '';

  static const _fields = {
    'name': 'Client name',
    'designation': 'Designation',
    'number': 'Phone number',
    'company_name': 'Company name',
    'email': 'Email',
    'address': 'Address',
    'business_type': 'Business type',
    'business_description': 'Business description',
    'visit_date': 'Visit date (YYYY-MM-DD)',
    'next_visit_date': 'Next visit date (YYYY-MM-DD)',
    'visit_update': 'Visit update',
    'map_link': 'Map link',
  };

  @override
  void initState() {
    super.initState();
    final cl = widget.client ?? {};
    _c = {for (final k in _fields.keys) k: TextEditingController(text: cl[k]?.toString() ?? '')};
    _districtId = cl['district_id']?.toString();
    _zoneId = cl['zone_id']?.toString();
    _areaId = cl['area_id']?.toString();
    _statusId = cl['sale_status_id']?.toString();
    _loadLookups();
  }

  @override
  void dispose() { for (final c in _c.values) { c.dispose(); } super.dispose(); }

  Future<void> _loadLookups() async {
    try {
      final r = await Future.wait([
        ApiService.districts().catchError((_) => <String, dynamic>{}),
        ApiService.zones().catchError((_) => <String, dynamic>{}),
        ApiService.areas().catchError((_) => <String, dynamic>{}),
        ApiService.saleStatuses().catchError((_) => <String, dynamic>{}),
      ]);
      setState(() {
        _districts = r[0]['data'] ?? [];
        _zones = r[1]['data'] ?? [];
        _areas = r[2]['data'] ?? [];
        _statuses = r[3]['data'] ?? [];
      });
    } catch (_) {}
  }

  Future<void> _submit() async {
    if (_c['name']!.text.trim().isEmpty) { setState(() => _msg = 'Client name is required.'); return; }
    setState(() { _submitting = true; _msg = ''; });
    final f = <String, String>{for (final e in _c.entries) e.key: e.value.text.trim()};
    if (_districtId != null) f['district_id'] = _districtId!;
    if (_zoneId != null) f['zone_id'] = _zoneId!;
    if (_areaId != null) f['area_id'] = _areaId!;
    if (_statusId != null) f['sale_status_id'] = _statusId!;
    try {
      final uid = await ApiService.getUserId();
      f['responsible_user'] = uid;
      if (widget.client == null) {
        await ApiService.clientCreate(f);
      } else {
        await ApiService.clientUpdate(widget.client!['id'].toString(), f);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() { _msg = e.toString().replaceAll('Exception: ', ''); _submitting = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.client != null;
    return SheetPage(
      title: editing ? 'Edit Client' : 'New Client',
      children: [
        SoftCard(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final e in _fields.entries) ...[
              _label(e.value),
              TextField(controller: _c[e.key], maxLines: e.key == 'business_description' || e.key == 'address' ? 2 : 1, decoration: _dec()),
              const SizedBox(height: 13),
            ],
            _label('District'),
            _lookupDropdown(_districts, _districtId, (v) => setState(() => _districtId = v)),
            const SizedBox(height: 13),
            _label('Zone'),
            _lookupDropdown(_zones, _zoneId, (v) => setState(() => _zoneId = v)),
            const SizedBox(height: 13),
            _label('Area'),
            _lookupDropdown(_areas, _areaId, (v) => setState(() => _areaId = v)),
            const SizedBox(height: 13),
            _label('Sale status'),
            _lookupDropdown(_statuses, _statusId, (v) => setState(() => _statusId = v)),
            if (_msg.isNotEmpty) ...[const SizedBox(height: 10), Text(_msg, style: const TextStyle(fontSize: 13, color: AppColors.red))],
            const SizedBox(height: 18),
            SizedBox(width: double.infinity, child: ElevatedButton(
              onPressed: _submitting ? null : _submit,
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.blue, foregroundColor: Colors.white, elevation: 0, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: Text(_submitting ? 'Saving…' : (editing ? 'Save changes' : 'Create client'), style: const TextStyle(fontWeight: FontWeight.w600)),
            )),
          ]),
        ),
      ],
    );
  }

  Widget _lookupDropdown(List items, String? value, ValueChanged<String?> onChanged) {
    final ids = items.map((m) => (m as Map)['id'].toString()).toSet();
    return DropdownButtonFormField<String>(
      initialValue: ids.contains(value) ? value : null,
      isExpanded: true,
      decoration: _dec(),
      items: items.map((m) {
        final mm = m as Map;
        return DropdownMenuItem(value: mm['id'].toString(), child: Text(mm['name']?.toString() ?? '', style: const TextStyle(fontSize: 13)));
      }).toList(),
      onChanged: onChanged,
    );
  }

  Widget _label(String t) => Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(t, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.inkMuted, letterSpacing: 0.5)));

  InputDecoration _dec({String? hint}) => InputDecoration(
        hintText: hint, hintStyle: const TextStyle(color: AppColors.inkMuted),
        filled: true, fillColor: AppColors.surface, isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE0E7F5))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE0E7F5))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.blue)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      );
}
