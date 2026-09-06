import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'platform/app_services.dart';
import 'platform/platform_info.dart';
import 'platform/window.dart';
import 'ui/app.dart';
import 'ui/fake/fake_chat_facade.dart';
import 'ui/providers.dart';
import 'ui/router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final platform = PlatformInfo.detect();
  await initializeDateFormatting('pt_BR');
  await setupWindow(platform);
  // Até o app-core expor a ChatFacade real, o app roda com o fake em memória.
  final facade = FakeChatFacade.seeded(autoReply: true);
  runApp(
    ProviderScope(
      overrides: [
        chatFacadeProvider.overrideWithValue(facade),
        platformInfoProvider.overrideWithValue(platform),
      ],
      child: const MainApp(),
    ),
  );
}

class MainApp extends ConsumerWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppServices(
      onOpenConversation: (id) =>
          ref.read(routerProvider(null)).go('/c/${Uri.encodeComponent(id)}'),
      child: const ChatitoApp(),
    );
  }
}
