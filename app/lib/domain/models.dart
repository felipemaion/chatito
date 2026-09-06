import '../protocol/protocol.dart';

/// Erro de domínio. [code] segue os códigos do servidor (`unauthorized`,
/// `invalid_invite`, `not_found`, `validation`, …) mais os locais:
/// `not_registered`, `network`, `crypto`.
class ChatException implements Exception {
  const ChatException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'ChatException($code): $message';
}

sealed class SessionState {
  const SessionState();
}

class NotRegistered extends SessionState {
  const NotRegistered();
}

class Registered extends SessionState {
  const Registered({required this.user, required this.device});

  final User user;
  final Device device;
}

enum ConnectionState { offline, connecting, online }

/// Usuário do diretório com todos os seus devices.
class Contact {
  const Contact({required this.user, required this.devices});

  final User user;
  final List<Device> devices;
}

/// 60 dígitos em 12 grupos de 5, para conferência presencial.
class SafetyNumber {
  const SafetyNumber(this.digits) : assert(digits.length == 60);

  final String digits;

  String get formatted =>
      [for (var i = 0; i < 60; i += 5) digits.substring(i, i + 5)].join(' ');
}

enum ConversationKind { direct, group }

class Conversation {
  const Conversation({
    required this.id,
    required this.kind,
    required this.title,
    required this.participantUserIds,
    required this.updatedAt,
    this.lastMessage,
    this.unreadCount = 0,
  });

  /// `conv_id` do protocolo (`u:…:…` ou `g:familia`).
  final String id;
  final ConversationKind kind;

  /// Nome do peer (1:1) ou "Família" (grupo).
  final String title;
  final List<String> participantUserIds;
  final DateTime updatedAt;
  final Message? lastMessage;
  final int unreadCount;

  Conversation copyWith({
    Message? lastMessage,
    int? unreadCount,
    DateTime? updatedAt,
  }) => Conversation(
    id: id,
    kind: kind,
    title: title,
    participantUserIds: participantUserIds,
    updatedAt: updatedAt ?? this.updatedAt,
    lastMessage: lastMessage ?? this.lastMessage,
    unreadCount: unreadCount ?? this.unreadCount,
  );
}

enum MessageKind { text, file, keyChange }

/// Ciclo: `pending` (na outbox) → `sent` (aceito pelo relay) → `delivered` →
/// `read` (receipts do destinatário). `failed` só após esgotar retentativas.
enum MessageStatus { pending, sent, delivered, read, failed }

class MessageAttachment {
  const MessageAttachment({
    required this.blobId,
    required this.name,
    required this.size,
    required this.mime,
    this.downloaded = false,
  });

  final String blobId;
  final String name;
  final int size;
  final String mime;

  /// `true` quando o conteúdo já está decifrado localmente.
  final bool downloaded;
}

class Message {
  const Message({
    required this.id,
    required this.convId,
    required this.senderUserId,
    required this.senderDeviceId,
    required this.kind,
    required this.sentAt,
    required this.isMine,
    this.body,
    this.attachments = const [],
    this.status = MessageStatus.sent,
  });

  /// `msg_id` do payload (UUID v4).
  final String id;
  final String convId;
  final String senderUserId;
  final String senderDeviceId;
  final MessageKind kind;
  final DateTime sentAt;

  /// Enviada por qualquer device meu.
  final bool isMine;
  final String? body;
  final List<MessageAttachment> attachments;
  final MessageStatus status;

  Message copyWith({
    MessageStatus? status,
    List<MessageAttachment>? attachments,
  }) => Message(
    id: id,
    convId: convId,
    senderUserId: senderUserId,
    senderDeviceId: senderDeviceId,
    kind: kind,
    sentAt: sentAt,
    isMine: isMine,
    body: body,
    attachments: attachments ?? this.attachments,
    status: status ?? this.status,
  );
}
