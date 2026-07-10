import 'package:flutter/material.dart';

class StatusBadge extends StatelessWidget {
  final String status;
  const StatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final s = status.toLowerCase();
    Color bg, fg;
    if (s.contains('present') || s.contains('approved') || s.contains('paid') || s.contains('national') || s.contains('active')) {
      bg = const Color(0xFF004A31); fg = const Color(0xFF4EDEA3);
    } else if (s.contains('late') || s.contains('pending') || s.contains('processing') || s.contains('half')) {
      bg = const Color(0xFF5C2400); fg = const Color(0xFFFFB690);
    } else if (s.contains('absent') || s.contains('absend') || s.contains('reject')) {
      bg = const Color(0xFF5D000A); fg = const Color(0xFFFF8A80);
    } else if (s.contains('weekend') || s.contains('holiday') || s.contains('leave')) {
      bg = const Color(0xFF1A2A6E); fg = const Color(0xFF93C5FD);
    } else {
      bg = const Color(0xFF00164E); fg = const Color(0xFF90A8FF);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20), border: Border.all(color: fg.withOpacity(0.3))),
      child: Text(status, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
    );
  }
}
