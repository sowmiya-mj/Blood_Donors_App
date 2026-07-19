import 'package:flutter/material.dart';

class EcgPainter extends CustomPainter {
  final Path path;
  final Paint glowPaint;
  final Paint linePaint;

  EcgPainter({
    required this.path,
    required this.glowPaint,
    required this.linePaint,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw Glow
    canvas.drawPath(path, glowPaint);

    // Draw Main ECG
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant EcgPainter oldDelegate) {
    return true;
  }

  /// Complete ECG Shape
  static Path buildPath(Size size) {
    final h = size.height / 2;
    final w = size.width;

    final path = Path();

    path.moveTo(0, h);

    // Straight line
    path.lineTo(w * 0.15, h);

    // Small Peak
    path.lineTo(w * 0.22, h - 18);
    path.lineTo(w * 0.28, h + 20);
    path.lineTo(w * 0.34, h);

    // Flat
    path.lineTo(w * 0.42, h);

    // Main Beat
    path.lineTo(w * 0.48, h - 65);
    path.lineTo(w * 0.54, h + 45);
    path.lineTo(w * 0.60, h - 12);
    path.lineTo(w * 0.66, h);

    // Second Small Beat
    path.lineTo(w * 0.72, h);
    path.lineTo(w * 0.76, h - 25);
    path.lineTo(w * 0.80, h + 18);
    path.lineTo(w * 0.84, h);

    // Ending
    path.lineTo(w, h);

    return path;
  }

  /// Main Red Line
  static Paint createLinePaint() {
    return Paint()
      ..color = const Color(0xFFD32F2F)
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
  }

  /// Soft Glow
  static Paint createGlowPaint() {
    return Paint()
      ..color = const Color(0x66D32F2F)
      ..strokeWidth = 10
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = const MaskFilter.blur(
        BlurStyle.normal,
        10,
      );
  }
}