import 'package:flutter/material.dart';

class EcgPainter extends CustomPainter {
  final double progress;

  EcgPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.red
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();

    final width = size.width;
    final visibleWidth = width * progress;

    path.moveTo(0, size.height / 2);

    path.lineTo(visibleWidth * 0.15, size.height / 2);
    path.lineTo(visibleWidth * 0.22, size.height / 2 - 20);
    path.lineTo(visibleWidth * 0.28, size.height / 2 + 35);
    path.lineTo(visibleWidth * 0.35, size.height / 2 - 60);
    path.lineTo(visibleWidth * 0.42, size.height / 2 + 15);
    path.lineTo(visibleWidth * 0.50, size.height / 2);

    path.lineTo(visibleWidth, size.height / 2);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant EcgPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}