import 'dart:async';
import 'dart:convert';
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
  final Random _random;
  final void Function(String) _log;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _retry;
  bool _wanted = false;
  bool _disposed = false;
  int _attempts = 0;
  int? _lastCloseCode;
  ConnectionState _state = ConnectionState.offline;
  final _stateCtl = StreamController<ConnectionState>.broadcast();
  final _errors = StreamController<RelayException>.broadcast();

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

  /// Abre (ou mantém) a conexão. Idempotente.
  Future<void> connect() async {
    if (_disposed) throw StateError('RelayWs já descartado');
    _wanted = true;
    if (_channel != null || _retry != null) return;
    await _open();
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
  Future<void> _open() async {
    _setState(ConnectionState.connecting);
    try {
      final ch = IOWebSocketChannel.connect(
        _uri,
        headers: {'Authorization': 'Bearer $_token'},
        connectTimeout: const Duration(seconds: 10),
      );
      await ch.ready;
      _channel = ch;
      _sub = ch.stream.listen(
        _onData,
        onError: _onError,
        onDone: _onDone,
        cancelOnError: false,
      );
    } on Object catch (e) {
      _log('ws connect falhou: $e');
      _channel = null;
      _scheduleRetry();
    }
  }

  void _onData(dynamic data) {
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
        _attempts = 0;
        _setState(ConnectionState.online);
      case WsEnvelope(:final envelope):
        _queue.add(envelope);
        unawaited(_drainQueue());
      case WsPing():
        _channel?.sink.add(jsonEncode(const WsPong().toJson()));
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

  void _onError(Object e) {
    _log('ws erro: $e');
  }

  Future<void> _onDone() async {
    final code = _channel?.closeCode;
    _lastCloseCode = code;
    _channel = null;
    await _sub?.cancel();
    _sub = null;
    if (!_wanted || _disposed) {
      _setState(ConnectionState.offline);
      return;
    }
    if (code == 4401 || code == 4409) {
      // Token inválido ou outra conexão do mesmo device: não insistir.
      _log('ws fechado com $code; parando reconexão');
      _wanted = false;
      _attempts = 0;
      _setState(ConnectionState.offline);
      return;
    }
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
    _retry = Timer(delay, () {
      _retry = null;
      _open();
    });
  }

  Future<void> _close() async {
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
