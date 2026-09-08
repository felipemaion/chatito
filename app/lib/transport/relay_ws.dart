import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math';

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../domain/models.dart' show ConnectionState;
import '../protocol/protocol.dart';
import 'relay_api.dart' show RelayException;

/// Cliente do `GET /v1/ws` (PROTOCOL.md §4) com reconexão exponencial.
///
/// Cada envelope passa por [onEnvelope]; se o handler completa sem lançar,
/// o `ack` é enviado automaticamente (o envelope some do relay). Se lançar,
/// nada é enviado e o relay reentrega na próxima conexão.
class RelayWs {
  RelayWs({
    required String baseUrl,
    required this._token,
    required this.onEnvelope,
    this.backoffBase = const Duration(seconds: 1),
    this.backoffMax = const Duration(seconds: 30),
    // Maior que o intervalo de ping do servidor com folga (30s × 2 faltados,
    // PROTOCOL.md §4) — cobre tanto um handshake que trava depois do upgrade
    // HTTP (nunca chega `hello`) quanto uma conexão que já estava online e
    // simplesmente para de mandar qualquer coisa sem fechar (NAT/rede que
    // engole a conexão sem RST/FIN: nem onDone nem onError chegam nesse caso).
    this.staleTimeout = const Duration(seconds: 75),
    // Acima disso, `ensureConnected` desiste de esperar uma tentativa em voo
    // e abre outra na hora, em vez de ficar de refém de um handshake lento.
    this.ensureConnectedGraceTime = const Duration(seconds: 5),
    Random? random,
    void Function(String message)? log,
  }) : _uri = _wsUri(baseUrl),
       _random = random ?? Random(),
       _log = log ?? ((_) {});

  final Uri _uri;
  final String _token;
  final Future<void> Function(Envelope envelope) onEnvelope;
  final Duration backoffBase;
  final Duration backoffMax;
  final Duration staleTimeout;
  final Duration ensureConnectedGraceTime;
  final Random _random;
  final void Function(String) _log;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _retry;
  Timer? _staleTimer;
  Future<void>? _connecting;
  bool _wanted = false;
  bool _disposed = false;
  int _attempts = 0;
  int? _lastCloseCode;
  ConnectionState _state = ConnectionState.offline;
  final _stateCtl = StreamController<ConnectionState>.broadcast();
  final _errors = StreamController<RelayException>.broadcast();

  /// Identifica cada tentativa de conexão. Incrementada a cada [_open]; os
  /// callbacks de uma tentativa (`_onData`/`_onError`/`_onDone`) capturam o
  /// número da sua geração e se auto-descartam se ela não for mais a atual
  /// (abandonada por [ensureConnected] ou substituída por uma reconexão
  /// nova) — assim uma resposta atrasada de uma tentativa velha (ex.: um
  /// `hello` que demorou, ou o 4409 causado por nós mesmos ao abrir a
  /// próxima) nunca mexe no estado da conexão atual.
  int _generation = 0;

  /// Quando a tentativa atual começou (para [ensureConnected] decidir se ela
  /// já está "velha demais" e vale a pena abandonar).
  DateTime? _attemptStartedAt;

  /// Envelopes recebidos aguardando processamento sequencial (sem
  /// backpressure não daria para garantir ordem nem limitar concorrência
  /// quando vários chegam de uma vez, ex.: ao reconectar com pendentes).
  final _queue = <Envelope>[];
  bool _draining = false;

  /// Tentativas consecutivas de reconexão (zera ao conectar).
  int get reconnectAttempts => _attempts;
  int? get lastCloseCode => _lastCloseCode;
  Stream<RelayException> get errors => _errors.stream;

  Stream<ConnectionState> watchConnection() async* {
    yield _state;
    yield* _stateCtl.stream;
  }

