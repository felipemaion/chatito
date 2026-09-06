import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../../protocol/protocol.dart';
import '../chat_facade.dart';
import '../models.dart';

/// Implementação em memória, determinística, para o app-ui trabalhar antes da
/// integração. Dois usuários (ids das fixtures): Felipe (eu, admin, macOS) e
/// Mãe (member, Android). Responde automaticamente a cada texto enviado.
class FakeChatFacade implements ChatFacade {
  FakeChatFacade({
    bool startRegistered = true,
    this.autoReplyDelay = const Duration(milliseconds: 400),
    DateTime? now,
  }) : _now = now ?? DateTime.utc(2026, 9, 6, 18, 30) {
    if (startRegistered) {
      _registerAs(_felipeDevice);
    }
  }

  static const felipeId = 'usr_YWxpY2VhbGljZWFsaWNlMQ';
  static const maeId = 'usr_Ym9iYm9iYm9iYm9iYm9iYjI';
  static const felipeDeviceId = 'dev_Zm9vYmFyYmF6cXV4MTIzNA';
  static const maeDeviceId = 'dev_YW5kcm9pZGRldmljZTAwMDE';

  /// Convite que sempre falha, para a UI testar o caminho de erro.
  static const badInvite = '0000-0000';

  final Duration autoReplyDelay;
  DateTime _now;
  int _seq = 0;

  final _felipe = User(id: felipeId, name: 'Felipe', role: UserRole.admin);
  final _mae = User(id: maeId, name: 'Mãe', role: UserRole.member);
  final _felipeDevice = Device(
    id: felipeDeviceId,
    userId: felipeId,
    name: 'MacBook do Felipe',
    platform: 'macos',
    identityKey: 'hSDwCYkwp1R0i33ctD73Wg2/Og0mOBr066SpjqqbTmo=',
    createdAt: DateTime.utc(2026, 9, 6, 18),
  );
  final _maeDevice = Device(
    id: maeDeviceId,
    userId: maeId,
    name: 'Galaxy',
    platform: 'android',
    identityKey: '3p7bfXt9wbTTW2HC7OQ1Nz+DQ8hbeGdNrfx+FG+IK08=',
    createdAt: DateTime.utc(2026, 9, 6, 18, 5),
  );

  final _session = _Value<SessionState>(const NotRegistered());
  final _connection = _Value<ConnectionState>(ConnectionState.offline);
  final _contacts = _Value<List<Contact>>(const []);
  final _conversations = _Value<List<Conversation>>(const []);
  final _messages = <String, _Value<List<Message>>>{};
  final _blobs = <String, Uint8List>{};
  final _timers = <Timer>[];

  // ── Sessão ────────────────────────────────────────────────────────────────
  @override
  Future<SessionState> get session async => _session.value;

  @override
  Stream<SessionState> watchSession() => _session.stream;

  @override
  Future<void> register({
    required String inviteCode,
    required String deviceName,
    required String platform,
  }) async {
    if (inviteCode == badInvite ||
        !RegExp(r'^[0-9A-Z]{4}-[0-9A-Z]{4}$').hasMatch(inviteCode)) {
      throw const ChatException(
        'invalid_invite',
        'invite code expired or already used',
      );
    }
    _registerAs(
      Device(
        id: felipeDeviceId,
        userId: felipeId,
        name: deviceName,
        platform: platform,
        identityKey: _felipeDevice.identityKey,
        createdAt: _tick(),
      ),
    );
  }

  void _registerAs(Device device) {
    _contacts.value = [
      Contact(user: _felipe, devices: [device]),
      Contact(user: _mae, devices: [_maeDevice]),
    ];
    _seedConversations();
    _session.value = Registered(user: _felipe, device: device);
  }

  // ── Conexão ───────────────────────────────────────────────────────────────
  @override
  Stream<ConnectionState> watchConnection() => _connection.stream;

  @override
  Future<void> connect() async {
    _requireRegistered();
    _connection.value = ConnectionState.online;
  }

  @override
  Future<void> disconnect() async =>
      _connection.value = ConnectionState.offline;

  // ── Diretório ─────────────────────────────────────────────────────────────
  @override
  Stream<List<Contact>> watchContacts() => _contacts.stream;

  @override
  Future<void> refreshDirectory() async => _requireRegistered();

