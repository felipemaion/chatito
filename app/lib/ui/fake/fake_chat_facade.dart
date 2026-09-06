/// Implementação em memória da [ChatFacade] para desenvolvimento da UI e testes.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import '../contracts.dart';

class FakeChatFacade implements ChatFacade {
  FakeChatFacade({
    this.autoReply = false,
    this.progressSteps = 5,
    this.latency = Duration.zero,
  });

  /// Fachada já registrada com dados parecidos com `docs/protocol/fixtures`.
  factory FakeChatFacade.seeded({
    bool autoReply = false,
    int progressSteps = 5,
  }) {
    final f = FakeChatFacade(
      autoReply: autoReply,
      progressSteps: progressSteps,
    );
    f._seed();
    return f;
  }

  static const validInvite = '7K3M-9QZR';
  static const userFelipe = 'usr_A';
  static const userMae = 'usr_B';
  static const userFilha = 'usr_C';
  static const groupConv = 'g:familia';

  final bool autoReply;
  final int progressSteps;
  final Duration latency;

  final _session = ValueStream<SessionState>(const SessionState());
  final _connection = ValueStream<ConnectionState>(ConnectionState.online);
  final _conversations = ValueStream<List<Conversation>>(const []);
  final _directory = ValueStream<List<UserInfo>>(const []);
  final Map<String, ValueStream<List<Message>>> _messages = {};

  int syncCalls = 0;
  String? pushToken;
  int _seq = 0;

  @override
  Watchable<SessionState> get session => _session;
  @override
  Watchable<ConnectionState> get connection => _connection;
  @override
  Watchable<List<Conversation>> get conversations => _conversations;
  @override
  Watchable<List<UserInfo>> get directory => _directory;

  @override
  Watchable<List<Message>> messages(String convId) =>
      _messages.putIfAbsent(convId, () => ValueStream<List<Message>>(const []));

  void setConnection(ConnectionState s) => _connection.value = s;

  @override
  Future<Identity> register({
    required String inviteCode,
    required String deviceName,
    required String platform,
    String? serverUrl,
  }) async {
    await Future<void>.delayed(latency);
    if (inviteCode.trim().toUpperCase() != validInvite) {
      throw const ChatException(
        'invalid_invite',
        'Convite inválido ou expirado',
      );
    }
    if (deviceName.trim().isEmpty) {
      throw const ChatException('validation', 'Nome do device obrigatório');
    }
    _seed(deviceName: deviceName.trim(), platform: platform);
    return _session.value.me!;
  }

  @override
  Future<void> sendText(String convId, String body) async {
    _requireSession();
    if (body.trim().isEmpty) {
      throw const ChatException('validation', 'Mensagem vazia');
    }
    final me = _session.value.me!;
    final msg = Message(
      id: _id('msg'),
      convId: convId,
      fromUserId: me.user.id,
      fromDeviceId: me.device.id,
      kind: MessageKind.text,
      sentAt: DateTime.now().toUtc(),
      isMine: true,
      body: body.trim(),
      status: MessageStatus.sent,
    );
    _append(msg);
    if (autoReply) {
      unawaited(_reply(convId, msg.id));
    }
  }

  @override
  Future<void> sendFile(
    String convId,
    String path, {
    required String name,
    required int size,
    required String mime,
    String? caption,
  }) async {
    _requireSession();
    final me = _session.value.me!;
    final msgId = _id('msg');
    final blobId = _id('blob');
    _append(
      Message(
        id: msgId,
        convId: convId,
        fromUserId: me.user.id,
        fromDeviceId: me.device.id,
        kind: MessageKind.file,
        sentAt: DateTime.now().toUtc(),
        isMine: true,
        body: caption,
        status: MessageStatus.sending,
        attachments: [
          Attachment(
            blobId: blobId,
            name: name,
            size: size,
            mime: mime,
            localPath: path,
            transfer: const TransferProgress(state: TransferState.uploading),
          ),
        ],
      ),
    );
    await _progress(convId, msgId, TransferState.uploading);
    _update(convId, msgId, (m) => m.copyWith(status: MessageStatus.sent));
    if (autoReply) {
      unawaited(_reply(convId, msgId));
    }
  }

  @override
  Future<String> downloadAttachment(String msgId, String blobId) async {
    final convId = _convOf(msgId);
    final path = '/tmp/chatito/$blobId';
    await _progress(convId, msgId, TransferState.downloading);
    _update(
      convId,
      msgId,
      (m) => m.copyWith(
        attachments: [
          for (final a in m.attachments)
            a.blobId == blobId ? a.copyWith(localPath: path) : a,
        ],
      ),
    );
    return path;
  }

