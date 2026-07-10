import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';
import '../widgets/ui_kit.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map _info = {};
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final r = await ApiService.myInfo();
      setState(() { _info = r['data'] ?? r; _loading = false; });
    } catch (_) { setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(backgroundColor: AppColors.surface, body: Center(child: CircularProgressIndicator(color: AppColors.blue)));
    final url = ApiService.photoUrl(_info['photo']?.toString());
    return SheetPage(
      title: 'My Profile',
      onRefresh: _load,
      headerBottomPad: 86,
      headerChild: Row(children: [
        CircleAvatar(
          radius: 34, backgroundColor: Colors.white.withValues(alpha: 0.2),
          backgroundImage: url.isNotEmpty ? NetworkImage(url) : null,
          child: url.isEmpty ? const Icon(Icons.person, size: 34, color: Colors.white) : null,
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_info['name']?.toString() ?? '—', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: Colors.white)),
          const SizedBox(height: 3),
          Text(_info['designation']?.toString() ?? '', style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.75))),
        ])),
      ]),
      children: [
        const SectionTitle('Personal information'),
        SoftCard(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _row('Employee ID', _info['employee_id']?.toString() ?? '—'),
            _row('Designation', _info['designation']?.toString() ?? '—'),
            _row('Department', _department()),
            _row('Branch', _v(_info['branch_name'] ?? (_info['branch'] is Map ? _info['branch']['name'] : null))),
            _row('Phone', _info['phone']?.toString() ?? '—'),
            _row('Email', _info['email']?.toString() ?? '—'),
            _row('Gender', _info['gender']?.toString() ?? '—'),
            _row('Blood Group', _info['blood_group']?.toString() ?? '—'),
            _row('Date of Birth', _date(_info['date_of_birth'])),
            _row('Join Date', _date(_info['joining_date'])),
            _row('Weekend', [_info['weekend'], _info['weekend2']].where((e) => e != null && e.toString().isNotEmpty).join(', ')),
            _row('Address', _v(_info['address'])),
          ]),
        ),
        const SectionTitle('Emergency contact'),
        SoftCard(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _row('Name', _v(_info['emergency_contact_name'])),
            _row('Number', _v(_info['emergency_contact_number'])),
            _row('Relation', _v(_info['emergency_contact_relation'])),
          ]),
        ),
        const SectionTitle('Compensation & policy'),
        SoftCard(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _row('Monthly Salary', '৳${_v(_info['salary'], '0')}'),
            _row('Eid Bonus', '৳${_v(_info['eid_bouns'] ?? _info['eid_bonus'], '0')}'),
            _row('OT Rate/hr', '৳${_v(_info['overtime_amount'], '0')}'),
            _row('Office Hours/day', '${_v(_info['office_hour'], '0')} hrs'),
            _row('Extra Days', '${_v(_info['extra_day'], '0')} days'),
            const Divider(color: Color(0xFFF0F3FA), height: 24),
            _row('Annual Leave', '${_v(_info['annual_leave'], '0')} days'),
            _row('Sick Leave', '${_v(_info['sick_leave'], '0')} days'),
            _row('Casual Leave', '${_v(_info['casual_leave'], '0')} days'),
            const Divider(color: Color(0xFFF0F3FA), height: 24),
            _row('Late Fine/day', '৳${_v(_info['late_in_amount'], '0')}'),
            _row('Early Out Fine/day', '৳${_v(_info['early_out_amount'], '0')}'),
            _row('Absent Fine/day', '৳${_v(_info['absent_amount'], '0')}'),
          ]),
        ),
      ],
    );
  }

  String _department() {
    final joined = _info['department_names']?.toString().trim() ?? '';
    if (joined.isNotEmpty && joined != 'null') return joined;
    final rel = _info['departments'];
    if (rel is List && rel.isNotEmpty) {
      final names = rel
          .map((e) => e is Map ? e['name']?.toString() : e?.toString())
          .where((s) => s != null && s.trim().isNotEmpty)
          .join(', ');
      if (names.isNotEmpty) return names;
    }
    return _v(_info['department']);
  }

  String _v(dynamic v, [String fallback = '—']) {
    final s = v?.toString().trim() ?? '';
    return s.isEmpty || s == 'null' ? fallback : s;
  }

  String _date(dynamic v) {
    final s = v?.toString().trim() ?? '';
    if (s.isEmpty || s == 'null') return '—';
    return s.split(' ').first.split('T').first;
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          SizedBox(width: 120, child: Text(label, style: const TextStyle(fontSize: 13, color: AppColors.inkMuted))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.ink))),
        ]),
      );
}
