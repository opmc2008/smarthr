import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../widgets/ui_kit.dart';
import '../services/api_service.dart';
import 'profile_screen.dart';
import 'overtime_screen.dart';
import 'tracking_screen.dart';
import 'noticeboard_screen.dart';
import 'holidays_screen.dart';
import 'rules_screen.dart';
import 'reports_screen.dart';
import 'change_password_screen.dart';
import 'html_doc_screen.dart';
import 'advance_salary_screen.dart';
import 'tasks_screen.dart';
import 'clients_screen.dart';
import 'login_screen.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final items = <_Item>[
      _Item(Icons.person, 'My Profile', () => _go(context, const ProfileScreen())),
      _Item(Icons.more_time, 'Over Time', () => _go(context, const OvertimeScreen())),

      _Item(Icons.campaign, 'Notice Board', () => _go(context, const NoticeboardScreen())),
      _Item(Icons.celebration, 'Holidays', () => _go(context, const HolidaysScreen())),
      _Item(Icons.gavel, 'Company Rules', () => _go(context, const RulesScreen())),
      _Item(Icons.task_alt, 'Tasks', () => _go(context, const TasksScreen())),
      _Item(Icons.groups, 'Clients', () => _go(context, const ClientsScreen())),
      _Item(Icons.bar_chart, 'Reports', () => _go(context, const ReportsScreen())),

      _Item(Icons.lock_reset, 'Change Password', () => _go(context, const ChangePasswordScreen())),
    ];

    return SheetPage(
      title: 'More',
      showBack: false,
      children: [
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 0.95),
          itemCount: items.length,
          itemBuilder: (_, i) {
            final it = items[i];
            return SoftCard(
              onTap: it.onTap,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(width: 42, height: 42, decoration: BoxDecoration(color: AppColors.blueTint, borderRadius: BorderRadius.circular(13)), child: Icon(it.icon, color: AppColors.blue, size: 22)),
                const SizedBox(height: 8),
                Text(it.label, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600, fontSize: 11)),
              ]),
            );
          },
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.logout, color: AppColors.red, size: 18),
            label: const Text('Log Out', style: TextStyle(color: AppColors.red)),
            style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0x33DC2626)), padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            onPressed: () async {
              try { await ApiService.logout(); } catch (_) {}
              await ApiService.clearAll();
              if (context.mounted) Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
            },
          ),
        ),
      ],
    );
  }

  void _go(BuildContext context, Widget screen) => Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
}

class _Item {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  _Item(this.icon, this.label, this.onTap);
}
