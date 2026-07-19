import 'package:flutter/material.dart';

import '../auth/role_selection_screen.dart';
import 'onboarding_model.dart';
import 'onboarding_page.dart';
import 'widgets/blood_indicator.dart';
import 'widgets/next_button.dart';
import 'widgets/skip_button.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();

  int currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (currentPage < onboardingData.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => const RoleSelectionScreen(),
        ),
      );
    }
  }

  void _skip() {
    _pageController.animateToPage(
      onboardingData.length - 1,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 900;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // Background Glow
          Positioned(
            top: -120,
            left: -80,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.red.withOpacity(.06),
              ),
            ),
          ),

          Column(
            children: [
              SkipButton(
                onPressed: _skip,
              ),

              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: onboardingData.length,
                  onPageChanged: (index) {
                    setState(() {
                      currentPage = index;
                    });
                  },
                  itemBuilder: (context, index) {
                    return OnboardingPage(
                      model: onboardingData[index],
                    );
                  },
                ),
              ),

              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: isDesktop ? 120 : 24,
                  vertical: 24,
                ),
                child: Column(
                  children: [
                    BloodIndicator(
                      currentIndex: currentPage,
                      itemCount: onboardingData.length,
                    ),

                    const SizedBox(height: 25),

                    NextButton(
                      isLastPage:
                      currentPage == onboardingData.length - 1,
                      onPressed: _nextPage,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}