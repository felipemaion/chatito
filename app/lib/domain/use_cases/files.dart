import 'dart:async';
import 'dart:convert';

import '../../crypto/crypto.dart';
import '../../protocol/protocol.dart';
import '../../storage/storage.dart';
import '../../transport/transport.dart';
import '../attachment_cache.dart';
import '../models.dart';
import 'context.dart';
import 'send_message.dart';

/// Envio: cifra (secretstream) → sobe em chunks → payload `file`.
/// Recebimento: baixa → decifra → cache local.
class Files {
  Files(this._ctx, this._cache, this._sender, {ChunkUploader? uploader})
    : _uploader = uploader ?? ChunkUploader(_ctx.api);

  final ChatContext _ctx;
  final AttachmentCache _cache;
  final SendMessage _sender;
  final ChunkUploader _uploader;

  Future<void> send(
    ActiveSession session,
    String convId, {
    required String name,
    required String mime,
    required int size,
    required Stream<List<int>> data,
    String? caption,
  }) => ChatContext.guard(() async {
    final conv = await _ctx.db.conversationById(convId);
    if (conv == null) {
      throw const ChatException('not_found', 'conversa desconhecida');
    }
    final recipients = (await _ctx.db.devicesOfUsers(conv.participantUserIds))
        .map((d) => d.id)
        .where((id) => id != session.device.id)
        .toList();
    // Guarda o texto claro no cache enquanto cifra (o remetente também precisa ler o anexo).
    final tmpId = 'pending_${_ctx.newId()}';
    final sink = await _cache.openWrite(tmpId);
    Stream<List<int>> tee() async* {
      await for (final c in data) {
        sink.add(c);
        yield c;
      }
    }

    final String blobId;
    final FileEncryption enc;
    try {
      enc = await _ctx.fileCipher.encrypt(tee());
      blobId = await _uploader.upload(
        data: enc.ciphertext,
        size: _ctx.fileCipher.cipherSize(size),
        recipients: recipients.isEmpty ? [session.device.id] : recipients,
      );
    } on Object {
      await sink.abort();
      await _cache.remove(tmpId);
      rethrow;
    }
    await sink.close();
    await _cache.rename(tmpId, blobId);
    final msgId = _ctx.newId();
    final att = Attachment(
      blobId: blobId,
      name: name,
      size: size,
      mime: mime,
      key: base64.encode(enc.key),
      header: base64.encode(enc.header),
      chunkSize: FileCipher.chunkSize,
    );
    final payload = Payload(
      msgId: msgId,
      convId: convId,
      kind: PayloadKind.file,
      sentAt: _ctx.now(),
      body: caption,
      attachments: [att],
    );
    await _sender.send(
      session,
      payload,
      persist: Message(
        id: msgId,
        convId: convId,
        senderUserId: session.user.id,
        senderDeviceId: session.device.id,
        kind: MessageKind.file,
        sentAt: payload.sentAt,
        isMine: true,
        body: caption,
        attachments: [
          MessageAttachment(
            blobId: blobId,
            name: name,
            size: size,
            mime: mime,
            downloaded: true,
          ),
        ],
      ),
      attachmentSecrets: {
        blobId: AttachmentSecret(
          key: enc.key,
          header: enc.header,
          chunkSize: FileCipher.chunkSize,
        ),
      },
    );
    await _ctx.db.markAttachmentDownloaded(blobId, 'cache:$blobId');
  });

  Stream<List<int>> read(String blobId) async* {
    final stored = await _ctx.db.attachmentByBlob(blobId);
    if (stored == null) {
      throw const ChatException('not_found', 'anexo desconhecido');
    }
    final cached = _cache.openRead(blobId);
    if (cached != null) {
      yield* cached;
      return;
    }
    final sink = await _cache.openWrite(blobId);
    try {
      final cipher = _ctx.api.downloadBlob(blobId);
      final plain = _ctx.fileCipher.decrypt(
        ciphertext: cipher,
        key: stored.secret.key,
        header: stored.secret.header,
      );
      await for (final chunk in plain) {
        sink.add(chunk);
        yield chunk;
      }
    } on Object catch (e) {
      await sink.abort();
      ChatContext.rethrowAsChat(e);
    }
    await sink.close();
    await _ctx.db.markAttachmentDownloaded(blobId, 'cache:$blobId');
  }
}