  /// Log estruturado via `dart:developer` (aparece no logcat do Android sob
  /// a tag `flutter`, e no Console.app do macOS) — independe do callback
  /// [_log] injetável (usado só nos testes), porque em produção nada mais
  /// garantia que alguma mensagem chegasse a um log visível de verdade.
  /// Nunca inclui conteúdo de mensagens nem o token: só metadados de
  /// transição (geração, código de fechamento, tempos).
  void _devLog(String message) {
    developer.log(message, name: 'piriquito.ws', level: 800);
    // Em release o dart:developer é removido; print sai como I/flutter no logcat.
    // ignore: avoid_print
    print('[piriquito.ws] $message');
  }

  /// Abre (ou mantém) a conexão. Idempotente, inclusive com chamadas
  /// concorrentes: a 2ª nunca abre uma 2ª conexão real, só aguarda a 1ª
  /// (`_channel`/`_retry` só passam a não-nulo depois que `_open` já terminou
  /// o `await ch.ready`, então checá-los sozinho não bastava contra a corrida).
  Future<void> connect() async {
    if (_disposed) throw StateError('RelayWs já descartado');
    _wanted = true;
    if (_channel != null || _retry != null) return;
    if (_connecting != null) return _connecting;
    return _startAttempt();
  }

  /// Como [connect], mas nunca fica de refém de uma tentativa travada: se já
  /// há uma conexão em voo há mais de [ensureConnectedGraceTime], ou um
  /// retry agendado (backoff em andamento), cancela e abre uma geração nova
  /// na hora — não espera o handshake travado nem o fim do backoff. Se já
  /// está `online`, não faz nada. Pensado para chamadas explícitas do
  /// usuário/app-ui (botão "reconectar", voltar de segundo plano, rede
  /// voltando) — sinais de que vale tentar de novo agora, não daqui a pouco.
  Future<void> ensureConnected() async {
    if (_disposed) throw StateError('RelayWs já descartado');
    _wanted = true;

    if (_state == ConnectionState.online) return;

    if (_retry != null) {
      _retry!.cancel();
      _retry = null;
      return _abandonCurrentAndStart();
    }

    final startedAt = _attemptStartedAt;
    final stuck =
        startedAt != null &&
        DateTime.now().difference(startedAt) >= ensureConnectedGraceTime;
    if (stuck) {
      return _abandonCurrentAndStart();
    }

    return connect();
  }

  Future<void> disconnect() async {
    _wanted = false;
    _retry?.cancel();
    _retry = null;
    _attempts = 0;
    await _close();
    _setState(ConnectionState.offline);
  }

  Future<void> ack(List<String> ids) async {
    final ch = _channel;
    if (ch == null || ids.isEmpty) return;
    ch.sink.add(jsonEncode(WsAck(ids).toJson()));
  }

  Future<void> dispose() async {
    _disposed = true;
    await disconnect();
    await _stateCtl.close();
    await _errors.close();
  }

  // ── Internos ──────────────────────────────────────────────────────────────

  /// Abandona a tentativa/geração atual (fecha o canal se já existir; se
  /// ainda estiver no meio do `ch.ready`, o próprio [_open] dela fecha
  /// sozinho ao perceber que não é mais a geração corrente) e começa outra.
  Future<void> _abandonCurrentAndStart() async {
    _staleTimer?.cancel();
    _staleTimer = null;
    // Abandona a geração ANTES de fechar o canal: `sink.close()` pode
    // completar (e disparar o `onDone` do próprio canal) de forma síncrona
    // ou via microtask antes da próxima linha rodar — o gen check dela
    // precisa já enxergar a geração nova, senão ela seria tratada como
    // "atual" por engano e reagendaria uma reconexão fantasma.
    _generation++;
    final oldChannel = _channel;
    _channel = null;
    _sub = null; // não cancela: se a geração antiga ainda mandar algo, o
    // gen check no callback dela fecha o canal sozinho (ver _onData/_onDone).
    if (oldChannel != null) {
      unawaited(oldChannel.sink.close(WebSocketStatus.normalClosure));
    }
    _connecting = null;
    return _startAttempt();
  }

