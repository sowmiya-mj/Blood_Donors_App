import 'package:flutter/material.dart';

class BloodIndicator extends StatelessWidget {
  final int currentIndex;
  final int itemCount;

  const BloodIndicator({
    super.key,
    required this.currentIndex,
    required this.itemCount,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        itemCount,
            (index) => AnimatedContainer(
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOut,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          child: Icon(
            Icons.water_drop,
            size: currentIndex == index ? 24 : 16,
            color: currentIndex == index
                ? Colors.red
                : Colors.red.shade200,
            shadows: currentIndex == index
                ? const [
              Shadow(
                color: Colors.redAccent,
                blurRadius: 15,
              ),
            ]
                : [],
          ),
        ),
      ),
    );
  }
}