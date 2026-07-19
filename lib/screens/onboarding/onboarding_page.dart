import 'package:flutter/material.dart';
import 'onboarding_model.dart';
import 'widgets/animated_illustration.dart';

class OnboardingPage extends StatefulWidget {
  final OnboardingModel model;

  const OnboardingPage({
    super.key,
    required this.model,
  });

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage>
    with TickerProviderStateMixin {
  late AnimationController _textController;
  late Animation<double> _textFade;
  late Animation<Offset> _titleSlide;
  late Animation<Offset> _descSlide;

  @override
  void initState() {
    super.initState();

    _textController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _textFade = CurvedAnimation(
      parent: _textController,
      curve: Curves.easeOut,
    );

    // Title flies in from top
    _titleSlide = Tween<Offset>(
      begin: const Offset(0, -0.4),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _textController,
        curve: Curves.easeOutBack,
      ),
    );

    // Description flies in from top after title
    _descSlide = Tween<Offset>(
      begin: const Offset(0, -0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _textController,
        curve: Curves.easeOut,
      ),
    );

    // Image animates first, text follows after 300ms
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _textController.forward();
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

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
                  imagePath: widget.model.image,
                ),
              ),
            ),
            const SizedBox(width: 40),
            Expanded(
              child: _buildTextSection(),
            ),
          ],
        )
            : Column(
          children: [
            const Spacer(),
            AnimatedIllustration(
              imagePath: widget.model.image,
            ),
            const SizedBox(height: 40),
            _buildTextSection(),
            const Spacer(),
          ],
        ),
      ),
    );
  }

  Widget _buildTextSection() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [

        // Title — flies in from top
        FadeTransition(
          opacity: _textFade,
          child: SlideTransition(
            position: _titleSlide,
            child: Text(
              widget.model.title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 27,
                fontWeight: FontWeight.bold,
                color: Color(0xFFD32F2F),
              ),
            ),
          ),
        ),

        const SizedBox(height: 20),

        // Description — flies in from top slightly softer
        FadeTransition(
          opacity: _textFade,
          child: SlideTransition(
            position: _descSlide,
            child: Text(
              widget.model.description,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                color: Colors.grey.shade700,
                height: 1.6,
              ),
            ),
          ),
        ),
      ],
    );
  }
}