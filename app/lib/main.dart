import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sodium/sodium.dart';

import 'platform/app_services.dart';
import 'platform/platform_info.dart';
import 'platform/real_chat_facade_provider.dart';
import 'platform/secure_key_store.dart';
import 'platform/window.dart';
import 'storage/storage.dart';
import 'ui/app.dart';
import 'ui/providers.dart';
import 'ui/router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final platform = PlatformInfo.detect();
  await initializeDateFormatting('pt_BR');
  await setupWindow(platform);

  final sodium = await SodiumInit.init();
  final db = ChatDatabase(driftDatabase(name: 'chatito'));
  final keyStore = SecureKeyStore();

  runApp(
    ProviderScope(
      overrides: [
        platformInfoProvider.overrideWithValue(platform),
        chatDepsProvider.overrideWithValue(
          RealChatDeps(sodium: sodium, db: db, keyStore: keyStore),
        ),
        chatFacadeProvider.overrideWith(
          (ref) => ref.watch(realChatFacadeProvider),
        ),
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
