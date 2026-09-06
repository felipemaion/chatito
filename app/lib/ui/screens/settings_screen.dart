import 'package:flutter/material.dart';

import '../strings.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(
    key: Key('settings'),
    body: Center(child: Text(S.settings)),
  );
}
