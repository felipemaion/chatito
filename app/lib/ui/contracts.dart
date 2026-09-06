/// Contrato **provisório** entre a UI e o núcleo (app-core).
///
/// Enquanto `docs/status/app-core.md` não documentar a `ChatFacade` real, a UI
/// programa contra esta interface. O orquestrador unifica no merge. Este arquivo é
/// Dart puro (sem `flutter`) para poder ser testado na VM.
library;

import 'dart:async';

/// Valor observável: leitura síncrona do estado atual + stream de mudanças.
abstract class Watchable<T> {
  T get value;
  Stream<T> get stream;
}

/// Implementação simples de [Watchable] baseada em `StreamController.broadcast`.
class ValueStream<T> implements Watchable<T> {
  ValueStream(this._value);

  T _value;
  final _controller = StreamController<T>.broadcast();

  @override
  T get value => _value;

  @override
  Stream<T> get stream => _controller.stream;

  set value(T v) {
    _value = v;
    if (!_controller.isClosed) _controller.add(v);
  }

  void dispose() => _controller.close();
}

/// Erro do núcleo com código estável (espelha `docs/PROTOCOL.md §3`).
class ChatException implements Exception {
  const ChatException(this.code, this.message);
  final String code;
  final String message;

  @override
  String toString() => 'ChatException($code): $message';
}

enum RelayState { online, connecting, offline }

enum MessageKind { text, file, keyChange }

enum MessageStatus { sending, sent, delivered, read, failed }

enum TransferState { none, uploading, downloading, done, failed }

enum TransferDirection { upload, download }

class UserInfo {
  const UserInfo({
    required this.id,
    required this.name,
    required this.role,
    this.devices = const [],
  });
  final String id;
  final String name;
  final String role;
  final List<DeviceInfo> devices;
  bool get isAdmin => role == 'admin';
}

class DeviceInfo {
  const DeviceInfo({
    required this.id,
    required this.userId,
    required this.name,
    required this.platform,
    required this.identityKey,
    required this.createdAt,
  });
  final String id;
  final String userId;
  final String name;
  final String platform;
  final String identityKey;
  final DateTime createdAt;
}

/// Identidade local: usuário + device deste aparelho.
class Identity {
  const Identity({required this.user, required this.device});
  final UserInfo user;
  final DeviceInfo device;
}

class SessionState {
  const SessionState({this.me});
  final Identity? me;
  bool get isRegistered => me != null;
}

class TransferProgress {
  const TransferProgress({
    this.state = TransferState.none,
    this.progress = 0,
    this.error,
  });
  final TransferState state;

  /// 0.0 – 1.0.
  final double progress;
  final String? error;
  bool get isActive =>
      state == TransferState.uploading || state == TransferState.downloading;
}

class Attachment {
  const Attachment({
    required this.blobId,
    required this.name,
    required this.size,
    required this.mime,
    this.localPath,
    this.transfer = const TransferProgress(),
  });
  final String blobId;
  final String name;
  final int size;
  final String mime;

  /// Caminho local do arquivo já decifrado (null enquanto não baixado).
  final String? localPath;
  final TransferProgress transfer;
  bool get isImage => mime.startsWith('image/');

  Attachment copyWith({String? localPath, TransferProgress? transfer}) =>
      Attachment(
        blobId: blobId,
        name: name,
        size: size,
        mime: mime,
        localPath: localPath ?? this.localPath,
        transfer: transfer ?? this.transfer,
      );
}

class Message {
  const Message({
    required this.id,
    required this.convId,
    required this.fromUserId,
    required this.fromDeviceId,
    required this.kind,
    required this.sentAt,
    required this.isMine,
    this.body,
    this.attachments = const [],
    this.status = MessageStatus.sent,
  });
  final String id;
  final String convId;
  final String fromUserId;
  final String fromDeviceId;
  final MessageKind kind;
  final DateTime sentAt;
  final bool isMine;
  final String? body;
  final List<Attachment> attachments;
  final MessageStatus status;

  Message copyWith({MessageStatus? status, List<Attachment>? attachments}) =>
      Message(
        id: id,
        convId: convId,
        fromUserId: fromUserId,
        fromDeviceId: fromDeviceId,
        kind: kind,
        sentAt: sentAt,
        isMine: isMine,
        body: body,
        attachments: attachments ?? this.attachments,
        status: status ?? this.status,
      );
}

class Conversation {
  const Conversation({
    required this.id,
    required this.title,
    required this.isGroup,
    required this.participantIds,
    this.lastMessage,
    this.unreadCount = 0,
    this.updatedAt,
  });
  final String id;
  final String title;
  final bool isGroup;

  /// user_ids dos participantes (sem o próprio usuário em 1:1).
  final List<String> participantIds;
  final Message? lastMessage;
  final int unreadCount;
  final DateTime? updatedAt;

  Conversation copyWith({
    Message? lastMessage,
    int? unreadCount,
    DateTime? updatedAt,
  }) => Conversation(
    id: id,
    title: title,
    isGroup: isGroup,
    participantIds: participantIds,
    lastMessage: lastMessage ?? this.lastMessage,
    unreadCount: unreadCount ?? this.unreadCount,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

/// Fachada que a UI consome. Implementada pelo app-core; aqui só o contrato.
abstract class ChatFacade {
  /// Sessão local (registrado ou não).
  Watchable<SessionState> get session;

  /// Estado da conexão com o relay.
  Watchable<RelayState> get connection;

  /// Conversas ordenadas por atividade (mais recente primeiro).
  Watchable<List<Conversation>> get conversations;

  /// Diretório de usuários e devices (com chaves públicas).
  Watchable<List<UserInfo>> get directory;

  /// Mensagens de uma conversa em ordem cronológica.
  Watchable<List<Message>> messages(String convId);

  /// Consome o convite, gera chaves e registra o device.
  Future<Identity> register({
    required String inviteCode,
    required String deviceName,
    required String platform,
    String? serverUrl,
  });

  Future<void> sendText(String convId, String body);

  /// Cifra e envia o arquivo local; progresso via `messages(convId)`.
  Future<void> sendFile(
    String convId,
    String path, {
    required String name,
    required int size,
    required String mime,
    String? caption,
  });

  /// Baixa e decifra o anexo; devolve o caminho local. Progresso via `messages`.
  Future<String> downloadAttachment(String msgId, String blobId);

  /// Marca a conversa como lida e envia recibos `read`.
  Future<void> markRead(String convId);

  /// Safety number (60 dígitos em 12 grupos de 5) entre este device e [deviceId].
  Future<String> safetyNumber(String deviceId);

  Future<void> removeDevice(String deviceId);

  Future<void> setPushToken(String? token);

  /// Busca envelopes pendentes (chamado ao acordar por push ou ao voltar ao foco).
  Future<void> sync();
}
