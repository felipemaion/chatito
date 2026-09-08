import 'package:piriquito/domain/domain.dart';
import 'package:piriquito/domain/fakes/fake_chat_facade.dart';
import 'package:piriquito/platform/server_config.dart';
import 'package:piriquito/ui/strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

FakeChatFacade _unregistered() =>
    FakeChatFacade(startRegistered: false, autoReplyDelay: Duration.zero);

void main() {
  testWidgets('valida campos obrigatórios', (tester) async {
    await pumpApp(tester, facade: _unregistered(), size: phoneSize);
    await tester.enterText(find.byKey(const Key('device-name')), '');
    await tester.tap(find.byKey(const Key('register')));
    await tester.pumpAndSettle();
    expect(find.text(S.required), findsNWidgets(2));
  });

  testWidgets('mostra erro de convite inválido', (tester) async {
    await pumpApp(tester, facade: _unregistered(), size: phoneSize);
    await tester.enterText(
      find.byKey(const Key('invite')),
      FakeChatFacade.badInvite,
    );
    await tester.enterText(find.byKey(const Key('device-name')), 'Meu Mac');
    await tester.tap(find.byKey(const Key('register')));
    await tester.pumpAndSettle();
    expect(find.text(S.invalidInvite), findsOneWidget);
    expect(find.byKey(const Key('onboarding')), findsOneWidget);
  });

  testWidgets('registra e vai para a lista de conversas', (tester) async {
    final f = await pumpApp(tester, facade: _unregistered(), size: phoneSize);
    await tester.enterText(find.byKey(const Key('invite')), ' 7k3m-9qzr ');
    await tester.enterText(find.byKey(const Key('device-name')), 'Meu Mac');
    await tester.tap(find.byKey(const Key('register')));
    await tester.pumpAndSettle();
    final session = await f.session;
    expect(session, isA<Registered>());
    expect((session as Registered).device.name, 'Meu Mac');
    expect(find.byKey(const Key('conversations')), findsOneWidget);
  });

  testWidgets('código é formatado em maiúsculas com hífen', (tester) async {
    await pumpApp(tester, facade: _unregistered(), size: phoneSize);
    await tester.enterText(find.byKey(const Key('invite')), '7k3m9qzr');
    await tester.pump();
    final field = tester.widget<TextFormField>(find.byKey(const Key('invite')));
    expect(field.controller!.text, '7K3M-9QZR');
  });

  testWidgets('endereço de servidor inválido não registra e mostra erro', (
    tester,
  ) async {
    final f = await pumpApp(tester, facade: _unregistered(), size: phoneSize);
    await tester.enterText(find.byKey(const Key('invite')), '7K3M-9QZR');
    await tester.enterText(find.byKey(const Key('device-name')), 'Meu Mac');
    await tester.enterText(
      find.byKey(const Key('server-url')),
      '192.168.0.10:8080', // sem http(s)://
    );
    await tester.tap(find.byKey(const Key('register')));
    await tester.pumpAndSettle();
    expect(find.text(S.invalidServerUrl), findsOneWidget);
    expect(find.byKey(const Key('onboarding')), findsOneWidget);
    expect(await f.session, isA<NotRegistered>());
  });

  testWidgets('registrar persiste a URL do servidor (sobrevive a reiniciar)', (
    tester,
  ) async {
    final saved = <String>[];
    await pumpApp(
      tester,
      facade: _unregistered(),
      size: phoneSize,
      overrides: [
        serverUrlPersisterProvider.overrideWithValue((url) async {
          saved.add(url);
        }),
      ],
    );
    await tester.enterText(find.byKey(const Key('invite')), '7K3M-9QZR');
    await tester.enterText(find.byKey(const Key('device-name')), 'Meu Mac');
    await tester.enterText(
      find.byKey(const Key('server-url')),
      'http://192.168.15.8:8080',
    );
    await tester.tap(find.byKey(const Key('register')));
    await tester.pumpAndSettle();
    expect(saved, ['http://192.168.15.8:8080']);
  });
}
