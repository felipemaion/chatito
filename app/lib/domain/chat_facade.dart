import 'models.dart';

/// Fachada única que a UI consome. Todos os `watch*` são broadcast e emitem o
/// estado atual imediatamente ao ouvir. Erros são [ChatException].
abstract interface class ChatFacade {
  // ── Sessão ────────────────────────────────────────────────────────────────
  Future<SessionState> get session;
  Stream<SessionState> watchSession();

  /// Onboarding: convite → keypair → `POST /v1/devices` → diretório.
  /// [platform]: `macos` | `windows` | `android`.
  Future<void> register({
    required String inviteCode,
    required String deviceName,
    required String platform,
  });

  // ── Conexão ───────────────────────────────────────────────────────────────
  Stream<ConnectionState> watchConnection();

  /// Abre o WS (reconexão automática) e drena a outbox. Idempotente.
  Future<void> connect();
  Future<void> disconnect();

  // ── Diretório ─────────────────────────────────────────────────────────────
  Stream<List<Contact>> watchContacts();
  Future<void> refreshDirectory();

  /// Safety number entre **meu** device e [deviceId].
  Future<SafetyNumber> safetyNumber(String deviceId);

  // ── Conversas ─────────────────────────────────────────────────────────────
  /// Ordenadas por [Conversation.updatedAt] desc.
  Stream<List<Conversation>> watchConversations();

  /// Cronológica (mais antiga primeiro).
  Stream<List<Message>> watchMessages(String convId);

  /// Garante que a conversa 1:1 com [userId] existe e a devolve.
  Future<Conversation> openDirect(String userId);

  Future<void> sendText(String convId, String body);

  /// Cifra, sobe em chunks e envia a mensagem `file`. [data] é consumido uma vez.
  Future<void> sendFile(
    String convId, {
    required String name,
    required String mime,
    required int size,
    required Stream<List<int>> data,
    String? caption,
  });

  /// Baixa (se preciso) e decifra o anexo, em chunks.
  Stream<List<int>> readAttachment({
    required String messageId,
    required String blobId,
  });

  /// Zera não lidas e envia receipts `read` das mensagens recebidas.
  Future<void> markRead(String convId);

  Future<void> dispose();
}
