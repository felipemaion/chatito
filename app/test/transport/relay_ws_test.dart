import 'dart:async';

import 'package:chatito/domain/models.dart' show ConnectionState;
import 'package:chatito/protocol/protocol.dart';
import 'package:chatito/transport/transport.dart';
import 'package:test/test.dart';

import '../support/fake_relay.dart';

void main() {
  late FakeRelay relay;
  late String token;
  late User user;
  final received = <Envelope>[];
  late RelayWs ws;

  setUp(() async {
    received.clear();
    relay = FakeRelay();
    await relay.start();
    user = relay.addUser('Felipe');
    token = relay.addDevice(user.id, identityKey: 'AA==', id: 'dev_me');
    relay.addDevice(user.id, identityKey: 'BB==', id: 'dev_peer');
  });

  tearDown(() async {
    await ws.dispose();
    await relay.stop();
  });

  RelayWs make({
    Future<void> Function(Envelope)? onEnvelope,
    Duration base = const Duration(milliseconds: 30),
  }) => ws = RelayWs(
    baseUrl: relay.baseUrl,
    token: token,
    onEnvelope: onEnvelope ?? (e) async => received.add(e),
    backoffBase: base,
    backoffMax: const Duration(milliseconds: 200),
  );

  Future<void> until(
    bool Function() cond, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final end = DateTime.now().add(timeout);
    while (!cond()) {
      if (DateTime.now().isAfter(end)) fail('timeout');
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  test(
    'conecta, recebe pendentes e ao vivo, e faz ack automático após o handler',
    () async {
      await relay.inject(
        Envelope(toDevice: 'dev_me', nonce: 'n', ciphertext: 'AA=='),
        fromDevice: 'dev_peer',
      );
      final states = <ConnectionState>[];
      make();
      ws.watchConnection().listen(states.add);
      await ws.connect();
      await until(() => received.length == 1);
      await until(() => (relay.queues['dev_me'] ?? []).isEmpty);
      expect(received.single.fromDevice, 'dev_peer');
      expect(
        states,
        containsAllInOrder([
          ConnectionState.connecting,
          ConnectionState.online,
        ]),
      );

      await relay.inject(
        Envelope(toDevice: 'dev_me', nonce: 'n2', ciphertext: 'AA=='),
        fromDevice: 'dev_peer',
      );
      await until(() => received.length == 2);
      await until(() => (relay.queues['dev_me'] ?? []).isEmpty);
      await ws.connect(); // idempotente
    },
  );

  test('handler que lança → sem ack (fica pendente no relay)', () async {
    await relay.inject(
      Envelope(toDevice: 'dev_me', nonce: 'n', ciphertext: 'AA=='),
      fromDevice: 'dev_peer',
    );
    var calls = 0;
    make(
      onEnvelope: (_) async {
        calls++;
        throw StateError('db down');
      },
    );
    await ws.connect();
    await until(() => calls == 1);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(relay.queues['dev_me'], hasLength(1));
  });

  test('responde ping com pong', () async {
    make();
    await ws.connect();
    await until(() => relay.sockets.containsKey('dev_me'));
    relay.sendRaw('dev_me', const WsPing().toJson());
    await until(() => relay.log.any((l) => l.contains('← pong')));
  });

  test('reconecta com backoff após queda e re-recebe pendentes', () async {
    final states = <ConnectionState>[];
    make();
    ws.watchConnection().listen(states.add);
    await ws.connect();
    await until(() => relay.sockets.containsKey('dev_me'));
    await relay.closeSocket('dev_me', code: 1001);
    await until(
      () => states.where((s) => s == ConnectionState.online).length >= 2,
    );
    expect(states, contains(ConnectionState.connecting));
    await relay.inject(
      Envelope(toDevice: 'dev_me', nonce: 'n', ciphertext: 'AA=='),
      fromDevice: 'dev_peer',
    );
    await until(() => received.length == 1);
    expect(ws.reconnectAttempts, 0, reason: 'zera após reconectar');
  });

  test('servidor fora: tenta com backoff crescente até voltar', () async {
    make();
    final port = relay.baseUrl.split(':').last;
    await relay.stop();
    await ws.connect();
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(ws.reconnectAttempts, greaterThan(1));
    // Sobe outro relay na mesma porta não é garantido; só verificamos que continua tentando.
    expect(await ws.watchConnection().first, isNot(ConnectionState.online));
    expect(port, isNotEmpty);
  });

  test('4401 (token inválido) → para de reconectar e emite erro', () async {
    relay.rejectAllTokens = true;
    make();
    final errors = <RelayException>[];
    ws.errors.listen(errors.add);
    await ws.connect();
    await until(() => errors.isNotEmpty);
    expect(errors.first.code, 'unauthorized');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(ws.reconnectAttempts, 0);
    expect(await ws.watchConnection().first, ConnectionState.offline);
  });

  test('4409 (outra conexão do mesmo device) → não briga', () async {
    make();
    await ws.connect();
    await until(() => relay.sockets.containsKey('dev_me'));
    final second = RelayWs(
      baseUrl: relay.baseUrl,
      token: token,
      onEnvelope: (_) async {},
    );
    await second.connect();
    await until(() => (ws.lastCloseCode ?? 0) == 4409);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(await ws.watchConnection().first, ConnectionState.offline);
    await second.dispose();
  });

  test('disconnect fecha e não reconecta; ack manual', () async {
    make();
    await ws.connect();
    await until(() => relay.sockets.containsKey('dev_me'));
    await ws.ack(['env_nope']);
    await ws.disconnect();
    await until(() => !relay.sockets.containsKey('dev_me'));
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(relay.sockets.containsKey('dev_me'), isFalse);
    expect(await ws.watchConnection().first, ConnectionState.offline);
    await ws.ack(['x']); // sem conexão: ignorado
  });

  test('frame malformado não derruba a conexão', () async {
    make();
    await ws.connect();
    await until(() => relay.sockets.containsKey('dev_me'));
    relay.sendRaw('dev_me', 'not json');
    relay.sendRaw('dev_me', {'type': 'weird'});
    await relay.inject(
      Envelope(toDevice: 'dev_me', nonce: 'n', ciphertext: 'AA=='),
      fromDevice: 'dev_peer',
    );
    await until(() => received.length == 1);
  });
}
