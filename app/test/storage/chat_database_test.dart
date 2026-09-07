import 'dart:typed_data';

import 'package:chatito/domain/models.dart';
import 'package:chatito/protocol/protocol.dart';
import 'package:chatito/storage/storage.dart';
import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../support/fixtures.dart';

void main() {
  late ChatDatabase db;
  const me = 'usr_YWxpY2VhbGljZWFsaWNlMQ';
  const mae = 'usr_Ym9iYm9iYm9iYm9iYm9iYjI';
  const myDev = 'dev_Zm9vYmFyYmF6cXV4MTIzNA';
  const maeDev = 'dev_YW5kcm9pZGRldmljZTAwMDE';

  setUp(() => db = ChatDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Message msg(
    String id, {
    required bool mine,
    String conv = ConvId.family,
    DateTime? at,
    MessageStatus status = MessageStatus.sent,
    MessageKind kind = MessageKind.text,
  }) => Message(
    id: id,
    convId: conv,
    senderUserId: mine ? me : mae,
    senderDeviceId: mine ? myDev : maeDev,
    kind: kind,
    sentAt: at ?? DateTime.utc(2026, 9, 6, 18, 0, 0, 123),
    isMine: mine,
    body: 'b$id',
    status: status,
  );

  group('diretório', () {
    test('upsertDirectory substitui e watchContacts emite', () async {
      final dir = Directory.fromJson(loadFixture('directory'));
      await db.upsertDirectory(dir);
      final contacts = await db.watchContacts().first;
      expect(contacts.map((c) => c.user.name), ['Felipe', 'Mãe']);
      expect(contacts.last.devices.single.id, maeDev);
      expect(contacts.last.devices.single.userId, mae);
      expect(
        (await db.deviceById(maeDev))!.identityKey,
        '3p7bfXt9wbTTW2HC7OQ1Nz+DQ8hbeGdNrfx+FG+IK08=',
      );
      expect(await db.deviceById('dev_nope'), isNull);

      // device removido do diretório some; nome atualizado
      final updated = Directory(
        users: [
          User(
            id: me,
            name: 'Felipe M.',
            role: UserRole.admin,
            devices: dir.users.first.devices,
          ),
          User(id: mae, name: 'Mãe', role: UserRole.member, devices: const []),
        ],
      );
      await db.upsertDirectory(updated);
      final after = await db.watchContacts().first;
      expect(after.first.user.name, 'Felipe M.');
      expect(after.last.devices, isEmpty);
      expect(await db.deviceById(maeDev), isNull);
      expect(await db.devicesOfUsers([me, mae]), hasLength(1));
      expect(await db.userById(mae), isNotNull);
      expect(await db.userById('usr_nope'), isNull);
    });
  });

  group('conversas e mensagens', () {
    test(
      'conversa é criada/atualizada e ordenada por updatedAt desc',
      () async {
        await db.upsertConversation(
          Conversation(
            id: ConvId.family,
            kind: ConversationKind.group,
            title: 'Família',
            participantUserIds: const [me, mae],
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
        );
        final direct = ConvId.direct(me, mae);
        await db.upsertConversation(
          Conversation(
            id: direct,
            kind: ConversationKind.direct,
            title: 'Mãe',
            participantUserIds: const [me, mae],
            updatedAt: DateTime.utc(2026, 1, 2),
          ),
        );
        var list = await db.watchConversations().first;
        expect(list.map((c) => c.id), [direct, ConvId.family]);
        expect(list.first.participantUserIds, containsAll([me, mae]));
        expect(list.first.kind, ConversationKind.direct);

        await db.insertMessage(
          msg('m1', mine: true, at: DateTime.utc(2026, 1, 3)),
        );
        list = await db.watchConversations().first;
        expect(list.first.id, ConvId.family);
        expect(list.first.lastMessage!.id, 'm1');
        expect(list.first.updatedAt, DateTime.utc(2026, 1, 3));
        expect(list.first.unreadCount, 0);
        expect((await db.conversationById(ConvId.family))!.title, 'Família');
        expect(await db.conversationById('nope'), isNull);
      },
    );

    test(
      'mensagem recebida incrementa não lidas; markRead zera e devolve ids',
      () async {
        await db.upsertConversation(
          Conversation(
            id: ConvId.family,
            kind: ConversationKind.group,
            title: 'Família',
            participantUserIds: const [me, mae],
            updatedAt: DateTime.utc(2026),
          ),
        );
        await db.insertMessage(
          msg('a', mine: false, status: MessageStatus.delivered),
        );
        await db.insertMessage(
          msg('b', mine: false, status: MessageStatus.delivered),
        );
        await db.insertMessage(msg('c', mine: true));
        expect((await db.conversationById(ConvId.family))!.unreadCount, 2);
        final ids = await db.markRead(ConvId.family);
        expect(ids, unorderedEquals(['a', 'b']));
        expect((await db.conversationById(ConvId.family))!.unreadCount, 0);
        final msgs = await db.watchMessages(ConvId.family).first;
        expect(
          msgs
              .where((m) => !m.isMine)
              .every((m) => m.status == MessageStatus.read),
          isTrue,
        );
        expect(msgs.firstWhere((m) => m.id == 'c').status, MessageStatus.sent);
        expect(await db.markRead(ConvId.family), isEmpty);
      },
    );

    test(
      'insertMessage é idempotente por id (fan-out para meus outros devices)',
      () async {
        await db.upsertConversation(
          Conversation(
            id: ConvId.family,
            kind: ConversationKind.group,
            title: 'F',
            participantUserIds: const [me],
            updatedAt: DateTime.utc(2026),
          ),
        );
        expect(await db.insertMessage(msg('dup', mine: false)), isTrue);
        expect(await db.insertMessage(msg('dup', mine: false)), isFalse);
        expect(await db.watchMessages(ConvId.family).first, hasLength(1));
        expect((await db.conversationById(ConvId.family))!.unreadCount, 1);
        expect(await db.messageById('dup'), isNotNull);
        expect(await db.messageById('nope'), isNull);
      },
    );

    test(
      'watchMessages cronológico, preserva milissegundos e emite atualizações',
      () async {
        await db.upsertConversation(
          Conversation(
            id: ConvId.family,
            kind: ConversationKind.group,
            title: 'F',
            participantUserIds: const [me],
            updatedAt: DateTime.utc(2026),
          ),
        );
        final snapshots = <List<Message>>[];
        final sub = db.watchMessages(ConvId.family).listen(snapshots.add);
        await db.insertMessage(
          msg('late', mine: true, at: DateTime.utc(2026, 1, 2)),
        );
        await db.insertMessage(
          msg('early', mine: true, at: DateTime.utc(2026, 1, 1, 0, 0, 0, 7)),
        );
        await db.updateMessageStatus('late', MessageStatus.read);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await sub.cancel();
        final last = snapshots.last;
        expect(last.map((m) => m.id), ['early', 'late']);
        expect(last.first.sentAt, DateTime.utc(2026, 1, 1, 0, 0, 0, 7));
        expect(last.last.status, MessageStatus.read);
        expect(last.first.body, 'bearly');
      },
    );

    test('status só avança (delivered não regride read)', () async {
      await db.upsertConversation(
        Conversation(
          id: ConvId.family,
          kind: ConversationKind.group,
          title: 'F',
          participantUserIds: const [me],
          updatedAt: DateTime.utc(2026),
        ),
      );
      await db.insertMessage(msg('x', mine: true));
      await db.updateMessageStatus('x', MessageStatus.read);
      await db.updateMessageStatus('x', MessageStatus.delivered);
      expect((await db.messageById('x'))!.status, MessageStatus.read);
      await db.updateMessageStatus('x', MessageStatus.failed, force: true);
      expect((await db.messageById('x'))!.status, MessageStatus.failed);
    });
  });

  group('anexos', () {
    test('anexo guarda chave/header e marca download', () async {
      await db.upsertConversation(
        Conversation(
          id: ConvId.family,
          kind: ConversationKind.group,
          title: 'F',
          participantUserIds: const [me],
          updatedAt: DateTime.utc(2026),
        ),
      );
      final m = Message(
        id: 'f1',
        convId: ConvId.family,
        senderUserId: mae,
        senderDeviceId: maeDev,
        kind: MessageKind.file,
        sentAt: DateTime.utc(2026),
        isMine: false,
        body: 'legenda',
        attachments: const [
          MessageAttachment(
            blobId: 'blob_1',
            name: 'a.jpg',
            size: 10,
            mime: 'image/jpeg',
          ),
        ],
      );
      await db.insertMessage(
        m,
        attachmentSecrets: {
          'blob_1': AttachmentSecret(
            key: Uint8List(32),
            header: Uint8List(24),
            chunkSize: 65536,
          ),
        },
      );
      final stored = (await db.watchMessages(ConvId.family).first).single;
      expect(stored.kind, MessageKind.file);
      expect(stored.attachments.single.name, 'a.jpg');
      expect(stored.attachments.single.downloaded, isFalse);
      final a = await db.attachmentByBlob('blob_1');
      expect(a!.messageId, 'f1');
      expect(a.secret.key, hasLength(32));
      expect(a.secret.header, hasLength(24));
      expect(a.localPath, isNull);
      await db.markAttachmentDownloaded('blob_1', '/tmp/a.jpg');
      final a2 = await db.attachmentByBlob('blob_1');
      expect(a2!.localPath, '/tmp/a.jpg');
      expect(
        (await db.watchMessages(ConvId.family).first)
            .single
            .attachments
            .single
            .downloaded,
        isTrue,
      );
      expect(await db.attachmentByBlob('nope'), isNull);
    });

    test('markAttachmentDownloaded reemite em uma inscrição já aberta de watchMessages', () async {
      await db.upsertConversation(
        Conversation(
          id: ConvId.family,
          kind: ConversationKind.group,
          title: 'F',
          participantUserIds: const [me],
          updatedAt: DateTime.utc(2026),
        ),
      );
      await db.insertMessage(
        Message(
          id: 'f2',
          convId: ConvId.family,
          senderUserId: mae,
          senderDeviceId: maeDev,
          kind: MessageKind.file,
          sentAt: DateTime.utc(2026),
          isMine: false,
          attachments: const [
            MessageAttachment(
              blobId: 'blob_2',
              name: 'b.jpg',
              size: 5,
              mime: 'image/jpeg',
            ),
          ],
        ),
        attachmentSecrets: {
          'blob_2': AttachmentSecret(
            key: Uint8List(32),
            header: Uint8List(24),
            chunkSize: 65536,
          ),
        },
      );
      final snapshots = <List<Message>>[];
      final sub = db.watchMessages(ConvId.family).listen(snapshots.add);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(snapshots.last.single.attachments.single.downloaded, isFalse);
      await db.markAttachmentDownloaded('blob_2', '/tmp/b.jpg');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await sub.cancel();
      expect(snapshots.last.single.attachments.single.downloaded, isTrue);
    });

    test(
      'markAttachmentDownloaded reemite em watchConversations (lastMessage)',
      () async {
        await db.upsertConversation(
          Conversation(
            id: ConvId.family,
            kind: ConversationKind.group,
            title: 'F',
            participantUserIds: const [me],
            updatedAt: DateTime.utc(2026),
          ),
        );
        await db.insertMessage(
          Message(
            id: 'f3',
            convId: ConvId.family,
            senderUserId: mae,
            senderDeviceId: maeDev,
            kind: MessageKind.file,
            sentAt: DateTime.utc(2026),
            isMine: false,
            attachments: const [
              MessageAttachment(
                blobId: 'blob_3',
                name: 'c.jpg',
                size: 5,
                mime: 'image/jpeg',
              ),
            ],
          ),
          attachmentSecrets: {
            'blob_3': AttachmentSecret(
              key: Uint8List(32),
              header: Uint8List(24),
              chunkSize: 65536,
            ),
          },
        );
        final snapshots = <List<Conversation>>[];
        final sub = db.watchConversations().listen(snapshots.add);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(
          snapshots.last.single.lastMessage!.attachments.single.downloaded,
          isFalse,
        );
        await db.markAttachmentDownloaded('blob_3', '/tmp/c.jpg');
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await sub.cancel();
        expect(
          snapshots.last.single.lastMessage!.attachments.single.downloaded,
          isTrue,
        );
      },
    );
  });

  group('outbox', () {
    test('enfileira, lista em ordem, conta tentativas e remove', () async {
      final envs = [
        Envelope(toDevice: 'dev_a', nonce: 'n1', ciphertext: 'c1'),
        Envelope(toDevice: 'dev_b', nonce: 'n2', ciphertext: 'c2'),
      ];
      await db.enqueueOutbox('m1', envs);
      await db.enqueueOutbox('m2', [
        Envelope(toDevice: 'dev_a', nonce: 'n3', ciphertext: 'c3'),
      ]);
      var pending = await db.pendingOutbox();
      expect(pending.map((o) => o.envelope.nonce), ['n1', 'n2', 'n3']);
      expect(pending.first.msgId, 'm1');
      expect(pending.first.attempts, 0);
      await db.bumpOutboxAttempts([pending.first.id]);
      pending = await db.pendingOutbox();
      expect(pending.first.attempts, 1);
      await db.deleteOutbox(pending.take(2).map((o) => o.id).toList());
      pending = await db.pendingOutbox();
      expect(pending.single.msgId, 'm2');
      expect(await db.outboxCountFor('m2'), 1);
      expect(await db.outboxCountFor('m1'), 0);
    });
  });
}
