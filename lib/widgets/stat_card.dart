import 'dart:ui';
import 'package:flutter/material.dart';

class StatCard extends StatelessWidget {
  final String label, value;
  final Color color;
  final IconData icon;

  const StatCard({super.key, required this.label, required this.value, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(16),
      boxShadow: [BoxShadow(color: color.withOpacity(0.4), blurRadius: 20, spreadRadius: 0)],
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [color.withOpacity(0.6), color.withOpacity(0.35)],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withOpacity(0.4)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                child: Icon(icon, color: Colors.white, size: 14),
              ),
            ]),
            const SizedBox(height: 10),
            Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white, height: 1)),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.7), fontWeight: FontWeight.w500)),
          ]),
        ),
      ),
    ),
  );
}
