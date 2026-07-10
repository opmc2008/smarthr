import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';
import '../widgets/ui_kit.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});
  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _oldCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _submitting = false;
  String _msg = '';
  bool _ok = false;

  @override
  void dispose() { _oldCtrl.dispose(); _newCtrl.dispose(); _confirmCtrl.dispose(); super.dispose(); }

  Future<void> _submit() async {
    final oldP = _oldCtrl.text, newP = _newCtrl.text, conf = _confirmCtrl.text;
    if (oldP.isEmpty || newP.isEmpty) { setState(() { _ok = false; _msg = 'Fill in all fields.'; }); return; }
    if (newP.length < 6) { setState(() { _ok = false; _msg = 'New password must be at least 6 characters.'; }); return; }
    if (newP != conf) { setState(() { _ok = false; _msg = 'Passwords do not match.'; }); return; }
    setState(() { _submitting = true; _msg = ''; });
    try {
      await ApiService.changePassword(oldP, newP, conf);
      setState(() { _ok = true; _msg = '✓ Password changed successfully.'; _submitting = false; });
      _oldCtrl.clear(); _newCtrl.clear(); _confirmCtrl.clear();
    } catch (e) {
      setState(() { _ok = false; _msg = e.toString().replaceAll('Exception: ', ''); _submitting = false; });
    }
  }

  @override
  Widget build(BuildContext context) => SheetPage(
        title: 'Change Password',
        children: [
          SoftCard(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SectionTitle('Update password'),
              const SizedBox(height: 6),
              _label('Current password'),
              _field(_oldCtrl, 'Enter current password'),
              const SizedBox(height: 14),
              _label('New password'),
              _field(_newCtrl, 'At least 6 characters'),
              const SizedBox(height: 14),
              _label('Confirm new password'),
              _field(_confirmCtrl, 'Re-enter new password'),
              if (_msg.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(_msg, style: TextStyle(fontSize: 13, color: _ok ? AppColors.green : AppColors.red)),
              ],
              const SizedBox(height: 20),
              SizedBox(width: double.infinity, child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.blue, foregroundColor: Colors.white, elevation: 0, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: Text(_submitting ? 'Updating…' : 'Update password', style: const TextStyle(fontWeight: FontWeight.w600)),
              )),
            ]),
          ),
        ],
      );

  Widget _label(String t) => Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(t, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.inkMuted, letterSpacing: 0.5)));

  Widget _field(TextEditingController c, String hint) => TextField(
        controller: c, obscureText: true, style: const TextStyle(color: AppColors.ink),
        decoration: InputDecoration(
          hintText: hint, hintStyle: const TextStyle(color: AppColors.inkMuted),
          filled: true, fillColor: AppColors.surface, isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE0E7F5))),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE0E7F5))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.blue)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      );
}
