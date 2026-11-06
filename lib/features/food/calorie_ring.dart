import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/palette.dart';

/// Chunky pixel-flavored circular progress ring for daily calories,
/// matching the water ring's look (peach palette instead of sky).
/// Animates smoothly between values. Center is a free slot — the mascot
/// will live there later; the numbers sit below the ring.
class CalorieRing extends StatefulWidget {
  const CalorieRing({
    super.key,
    required this.totalKcal,
    required this.goalKcal,
    this.size = 230,
    this.centerChild = const SizedBox.shrink(),
  });

  final double totalKcal;
  final int goalKcal;
  final double size;
  final Widget centerChild;

  @override
  State<CalorieRing> createState() => _CalorieRingState();
}

class _CalorieRingState extends State<CalorieRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 550),
  );

  late double _display = _target();
  Animation<double>? _anim;

  double _target() {
    if (widget.goalKcal <= 0) return 0;
    return (widget.totalKcal / widget.goalKcal).clamp(0.0, 1.0);
  }

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      if (_anim != null && mounted) {
        setState(() => _display = _anim!.value);
      }
    });
  }

  @override
  void didUpdateWidget(covariant CalorieRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    final to = _target();
    if ((to - _display).abs() > 0.0001) {
      _anim = Tween<double>(begin: _display, end: to).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
      );
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size.square(widget.size),
            painter: _CalorieRingPainter(_display),
          ),
          widget.centerChild,
        ],
      ),
    );
  }
}

class _CalorieRingPainter extends CustomPainter {
  _CalorieRingPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 18.0;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - stroke / 2 - 3;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Outline pass (chunky pixel-ish border), then base, then fill arc.
    final outlinePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke + 4
      ..color = Palette.outline;
    canvas.drawCircle(center, radius, outlinePaint);

    final basePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = Palette.creamDeep;
    canvas.drawCircle(center, radius, basePaint);

    if (progress > 0) {
      final fillPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = progress >= 1 ? Palette.peachDeep : Palette.peach;
      canvas.drawArc(
          rect, -math.pi / 2, 2 * math.pi * progress, false, fillPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _CalorieRingPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
