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
/// O carregamento da sessão do [KeyStore] começa sozinho na construção;
/// qualquer método que precise dela espera esse carregamento terminar antes
/// de decidir (nunca lança `not_registered` só porque foi chamado cedo
/// demais). Chamar [init] continua funcionando, mas não é mais necessário.
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
    // Começa a carregar a sessão do KeyStore já na construção — nunca fica
    // pendente de alguém lembrar de chamar `init()` antes de usar a fachada.
    // Bug de campo: a UI (observador de conectividade) chamava `connect()`
    // logo depois de construir, antes desse carregamento terminar; `_require`
    // via `_active == null` e lançava `not_registered` como exceção não
    // tratada, e o app nunca conectava. Todo método que depende de sessão
    // agora espera [_ready] antes de decidir (ver [_requireReady]).
    _ready = _loadInitialSession();
  }

  Future<void> _loadInitialSession() async {
    // ignore: avoid_print
    print('[piriquito.boot] restore: início');
    final s = await _onboarding.restore();
    // ignore: avoid_print
    print('[piriquito.boot] restore: fim (sessão=${s != null})');
    if (s == null) return;
    _setActive(s);
    // dispose() pode ter rodado entre a construção e aqui (raro, mas
    // possível se o chamador descartar a fachada sem nunca usá-la) — não
    // inicia nada em cima de uma fachada já descartada.
    if (_disposed) return;
    // Bug de boot (Android): quem chamaria connect() é o observador de
    // conectividade (connectivity_plus) no app-ui, mas ele pode não emitir
    // um evento inicial — nada mais conecta sozinho. Se já há sessão salva,
    // conecta por conta própria assim que o carregamento termina, sem
    // esperar ninguém pedir. Roda em segundo plano: não atrasa [_ready] (que
    // é só sobre saber quem eu sou, não sobre estar online), e falhas de
    // rede aqui não devem virar exceção não tratada. [dispose] espera esta
    // tarefa (`_autoConnectTask`) para nunca deixar um `RelayWs` órfão sendo
    // criado depois que a fachada já foi descartada.
    _autoConnectTask = _autoConnect();
  }

  Future<void> _autoConnect() async {
    try {
      await connect();
    } on Object catch (e) {
      _log('autoConnect: $e');
    }
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

  /// Completa quando a sessão persistida (ou a ausência dela) já foi
  /// carregada do [KeyStore] — todo método que usa [_require] espera por
  /// isto primeiro (ver [_requireReady]).
  late final Future<void> _ready;

  /// A tarefa do autoConnect de boot, se ela chegou a começar (ver
  /// [_loadInitialSession]). [dispose] espera por ela antes de seguir, para
  /// nunca deixar um [RelayWs] sendo criado depois de já descartada.
  Future<void>? _autoConnectTask;

  /// Single-flight de [_ensureWs]: enquanto não nulo, uma criação do
  /// [RelayWs] já está em andamento e ninguém mais deve iniciar outra.
  Future<void>? _connecting;

  ActiveSession? _active;
  RelayWs? _ws;
  StreamSubscription<ConnectionState>? _wsStateSub;
  StreamSubscription<RelayException>? _wsErrSub;
  final _session = Observable<SessionState>(const NotRegistered());
  final _connection = Observable<ConnectionState>(ConnectionState.offline);
  bool _disposed = false;

  ConnectionState get currentConnection => _connection.value;

  /// O carregamento inicial já começa sozinho na construção; chamar isto não
  /// é mais necessário, mas continua funcionando (idempotente) para quem já
  /// chamava antes de usar o resto da fachada.
  Future<void> init() => _ready;

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
    // Espera o carregamento inicial terminar antes de registrar, para não
    // correr o risco de `_loadInitialSession` sobrescrever `_active` com uma
    // sessão velha do KeyStore depois que o registro novo já rodou.
    await _ready;
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

  /// Como [_require], mas espera o carregamento inicial da sessão terminar
  /// primeiro — só lança `not_registered` se, depois disso, ainda não houver
  /// sessão de verdade. Use em todo método que depende de sessão.
  Future<ActiveSession> _requireReady() async {
    await _ready;
    return _require();
  }

  // ── Conexão ───────────────────────────────────────────────────────────────
  @override
  Stream<ConnectionState> watchConnection() => _connection.stream;

  @override
  Future<void> connect() async {
    final s = await _requireReady();
    final ws = await _ensureWs(s);
    await ws.connect();
    unawaited(_sender.drain());
  }

  @override
  Future<void> ensureConnected() async {
    final s = await _requireReady();
    final ws = await _ensureWs(s);
    await ws.ensureConnected();
    unawaited(_sender.drain());
  }

  /// Cria o [RelayWs] (com o token do [KeyStore]) na 1ª chamada; devolve o
  /// mesmo depois. Compartilhado por [connect] e [ensureConnected].
  ///
  /// Single-flight: bug de campo (evidência de logcat) tinha 3 `RelayWs`
  /// nascendo de chamadas concorrentes (autoConnect + gatilhos da UI) porque
  /// a checagem `_ws == null` era seguida de um `await` (a leitura do token)
  /// antes de `_ws` ser atribuído — toda chamada que chegasse nesse meio
  /// tempo via `_ws` ainda nulo e criava a sua própria. [_connecting] fecha
  /// essa janela: a 2ª e 3ª chamada só esperam a 1ª terminar de criar.
  Future<RelayWs> _ensureWs(ActiveSession s) {
    final existing = _ws;
    if (existing != null) return Future.value(existing);
    final inFlight = _connecting;
    if (inFlight != null) return inFlight.then((_) => _ws!);
    final future = _createWs(s);
    _connecting = future;
    return future.then((_) => _ws!).whenComplete(() {
      if (identical(_connecting, future)) _connecting = null;
    });
  }

  Future<void> _createWs(ActiveSession s) async {
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
  Future<void> refreshDirectory() async =>
      _directory.refresh(await _requireReady());

  @override
  Future<SafetyNumber> safetyNumber(String deviceId) async {
    final s = await _requireReady();
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
    final s = await _requireReady();
    if (await _ctx.db.userById(userId) == null) {
      throw const ChatException('not_found', 'usuário desconhecido');
    }
    return _directory.ensureDirect(ConvId.direct(s.user.id, userId), s);
  }

  @override
  Future<void> sendText(String convId, String body) async {
    final s = await _requireReady();
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
  }) async => _files.send(
    await _requireReady(),
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
  }) async* {
    await _requireReady();
    yield* _files.read(blobId);
  }

  @override
  Future<void> markRead(String convId) async {
    final s = await _requireReady();
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
    // Espera o autoConnect de boot terminar antes de seguir: se ele ainda
    // estivesse criando o RelayWs quando `_ws?.dispose()` rodasse, o WS
    // nasceria depois, órfão, e continuaria tentando conectar (e mexendo no
    // banco) mesmo com a fachada já descartada.
    await _autoConnectTask;
    await _wsStateSub?.cancel();
    await _wsErrSub?.cancel();
    await _ws?.dispose();
    await _session.close();
    await _connection.close();
  }
}