  @override
  Future<void> markRead(String convId) async {
    _setConv(convId, (c) => c.copyWith(unreadCount: 0));
  }

  @override
  Future<String> safetyNumber(String deviceId) async {
    final me = _session.value.me!.device.identityKey;
    final other = _allDevices().firstWhere((d) => d.id == deviceId).identityKey;
    final keys = [me, other]..sort();
    // Derivação determinística e simétrica; o núcleo real usa SHA-256(sorted(pk_a‖pk_b)).
    final bytes = utf8.encode(keys.join());
    final rnd = Random(
      bytes.fold<int>(17, (h, b) => (h * 31 + b) & 0x7fffffff),
    );
    final digits = List.generate(60, (_) => rnd.nextInt(10)).join();
    return [for (var i = 0; i < 60; i += 5) digits.substring(i, i + 5)]
        .join(' ');
  }

  @override
  Future<void> removeDevice(String deviceId) async {
    if (deviceId == _session.value.me!.device.id) {
      throw const ChatException(
        'forbidden',
        'Não é possível remover este device por aqui',
      );
    }
    _directory.value = [
      for (final u in _directory.value)
        UserInfo(
          id: u.id,
          name: u.name,
          role: u.role,
          devices: u.devices.where((d) => d.id != deviceId).toList(),
        ),
    ];
  }

  @override
  Future<void> setPushToken(String? token) async => pushToken = token;

  @override
  Future<void> sync() async => syncCalls++;

  /// Simula uma mensagem recebida de outro participante.
  void simulateIncoming(String convId, String body, {String? fromUserId}) {
    final conv = _conversations.value.firstWhere((c) => c.id == convId);
    final from = fromUserId ?? conv.participantIds.first;
    final dev = _directory.value.firstWhere((u) => u.id == from).devices.first;
    _append(
      Message(
        id: _id('msg'),
        convId: convId,
        fromUserId: from,
        fromDeviceId: dev.id,
        kind: MessageKind.text,
        sentAt: DateTime.now().toUtc(),
        isMine: false,
        body: body,
      ),
      incrementUnread: true,
    );
  }

  // ---- internos ----

  void _requireSession() {
    if (!_session.value.isRegistered) {
      throw const ChatException('unauthorized', 'Device não registrado');
    }
  }

  String _id(String prefix) =>
      '${prefix}_${(++_seq).toString().padLeft(4, '0')}';

  String _convOf(String msgId) => _messages.entries
      .firstWhere((e) => e.value.value.any((m) => m.id == msgId))
      .key;

  Iterable<DeviceInfo> _allDevices() =>
      _directory.value.expand((u) => u.devices);

  void _append(Message msg, {bool incrementUnread = false}) {
    final s = _messages.putIfAbsent(
      msg.convId,
      () => ValueStream<List<Message>>(const []),
    );
    s.value = [...s.value, msg];
    _setConv(
      msg.convId,
      (c) => c.copyWith(
        lastMessage: msg,
        updatedAt: msg.sentAt,
        unreadCount: incrementUnread ? c.unreadCount + 1 : c.unreadCount,
      ),
    );
  }

  void _update(String convId, String msgId, Message Function(Message) f) {
    final s = _messages[convId]!;
    s.value = [for (final m in s.value) m.id == msgId ? f(m) : m];
    final last = s.value.last;
    if (last.id == msgId) {
      _setConv(convId, (c) => c.copyWith(lastMessage: last));
    }
  }

  void _setConv(String convId, Conversation Function(Conversation) f) {
    final list = [
      for (final c in _conversations.value) c.id == convId ? f(c) : c,
    ];
    list.sort(
      (a, b) =>
          (b.updatedAt ?? DateTime(0)).compareTo(a.updatedAt ?? DateTime(0)),
    );
    _conversations.value = list;
  }

  Future<void> _progress(
    String convId,
    String msgId,
    TransferState state,
  ) async {
    for (var i = 1; i <= progressSteps; i++) {
      await Future<void>.delayed(latency);
      final done = i == progressSteps;
      _update(
        convId,
        msgId,
        (m) => m.copyWith(
          attachments: [
            for (final a in m.attachments)
              a.copyWith(
                transfer: TransferProgress(
                  state: done ? TransferState.done : state,
                  progress: i / progressSteps,
                ),
              ),
          ],
        ),
      );
    }
  }

