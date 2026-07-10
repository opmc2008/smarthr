import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'liquid_dial.dart';

/// Sculpted blue header (redesign v4): carved geometry, a slow light sweep,
/// curved bottom corners, a title, optional back button and optional content
/// (e.g. summary chips) that the page sheet overlaps.
class GradientHeader extends StatelessWidget {
  final String title;
  final bool showBack;
  final Widget? trailing;
  final Widget? child;
  final double bottomPad;
  const GradientHeader({super.key, required this.title, this.showBack = true, this.trailing, this.child, this.bottomPad = 70});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.blueHeaderTop, AppColors.blue, AppColors.blueDeep],
          stops: [0.0, 0.55, 1.0],
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(34)),
        boxShadow: [BoxShadow(color: AppColors.blueDeep.withValues(alpha: 0.35), blurRadius: 30, offset: const Offset(0, 14))],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(34)),
        child: Stack(children: [
          const Positioned.fill(child: MeshBlobs()),
          const Positioned.fill(child: HeaderSheen()),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 52, 16, bottomPad),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                if (showBack) ...[
                  GestureDetector(
                    onTap: () => Navigator.of(context).maybePop(),
                    child: const Icon(Icons.arrow_back, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white))),
                if (trailing != null) trailing!,
              ]),
              if (child != null) ...[const SizedBox(height: 16), child!],
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Slow diagonal light sweep that passes across the header every few seconds.
class HeaderSheen extends StatefulWidget {
  const HeaderSheen({super.key});
  @override
  State<HeaderSheen> createState() => _HeaderSheenState();
}

class _HeaderSheenState extends State<HeaderSheen> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 5))..repeat();
  }
  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => LayoutBuilder(
          builder: (_, box) {
            final x = (box.maxWidth + 260) * _c.value - 260;
            return Stack(children: [
              Positioned(
                left: x, top: -40, bottom: -40, width: 130,
                child: Transform.rotate(
                  angle: 0.28,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        Colors.white.withValues(alpha: 0.0),
                        Colors.white.withValues(alpha: 0.10),
                        Colors.white.withValues(alpha: 0.0),
                      ]),
                    ),
                  ),
                ),
              ),
            ]);
          },
        ),
      ),
    );
  }
}

/// Standard page scaffold for the light theme: gradient header + a content
/// sheet that pulls up over it with rounded top corners.
class SheetPage extends StatelessWidget {
  final String title;
  final bool showBack;
  final Widget? headerTrailing;
  final Widget? headerChild;
  final double headerBottomPad;
  final List<Widget> children;
  final Future<void> Function()? onRefresh;
  final PreferredSizeWidget? tabBar;
  const SheetPage({
    super.key,
    required this.title,
    required this.children,
    this.showBack = true,
    this.headerTrailing,
    this.headerChild,
    this.headerBottomPad = 70,
    this.onRefresh,
    this.tabBar,
  });

  @override
  Widget build(BuildContext context) {
    Widget body = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      children: [
        GradientHeader(title: title, showBack: showBack, trailing: headerTrailing, child: headerChild, bottomPad: headerBottomPad),
        Transform.translate(
          offset: const Offset(0, -50),
          child: Container(
            decoration: const BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
            constraints: const BoxConstraints(minHeight: 400),
            padding: const EdgeInsets.fromLTRB(14, 18, 14, 30),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
          ),
        ),
      ],
    );
    if (onRefresh != null) body = RefreshIndicator(color: AppColors.orange, onRefresh: onRefresh!, child: body);
    return Scaffold(backgroundColor: AppColors.surface, body: body);
  }
}

/// White card with a soft navy-tinted lift shadow. An optional [spine] draws
/// a coloured edge — top by default, left when [spineLeft] is true — giving
/// the card meaning (blue = data, orange = attention).
class SoftCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final EdgeInsets margin;
  final VoidCallback? onTap;
  final Color? spine;
  final bool spineLeft;
  const SoftCard({super.key, required this.child, this.padding = const EdgeInsets.all(14), this.margin = EdgeInsets.zero, this.onTap, this.spine, this.spineLeft = false});

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: padding,
      margin: margin,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: spine == null
            ? null
            : Border(
                top: spineLeft ? BorderSide.none : BorderSide(color: spine!, width: 3),
                left: spineLeft ? BorderSide(color: spine!, width: 4) : BorderSide.none,
              ),
        boxShadow: const [BoxShadow(color: AppColors.softShadow, blurRadius: 16, offset: Offset(0, 6))],
      ),
      child: child,
    );
    return onTap == null ? card : GestureDetector(onTap: onTap, child: card);
  }
}

/// Small pill used for statuses/tags on the light theme.
class SoftPill extends StatelessWidget {
  final String text;
  final Color color;
  const SoftPill(this.text, this.color, {super.key});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
        child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
      );

  static Color forStatus(String s) {
    final t = s.toLowerCase();
    if (t.contains('approve') || t.contains('present') || t.contains('paid') || t.contains('active')) return AppColors.green;
    if (t.contains('reject') || t.contains('absent') || t.contains('absend')) return AppColors.red;
    if (t.contains('weekend') || t.contains('holiday')) return AppColors.violet;
    if (t.contains('pending') || t.contains('late') || t.contains('half')) return AppColors.orange;
    return AppColors.blue;
  }
}

/// Section header: orange tick + title.
class SectionTitle extends StatelessWidget {
  final String text;
  const SectionTitle(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Container(width: 3, height: 14, decoration: BoxDecoration(color: AppColors.orange, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 8),
          Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.ink)),
        ]),
      );
}
