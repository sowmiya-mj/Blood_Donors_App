import 'package:flutter/material.dart';

class NextButton extends StatefulWidget {
  final bool isLastPage;
  final VoidCallback onPressed;

  const NextButton({
    super.key,
    required this.isLastPage,
    required this.onPressed,
  });

  @override
  State<NextButton> createState() => _NextButtonState();
}

class _NextButtonState extends State<NextButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        setState(() => _isPressed = true);
      },
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onPressed();
      },
      onTapCancel: () {
        setState(() => _isPressed = false);
      },
      child: AnimatedScale(
        scale: _isPressed ? 0.95 : 1,
        duration: const Duration(milliseconds: 120),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          height: 58,
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            gradient: const LinearGradient(
              colors: [
                Color(0xFFE53935),
                Color(0xFFD32F2F),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.red.withOpacity(0.35),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                widget.isLastPage
                    ? "Get Started"
                    : "Next",
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),

              const SizedBox(width: 10),

              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Icon(
                  widget.isLastPage
                      ? Icons.favorite
                      : Icons.arrow_forward_rounded,
                  key: ValueKey(widget.isLastPage),
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}