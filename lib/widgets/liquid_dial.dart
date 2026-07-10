import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Animated circular dial with a rippling liquid fill + an orange progress arc.
/// [progress] 0..1 drives both the fill level and the arc sweep.
class LiquidDial extends StatefulWidget {
  final double size;
  final double progress;
  final Widget center;
  const LiquidDial({super.key, required this.size, required this.progress, required this.center});

  @override
  State<LiquidDial> createState() => _LiquidDialState();
}

class _LiquidDialState extends State<LiquidDial> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  double _shown = 0; // animated progress (eases toward widget.progress)

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();
    _c.addListener(_tick);
  }

  void _tick() {
    final target = widget.progress.clamp(0.0, 1.0);
    if ((_shown - target).abs() > 0.001) {
      setState(() => _shown += (target - _shown) * 0.05);
    }
  }

  @override
  void dispose() { _c.removeListener(_tick); _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(alignment: Alignment.center, children: [
        CustomPaint(
          size: Size(widget.size, widget.size),
          painter: _DialPainter(phase: _c.value * 2 * math.pi, level: _shown, progress: _shown),
        ),
        widget.center,
      ]),
    );
  }
}

class _DialPainter extends CustomPainter {
  final double phase, level, progress;
  _DialPainter({required this.phase, required this.level, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;
    final inner = r - 5;

    // Outer faint ring
    canvas.drawCircle(c, r, Paint()..color = Colors.white.withValues(alpha: 0.06));
    canvas.drawCircle(c, inner, Paint()..color = Colors.white.withValues(alpha: 0.05));
    canvas.drawCircle(c, inner, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white.withValues(alpha: 0.16));

    // Liquid fill, clipped to the inner circle
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: inner)));
    final fillTop = size.height * (1 - level * 0.78) - size.height * 0.06;
    _wave(canvas, size, fillTop, 4, phase, const Color(0xFF39A0FF), 0.92);
    _wave(canvas, size, fillTop + 6, 3, phase + 1.6, AppColors.blue, 0.5);
    canvas.restore();

    // Orange progress arc
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: inner),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.5
        ..strokeCap = StrokeCap.round
        ..color = AppColors.orange,
    );
  }

  void _wave(Canvas canvas, Size size, double base, double amp, double phase, Color color, double opacity) {
    final path = Path()..moveTo(0, base);
    for (double x = 0; x <= size.width; x += size.width / 12) {
      final y = base + math.sin((x / size.width * 4 * math.pi) + phase) * amp;
      path.lineTo(x, y);
    }
    path..lineTo(size.width, size.height)..lineTo(0, size.height)..close();
    canvas.drawPath(path, Paint()..color = color.withValues(alpha: opacity));
  }

  @override
  bool shouldRepaint(_DialPainter old) => old.phase != phase || old.level != level || old.progress != progress;
}

/// Carved geometry — rings and plates cut into the blue surface, with a
/// slow-bobbing orange ring (redesign v4, background variant A).
class MeshBlobs extends StatefulWidget {
  const MeshBlobs({super.key});
  @override
  State<MeshBlobs> createState() => _MeshBlobsState();
}

class _MeshBlobsState extends State<MeshBlobs> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 8))..repeat(reverse: true);
  }
  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final t = Curves.easeInOut.transform(_c.value);
        return ClipRect(
          child: Stack(children: [
            // Big carved ring, top right
            Positioned(
              top: -56, right: -56,
              child: Container(
                width: 180, height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withValues(alpha: 0.09), width: 28),
                ),
              ),
            ),
            // Rotated plate, left
            Positioned(
              top: 90, left: -44,
              child: Transform.rotate(
                angle: 28 * math.pi / 180,
                child: Container(
                  width: 120, height: 120,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(36),
                  ),
                ),
              ),
            ),
            // Bobbing orange ring, bottom right
            Positioned(
              bottom: 40 + t * 18, right: -26,
              child: Container(
                width: 92, height: 92,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.orange.withValues(alpha: 0.38), width: 15),
                ),
              ),
            ),
          ]),
        );
      },
    );
  }
}
