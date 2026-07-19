class OnboardingModel {
  final String image;
  final String title;
  final String description;

  const OnboardingModel({
    required this.image,
    required this.title,
    required this.description,
  });
}

const List<OnboardingModel> onboardingData = [
  OnboardingModel(
    image: 'assets/images/onboarding1_3.png',
    title: 'Be Someone\'s Lifeline',
    description:
    'One blood donation can save up to three lives.\nJoin our community of lifesavers.',
  ),

  OnboardingModel(
    image: 'assets/images/onboarding2_3_1.png',
    title: 'Find Blood Instantly',
    description:
    'Locate nearby verified donors and blood banks whenever every second matters.',
  ),

  OnboardingModel(
    image: 'assets/images/onboarding3_3_1.png',
    title: 'Emergency Help in One Tap',
    description:
    'Send instant SOS alerts and connect with eligible donors around you.',
  ),
];