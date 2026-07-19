import 'dart:math' as math;
import 'package:flutter/material.dart';

class AnimatedIllustration extends StatefulWidget {
  final String imagePath;

  const AnimatedIllustration({
    super.key,
    required this.imagePath,
  });

  @override
  State<AnimatedIllustration> createState() =>
      _AnimatedIllustrationState();
}

class _AnimatedIllustrationState
    extends State<AnimatedIllustration>
    with TickerProviderStateMixin {
  late AnimationController _floatController;
  late AnimationController _fadeController;
  late AnimationController _pulseController;

  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();

    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, .15),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _fadeController,
        curve: Curves.easeOutBack,
      ),
    );

    _fadeController.forward();
  }

  @override
  void dispose() {
    _floatController.dispose();
    _fadeController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    final imageSize = width > 900
        ? 500.0
        : width > 600
        ? 380.0
        : 280.0;

    return AnimatedBuilder(
      animation: Listenable.merge([
        _floatController,
        _pulseController,
      ]),
      builder: (context, child) {
        final floatOffset =
            math.sin(_floatController.value * 2 * math.pi) * 10;

        final pulseScale =
            1 + (_pulseController.value * .03);

        return FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(
            position: _slideAnimation,
            child: Transform.translate(
              offset: Offset(0, floatOffset),
              child: Transform.scale(
                scale: pulseScale,
                child: Stack(
                  alignment: Alignment.center,
                  children: [

                    // Soft Glow
                    Container(
                      width: imageSize * .85,
                      height: imageSize * .85,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.red.withOpacity(.12),
                            blurRadius: 70,
                            spreadRadius: 25,
                          ),
                        ],
                      ),
                    ),

                    Hero(
                      tag: widget.imagePath,
                      child: Image.asset(
                        widget.imagePath,
                        width: imageSize,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}