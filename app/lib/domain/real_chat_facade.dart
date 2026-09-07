import 'dart:async';
import 'dart:convert' show base64Decode;

import 'package:uuid/uuid.dart';

import '../crypto/crypto.dart';
import '../protocol/protocol.dart';
import '../storage/storage.dart';
import '../transport/transport.dart';
import 'attachment_cache.dart';
import 'chat_facade.dart';
import 'models.dart';
import 'observable.dart';
import 'use_cases/context.dart';
import 'use_cases/directory_sync.dart';
import 'use_cases/files.dart';
import 'use_cases/onboarding.dart';
import 'use_cases/receive_envelope.dart';
import 'use_cases/send_message.dart';

/// Implementação real do [ChatFacade]: crypto + storage + transport.
///
/// Chame [init] após construir para restaurar a sessão do [KeyStore].
class RealChatFacade implements ChatFacade {
  RealChatFacade({
    required CryptoBox cryptoBox,
    required FileCipher fileCipher,
    required ChatDatabase db,
    required KeyStore keyStore,
    required String baseUrl,
    RelayApi? api,
    AttachmentCache? cache,
    DateTime Function()? now,
    String Function()? newId,
    void Function(String message)? log,
    this.wsBackoffBase = const Duration(seconds: 1),
    this.wsBackoffMax = const Duration(seconds: 30),
  }) : _log = log ?? ((_) {}),
       _cache = cache ?? InMemoryAttachmentCache() {
    _ctx = ChatContext(
      cryptoBox: cryptoBox,
      fileCipher: fileCipher,
      db: db,
      keyStore: keyStore,
      api: api ?? RelayApi(baseUrl: baseUrl),
      log: _log,
      now: now ?? () => DateTime.now().toUtc(),
      newId: newId ?? const Uuid().v4,
    );
    _directory = DirectorySync(_ctx);
    _onboarding = Onboarding(_ctx, _directory);
    _sender = SendMessage(_ctx);
    _receiver = ReceiveEnvelope(_ctx, _directory, _sender);
    _files = Files(_ctx, _cache, _sender);
  }

  final void Function(String) _log;
  final AttachmentCache _cache;
  final Duration wsBackoffBase;
  final Duration wsBackoffMax;
  late final ChatContext _ctx;
  late final DirectorySync _directory;
  late final Onboarding _onboarding;
  late final SendMessage _sender;
  late final ReceiveEnvelope _receiver;
  late final Files _files;

  ActiveSession? _active;
  RelayWs? _ws;
  StreamSubscription<ConnectionState>? _wsStateSub;
  StreamSubscription<RelayException>? _wsErrSub;
  final _session = Observable<SessionState>(const NotRegistered());
  final _connection = Observable<ConnectionState>(ConnectionState.offline);
  bool _disposed = false;

  ConnectionState get currentConnection => _connection.value;

