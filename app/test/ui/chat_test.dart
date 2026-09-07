import 'dart:io';

import 'package:chatito/domain/domain.dart';
import 'package:chatito/domain/fakes/fake_chat_facade.dart';
import 'package:chatito/platform/files.dart';
import 'package:chatito/protocol/protocol.dart' show ConvId;
import 'package:chatito/ui/screens/chat_screen.dart';
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

/// Sem resposta automática (delay bem longo) — para não interferir em testes
/// que verificam a própria mensagem enviada.
FakeChatFacade _seeded() =>
    FakeChatFacade(autoReplyDelay: const Duration(days: 1));

/// Com resposta automática imediata — só para o teste que exercita esse fluxo.
FakeChatFacade _seededAutoReply() =>
    FakeChatFacade(autoReplyDelay: Duration.zero);

void main() {
  final family = ConvId.family;
  final direct = ConvId.direct(FakeChatFacade.felipeId, FakeChatFacade.maeId);

  testWidgets('mostra mensagens com nome do remetente em grupo', (
    tester,
  ) async {
    await pumpScreen(tester, ChatScreen(convId: family));
    expect(find.text('Bem-vindos ao Chatito! 🎉'), findsOneWidget);
    expect(find.text('Mãe'), findsWidgets);
    expect(find.text('Que chique! Funciona no meu celular?'), findsOneWidget);
  });

  testWidgets('abrir a conversa marca como lida', (tester) async {
    final f = _seeded();
    await pumpScreen(tester, ChatScreen(convId: family), facade: f);
    final convs = await f.watchConversations().first;
    expect(convs.firstWhere((c) => c.id == family).unreadCount, 0);
  });

  testWidgets('envia texto e limpa o campo', (tester) async {
    final f = _seeded();
    await pumpScreen(tester, ChatScreen(convId: family), facade: f);
    final send = find.byKey(const Key('send'));
    expect(tester.widget<IconButton>(send).onPressed, isNull);
    await tester.enterText(find.byKey(const Key('composer')), 'Oi família');
    await tester.pump();
    expect(tester.widget<IconButton>(send).onPressed, isNotNull);
    await tester.tap(send);
    await tester.pumpAndSettle();
    final msgs = await f.watchMessages(family).first;
    expect(msgs.last.body, 'Oi família');
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
    final f = _seeded();
    await pumpScreen(
      tester,
      ChatScreen(convId: family),
      facade: f,
      size: wideSize,
    );
    await tester.enterText(find.byKey(const Key('composer')), 'via enter');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();
    final msgs = await f.watchMessages(family).first;
    expect(msgs.last.body, 'via enter');
  });

  testWidgets('recibos: entregue e lido', (tester) async {
    await pumpScreen(tester, ChatScreen(convId: direct));
    expect(find.byKey(const Key('receipt-read')), findsOneWidget);
    await pumpScreen(tester, ChatScreen(convId: family));
    expect(find.byKey(const Key('receipt-delivered')), findsOneWidget);
  });

  testWidgets(
    'resposta automática chega com a conversa aberta e continua lida',
    (tester) async {
      final f = _seededAutoReply();
      await pumpScreen(tester, ChatScreen(convId: direct), facade: f);
      await tester.enterText(find.byKey(const Key('composer')), 'oi mãe');
      await tester.tap(find.byKey(const Key('send')));
      await tester.pumpAndSettle();
      final msgs = await f.watchMessages(direct).first;
      expect(msgs.last.isMine, isFalse);
      expect(msgs.last.body, contains('oi mãe'));
      final convs = await f.watchConversations().first;
      expect(convs.firstWhere((c) => c.id == direct).unreadCount, 0);
    },
  );

  testWidgets('anexar arquivo envia e mostra como disponível', (tester) async {
    final tmp = File(
      '${Directory.systemTemp.path}/chatito_test_${DateTime.now().microsecondsSinceEpoch}.pdf',
    );
    await tmp.writeAsBytes(List.generate(4096, (i) => i % 256));
    addTearDown(() => tmp.delete());
    final f = _seeded();
    final picker = _FakePicker(
      PickedFile(
        path: tmp.path,
        name: 'doc.pdf',
        size: 4096,
        mime: 'application/pdf',
      ),
    );
    await pumpScreen(
      tester,
      ChatScreen(convId: family),
      facade: f,
      overrides: [filePickerProvider.overrideWithValue(picker)],
    );
    await tester.tap(find.byKey(const Key('attach')));
    await tester.pumpAndSettle();
    expect(picker.calls, 1);
    final msgs = await f.watchMessages(family).first;
    final last = msgs.last;
    expect(last.kind, MessageKind.file);
    expect(last.attachments.single.downloaded, isTrue);
    expect(find.text('doc.pdf'), findsOneWidget);
    expect(find.text('4,0 KB'), findsOneWidget);
    // downloaded == true → botão de abrir (não de baixar), sem precisar
    // materializar o arquivo em disco de novo neste teste.
    expect(
      find.byKey(Key('open-${last.attachments.single.blobId}')),
      findsOneWidget,
    );
  });

  testWidgets('picker cancelado não envia nada', (tester) async {
    final f = _seeded();
    final before = (await f.watchMessages(family).first).length;
    await pumpScreen(
      tester,
      ChatScreen(convId: family),
      facade: f,
      overrides: [filePickerProvider.overrideWithValue(_FakePicker(null))],
    );
    await tester.tap(find.byKey(const Key('attach')));
    await tester.pumpAndSettle();
    expect((await f.watchMessages(family).first).length, before);
  });

  testWidgets('título abre detalhe do contato em 1:1', (tester) async {
    await pumpApp(
      tester,
      size: phoneSize,
      initialLocation: '/c/${Uri.encodeComponent(direct)}',
    );
    await tester.tap(find.byKey(const Key('chat-title')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('contact')), findsOneWidget);
  });
}
