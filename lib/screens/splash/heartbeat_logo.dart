import 'dart:math' as math;

import 'package:flutter/material.dart';

class HeartbeatLogo extends StatefulWidget {
  const HeartbeatLogo({super.key});

  @override
  State<HeartbeatLogo> createState() => _HeartbeatLogoState();
}

class _HeartbeatLogoState extends State<HeartbeatLogo>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final AnimationController _floatController;
  late final AnimationController _shineController;

  @override
  void initState() {
    super.initState();

    // Heartbeat Animation
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    // Floating Animation
    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat(reverse: true);

    // Shine Animation
    _shineController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _floatController.dispose();
    _shineController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        _pulseController,
        _floatController,
        _shineController,
      ]),
      builder: (context, child) {
        final scale = 1 + (_pulseController.value * 0.08);

        final floatY = math.sin(_floatController.value * math.pi * 2) * 8;

        return Transform.translate(
          offset: Offset(0, floatY),
          child: Transform.scale(
            scale: scale,
            child: Stack(
              alignment: Alignment.center,
              children: [

                // Soft Glow
                Container(
                  width: 180,
                  height: 180,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.red.withOpacity(0.18),
                        blurRadius: 45,
                        spreadRadius: 15,
                      ),
                    ],
                  ),
                ),

                // Logo
                ClipRRect(
                  borderRadius: BorderRadius.circular(100),
                  child: Stack(
                    children: [

                      Image.asset(
                        "assets/images/logo1.png",
                        width: 150,
                        height: 130,
                        fit: BoxFit.contain,
                      ),

                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}