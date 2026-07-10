import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';
import '../widgets/ui_kit.dart';
import 'admin_employee_tracking_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});
  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  List<Map<String, dynamic>> _employees = [];
  bool _isLoading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _loadTeam();
  }

  Future<void> _loadTeam() async {
    setState(() { _isLoading = true; _error = ''; });
    try {
      final res = await ApiService.myTeam();
      final rawList = res['data'];
      if (rawList is List) {
        setState(() {
          _employees = rawList.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          _isLoading = false;
        });
      } else {
        setState(() { _employees = []; _isLoading = false; });
      }
    } catch (e) {
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SheetPage(
      title: 'Team Monitoring',
      showBack: false,
      children: [
        Row(children: [
          Expanded(child: Text('Your Team', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink))),
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.inkMuted),
            onPressed: _loadTeam,
            tooltip: 'Refresh',
          ),
        ]),
        const SizedBox(height: 16),
        if (_isLoading)
          const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()))
        else if (_error.isNotEmpty)
          _buildError()
        else if (_employees.isEmpty)
          _buildEmpty()
        else
          ..._employees.map((emp) => _buildEmployeeCard(emp)),
      ],
    );
  }

  Widget _buildError() => SoftCard(child: Column(children: [
    const Icon(Icons.cloud_off, color: AppColors.red, size: 40),
    const SizedBox(height: 12),
    Text(_error, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.inkMuted, fontSize: 13)),
    const SizedBox(height: 16),
    ElevatedButton.icon(onPressed: _loadTeam, icon: const Icon(Icons.refresh), label: const Text('Try Again'),
      style: ElevatedButton.styleFrom(backgroundColor: AppColors.orange, foregroundColor: Colors.white)),
  ]));

  Widget _buildEmpty() => SoftCard(child: Column(children: [
    const Icon(Icons.group_off_outlined, color: AppColors.inkMuted, size: 40),
    const SizedBox(height: 12),
    const Text('No employees found in your branch.', style: TextStyle(color: AppColors.inkMuted)),
  ]));

  Widget _buildEmployeeCard(Map<String, dynamic> emp) {
    final isActive = (emp['status'] ?? '').toString().toLowerCase() == 'active';
    final name = emp['name']?.toString() ?? 'Employee';
    final designation = emp['designation']?.toString() ?? '';
    final branchName = emp['branch_name']?.toString() ?? '';
    final photoUrl = emp['photo'] != null ? ApiService.photoUrl(emp['photo'].toString()) : '';
    final userId = emp['user_id']?.toString() ?? emp['id']?.toString() ?? '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        elevation: 0,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: userId.isEmpty ? null : () {
            Navigator.push(context, MaterialPageRoute(
              builder: (_) => AdminEmployeeTrackingScreen(
                employeeUserId: userId,
                employeeName: name,
              ),
            ));
          },
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.blueTint),
            ),
            child: Row(children: [
              // Avatar
              CircleAvatar(
                radius: 24,
                backgroundColor: AppColors.blueTint,
                backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
                child: photoUrl.isEmpty ? Text(name[0].toUpperCase(),
                  style: const TextStyle(color: AppColors.blueLight, fontWeight: FontWeight.bold, fontSize: 18)) : null,
              ),
              const SizedBox(width: 14),
              // Info
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink, fontSize: 15)),
                if (designation.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(designation, style: const TextStyle(fontSize: 12, color: AppColors.inkMuted)),
                ],
                if (branchName.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Row(children: [
                    const Icon(Icons.business_outlined, size: 11, color: AppColors.inkMuted),
                    const SizedBox(width: 3),
                    Text(branchName, style: const TextStyle(fontSize: 11, color: AppColors.inkMuted)),
                  ]),
                ],
              ])),
              // Status + arrow
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 8, height: 8,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: isActive ? AppColors.green : AppColors.red)),
                  const SizedBox(width: 5),
                  Text(isActive ? 'Active' : 'Inactive',
                    style: TextStyle(fontSize: 11, color: isActive ? AppColors.green : AppColors.red, fontWeight: FontWeight.w600)),
                ]),
                const SizedBox(height: 8),
                const Icon(Icons.location_on, size: 16, color: AppColors.orange),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}