  Future<void> _startAttempt() {
    final future = _open();
    _connecting = future;
    return future.whenComplete(() {
      if (identical(_connecting, future)) _connecting = null;
    });
  }

  Future<void> _open() async {
    final gen = ++_generation;
    _attemptStartedAt = DateTime.now();
    _devLog('conectando (geração $gen)');
    _setState(ConnectionState.connecting);
    final WebSocketChannel ch;
    try {
      final c = IOWebSocketChannel.connect(
        _uri,
        headers: {'Authorization': 'Bearer $_token'},
        connectTimeout: const Duration(seconds: 10),
      );
      await c.ready;
      ch = c;
    } on Object catch (e) {
      if (gen == _generation) {
        _log('ws connect falhou: $e');
        _scheduleRetry();
      }
      return;
    }
    if (gen != _generation) {
      // Fomos abandonados enquanto o handshake HTTP acontecia (ensureConnected
      // já abriu outra geração). Fecha sem tocar no estado atual.
      _devLog(
        'ignorado: upgrade de geração antiga concluído (gen=$gen, atual=$_generation)',
      );
      unawaited(ch.sink.close(WebSocketStatus.normalClosure));
      return;
    }
    _channel = ch;
    _sub = ch.stream.listen(
      (data) => _onData(gen, ch, data),
      onError: (Object e) => _onError(gen, e),
      onDone: () => _onDone(gen, ch),
      cancelOnError: false,
    );
    _armStaleTimer(gen);
  }

  void _onData(int gen, WebSocketChannel ch, dynamic data) {
    if (gen != _generation) {
      // Frame de uma geração já abandonada (ex.: um `hello` atrasado depois
      // de `ensureConnected` ter desistido dela) — fecha essa conexão
      // fantasma de vez e ignora; nunca deixa uma geração velha "ficar viva".
      _devLog(
        'ignorado: frame de geração antiga (gen=$gen, atual=$_generation)',
      );
      unawaited(ch.sink.close(WebSocketStatus.normalClosure));
      return;
    }
    // Prova de vida: reseta o watchdog em qualquer byte recebido, mesmo um
    // frame que não vai parsear — o que importa é que a conexão não está muda.
    _armStaleTimer(gen);
    final WsFrame frame;
    try {
      frame = WsFrame.fromJson(
        jsonDecode(data as String) as Map<String, dynamic>,
      );
    } on Object catch (e) {
      _log('ws frame ignorado: $e');
      return;
    }
    switch (frame) {
      case WsHello():
        _devLog('hello recebido (geração $gen) — online');
        _attempts = 0;
        _setState(ConnectionState.online);
      case WsEnvelope(:final envelope):
        _queue.add(envelope);
        unawaited(_drainQueue());
      case WsPing():
        ch.sink.add(jsonEncode(const WsPong().toJson()));
      case WsError(:final error):
        _errors.add(RelayException(error.code, error.message));
      case WsPong() || WsAck():
        break;
    }
  }

  /// Processa a fila um envelope por vez, na ordem de chegada. Se já houver
  /// um drain em andamento, esta chamada só garante que ele continue (a
  /// função que o iniciou é a única que efetivamente consome a fila).
  Future<void> _drainQueue() async {
    if (_draining) return;
    _draining = true;
    try {
      while (_queue.isNotEmpty) {
        final envelope = _queue.removeAt(0);
        await _handle(envelope);
      }
    } finally {
      _draining = false;
    }
  }

  Future<void> _handle(Envelope envelope) async {
    try {
      await onEnvelope(envelope);
    } on Object catch (e) {
      _log('handler falhou para ${envelope.id}: $e (sem ack)');
      return;
    }
    final id = envelope.id;
    if (id == null) return;
    if (_channel == null) {
      _log(
        'ack de $id não enviado: conexão caída (relay reenviará ao reconectar)',
      );
      return;
    }
    await ack([id]);
  }