  @override
  Future<SafetyNumber> safetyNumber(String deviceId) async {
    final me = _requireRegistered();
    final other = _contacts.value
        .expand((c) => c.devices)
        .where((d) => d.id == deviceId)
        .firstOrNull;
    if (other == null)
      throw const ChatException('not_found', 'device desconhecido');
    // Determinístico e simétrico; NÃO é a regra real (ver crypto/SodiumCryptoBox).
    final keys = [me.device.identityKey, other.identityKey]..sort();
    final bytes = utf8.encode(keys.join());
    final buf = StringBuffer();
    var acc = 7;
    for (var i = 0; i < 60; i++) {
      acc = (acc * 31 + bytes[i % bytes.length]) % 1000003;
      buf.write(acc % 10);
    }
    return SafetyNumber(buf.toString());
  }

  // ── Conversas ─────────────────────────────────────────────────────────────
  @override
  Stream<List<Conversation>> watchConversations() => _conversations.stream;

  @override
  Stream<List<Message>> watchMessages(String convId) =>
      _messagesOf(convId).stream;

  @override
  Future<Conversation> openDirect(String userId) async {
    final me = _requireRegistered();
    final contact = _contacts.value
        .where((c) => c.user.id == userId)
        .firstOrNull;
    if (contact == null)
      throw const ChatException('not_found', 'usuário desconhecido');
    final id = ConvId.direct(me.user.id, userId);
    final existing = _conversations.value.where((c) => c.id == id).firstOrNull;
    if (existing != null) return existing;
    final conv = Conversation(
      id: id,
      kind: ConversationKind.direct,
      title: contact.user.name,
      participantUserIds: [me.user.id, userId],
      updatedAt: _tick(),
    );
    _conversations.value = _sorted([..._conversations.value, conv]);
    return conv;
  }

  @override
  Future<void> sendText(String convId, String body) async {
    final me = _requireRegistered();
    _conversation(convId);
    final msg = Message(
      id: _nextId('msg'),
      convId: convId,
      senderUserId: me.user.id,
      senderDeviceId: me.device.id,
      kind: MessageKind.text,
      sentAt: _tick(),
      isMine: true,
      body: body,
      status: MessageStatus.sent,
    );
    _append(msg);
    _scheduleReply(convId, body);
  }

  @override
  Future<void> sendFile(
    String convId, {
    required String name,
    required String mime,
    required int size,
    required Stream<List<int>> data,
    String? caption,
  }) async {
    final me = _requireRegistered();
    _conversation(convId);
    final builder = BytesBuilder(copy: false);
    await for (final chunk in data) {
      builder.add(chunk);
    }
    final blobId = _nextId('blob');
    _blobs[blobId] = builder.takeBytes();
    _append(
      Message(
        id: _nextId('msg'),
        convId: convId,
        senderUserId: me.user.id,
        senderDeviceId: me.device.id,
        kind: MessageKind.file,
        sentAt: _tick(),
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
        status: MessageStatus.sent,
      ),
    );
  }

  @override
  Stream<List<int>> readAttachment({
    required String messageId,
    required String blobId,
  }) {
    final bytes = _blobs[blobId];
    if (bytes == null) {
      return Stream.error(
        const ChatException('not_found', 'blob desconhecido'),
      );
    }
    const chunk = 65536;
    return Stream.fromIterable([
      for (var i = 0; i < bytes.length; i += chunk)
        bytes.sublist(i, i + chunk > bytes.length ? bytes.length : i + chunk),
    ]);
  }

  @override
  Future<void> markRead(String convId) async {
    final conv = _conversation(convId);
    final msgs = _messagesOf(convId);
    msgs.value = [
      for (final m in msgs.value)
        m.isMine || m.status == MessageStatus.read
            ? m
            : m.copyWith(status: MessageStatus.read),
    ];
    _replaceConversation(conv.copyWith(unreadCount: 0));
  }

  @override
  Future<void> dispose() async {
    for (final t in _timers) {
      t.cancel();
    }
    await Future.wait([
      _session.close(),
      _connection.close(),
      _contacts.close(),
      _conversations.close(),
      ..._messages.values.map((v) => v.close()),
    ]);
  }

  // ── Internos ──────────────────────────────────────────────────────────────
  Registered _requireRegistered() {
    final s = _session.value;
    if (s is Registered) return s;
    throw const ChatException('not_registered', 'faça o onboarding primeiro');
  }

