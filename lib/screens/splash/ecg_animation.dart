import 'dart:ui';

import 'package:flutter/material.dart';

import 'ecg_painter.dart';

class EcgAnimation extends StatefulWidget {
  const EcgAnimation({super.key});

  @override
  State<EcgAnimation> createState() => _EcgAnimationState();
}

class _EcgAnimationState extends State<EcgAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 300,
      height: 90,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return CustomPaint(
            painter: _AnimatedEcgPainter(_controller.value),
          );
        },
      ),
    );
  }
}

class _AnimatedEcgPainter extends CustomPainter {
  final double progress;

  _AnimatedEcgPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final fullPath = EcgPainter.buildPath(size);

    final metric = fullPath.computeMetrics().first;

    final drawPath = metric.extractPath(
      0,
      metric.length * progress,
    );

    final glowPaint = EcgPainter.createGlowPaint();
    final linePaint = EcgPainter.createLinePaint();

    canvas.drawPath(drawPath, glowPaint);
    canvas.drawPath(drawPath, linePaint);

    final tangent = metric.getTangentForOffset(
      metric.length * progress,
    );

    if (tangent != null) {
      final position = tangent.position;

      // Outer Glow
      canvas.drawCircle(
        position,
        10,
        Paint()
          ..color = Colors.red.withOpacity(.25)
          ..maskFilter = const MaskFilter.blur(
            BlurStyle.normal,
            12,
          ),
      );

      // Inner Glow
      canvas.drawCircle(
        position,
        6,
        Paint()
          ..color = Colors.redAccent,
      );

      // White Center
      canvas.drawCircle(
        position,
        2.5,
        Paint()..color = Colors.white,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AnimatedEcgPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}