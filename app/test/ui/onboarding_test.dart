import 'package:chatito/ui/fake/fake_chat_facade.dart';
import 'package:chatito/ui/strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  testWidgets('valida campos obrigatórios', (tester) async {
    await pumpApp(tester, facade: FakeChatFacade(), size: phoneSize);
    await tester.enterText(find.byKey(const Key('device-name')), '');
    await tester.tap(find.byKey(const Key('register')));
    await tester.pumpAndSettle();
    expect(find.text(S.required), findsNWidgets(2));
  });

  testWidgets('mostra erro de convite inválido', (tester) async {
    await pumpApp(tester, facade: FakeChatFacade(), size: phoneSize);
    await tester.enterText(find.byKey(const Key('invite')), 'AAAA-0000');
    await tester.enterText(find.byKey(const Key('device-name')), 'Meu Mac');
    await tester.tap(find.byKey(const Key('register')));
    await tester.pumpAndSettle();
    expect(find.text(S.invalidInvite), findsOneWidget);
    expect(find.byKey(const Key('onboarding')), findsOneWidget);
  });

  testWidgets('registra e vai para a lista de conversas', (tester) async {
    final f = await pumpApp(tester, facade: FakeChatFacade(), size: phoneSize);
    await tester.enterText(find.byKey(const Key('invite')), ' 7k3m-9qzr ');
    await tester.enterText(find.byKey(const Key('device-name')), 'Meu Mac');
    await tester.tap(find.byKey(const Key('register')));
    await tester.pumpAndSettle();
    expect(f.session.value.isRegistered, isTrue);
    expect(f.session.value.me!.device.name, 'Meu Mac');
    expect(find.byKey(const Key('conversations')), findsOneWidget);
  });

  testWidgets('código é formatado em maiúsculas com hífen', (tester) async {
    await pumpApp(tester, facade: FakeChatFacade(), size: phoneSize);
    await tester.enterText(find.byKey(const Key('invite')), '7k3m9qzr');
    await tester.pump();
    final field = tester.widget<TextFormField>(find.byKey(const Key('invite')));
    expect(field.controller!.text, '7K3M-9QZR');
  });
}
