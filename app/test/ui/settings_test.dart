import 'package:chatito/ui/fake/fake_chat_facade.dart';
import 'package:chatito/ui/screens/settings_screen.dart';
import 'package:chatito/ui/settings.dart';
import 'package:chatito/ui/strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  testWidgets('lista meus aparelhos e marca este aparelho', (tester) async {
    await pumpScreen(tester, const SettingsScreen());
    expect(find.textContaining('MacBook do Felipe'), findsOneWidget);
    expect(find.text('PC Windows'), findsOneWidget);
    expect(find.textContaining(S.thisDevice), findsOneWidget);
    expect(find.byKey(const Key('remove-dev_me')), findsNothing);
    expect(find.byKey(const Key('remove-dev_win')), findsOneWidget);
  });

  testWidgets('remover aparelho pede confirmação e remove', (tester) async {
    final f = FakeChatFacade.seeded();
    await pumpScreen(tester, const SettingsScreen(), facade: f);
    await tester.tap(find.byKey(const Key('remove-dev_win')));
    await tester.pumpAndSettle();
    expect(find.text(S.removeDeviceConfirm), findsOneWidget);
    await tester.tap(find.text(S.cancel));
    await tester.pumpAndSettle();
    expect(find.text('PC Windows'), findsOneWidget);
    await tester.tap(find.byKey(const Key('remove-dev_win')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(S.remove));
    await tester.pumpAndSettle();
    expect(find.text('PC Windows'), findsNothing);
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
