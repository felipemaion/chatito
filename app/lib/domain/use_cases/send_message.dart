import 'dart:convert';

import '../../protocol/protocol.dart';
import '../../storage/storage.dart';
import '../../transport/transport.dart';
import '../models.dart';
import 'context.dart';

/// Fan-out: cifra o payload para **cada device** dos participantes (inclusive
/// meus outros devices), enfileira na outbox e drena para o relay.
class SendMessage {
  SendMessage(this._ctx);

  final ChatContext _ctx;
  bool _draining = false;
  bool _drainAgain = false;

  /// Persiste (se [persist]) e envia. [toUserIds] restringe os destinatários
  /// (ex.: recibo só para quem enviou); padrão = participantes da conversa.
  Future<void> send(
    ActiveSession session,
    Payload payload, {
    Message? persist,
    Map<String, AttachmentSecret> attachmentSecrets = const {},
    List<String>? toUserIds,
  }) => ChatContext.guard(() async {
    final conv = await _ctx.db.conversationById(payload.convId);
    if (conv == null) {
      throw const ChatException('not_found', 'conversa desconhecida');
    }
    final users = toUserIds ?? conv.participantUserIds;
    final devices = (await _ctx.db.devicesOfUsers(users))
        .where((d) => d.id != session.device.id)
        .toList();
    final bytes = _ctx.encodePayload(payload);
    final envelopes = <Envelope>[];
    for (final d in devices) {
      final sealed = _ctx.cryptoBox.seal(
        plaintext: bytes,
        recipientPk: base64.decode(d.identityKey),
        senderSk: session.keys.secretKey,
      );
      envelopes.add(
        Envelope(
          toDevice: d.id,
          nonce: base64.encode(sealed.nonce),
          ciphertext: base64.encode(sealed.ciphertext),
        ),
      );
    }
    await _ctx.db.transaction(() async {
      if (persist != null) {
        await _ctx.db.insertMessage(
          persist.copyWith(
            status: envelopes.isEmpty
                ? MessageStatus.sent
                : MessageStatus.pending,
          ),
          attachmentSecrets: attachmentSecrets,
        );
      }
      if (envelopes.isNotEmpty) {
        await _ctx.db.enqueueOutbox(payload.msgId, envelopes);
      }
    });
    await drain();
  });

  /// Envia o que está na outbox. Erros de rede deixam tudo pendente.
  Future<void> drain() async {
    if (_draining) {
      _drainAgain = true;
      return;
    }
    _draining = true;
    try {
      do {
        _drainAgain = false;
        await _drainOnce();
      } while (_drainAgain);
    } finally {
      _draining = false;
    }
  }

  Future<void> _drainOnce() async {
    while (true) {
      final batch = await _ctx.db.pendingOutbox(limit: 100);
      if (batch.isEmpty) {
        return;
      }
      final ids = batch.map((o) => o.id).toList();
      final msgIds = batch.map((o) => o.msgId).toSet();
      try {
        await _ctx.api.postEnvelopes(batch.map((o) => o.envelope).toList());
      } on RelayException catch (e) {
        _ctx.log(
          'outbox: ${e.code} (${batch.length} envelopes ficam pendentes)',
        );
        await _ctx.db.bumpOutboxAttempts(ids);
        final exhausted = batch
            .where((o) => o.attempts + 1 >= 5 && e.code != 'network')
            .toList();
        if (exhausted.isEmpty) {
          return;
        }
        await _ctx.db.deleteOutbox(exhausted.map((o) => o.id).toList());
        for (final m in exhausted.map((o) => o.msgId).toSet()) {
          await _ctx.db.updateMessageStatus(
            m,
            MessageStatus.failed,
            force: true,
          );
        }
        return;
      }
      await _ctx.db.deleteOutbox(ids);
      for (final m in msgIds) {
        if (await _ctx.db.outboxCountFor(m) == 0) {
          await _ctx.db.updateMessageStatus(m, MessageStatus.sent);
        }
      }
    }
  }
}
