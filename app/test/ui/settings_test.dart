import 'package:chatito/ui/screens/settings_screen.dart';
import 'package:chatito/ui/settings.dart';
import 'package:chatito/ui/strings.dart';
import 'package:flutter/material.dart';
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
}