  /// Restaura a sessão persistida (sem rede). Idempotente.
  Future<void> init() async {
    final s = await _onboarding.restore();
    if (s != null) {
      _setActive(s);
    }
  }

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
    final s = await _onboarding.register(
      inviteCode: inviteCode,
      deviceName: deviceName,
      platform: platform,
    );
    _setActive(s);
  }

  void _setActive(ActiveSession s) {
    _active = s;
    _session.value = s.asState;
  }

  ActiveSession _require() {
    final s = _active;
    if (s == null) {
      throw const ChatException('not_registered', 'faça o onboarding primeiro');
    }
    return s;
  }

  // ── Conexão ───────────────────────────────────────────────────────────────
  @override
  Stream<ConnectionState> watchConnection() => _connection.stream;

  @override
  Future<void> connect() async {
    final s = _require();
    if (_ws == null) {
      final token = await _ctx.keyStore.readToken();
      if (token == null) {
        throw const ChatException('not_registered', 'sem token');
      }
      final ws = RelayWs(
        baseUrl: _ctx.api.baseUrl,
        token: token,
        onEnvelope: (e) => _receiver.handle(s, e),
        backoffBase: wsBackoffBase,
        backoffMax: wsBackoffMax,
        log: _log,
      );
      _wsStateSub = ws.watchConnection().listen((st) {
        _connection.value = st;
        if (st == ConnectionState.online) {
          unawaited(_afterOnline(s));
        }
      });
      _wsErrSub = ws.errors.listen((e) => _log('ws: $e'));
      _ws = ws;
    }
    await _ws!.connect();
    unawaited(_sender.drain());
  }

  Future<void> _afterOnline(ActiveSession s) async {
    try {
      await _sender.drain();
      await _directory.refresh(s);
    } on ChatException catch (e) {
      _log('sincronização pós-conexão: $e');
    }
  }

  @override
  Future<void> disconnect() async {
    await _ws?.disconnect();
  }

  // ── Diretório ─────────────────────────────────────────────────────────────
  @override
  Stream<List<Contact>> watchContacts() => _ctx.db.watchContacts();

  @override
  Future<void> refreshDirectory() => _directory.refresh(_require());

  @override
  Future<SafetyNumber> safetyNumber(String deviceId) async {
    final s = _require();
    final other = await _ctx.db.deviceById(deviceId);
    if (other == null) {
      throw const ChatException('not_found', 'device desconhecido');
    }
    return ChatContext.guard(() async {
      return SafetyNumber(
        _ctx.cryptoBox.safetyNumber(
          s.keys.publicKey,
          base64Decode(other.identityKey),
        ),
      );
    });
  }

  // ── Conversas ─────────────────────────────────────────────────────────────
  @override
  Stream<List<Conversation>> watchConversations() =>
      _ctx.db.watchConversations();

  @override
  Stream<List<Message>> watchMessages(String convId) =>
      _ctx.db.watchMessages(convId);

  @override
  Future<Conversation> openDirect(String userId) async {
    final s = _require();
    if (await _ctx.db.userById(userId) == null) {
      throw const ChatException('not_found', 'usuário desconhecido');
    }
    return _directory.ensureDirect(ConvId.direct(s.user.id, userId), s);
  }

  @override
  Future<void> sendText(String convId, String body) async {
    final s = _require();
    if (body.isEmpty) {
      throw const ChatException('validation', 'texto vazio');
    }
    final msgId = _ctx.newId();
    final payload = Payload(
      msgId: msgId,
      convId: convId,
      kind: PayloadKind.text,
      sentAt: _ctx.now(),
      body: body,
    );
    await _sender.send(
      s,
      payload,
      persist: Message(
        id: msgId,
        convId: convId,
        senderUserId: s.user.id,
        senderDeviceId: s.device.id,
        kind: MessageKind.text,
        sentAt: payload.sentAt,
        isMine: true,
        body: body,
      ),
    );
  }

  @override
  Future<void> sendFile(
    String convId, {
    required String name,
    required String mime,
    required int size,
    required Stream<List<int>> data,
    String? caption,
  }) => _files.send(
    _require(),
    convId,
    name: name,
    mime: mime,
    size: size,
    data: data,
    caption: caption,
  );

  @override
  Stream<List<int>> readAttachment({
    required String messageId,
    required String blobId,
  }) {
    _require();
    return _files.read(blobId);
  }

  @override
  Future<void> markRead(String convId) async {
    final s = _require();
    final ids = await _ctx.db.markRead(convId);
    for (final id in ids) {
      final m = await _ctx.db.messageById(id);
      if (m == null || m.kind == MessageKind.keyChange) {
        continue;
      }
      try {
        await _sender.send(
          s,
          Payload(
            msgId: _ctx.newId(),
            convId: convId,
            kind: PayloadKind.receipt,
            sentAt: _ctx.now(),
            receipt: Receipt(msgId: id, status: ReceiptStatus.read),
          ),
          toUserIds: [m.senderUserId],
        );
      } on ChatException catch (e) {
        _log('recibo read de $id não enviado: $e');
      }
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await _wsStateSub?.cancel();
    await _wsErrSub?.cancel();
    await _ws?.dispose();
    await _session.close();
    await _connection.close();
  }
}
