import 'package:chatito/platform/files.dart';
import 'package:chatito/ui/contracts.dart';
import 'package:chatito/ui/fake/fake_chat_facade.dart';
import 'package:chatito/ui/screens/chat_screen.dart';
import 'package:chatito/ui/strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

class _FakePicker implements FilePickerService {
  _FakePicker(this.result);
  final PickedFile? result;
  int calls = 0;
  @override
  Future<PickedFile?> pick() async {
    calls++;
    return result;
  }
}

class _FakeOpener implements FileOpener {
  final opened = <String>[];
  @override
  Future<void> open(String path) async => opened.add(path);
}

void main() {
  const conv = FakeChatFacade.groupConv;

  testWidgets('mostra mensagens com nome do remetente em grupo', (
    tester,
  ) async {
    await pumpScreen(tester, const ChatScreen(convId: conv));
    expect(find.text('Chegaram bem?'), findsOneWidget);
    expect(find.text('Mãe'), findsWidgets);
    expect(find.text('Sim! Tudo certo por aqui.'), findsOneWidget);
  });

  testWidgets('abrir a conversa marca como lida', (tester) async {
    final f = FakeChatFacade.seeded();
    await pumpScreen(tester, const ChatScreen(convId: conv), facade: f);
    expect(
      f.conversations.value.firstWhere((c) => c.id == conv).unreadCount,
      0,
    );
  });

  testWidgets('envia texto e limpa o campo', (tester) async {
    final f = FakeChatFacade.seeded();
    await pumpScreen(tester, const ChatScreen(convId: conv), facade: f);
    final send = find.byKey(const Key('send'));
    expect(tester.widget<IconButton>(send).onPressed, isNull);
    await tester.enterText(find.byKey(const Key('composer')), 'Oi família');
    await tester.pump();
    expect(tester.widget<IconButton>(send).onPressed, isNotNull);
    await tester.tap(send);
    await tester.pumpAndSettle();
    expect(f.messages(conv).value.last.body, 'Oi família');
    expect(find.text('Oi família'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('composer')))
          .controller!
          .text,
      '',
    );
  });

  testWidgets('Enter envia no desktop', (tester) async {
    final f = FakeChatFacade.seeded();
    await pumpScreen(
      tester,
      const ChatScreen(convId: conv),
      facade: f,
      size: wideSize,
    );
    await tester.enterText(find.byKey(const Key('composer')), 'via enter');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();
    expect(f.messages(conv).value.last.body, 'via enter');
  });

  testWidgets('recibos: entregue e lido', (tester) async {
    await pumpScreen(tester, const ChatScreen(convId: 'u:usr_A:usr_B'));
    expect(find.byKey(const Key('receipt-read')), findsOneWidget);
    await pumpScreen(tester, const ChatScreen(convId: conv));
    expect(find.byKey(const Key('receipt-delivered')), findsOneWidget);
  });

  testWidgets('mensagem recebida aparece e conversa segue lida', (
    tester,
  ) async {
    final f = FakeChatFacade.seeded();
    await pumpScreen(tester, const ChatScreen(convId: conv), facade: f);
    f.simulateIncoming(conv, 'chegou agora');
    await tester.pumpAndSettle();
    expect(find.text('chegou agora'), findsOneWidget);
    expect(
      f.conversations.value.firstWhere((c) => c.id == conv).unreadCount,
      0,
    );
  });

  testWidgets('anexo: baixar mostra progresso e depois abre com o sistema', (
    tester,
  ) async {
    final f = FakeChatFacade.seeded(progressSteps: 3);
    final opener = _FakeOpener();
    await pumpScreen(
      tester,
      const ChatScreen(convId: conv),
      facade: f,
      overrides: [fileOpenerProvider.overrideWithValue(opener)],
    );
    expect(find.text('praia.jpg'), findsOneWidget);
    expect(find.text('2,3 MB'), findsOneWidget);
    await tester.tap(find.byKey(const Key('download-blob_praia')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('open-blob_praia')), findsOneWidget);
    await tester.tap(find.byKey(const Key('open-blob_praia')));
    await tester.pumpAndSettle();
    expect(opener.opened, ['/tmp/chatito/blob_praia']);
  });

  testWidgets('anexar arquivo envia com progresso de upload', (tester) async {
    final f = FakeChatFacade.seeded(progressSteps: 3);
    final picker = _FakePicker(
      const PickedFile(
        path: '/tmp/doc.pdf',
        name: 'doc.pdf',
        size: 4096,
        mime: 'application/pdf',
      ),
    );
    await pumpScreen(
      tester,
      const ChatScreen(convId: conv),
      facade: f,
      overrides: [filePickerProvider.overrideWithValue(picker)],
    );
    await tester.tap(find.byKey(const Key('attach')));
    await tester.pump();
    expect(picker.calls, 1);
    await tester.pumpAndSettle();
    final last = f.messages(conv).value.last;
    expect(last.kind, MessageKind.file);
    expect(last.attachments.first.transfer.state, TransferState.done);
    expect(find.text('doc.pdf'), findsOneWidget);
    expect(find.text('4,0 KB'), findsOneWidget);
  });

  testWidgets('picker cancelado não envia nada', (tester) async {
    final f = FakeChatFacade.seeded();
    final before = f.messages(conv).value.length;
    await pumpScreen(
      tester,
      const ChatScreen(convId: conv),
      facade: f,
      overrides: [filePickerProvider.overrideWithValue(_FakePicker(null))],
    );
    await tester.tap(find.byKey(const Key('attach')));
    await tester.pumpAndSettle();
    expect(f.messages(conv).value.length, before);
  });

  testWidgets('conversa vazia mostra aviso', (tester) async {
    await pumpScreen(tester, const ChatScreen(convId: 'u:usr_A:usr_C'));
    expect(find.text(S.noMessages), findsOneWidget);
  });

  testWidgets('título abre detalhe do contato em 1:1', (tester) async {
    await pumpApp(tester, size: phoneSize, initialLocation: '/c/u:usr_A:usr_B');
    await tester.tap(find.byKey(const Key('chat-title')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('contact')), findsOneWidget);
  });

  testWidgets('erro ao enviar mostra snackbar', (tester) async {
    final f = FakeChatFacade.seeded();
    await pumpScreen(tester, const ChatScreen(convId: conv), facade: f);
    f.failNextSend = const ChatException('rate_limited', 'Muitas mensagens');
    await tester.enterText(find.byKey(const Key('composer')), 'x');
    await tester.pump();
    await tester.tap(find.byKey(const Key('send')));
    await tester.pumpAndSettle();
    expect(find.text('Muitas mensagens'), findsOneWidget);
  });
}
