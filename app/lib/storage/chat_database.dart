import 'package:async/async.dart';
import 'package:drift/drift.dart';

import '../domain/models.dart';
import '../protocol/protocol.dart' as p;
import 'tables.dart';

part 'chat_database.g.dart';

/// Chave/header secretstream de um anexo (viajam no payload, ficam no banco).
class AttachmentSecret {
  const AttachmentSecret({
    required this.key,
    required this.header,
    required this.chunkSize,
  });

  final Uint8List key;
  final Uint8List header;
  final int chunkSize;
}

class StoredAttachment {
  const StoredAttachment({
    required this.messageId,
    required this.attachment,
    required this.secret,
    this.localPath,
  });

  final String messageId;
  final MessageAttachment attachment;
  final AttachmentSecret secret;
  final String? localPath;
}

class OutboxItem {
  const OutboxItem({
    required this.id,
    required this.msgId,
    required this.envelope,
    required this.attempts,
  });

  final int id;
  final String msgId;
  final p.Envelope envelope;
  final int attempts;
}

@DriftDatabase(
  tables: [Users, Devices, Conversations, Messages, Attachments, Outbox],
)
class ChatDatabase extends _$ChatDatabase {
  ChatDatabase(super.e) : super();

  @override
  int get schemaVersion => 1;

  @override
  DriftDatabaseOptions get options =>
      const DriftDatabaseOptions(storeDateTimeAsText: true);

  // ── Diretório ─────────────────────────────────────────────────────────────
  /// Substitui o diretório inteiro (usuários e devices removidos somem).
  Future<void> upsertDirectory(p.Directory dir) => transaction(() async {
    await delete(devices).go();
    await delete(users).go();
    for (final u in dir.users) {
      await into(users).insert(
        UsersCompanion.insert(id: u.id, name: u.name, role: u.role.name),
      );
      for (final d in u.devices ?? const <p.Device>[]) {
        await into(devices).insert(
          DevicesCompanion.insert(
            id: d.id,
            userId: u.id,
            name: d.name,
            platform: d.platform,
            identityKey: d.identityKey,
            createdAt: d.createdAt,
          ),
        );
      }
    }
  });

  Stream<List<Contact>> watchContacts() {
    final q = select(users).join([
      leftOuterJoin(devices, devices.userId.equalsExp(users.id)),
    ])..orderBy([OrderingTerm.asc(users.name)]);
    return q.watch().map((rows) {
      final byUser = <String, Contact>{};
      for (final row in rows) {
        final u = row.readTable(users);
        final d = row.readTableOrNull(devices);
        final c = byUser.putIfAbsent(
          u.id,
          () => Contact(
            user: p.User(
              id: u.id,
              name: u.name,
              role: p.UserRole.values.byName(u.role),
            ),
            devices: [],
          ),
        );
        if (d != null) c.devices.add(_toDevice(d));
      }
      return byUser.values.toList();
    });
  }