  void _onError(int gen, Object e) {
    if (gen != _generation) return;
    _log('ws erro: $e');
  }

  /// (Re)inicia o relógio de "sinal de vida" da geração [gen]. Se ele chegar
  /// ao fim sem [_armStaleTimer] ter sido chamado de novo (nova conexão ou
  /// frame recebido), [_onStale] força uma reconexão — só se [gen] ainda for
  /// a geração atual (um watchdog de uma geração já trocada é irrelevante).
  void _armStaleTimer(int gen) {
    _staleTimer?.cancel();
    _staleTimer = Timer(staleTimeout, () => _onStale(gen));
  }

  void _onStale(int gen) {
    if (gen != _generation) return;
    final msg =
        'watchdog: sem nenhum frame em $staleTimeout — forçando reconexão '
        '(handshake travado ou conexão morta sem close/error, geração $gen)';
    _log(msg);
    _devLog(msg);
    unawaited(_forceReconnect());
  }

  /// Fecha a conexão atual (sem esperar resposta do outro lado, que já
  /// provou estar mudo) e agenda una nova tentativa, como se tivesse caído.
  Future<void> _forceReconnect() async {
    await _close();
    if (_wanted && !_disposed) _scheduleRetry();
  }

  Future<void> _onDone(int gen, WebSocketChannel ch) async {
    if (gen != _generation) {
      // Geração velha fechando — normalmente porque NÓS mesmos abrimos uma
      // geração nova (ensureConnected) e o relay derrubou esta com 4409.
      // Não afeta a conexão atual: nada a fazer.
      _devLog(
        'ignorado: close de geração antiga (gen=$gen, atual=$_generation, '
        'code=${ch.closeCode})',
      );
      return;
    }
    _staleTimer?.cancel();
    _staleTimer = null;
    final code = ch.closeCode;
    _devLog('fechado code=$code reason=${ch.closeReason} (geração $gen)');
    _lastCloseCode = code;
    _channel = null;
    _sub = null;
    if (!_wanted || _disposed) {
      _setState(ConnectionState.offline);
      return;
    }
    if (code == 4401) {
      // Token inválido: não insistir.
      _log('ws fechado com 4401; parando reconexão');
      _wanted = false;
      _attempts = 0;
      _setState(ConnectionState.offline);
      return;
    }
    // Inclui 4409 na geração atual: uma conexão de verdade tomou o lugar
    // desta (não fomos nós, já que geração != atual teria retornado acima).
    // Continua tentando reconectar com backoff normal — ficar offline para
    // sempre seria pior do que insistir.
    _scheduleRetry();
  }

  void _scheduleRetry() {
    if (!_wanted || _disposed) {
      _setState(ConnectionState.offline);
      return;
    }
    _setState(ConnectionState.connecting);
    final exp = min(_attempts, 10);
    final base = backoffBase.inMilliseconds * pow(2, exp);
    final capped = min(base.toDouble(), backoffMax.inMilliseconds.toDouble());
    final jitter = 0.75 + _random.nextDouble() * 0.5;
    final delay = Duration(milliseconds: (capped * jitter).round());
    _attempts++;
    _devLog('reagendando em ${delay.inMilliseconds}ms (tentativa $_attempts)');
    _retry = Timer(delay, () {
      _retry = null;
      _startAttempt();
    });
  }

  Future<void> _close() async {
    _staleTimer?.cancel();
    _staleTimer = null;
    final ch = _channel;
    _channel = null;
    await _sub?.cancel();
    _sub = null;
    await ch?.sink.close(WebSocketStatus.normalClosure);
  }

  void _setState(ConnectionState s) {
    if (_state == s) return;
    _state = s;
    if (!_stateCtl.isClosed) _stateCtl.add(s);
  }

  static Uri _wsUri(String baseUrl) {
    final u = Uri.parse(baseUrl);
    return u.replace(
      scheme: u.scheme == 'https' ? 'wss' : 'ws',
      path: '/v1/ws',
    );
  }
}