  Future<void> _reply(String convId, String myMsgId) async {
    await Future<void>.delayed(latency);
    _update(
      convId,
      myMsgId,
      (m) => m.copyWith(status: MessageStatus.delivered),
    );
    _update(convId, myMsgId, (m) => m.copyWith(status: MessageStatus.read));
    simulateIncoming(
      convId,
      'Recebi: ${messages(convId).value.firstWhere((m) => m.id == myMsgId).body ?? '📎'}',
    );
  }

  void _seed({
    String deviceName = 'MacBook do Felipe',
    String platform = 'macos',
  }) {
    final t0 = DateTime.utc(2026, 9, 6, 18);
    DeviceInfo dev(
      String id,
      String user,
      String name,
      String plat,
      String key,
      int min,
    ) => DeviceInfo(
      id: id,
      userId: user,
      name: name,
      platform: plat,
      identityKey: key,
      createdAt: t0.add(Duration(minutes: min)),
    );
    final myDev = dev(
      'dev_me',
      userFelipe,
      deviceName,
      platform,
      'hSDwCYkwp1R0i33ctD73Wg2/Og0mOBr066SpjqqbTmo=',
      0,
    );
    final myWin = dev(
      'dev_win',
      userFelipe,
      'PC Windows',
      'windows',
      'WINDOWSKEY0000000000000000000000000000000000=',
      1,
    );
    final maeDev = dev(
      'dev_mae',
      userMae,
      'Galaxy',
      'android',
      '3p7bfXt9wbTTW2HC7OQ1Nz+DQ8hbeGdNrfx+FG+IK08=',
      5,
    );
    final filhaDev = dev(
      'dev_filha',
      userFilha,
      'Moto G',
      'android',
      'FILHAKEY000000000000000000000000000000000000=',
      9,
    );
    final me = UserInfo(
      id: userFelipe,
      name: 'Felipe',
      role: 'admin',
      devices: [myDev, myWin],
    );
    final mae = UserInfo(
      id: userMae,
      name: 'Mãe',
      role: 'member',
      devices: [maeDev],
    );
    final filha = UserInfo(
      id: userFilha,
      name: 'Filha',
      role: 'member',
      devices: [filhaDev],
    );
    _directory.value = [me, mae, filha];
    _session.value = SessionState(
      me: Identity(user: me, device: myDev),
    );

    Message m(
      String id,
      String conv,
      String from,
      String fromDev,
      bool mine,
      String? body,
      int min, {
      List<Attachment> att = const [],
      MessageStatus st = MessageStatus.read,
    }) => Message(
      id: id,
      convId: conv,
      fromUserId: from,
      fromDeviceId: fromDev,
      kind: att.isEmpty ? MessageKind.text : MessageKind.file,
      sentAt: t0.add(Duration(minutes: min)),
      isMine: mine,
      body: body,
      attachments: att,
      status: st,
    );
    final group = [
      m('msg_g1', groupConv, userMae, 'dev_mae', false, 'Chegaram bem?', 10),
      m(
        'msg_g2',
        groupConv,
        userFelipe,
        'dev_me',
        true,
        'Sim! Tudo certo por aqui.',
        11,
        st: MessageStatus.delivered,
      ),
      m(
        'msg_g3',
        groupConv,
        userFilha,
        'dev_filha',
        false,
        'Fotos da viagem',
        12,
        att: const [
          Attachment(
            blobId: 'blob_praia',
            name: 'praia.jpg',
            size: 2457600,
            mime: 'image/jpeg',
          ),
        ],
      ),
      m('msg_g4', groupConv, userMae, 'dev_mae', false, 'Que lindo!', 13),
    ];
    const dm = 'u:usr_A:usr_B';
    final direct = [
      m('msg_d1', dm, userMae, 'dev_mae', false, 'Me liga quando puder', 3),
      m(
        'msg_d2',
        dm,
        userFelipe,
        'dev_me',
        true,
        'Ligo à noite',
        4,
        st: MessageStatus.read,
      ),
    ];
    _messages[groupConv] = ValueStream(group);
    _messages[dm] = ValueStream(direct);
    _messages['u:usr_A:usr_C'] = ValueStream(const []);
    _conversations.value = [
      Conversation(
        id: groupConv,
        title: 'Família',
        isGroup: true,
        participantIds: [userMae, userFilha],
        lastMessage: group.last,
        unreadCount: 2,
        updatedAt: group.last.sentAt,
      ),
      Conversation(
        id: dm,
        title: 'Mãe',
        isGroup: false,
        participantIds: const [userMae],
        lastMessage: direct.last,
        updatedAt: direct.last.sentAt,
      ),
      const Conversation(
        id: 'u:usr_A:usr_C',
        title: 'Filha',
        isGroup: false,
        participantIds: [userFilha],
      ),
    ];
  }
}
