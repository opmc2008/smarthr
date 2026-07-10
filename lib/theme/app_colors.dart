import 'package:flutter/material.dart';

/// SmartHR "structured blue" palette (redesign v4):
/// white sheets (60%) · sculpted blue headers (30%) · orange ignition (10%).
class AppColors {
  // Accent (10%) — "act here"
  static const orange = Color(0xFFFF7A1A);
  static const orangeDeep = Color(0xFFE05F00);
  static const orangeTint = Color(0xFFFFF0E2);

  // Structure (30%)
  static const blue = Color(0xFF1B5CFF);
  static const blueLight = Color(0xFF4C82FF);
  static const blueHeaderTop = Color(0xFF2B67F0);
  static const blueDeep = Color(0xFF0F3FB8);
  static const blueTint = Color(0xFFEAF1FF);
  static const royal = Color(0xFF123B9E); // login canvas mid
  static const royalDark = Color(0xFF0B2668); // login canvas base

  // Canvas (60%)
  static const surface = Color(0xFFF4F7FE); // warm-white sheet
  static const card = Color(0xFFFFFFFF);
  static const heroNavy = Color(0xFF0A1F4E); // navy anchor (nav, phone frame)

  // Text
  static const ink = Color(0xFF0A1F4E);
  static const inkMuted = Color(0xFF7387B5);
  static const inkSoft = Color(0xFF5E6F9E);

  // Semantic
  static const green = Color(0xFF178A4C);
  static const greenTint = Color(0xFFE3F9EC);
  static const violet = Color(0xFF7C3AED);
  static const red = Color(0xFFD63649);
  static const redTint = Color(0xFFFFE7E9);

  static const softShadow = Color(0x1A0A1F4E); // navy-tinted card lift
}
