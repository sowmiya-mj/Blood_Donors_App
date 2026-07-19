import 'package:flutter/material.dart';

import 'onboarding_model.dart';
import 'widgets/animated_illustration.dart';

class OnboardingPage extends StatelessWidget {
  final OnboardingModel model;

  const OnboardingPage({
    super.key,
    required this.model,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    final isDesktop = size.width >= 900;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 24,
          vertical: 20,
        ),
        child: isDesktop
            ? Row(
          children: [
            Expanded(
              child: Center(
                child: AnimatedIllustration(
                  imagePath: model.image,
                ),
              ),
            ),
            const SizedBox(width: 40),
            Expanded(
              child: _buildTextSection(context),
            ),
          ],
        )
            : Column(
          children: [
            const Spacer(),

            AnimatedIllustration(
              imagePath: model.image,
            ),

            const SizedBox(height: 40),

            _buildTextSection(context),

            const Spacer(),
          ],
        ),
      ),
    );
  }

  Widget _buildTextSection(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [

        Text(
          model.title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.bold,
            color: Color(0xFFD32F2F),
          ),
        ),

        const SizedBox(height: 20),

        Text(
          model.description,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 17,
            color: Colors.grey.shade700,
            height: 1.6,
          ),
        ),
      ],
    );
  }
}