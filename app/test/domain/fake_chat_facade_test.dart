import 'dart:convert';

import 'package:piriquito/domain/domain.dart';
import 'package:piriquito/domain/fakes/fake_chat_facade.dart';
import 'package:piriquito/protocol/protocol.dart';
import 'package:test/test.dart';

void main() {
  late FakeChatFacade fake;

  setUp(() {
    fake = FakeChatFacade(autoReplyDelay: Duration.zero);
  });

  tearDown(() => fake.dispose());

  group('sessão', () {
    test('começa registrado como Felipe com dados de exemplo', () async {
      final s = await fake.session;
      expect(s, isA<Registered>());
      final me = s as Registered;
      expect(me.user.name, 'Felipe');
      expect(me.user.id, FakeChatFacade.felipeId);
      expect(me.device.platform, 'macos');
      expect(await fake.watchSession().first, isA<Registered>());
    });

    test('startRegistered=false: registra com convite válido', () async {
      final f = FakeChatFacade(startRegistered: false);
      addTearDown(f.dispose);
      expect(await f.session, isA<NotRegistered>());
      final states = <SessionState>[];
      final sub = f.watchSession().listen(states.add);
      await f.register(
        inviteCode: '7K3M-9QZR',
        deviceName: 'Teste',
        platform: 'windows',
      );
      await Future<void>.delayed(Duration.zero);
      expect(await f.session, isA<Registered>());
      expect((await f.session as Registered).device.name, 'Teste');
      expect(states.last, isA<Registered>());
      await sub.cancel();
      expect(await f.watchConversations().first, isNotEmpty);
    });

    test('convite inválido lança ChatException(invalid_invite)', () async {
      final f = FakeChatFacade(startRegistered: false);
      addTearDown(f.dispose);
      await expectLater(
        f.register(inviteCode: '0000-0000', deviceName: 'x', platform: 'macos'),
        throwsA(
          isA<ChatException>().having((e) => e.code, 'code', 'invalid_invite'),
        ),
      );
    });
  });

  group('conexão', () {
    test('connect/disconnect alternam estado', () async {
      expect(await fake.watchConnection().first, ConnectionState.offline);
      await fake.connect();
      expect(await fake.watchConnection().first, ConnectionState.online);
      await fake.disconnect();
      expect(await fake.watchConnection().first, ConnectionState.offline);
    });
  });

  group('contatos', () {
    test(
      'diretório tem 2 usuários com devices e safety number de 60 dígitos',
      () async {
        final contacts = await fake.watchContacts().first;
        expect(contacts.map((c) => c.user.name), ['Felipe', 'Mãe']);
        expect(contacts.last.devices.single.platform, 'android');
        final sn = await fake.safetyNumber(contacts.last.devices.single.id);
        expect(sn.digits, hasLength(60));
        expect(sn.digits, matches(RegExp(r'^\d{60}$')));
        expect(sn.formatted.split(' '), hasLength(12));
        await fake.refreshDirectory();
      },
    );

    test('safetyNumber de device desconhecido lança not_found', () {
      expect(
        () => fake.safetyNumber('dev_nope'),
        throwsA(
          isA<ChatException>().having((e) => e.code, 'code', 'not_found'),
        ),
      );
    });
  });

  group('conversas', () {
    test(
      'lista ordenada por updatedAt desc, com grupo Família e 1:1',
      () async {
        final convs = await fake.watchConversations().first;
        expect(convs, hasLength(2));
        expect(convs.map((c) => c.id), contains(ConvId.family));
        expect(
          convs.map((c) => c.id),
          contains(
            ConvId.direct(FakeChatFacade.felipeId, FakeChatFacade.maeId),
          ),
        );
        for (var i = 1; i < convs.length; i++) {
          expect(convs[i - 1].updatedAt.isAfter(convs[i].updatedAt), isTrue);
        }
        final group = convs.firstWhere((c) => c.id == ConvId.family);
        expect(group.kind, ConversationKind.group);
        expect(group.title, 'Família');
        expect(group.lastMessage, isNotNull);
        final direct = convs.firstWhere(
          (c) => c.kind == ConversationKind.direct,
        );
        expect(direct.title, 'Mãe');
        expect(direct.unreadCount, greaterThan(0));
      },
    );

    test('mensagens de uma conversa em ordem cronológica', () async {
      final msgs = await fake.watchMessages(ConvId.family).first;
      expect(msgs, isNotEmpty);
      for (var i = 1; i < msgs.length; i++) {
        expect(msgs[i].sentAt.isBefore(msgs[i - 1].sentAt), isFalse);
      }
      expect(msgs.any((m) => m.isMine), isTrue);
      expect(msgs.any((m) => !m.isMine), isTrue);
    });

    test('openDirect devolve a conversa existente ou cria nova', () async {
      final c = await fake.openDirect(FakeChatFacade.maeId);
      expect(
        c.id,
        ConvId.direct(FakeChatFacade.felipeId, FakeChatFacade.maeId),
      );
      expect(
        c.participantUserIds,
        containsAll([FakeChatFacade.felipeId, FakeChatFacade.maeId]),
      );
      expect(() => fake.openDirect('usr_nope'), throwsA(isA<ChatException>()));
    });

    test('sendText adiciona mensagem minha (sent), atualiza conversa e recebe resposta', () async {
      final convId = ConvId.direct(
        FakeChatFacade.felipeId,
        FakeChatFacade.maeId,
      );
      final snapshots = <List<Message>>[];
      final sub = fake.watchMessages(convId).listen(snapshots.add);
      await Future<void>.delayed(Duration.zero);
      final before = snapshots.last.length;

      await fake.sendText(convId, 'Tudo bem?');
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final msgs = snapshots.last;
      expect(msgs.length, before + 2, reason: 'minha + resposta automática');
      final mine = msgs[before];
      expect(mine.isMine, isTrue);
      expect(mine.body, 'Tudo bem?');
      expect(mine.kind, MessageKind.text);
      expect(
        mine.status,
        anyOf(MessageStatus.sent, MessageStatus.delivered, MessageStatus.read),
      );
      expect(mine.senderUserId, FakeChatFacade.felipeId);
      final reply = msgs.last;
      expect(reply.isMine, isFalse);
      expect(reply.senderUserId, FakeChatFacade.maeId);

      final convs = await fake.watchConversations().first;
      expect(
        convs.first.id,
        convId,
        reason: 'conversa atualizada sobe para o topo',
      );
      expect(convs.first.lastMessage!.id, reply.id);
      await sub.cancel();
    });

    test('sendText em conversa desconhecida lança not_found', () {
      expect(
        () => fake.sendText('u:x:y', 'oi'),
        throwsA(
          isA<ChatException>().having((e) => e.code, 'code', 'not_found'),
        ),
      );
    });

    test(
      'markRead zera não lidas e marca mensagens recebidas como lidas',
      () async {
        final convId = ConvId.direct(
          FakeChatFacade.felipeId,
          FakeChatFacade.maeId,
        );
        await fake.markRead(convId);
        final convs = await fake.watchConversations().first;
        expect(convs.firstWhere((c) => c.id == convId).unreadCount, 0);
        final msgs = await fake.watchMessages(convId).first;
        expect(
          msgs
              .where((m) => !m.isMine)
              .every((m) => m.status == MessageStatus.read),
          isTrue,
        );
      },
    );

    test(
      'sendFile cria mensagem com anexo e readAttachment devolve os bytes',
      () async {
        final data = utf8.encode('conteúdo do arquivo');
        await fake.sendFile(
          ConvId.family,
          name: 'nota.txt',
          mime: 'text/plain',
          size: data.length,
          data: Stream.value(data),
          caption: 'segue',
        );
        final msgs = await fake.watchMessages(ConvId.family).first;
        final m = msgs.lastWhere((m) => m.isMine);
        expect(m.kind, MessageKind.file);
        expect(m.body, 'segue');
        expect(m.attachments.single.name, 'nota.txt');
        expect(m.attachments.single.size, data.length);
        final blobId = m.attachments.single.blobId;
        final read = await fake
            .readAttachment(messageId: m.id, blobId: blobId)
            .toList();
        expect(read.expand((c) => c).toList(), data);
        expect(
          () => fake
              .readAttachment(messageId: m.id, blobId: 'blob_nope')
              .toList(),
          throwsA(isA<ChatException>()),
        );
      },
    );

    test('ids de mensagem são determinísticos entre instâncias', () async {
      final a = FakeChatFacade(autoReplyDelay: Duration.zero);
      final b = FakeChatFacade(autoReplyDelay: Duration.zero);
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      await a.sendText(ConvId.family, 'x');
      await b.sendText(ConvId.family, 'x');
      final ma = await a.watchMessages(ConvId.family).first;
      final mb = await b.watchMessages(ConvId.family).first;
      expect(ma.map((m) => m.id), mb.map((m) => m.id));
    });
  });

  test('ChatException.toString inclui código', () {
    expect(
      const ChatException('validation', 'x').toString(),
      contains('validation'),
    );
  });
}