  DateTime _tick() => _now = _now.add(const Duration(seconds: 1));

  String _nextId(String prefix) =>
      '${prefix}_${(++_seq).toString().padLeft(4, '0')}';

  _Value<List<Message>> _messagesOf(String convId) =>
      _messages.putIfAbsent(convId, () => _Value<List<Message>>(const []));

  Conversation _conversation(String convId) {
    final c = _conversations.value.where((c) => c.id == convId).firstOrNull;
    if (c == null)
      throw const ChatException('not_found', 'conversa desconhecida');
    return c;
  }

  static List<Conversation> _sorted(List<Conversation> list) =>
      [...list]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  void _replaceConversation(Conversation conv) {
    _conversations.value = _sorted([
      for (final c in _conversations.value) c.id == conv.id ? conv : c,
    ]);
  }

  void _append(Message msg) {
    final msgs = _messagesOf(msg.convId);
    msgs.value = [...msgs.value, msg];
    final conv = _conversation(msg.convId);
    _replaceConversation(
      conv.copyWith(
        lastMessage: msg,
        updatedAt: msg.sentAt,
        unreadCount: msg.isMine ? conv.unreadCount : conv.unreadCount + 1,
      ),
    );
  }

  void _scheduleReply(String convId, String original) {
    void reply() {
      if (_session.isClosed) return;
      _append(
        Message(
          id: _nextId('msg'),
          convId: convId,
          senderUserId: maeId,
          senderDeviceId: maeDeviceId,
          kind: MessageKind.text,
          sentAt: _tick(),
          isMine: false,
          body: 'Recebi: "$original" 💛',
          status: MessageStatus.delivered,
        ),
      );
    }

    if (autoReplyDelay == Duration.zero) {
      reply();
    } else {
      _timers.add(Timer(autoReplyDelay, reply));
    }
  }

  void _seedConversations() {
    _seq = 0;
    _messages.clear();
    final direct = ConvId.direct(felipeId, maeId);
    final t0 = DateTime.utc(2026, 9, 6, 18, 10);
    _conversations.value = [
      Conversation(
        id: ConvId.family,
        kind: ConversationKind.group,
        title: 'Família',
        participantUserIds: const [felipeId, maeId],
        updatedAt: t0,
      ),
      Conversation(
        id: direct,
        kind: ConversationKind.direct,
        title: 'Mãe',
        participantUserIds: const [felipeId, maeId],
        updatedAt: t0,
      ),
    ];
    final seed = <(String, bool, String, DateTime, MessageStatus)>[
      (
        ConvId.family,
        true,
        'Bem-vindos ao Chatito! 🎉',
        t0,
        MessageStatus.read,
      ),
      (
        ConvId.family,
        false,
        'Que chique! Funciona no meu celular?',
        t0.add(const Duration(minutes: 1)),
        MessageStatus.read,
      ),
      (
        ConvId.family,
        true,
        'Funciona sim. Tudo cifrado ponta a ponta.',
        t0.add(const Duration(minutes: 2)),
        MessageStatus.delivered,
      ),
      (
        direct,
        true,
        'Oi! Chegou bem?',
        t0.add(const Duration(minutes: 5)),
        MessageStatus.read,
      ),
      (
        direct,
        false,
        'Cheguei sim, filho. Foto da praia depois!',
        t0.add(const Duration(minutes: 6)),
        MessageStatus.delivered,
      ),
    ];
    for (final (conv, mine, body, at, status) in seed) {
      _append(
        Message(
          id: _nextId('msg'),
          convId: conv,
          senderUserId: mine ? felipeId : maeId,
          senderDeviceId: mine ? felipeDeviceId : maeDeviceId,
          kind: MessageKind.text,
          sentAt: at,
          isMine: mine,
          body: body,
          status: status,
        ),
      );
    }
    _now = t0.add(const Duration(minutes: 20));
  }
}

/// Valor observável: `stream` emite o valor atual ao ouvir e cada mudança.
class _Value<T> {
  _Value(this._value);

  T _value;
  final _controller = StreamController<T>.broadcast();

  T get value => _value;

  set value(T v) {
    _value = v;
    if (!_controller.isClosed) _controller.add(v);
  }

  bool get isClosed => _controller.isClosed;

  Stream<T> get stream async* {
    yield _value;
    yield* _controller.stream;
  }

  Future<void> close() => _controller.close();
}
