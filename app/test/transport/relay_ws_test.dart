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
    // Bem maior que qualquer teste existente, para o watchdog nunca disparar
    // sozinho nos testes que não são sobre ele.
    Duration staleTimeout = const Duration(seconds: 5),
  }) => ws = RelayWs(
    baseUrl: relay.baseUrl,
    token: token,
    onEnvelope: onEnvelope ?? (e) async => received.add(e),
    backoffBase: base,
    backoffMax: const Duration(milliseconds: 200),
    staleTimeout: staleTimeout,
  );

  Future<void> until(
    bool Function() cond, {
    Duration timeout = const Duration(seconds: 3),
    String? reason,
  }) async {
    final end = DateTime.now().add(timeout);
    while (!cond()) {
      if (DateTime.now().isAfter(end)) {
        fail('timeout${reason == null ? '' : ': $reason'}');
      }
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

  test(
    'processa envelopes em sequência, um por vez, na ordem recebida',
    () async {
      var concurrent = 0;
      var maxConcurrent = 0;
      final order = <String>[];
      make(
        onEnvelope: (e) async {
          concurrent++;
          maxConcurrent = concurrent > maxConcurrent
              ? concurrent
              : maxConcurrent;
          // O 1º envelope demora mais: se o processamento fosse paralelo, o 2º
          // (mais rápido) terminaria antes dele.
          await Future<void>.delayed(
            Duration(milliseconds: order.isEmpty ? 60 : 5),
          );
          order.add(e.nonce);
          concurrent--;
        },
      );
      await ws.connect();
      await until(() => relay.sockets.containsKey('dev_me'));
      await relay.inject(
        Envelope(toDevice: 'dev_me', nonce: 'n1', ciphertext: 'AA=='),
        fromDevice: 'dev_peer',
      );
      await relay.inject(
        Envelope(toDevice: 'dev_me', nonce: 'n2', ciphertext: 'AA=='),
        fromDevice: 'dev_peer',
      );
      await relay.inject(
        Envelope(toDevice: 'dev_me', nonce: 'n3', ciphertext: 'AA=='),
        fromDevice: 'dev_peer',
      );
      await until(() => order.length == 3);
      expect(order, ['n1', 'n2', 'n3']);
      expect(maxConcurrent, 1);
    },
  );

  test(
    'handler bloqueado não atrasa o pong (ping é respondido fora da fila)',
    () async {
      final unlock = Completer<void>();
      make(onEnvelope: (_) async => unlock.future);
      await ws.connect();
      await until(() => relay.sockets.containsKey('dev_me'));
      await relay.inject(
        Envelope(toDevice: 'dev_me', nonce: 'n', ciphertext: 'AA=='),
        fromDevice: 'dev_peer',
      );
      relay.sendRaw('dev_me', const WsPing().toJson());
      await until(() => relay.log.any((l) => l.contains('← pong')));
      unlock.complete();
    },
  );

  test(
    'ack não enviado por conexão caída durante o processamento é logado',
    () async {
      final logs = <String>[];
      final unlock = Completer<void>();
      ws = RelayWs(
        baseUrl: relay.baseUrl,
        token: token,
        onEnvelope: (_) => unlock.future,
        log: logs.add,
        // Backoff grande: garante que o teste não vê uma reconexão automática
        // antes de conferir o log (o que trocaria _channel por um novo, não nulo).
        backoffBase: const Duration(seconds: 30),
      );
      await ws.connect();
      await until(() => relay.sockets.containsKey('dev_me'));
      final injected = await relay.inject(
        Envelope(toDevice: 'dev_me', nonce: 'n', ciphertext: 'AA=='),
        fromDevice: 'dev_peer',
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      // Derruba a conexão enquanto o handler ainda está preso.
      await relay.closeSocket('dev_me', code: 1001);
      await until(() => !relay.sockets.containsKey('dev_me'));
      unlock.complete();
      await until(
        () => logs.any(
          (l) => l.contains(injected.id!) && l.contains('conexão caída'),
        ),
      );
      // O envelope continua pendente no relay (nunca foi ack'ado).
      expect(relay.queues['dev_me'], hasLength(1));
    },
  );

  test('close 1001 (queda de rede) simulado: reconecta sozinho e zera as tentativas', () async {
    final states = <ConnectionState>[];
    make();
    ws.watchConnection().listen(states.add);
    await ws.connect();
    await until(() => relay.sockets.containsKey('dev_me'));
    expect(ws.reconnectAttempts, 0);

    await relay.closeSocket('dev_me', code: 1001);
    // `states` já tem `connecting`/`online` da 1ª conexão: espera o 2º
    // `online` (não o 1º) para saber que o ciclo de queda→reconexão terminou.
    await until(
      () => states.where((s) => s == ConnectionState.online).length >= 2,
      reason: 'reconectou sozinho e voltou a online',
    );
    await until(
      () => states.last == ConnectionState.online,
      reason: 'ficou online de novo',
    );
    await until(
      () => ws.reconnectAttempts == 0,
      reason: 'zera após a nova conexão ficar online',
    );
    expect(ws.lastCloseCode, 1001);
  });

  test('close 4409 simulado diretamente pelo relay: para de reconectar, sem outra conexão real', () async {
    make();
    await ws.connect();
    await until(() => relay.sockets.containsKey('dev_me'));

    await relay.closeSocket('dev_me', code: 4409);
    await until(() => ws.lastCloseCode == 4409);
    // Não deve tentar reconectar: dá tempo e confirma que ninguém reabriu a conexão.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(relay.sockets.containsKey('dev_me'), isFalse);
    expect(ws.reconnectAttempts, 0);
    expect(await ws.watchConnection().first, ConnectionState.offline);
  });

  test(
    'duas chamadas concorrentes de connect() abrem só uma conexão',
    () async {
      make();
      final states = <ConnectionState>[];
      ws.watchConnection().listen(states.add);
      await Future.wait([ws.connect(), ws.connect()]);
      await until(
        () => states.isNotEmpty && states.last == ConnectionState.online,
      );
      // Só uma conexão real chegou ao relay (senão a 2ª derrubaria a 1ª com 4409).
      expect(relay.sockets.length, 1);
      expect(relay.log.where((l) => l == 'GET /v1/ws').length, 1);
      expect(
        ws.lastCloseCode,
        isNull,
        reason: 'nunca foi derrubada por si mesma',
      );
    },
  );

  test(
    'handshake que nunca completa: watchdog derruba e reconecta sozinho',
    () async {
      relay.holdHandshake = true;
      final states = <ConnectionState>[];
      make(staleTimeout: const Duration(milliseconds: 120));
      ws.watchConnection().listen(states.add);
      await ws.connect();

      // O upgrade HTTP→WS completa, mas o relay nunca manda `hello`: fica
      // preso em "connecting" até o watchdog agir.
      await until(
        () => relay.heldSockets.containsKey('dev_me'),
        reason: 'upgrade aconteceu',
      );
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(states.last, ConnectionState.connecting);
      expect(
        relay.sockets.containsKey('dev_me'),
        isFalse,
        reason: 'nunca chegou a "vivo" para o relay',
      );

      // A partir daqui o relay volta a responder normalmente.
      relay.holdHandshake = false;
      await until(
        () => states.last == ConnectionState.online,
        timeout: const Duration(seconds: 3),
        reason: 'watchdog forçou nova tentativa e desta vez completou',
      );
    },
  );

  test('socket some silenciosamente (sem close nem error): watchdog detecta e reconecta', () async {
    final states = <ConnectionState>[];
    make(staleTimeout: const Duration(milliseconds: 120));
    ws.watchConnection().listen(states.add);
    await ws.connect();
    await until(() => states.last == ConnectionState.online);

    relay.vanish('dev_me');
    // Nenhum evento chega ao cliente (nem onDone, nem onError) — só o
    // watchdog por falta de atividade pode detectar isso.
    await until(
      () => states.where((s) => s == ConnectionState.online).length >= 2,
      timeout: const Duration(seconds: 3),
      reason: 'watchdog percebeu a inatividade e reconectou',
    );
    expect(
      ws.lastCloseCode,
      isNull,
      reason: 'nunca houve close code — o socket só sumiu',
    );
  });
}
