import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ui/app.dart';
import 'ui/fake/fake_chat_facade.dart';
import 'ui/providers.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Até o app-core expor a ChatFacade real, o app roda com o fake em memória.
  final facade = FakeChatFacade.seeded(autoReply: true);
  runApp(
    ProviderScope(
      overrides: [chatFacadeProvider.overrideWithValue(facade)],
      child: const MainApp(),
    ),
  );
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) => const ChatitoApp();
}
