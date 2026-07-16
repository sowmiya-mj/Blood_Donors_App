import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';

class HeartbeatLogo extends StatefulWidget {
  const HeartbeatLogo({super.key});

  @override
  State<HeartbeatLogo> createState() => _HeartbeatLogoState();
}

class _HeartbeatLogoState extends State<HeartbeatLogo>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _animation = Tween<double>(
      begin: 1.0,
      end: 1.12,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _animation,
      child: Container(
        width: 150,
        height: 150,
        decoration: BoxDecoration(
          color: AppColors.primary.withOpacity(0.1),
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.bloodtype,
          color: AppColors.primary,
          size: 90,
        ),
      ),
    );
  }
}