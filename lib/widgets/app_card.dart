import 'dart:ui';
import 'package:flutter/material.dart';

class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final EdgeInsets? margin;
  final Color? borderColor;

  const AppCard({super.key, required this.child, this.padding, this.margin, this.borderColor});

  @override
  Widget build(BuildContext context) => Container(
    margin: margin,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: padding ?? const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.07),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor ?? Colors.white.withOpacity(0.13)),
          ),
          child: child,
        ),
      ),
    ),
  );
}
