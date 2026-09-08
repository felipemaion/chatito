import 'package:piriquito/domain/fakes/fake_chat_facade.dart';
import 'package:piriquito/ui/layout.dart';
import 'package:piriquito/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  group('tema', () {
    test('claro e escuro em Material 3', () {
      expect(buildTheme(Brightness.light).brightness, Brightness.light);
      expect(buildTheme(Brightness.dark).brightness, Brightness.dark);
      expect(buildTheme(Brightness.dark).useMaterial3, isTrue);
    });
  });

  group('layout', () {
    testWidgets('isWide depende da largura', (tester) async {
      Future<bool> probe(Size size) async {
        late bool wide;
        await tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(size: size),
            child: Builder(
              builder: (c) {
                wide = isWide(c);
                return const SizedBox();
              },
            ),
          ),
        );
        return wide;
      }

      expect(await probe(wideSize), isTrue);
      expect(await probe(phoneSize), isFalse);
      expect(await probe(const Size(wideBreakpoint, 600)), isTrue);
    });
  });

  group('app', () {
    testWidgets('sem registro vai para onboarding', (tester) async {
      await pumpApp(tester, facade: FakeChatFacade(startRegistered: false));
      expect(find.byKey(const Key('onboarding')), findsOneWidget);
    });

    testWidgets('registrado abre lista de conversas em pt-BR', (tester) async {
      await pumpApp(tester);
      expect(find.byKey(const Key('conversations')), findsOneWidget);
      expect(find.text('Família'), findsOneWidget);
      final ctx = tester.element(find.byKey(const Key('conversations')));
      expect(Localizations.localeOf(ctx).languageCode, 'pt');
    });

    testWidgets('desktop mostra lista e painel de chat lado a lado', (
      tester,
    ) async {
      await pumpApp(tester, size: wideSize, initialLocation: '/c/g:familia');
      expect(find.byKey(const Key('conversations')), findsOneWidget);
      expect(find.byKey(const Key('chat')), findsOneWidget);
    });

    testWidgets('desktop sem conversa selecionada mostra placeholder', (
      tester,
    ) async {
      await pumpApp(tester, size: wideSize);
      expect(find.byKey(const Key('chat-empty')), findsOneWidget);
    });

    testWidgets('celular mostra só a lista, e o chat em pilha', (tester) async {
      await pumpApp(tester, size: phoneSize);
      expect(find.byKey(const Key('conversations')), findsOneWidget);
      expect(find.byKey(const Key('chat')), findsNothing);
      await tester.tap(find.text('Família'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('chat')), findsOneWidget);
      expect(find.byKey(const Key('conversations')), findsNothing);
      // volta
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('conversations')), findsOneWidget);
    });
  });
}
