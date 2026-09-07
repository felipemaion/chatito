import 'dart:convert';

import '../../crypto/crypto.dart';
import '../../protocol/protocol.dart';
import '../../storage/storage.dart';
import '../models.dart';
import 'context.dart';
import 'directory_sync.dart';
import 'send_message.dart';

/// open → persistir → (ack é feito pelo `RelayWs` quando este handler retorna).
/// Falha de MAC ou payload inválido = descartar + log (e retornar normalmente,
/// para que o envelope seja ack'ado e não volte).
class ReceiveEnvelope {
  ReceiveEnvelope(this._ctx, this._directory, this._sender);

  final ChatContext _ctx;
  final DirectorySync _directory;
  final SendMessage _sender;

  Future<void> handle(ActiveSession session, Envelope envelope) async {
    final from = envelope.fromDevice;
    if (from == null) {
      _ctx.log('envelope ${envelope.id} sem from_device: descartado');
      return;
    }
    var device = await _ctx.db.deviceById(from);
    if (device == null) {
      try {
        await _directory.refresh(session);
      } on ChatException catch (e) {
        _ctx.log('diretório indisponível ao resolver $from: $e');
      }
      device = await _ctx.db.deviceById(from);
    }
    if (device == null) {
      _ctx.log(
        'envelope ${envelope.id} de device desconhecido $from: descartado',
      );
      return;
    }
    final List<int> plain;
    try {
      plain = _ctx.cryptoBox.open(
        ciphertext: base64.decode(envelope.ciphertext),
        nonce: base64.decode(envelope.nonce),
        senderPk: base64.decode(device.identityKey),
        recipientSk: session.keys.secretKey,
      );
    } on CryptoFailure catch (e) {
      _ctx.log(
        'envelope ${envelope.id} de $from: MAC inválido, descartado ($e)',
      );
      return;
    } on FormatException catch (e) {
      _ctx.log(
        'envelope ${envelope.id} de $from: base64 inválido, descartado ($e)',
      );
      return;
    }
    final Payload payload;
    try {
      payload = _ctx.decodePayload(plain);
    } on Object catch (e) {
      _ctx.log(
        'envelope ${envelope.id} de $from: payload inválido, descartado ($e)',
      );
      return;
    }
    if (payload.v != 1) {
      _ctx.log(
        'envelope ${envelope.id}: versão ${payload.v} não suportada, descartado',
      );
      return;
    }
    final senderUserId = device.userId ?? '';
    final isMine = senderUserId == session.user.id;
    switch (payload.kind) {
      case PayloadKind.text || PayloadKind.file:
        await _storeMessage(session, payload, device, isMine);
      case PayloadKind.receipt:
        final r = payload.receipt;
        if (r == null) {
          return;
        }
        await _ctx.db.updateMessageStatus(
          r.msgId,
          r.status == ReceiptStatus.read
              ? MessageStatus.read
              : MessageStatus.delivered,
        );
      case PayloadKind.keyChange:
        await _ensureConversation(session, payload.convId);
        final who = await _ctx.db.userById(senderUserId);
        await _ctx.db.insertMessage(
          Message(
            id: payload.msgId,
            convId: payload.convId,
            senderUserId: senderUserId,
            senderDeviceId: device.id,
            kind: MessageKind.keyChange,
            sentAt: payload.sentAt,
            isMine: isMine,
            body:
                '${who?.name ?? senderUserId} trocou de chave/device. Confira o safety number.',
            status: MessageStatus.read,
          ),
        );
    }
  }

  Future<void> _storeMessage(
    ActiveSession session,
    Payload payload,
    Device device,
    bool isMine,
  ) async {
    if (payload.kind == PayloadKind.text &&
        (payload.body == null || payload.body!.isEmpty)) {
      _ctx.log('texto vazio de ${device.id}: descartado');
      return;
    }
    final atts = payload.attachments ?? const <Attachment>[];
    if (payload.kind == PayloadKind.file && atts.isEmpty) {
      _ctx.log('file sem attachments de ${device.id}: descartado');
      return;
    }
    await _ensureConversation(session, payload.convId);
    final secrets = <String, AttachmentSecret>{};
    for (final a in atts) {
      try {
        secrets[a.blobId] = AttachmentSecret(
          key: base64.decode(a.key),
          header: base64.decode(a.header),
          chunkSize: a.chunkSize,
        );
      } on FormatException {
        _ctx.log('anexo ${a.blobId} com chave inválida: descartado');
        return;
      }
    }
    final inserted = await _ctx.db.insertMessage(
      Message(
        id: payload.msgId,
        convId: payload.convId,
        senderUserId: device.userId ?? '',
        senderDeviceId: device.id,
        kind: payload.kind == PayloadKind.text
            ? MessageKind.text
            : MessageKind.file,
        sentAt: payload.sentAt,
        isMine: isMine,
        body: payload.body,
        attachments: [
          for (final a in atts)
            MessageAttachment(
              blobId: a.blobId,
              name: a.name,
              size: a.size,
              mime: a.mime,
            ),
        ],
        status: isMine ? MessageStatus.sent : MessageStatus.delivered,
      ),
      attachmentSecrets: secrets,
    );
    if (inserted && !isMine) {
      try {
        await _sender.send(
          session,
          Payload(
            msgId: _ctx.newId(),
            convId: payload.convId,
            kind: PayloadKind.receipt,
            sentAt: _ctx.now(),
            receipt: Receipt(
              msgId: payload.msgId,
              status: ReceiptStatus.delivered,
            ),
          ),
          toUserIds: [device.userId ?? ''],
        );
      } on ChatException catch (e) {
        _ctx.log('recibo delivered de ${payload.msgId} não enviado: $e');
      }
    }
  }

  Future<void> _ensureConversation(ActiveSession session, String convId) async {
    if (ConvId.isGroup(convId)) {
      if (await _ctx.db.conversationById(convId) == null) {
        final contacts = await _ctx.db.watchContacts().first;
        await _ctx.db.upsertConversation(
          Conversation(
            id: convId,
            kind: ConversationKind.group,
            title: 'Família',
            participantUserIds: contacts.map((c) => c.user.id).toList()..sort(),
            updatedAt: _ctx.now(),
          ),
        );
      }
      return;
    }
    await _directory.ensureDirect(convId, session);
  }
}