  Future<p.User?> userById(String id) async {
    final u = await (select(
      users,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return u == null
        ? null
        : p.User(
            id: u.id,
            name: u.name,
            role: p.UserRole.values.byName(u.role),
          );
  }

  Future<p.Device?> deviceById(String id) async {
    final d = await (select(
      devices,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return d == null ? null : _toDevice(d);
  }

  Future<List<p.Device>> devicesOfUsers(List<String> userIds) async {
    final rows = await (select(
      devices,
    )..where((t) => t.userId.isIn(userIds))).get();
    return rows.map(_toDevice).toList();
  }

  // ── Conversas ─────────────────────────────────────────────────────────────
  Future<void> upsertConversation(Conversation c) =>
      into(conversations).insertOnConflictUpdate(
        ConversationsCompanion.insert(
          id: c.id,
          kind: c.kind.name,
          title: c.title,
          participants: c.participantUserIds.join(','),
          updatedAt: c.updatedAt,
          unreadCount: Value(c.unreadCount),
          lastMessageId: Value(c.lastMessage?.id),
        ),
      );

  Stream<List<Conversation>> watchConversations() {
    final q = select(conversations).join([
      leftOuterJoin(
        messages,
        messages.id.equalsExp(conversations.lastMessageId),
      ),
    ])..orderBy([OrderingTerm.desc(conversations.updatedAt)]);
    // Também reage a mudanças em `attachments` (ex.: download concluído do
    // `lastMessage`), que a query acima não referencia diretamente.
    final triggers = StreamGroup.merge([
      q.watch(),
      select(attachments).watch(),
    ]);
    return triggers.asyncMap((_) async {
      final rows = await q.get();
      final out = <Conversation>[];
      for (final row in rows) {
        final m = row.readTableOrNull(messages);
        out.add(
          _toConversation(
            row.readTable(conversations),
            m == null ? null : await _toMessage(m),
          ),
        );
      }
      return out;
    });
  }

  Future<Conversation?> conversationById(String id) async {
    final c = await (select(
      conversations,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (c == null) return null;
    final last = c.lastMessageId == null
        ? null
        : await messageById(c.lastMessageId!);
    return _toConversation(c, last);
  }

  // ── Mensagens ─────────────────────────────────────────────────────────────
  /// `false` se já existia (ex.: cópia do fan-out para outro device meu).
  Future<bool> insertMessage(
    Message m, {
    Map<String, AttachmentSecret> attachmentSecrets = const {},
  }) => transaction(() async {
    final exists = await (select(
      messages,
    )..where((t) => t.id.equals(m.id))).getSingleOrNull();
    if (exists != null) return false;
    await into(messages).insert(
      MessagesCompanion.insert(
        id: m.id,
        convId: m.convId,
        senderUserId: m.senderUserId,
        senderDeviceId: m.senderDeviceId,
        kind: m.kind.name,
        body: Value(m.body),
        sentAt: m.sentAt,
        isMine: m.isMine,
        status: m.status.name,
      ),
    );
    for (final a in m.attachments) {
      final s = attachmentSecrets[a.blobId];
      if (s == null) {
        throw ArgumentError('falta AttachmentSecret para ${a.blobId}');
      }
      await into(attachments).insert(
        AttachmentsCompanion.insert(
          blobId: a.blobId,
          messageId: m.id,
          name: a.name,
          size: a.size,
          mime: a.mime,
          key: s.key,
          header: s.header,
          chunkSize: s.chunkSize,
        ),
      );
    }
    final conv = await (select(
      conversations,
    )..where((t) => t.id.equals(m.convId))).getSingleOrNull();
    if (conv != null) {
      final newer = !m.sentAt.isBefore(conv.updatedAt);
      await (update(conversations)..where((t) => t.id.equals(m.convId))).write(
        ConversationsCompanion(
          updatedAt: newer ? Value(m.sentAt) : const Value.absent(),
          lastMessageId: newer ? Value(m.id) : const Value.absent(),
          unreadCount: m.isMine
              ? const Value.absent()
              : Value(conv.unreadCount + 1),
        ),
      );
    }
    return true;
  });

  Stream<List<Message>> watchMessages(String convId) {
    final q = select(messages)
      ..where((t) => t.convId.equals(convId))
      ..orderBy([(t) => OrderingTerm.asc(t.sentAt)]);
    // Idem: anexos baixados depois não mudam a tabela `messages`.
    final triggers = StreamGroup.merge([
      q.watch(),
      select(attachments).watch(),
    ]);
    return triggers.asyncMap(
      (_) async => Future.wait((await q.get()).map(_toMessage)),
    );
  }

  Future<Message?> messageById(String id) async {
    final m = await (select(
      messages,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return m == null ? null : _toMessage(m);
  }

  /// Só avança no ciclo pending→sent→delivered→read, salvo [force] (ex.: `failed`).
  Future<void> updateMessageStatus(
    String id,
    MessageStatus status, {
    bool force = false,
  }) async {
    final m = await (select(
      messages,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (m == null) return;
    final current = MessageStatus.values.byName(m.status);
    if (!force && status.index <= current.index) return;
    await (update(messages)..where((t) => t.id.equals(id))).write(
      MessagesCompanion(status: Value(status.name)),
    );
  }

  /// Zera não lidas, marca recebidas como `read` e devolve os ids que mudaram.
  Future<List<String>> markRead(String convId) => transaction(() async {
    final unread =
        await (select(messages)..where(
              (t) =>
                  t.convId.equals(convId) &
                  t.isMine.equals(false) &
                  t.status.equals(MessageStatus.read.name).not(),
            ))
            .get();
    final ids = unread.map((m) => m.id).toList();
    if (ids.isNotEmpty) {
      await (update(messages)..where((t) => t.id.isIn(ids))).write(
        MessagesCompanion(status: Value(MessageStatus.read.name)),
      );
    }
    await (update(conversations)..where((t) => t.id.equals(convId))).write(
      const ConversationsCompanion(unreadCount: Value(0)),
    );
    return ids;
  });

  // ── Anexos ────────────────────────────────────────────────────────────────
  Future<StoredAttachment?> attachmentByBlob(String blobId) async {
    final a = await (select(
      attachments,
    )..where((t) => t.blobId.equals(blobId))).getSingleOrNull();
    return a == null ? null : _toStoredAttachment(a);
  }

  Future<void> markAttachmentDownloaded(String blobId, String localPath) =>
      (update(attachments)..where((t) => t.blobId.equals(blobId))).write(
        AttachmentsCompanion(localPath: Value(localPath)),
      );

  // ── Outbox ────────────────────────────────────────────────────────────────
  Future<void> enqueueOutbox(String msgId, List<p.Envelope> envelopes) =>
      batch((b) {
        final now = DateTime.now().toUtc();
        b.insertAll(outbox, [
          for (final e in envelopes)
            OutboxCompanion.insert(
              msgId: msgId,
              toDevice: e.toDevice,
              nonce: e.nonce,
              ciphertext: e.ciphertext,
              createdAt: now,
            ),
        ]);
      });

  Future<List<OutboxItem>> pendingOutbox({int limit = 100}) async {
    final rows =
        await (select(outbox)
              ..orderBy([(t) => OrderingTerm.asc(t.id)])
              ..limit(limit))
            .get();
    return [
      for (final r in rows)
        OutboxItem(
          id: r.id,
          msgId: r.msgId,
          envelope: p.Envelope(
            toDevice: r.toDevice,
            nonce: r.nonce,
            ciphertext: r.ciphertext,
          ),
          attempts: r.attempts,
        ),
    ];
  }

  Future<void> bumpOutboxAttempts(List<int> ids) => customUpdate(
    'UPDATE outbox SET attempts = attempts + 1 WHERE id IN (${List.filled(ids.length, '?').join(',')})',
    variables: ids.map(Variable.withInt).toList(),
    updates: {outbox},
  );

  Future<void> deleteOutbox(List<int> ids) =>
      (delete(outbox)..where((t) => t.id.isIn(ids))).go();

  Future<int> outboxCountFor(String msgId) async {
    final count = outbox.id.count();
    final q = selectOnly(outbox)
      ..addColumns([count])
      ..where(outbox.msgId.equals(msgId));
    return (await q.getSingle()).read(count) ?? 0;
  }

  // ── Mapeamento ────────────────────────────────────────────────────────────
  p.Device _toDevice(DeviceRow d) => p.Device(
    id: d.id,
    userId: d.userId,
    name: d.name,
    platform: d.platform,
    identityKey: d.identityKey,
    createdAt: d.createdAt,
  );

  Conversation _toConversation(ConversationRow c, Message? last) =>
      Conversation(
        id: c.id,
        kind: ConversationKind.values.byName(c.kind),
        title: c.title,
        participantUserIds: c.participants.split(','),
        updatedAt: c.updatedAt,
        unreadCount: c.unreadCount,
        lastMessage: last,
      );

  Future<Message> _toMessage(MessageRow m) async {
    final atts = await (select(
      attachments,
    )..where((t) => t.messageId.equals(m.id))).get();
    return Message(
      id: m.id,
      convId: m.convId,
      senderUserId: m.senderUserId,
      senderDeviceId: m.senderDeviceId,
      kind: MessageKind.values.byName(m.kind),
      sentAt: m.sentAt,
      isMine: m.isMine,
      body: m.body,
      status: MessageStatus.values.byName(m.status),
      attachments: [for (final a in atts) _toStoredAttachment(a).attachment],
    );
  }

  StoredAttachment _toStoredAttachment(AttachmentRow a) => StoredAttachment(
    messageId: a.messageId,
    localPath: a.localPath,
    attachment: MessageAttachment(
      blobId: a.blobId,
      name: a.name,
      size: a.size,
      mime: a.mime,
      downloaded: a.localPath != null,
    ),
    secret: AttachmentSecret(
      key: a.key,
      header: a.header,
      chunkSize: a.chunkSize,
    ),
  );
}
