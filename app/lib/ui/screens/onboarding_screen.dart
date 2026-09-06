import 'package:flutter/material.dart';

import '../strings.dart';

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      key: Key('onboarding'),
      body: Center(child: Text(S.onboardingTitle)),
    );
  }
}
