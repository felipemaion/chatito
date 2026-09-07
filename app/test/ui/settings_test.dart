import 'package:chatito/domain/domain.dart';
import 'package:chatito/domain/fakes/fake_chat_facade.dart';
import 'package:chatito/platform/server_config.dart';
import 'package:chatito/ui/providers.dart';
import 'package:chatito/ui/screens/settings_screen.dart';
import 'package:chatito/ui/settings.dart';
import 'package:chatito/ui/strings.dart';
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  testWidgets('lista meu aparelho marcado como este aparelho', (tester) async {
    await pumpScreen(tester, const SettingsScreen());
    expect(find.textContaining('MacBook do Felipe'), findsOneWidget);
    expect(find.textContaining(S.thisDevice), findsOneWidget);
  });

  testWidgets('switch de notificações altera a preferência', (tester) async {
    late ProviderContainer container;
    await pumpScreen(
      tester,
      Consumer(
        builder: (context, ref, _) {
          container = ProviderScope.containerOf(context);
          return const SettingsScreen();
        },
      ),
    );
    expect(container.read(settingsProvider).notificationsEnabled, isTrue);
    await tester.tap(find.byKey(const Key('notifications-switch')));
    await tester.pumpAndSettle();
    expect(container.read(settingsProvider).notificationsEnabled, isFalse);
  });

  testWidgets('sobre mostra versão e protocolo', (tester) async {
    await pumpScreen(tester, const SettingsScreen());
    expect(find.textContaining(S.version), findsOneWidget);
    expect(find.text(S.protocol), findsOneWidget);
  });

  testWidgets('campo servidor começa preenchido com a URL atual', (
    tester,
  ) async {
    late ProviderContainer container;
    await pumpScreen(
      tester,
      Consumer(
        builder: (context, ref, _) {
          container = ProviderScope.containerOf(context);
          return const SettingsScreen();
        },
      ),
    );
    final field = tester.widget<TextField>(
      find.byKey(const Key('settings-server-url')),
    );
    expect(field.controller!.text, container.read(serverUrlProvider));
  });

  testWidgets('URL inválida em Ajustes mostra erro e não mexe no servidor', (
    tester,
  ) async {
    late ProviderContainer container;
    await pumpScreen(
      tester,
      Consumer(
        builder: (context, ref, _) {
          container = ProviderScope.containerOf(context);
          return const SettingsScreen();
        },
      ),
    );
    final before = container.read(serverUrlProvider);
    await tester.enterText(
      find.byKey(const Key('settings-server-url')),
      'sem-esquema.exemplo.com',
    );
    await tester.tap(find.byKey(const Key('save-server-url')));
    await tester.pumpAndSettle();
    expect(find.text(S.invalidServerUrl), findsOneWidget);
    expect(container.read(serverUrlProvider), before);
  });

  testWidgets(
    'salvar URL válida em Ajustes atualiza o provider, persiste e reconecta',
    (tester) async {
      final f = FakeChatFacade(autoReplyDelay: Duration.zero);
      final saved = <String>[];
      late ProviderContainer container;
      await pumpScreen(
        tester,
        Consumer(
          builder: (context, ref, _) {
            container = ProviderScope.containerOf(context);
            return const SettingsScreen();
          },
        ),
        facade: f,
        overrides: [
          serverUrlPersisterProvider.overrideWithValue((url) async {
            saved.add(url);
          }),
        ],
      );
      expect(container.read(connectionProvider), ConnectionState.offline);
      await tester.enterText(
        find.byKey(const Key('settings-server-url')),
        'http://192.168.15.8:9090',
      );
      await tester.tap(find.byKey(const Key('save-server-url')));
      await tester.pumpAndSettle();
      expect(container.read(serverUrlProvider), 'http://192.168.15.8:9090');
      expect(container.read(serverConfiguredProvider), isTrue);
      expect(saved, ['http://192.168.15.8:9090']);
      expect(container.read(connectionProvider), ConnectionState.online);
    },
  );
}
