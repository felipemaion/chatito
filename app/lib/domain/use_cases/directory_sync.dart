import '../../protocol/protocol.dart';
import '../models.dart';
import 'context.dart';

/// `GET /v1/directory` → banco, com detecção de troca de chave e garantia do
/// grupo Família.
class DirectorySync {
  DirectorySync(this._ctx);

  final ChatContext _ctx;

  Future<void> refresh(ActiveSession session) => ChatContext.guard(() async {
    final dir = await _ctx.api.directory();
    await apply(dir, session);
  });

  Future<void> apply(Directory dir, ActiveSession session) async {
    final db = _ctx.db;
    final hadUsers = (await db.watchContacts().first).isNotEmpty;
    final notices =
        <
          (
            String userId,
            String userName,
            String deviceId,
            String deviceName,
            bool isNew,
          )
        >[];
    if (hadUsers) {
      for (final u in dir.users) {
        if (u.id == session.user.id) {
          continue;
        }
        final known = await db.userById(u.id) != null;
        for (final d in u.devices ?? const <Device>[]) {
          final old = await db.deviceById(d.id);
          if (old == null) {
            if (known) {
              notices.add((u.id, u.name, d.id, d.name, true));
            }
          } else if (old.identityKey != d.identityKey) {
            notices.add((u.id, u.name, d.id, d.name, false));
          }
        }
      }
    }
    await db.upsertDirectory(dir);
    await ensureFamily(dir, session);
    for (final (userId, userName, deviceId, deviceName, isNew) in notices) {
      final convId = ConvId.direct(session.user.id, userId);
      await ensureDirect(convId, session);
      await db.insertMessage(
        Message(
          id: _ctx.newId(),
          convId: convId,
          senderUserId: userId,
          senderDeviceId: deviceId,
          kind: MessageKind.keyChange,
          sentAt: _ctx.now(),
          isMine: false,
          body: isNew
              ? '$userName adicionou o device "$deviceName". Confira o safety number.'
              : '$userName trocou a chave do device "$deviceName". Confira o safety number.',
          status: MessageStatus.read,
        ),
      );
    }
  }

  Future<void> ensureFamily(Directory dir, ActiveSession session) async {
    final ids = dir.users.map((u) => u.id).toList()..sort();
    final existing = await _ctx.db.conversationById(ConvId.family);
    await _ctx.db.upsertConversation(
      Conversation(
        id: ConvId.family,
        kind: ConversationKind.group,
        title: 'Família',
        participantUserIds: ids,
        updatedAt: existing?.updatedAt ?? _ctx.now(),
        unreadCount: existing?.unreadCount ?? 0,
        lastMessage: existing?.lastMessage,
      ),
    );
  }

  /// Garante a conversa 1:1 [convId]; devolve-a.
  Future<Conversation> ensureDirect(
    String convId,
    ActiveSession session,
  ) async {
    final existing = await _ctx.db.conversationById(convId);
    if (existing != null) {
      return existing;
    }
    final peerId = ConvId.peerOf(convId, session.user.id);
    if (peerId == null) {
      throw const ChatException('validation', 'conv_id não é 1:1');
    }
    final peer = await _ctx.db.userById(peerId);
    if (peer == null) {
      throw const ChatException('not_found', 'usuário desconhecido');
    }
    final conv = Conversation(
      id: convId,
      kind: ConversationKind.direct,
      title: peer.name,
      participantUserIds: [session.user.id, peerId]..sort(),
      updatedAt: _ctx.now(),
    );
    await _ctx.db.upsertConversation(conv);
    return conv;
  }
}
