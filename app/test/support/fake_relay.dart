import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:piriquito/protocol/protocol.dart';

/// Relay cego em memória que fala o PROTOCOL.md v1 (subconjunto suficiente
/// para transport e domínio). Não valida nada de crypto: só roteia.
class FakeRelay {
  FakeRelay({this.chunkSize = 8 * 1024 * 1024});

  final int chunkSize;
  late HttpServer _server;
  String get baseUrl => 'http://127.0.0.1:${_server.port}';

  final users = <String, User>{};
  final devices = <String, Device>{}; // device.id → Device (com userId)
  final tokens = <String, String>{}; // token → device id
  final invites = <String, String>{}; // code → user id
  final queues = <String, List<Envelope>>{}; // device id → pendentes
  final blobs = <String, _Blob>{};
  final sockets = <String, WebSocket>{};
  final pushTokens = <String, String?>{};
  final log = <String>[];

  /// Falhas injetáveis: rota → quantas vezes responder 500 antes de funcionar.
  final failNext = <String, int>{};

  /// Atraso artificial por request (para testar timeouts/reconexão).
  Duration latency = Duration.zero;
  bool rejectAllTokens = false;
  int _seq = 0;

  /// Quando `true`, aceita o upgrade HTTP→WebSocket mas trava aí: nunca manda
  /// `hello`, nunca lê frames do cliente. Simula um handshake de app que
  /// nunca completa (proxy/servidor travado depois do upgrade). O socket fica
  /// em [heldSockets], não em [sockets] (nunca chega a "vivo" para o relay).
  bool holdHandshake = false;
  final heldSockets = <String, WebSocket>{};

  /// Socket que "desapareceu": some da bookkeeping do relay sem mandar close
  /// nem error — o cliente nunca recebe nenhum evento (nem onDone, nem onError),
  /// simulando um NAT/rede que engole a conexão sem RST/FIN. Mantém uma
  /// referência em [vanishedSockets] só para o objeto não ser finalizado.
  final vanishedSockets = <String, WebSocket>{};

  void vanish(String deviceId) {
    final ws = sockets.remove(deviceId);
    if (ws != null) vanishedSockets[deviceId] = ws;
  }

  String _id(String prefix) =>
      '${prefix}_${base64Url.encode(List.filled(16, ++_seq & 0xff)).substring(0, 22)}';

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_handle, onError: (Object e) => log.add('server error: $e'));
  }

  Future<void> stop() async {
    for (final s in sockets.values.toList()) {
      await s.close();
    }
    await _server.close(force: true);
  }

  // ── Semeadura ─────────────────────────────────────────────────────────────
  User addUser(String name, {UserRole role = UserRole.member, String? id}) {
    final u = User(id: id ?? _id('usr'), name: name, role: role);
    users[u.id] = u;
    return u;
  }

  String addInvite(String userId, {String? code}) {
    final c = code ?? '7K3M-9QZ${(invites.length % 10)}';
    invites[c] = userId;
    return c;
  }

  /// Registra um device diretamente (sem convite) e devolve o token.
  String addDevice(
    String userId, {
    required String identityKey,
    String? id,
    String name = 'dev',
    String platform = 'macos',
  }) {
    final d = Device(
      id: id ?? _id('dev'),
      userId: userId,
      name: name,
      platform: platform,
      identityKey: identityKey,
      createdAt: DateTime.utc(2026, 9, 6, 18),
    );
    devices[d.id] = d;
    _seq++;
    final token = base64Url.encode(
      List.generate(32, (i) => (_seq * 7 + i) & 0xff),
    );
    tokens[token] = d.id;
    return token;
  }

  /// Enfileira um envelope como se outro device tivesse postado.
  Future<Envelope> inject(Envelope e, {required String fromDevice}) async {
    final stored = Envelope(
      id: _id('env'),
      fromDevice: fromDevice,
      toDevice: e.toDevice,
      nonce: e.nonce,
      ciphertext: e.ciphertext,
      createdAt: DateTime.now().toUtc(),
    );
    queues.putIfAbsent(e.toDevice, () => []).add(stored);
    final ws = sockets[e.toDevice];
    if (ws != null) {
      ws.add(jsonEncode(WsEnvelope(stored).toJson()));
    }
    return stored;
  }

  /// Envia um frame cru para o socket de um device (para testar ping/erro).
  void sendRaw(String deviceId, Object frame) =>
      sockets[deviceId]?.add(frame is String ? frame : jsonEncode(frame));

  Future<void> closeSocket(String deviceId, {int code = 1000}) async =>
      sockets[deviceId]?.close(code);

  // ── HTTP ──────────────────────────────────────────────────────────────────
  Future<void> _handle(HttpRequest req) async {
    final path = req.uri.path;
    final method = req.method;
    log.add('$method $path');
    if (latency > Duration.zero) {
      await Future<void>.delayed(latency);
    }
    try {
      final key = '$method $path';
      final matching = failNext.keys
          .where((k) => key.startsWith(k) && failNext[k]! > 0)
          .firstOrNull;
      if (matching != null) {
        failNext[matching] = failNext[matching]! - 1;
        return await _error(req, 500, 'internal', 'injected');
      }
      if (path == '/healthz') {
        return await _json(req, 200, {'status': 'ok'});
      }
      if (path == '/v1/devices' && method == 'POST') {
        return await _register(req);
      }

      final auth = _auth(req);
      if (auth == null) {
        if (path == '/v1/ws') {
          return await _wsReject(req);
        }
        return await _error(req, 401, 'unauthorized', 'invalid token');
      }
      final me = devices[auth]!;

      if (path == '/v1/ws') {
        return await _ws(req, me);
      }
      if (path == '/v1/me') {
        return await _json(
          req,
          200,
          MeResponse(user: users[me.userId]!, device: me).toJson(),
        );
      }
      if (path == '/v1/directory') {
        return await _json(req, 200, _directory().toJson());
      }
      if (path == '/v1/devices/me/push' && method == 'PUT') {
        pushTokens[me.id] = (await _body(req))['fcm_token'] as String?;
        return await _empty(req, 204);
      }
      if (path.startsWith('/v1/devices/') && method == 'DELETE') {
        final id = path.split('/').last;
        if (!devices.containsKey(id)) {
          return await _error(req, 404, 'not_found', 'no device');
        }
        devices.remove(id);
        queues.remove(id);
        return await _empty(req, 204);
      }
      if (path == '/v1/envelopes' && method == 'POST') {
        return await _postEnvelopes(req, me);
      }
      if (path == '/v1/envelopes' && method == 'GET') {
        final limit =
            int.tryParse(req.uri.queryParameters['limit'] ?? '100') ?? 100;
        final list = (queues[me.id] ?? const <Envelope>[]).take(limit).toList();
        return await _json(
          req,
          200,
          EnvelopesListResponse(envelopes: list).toJson(),
        );
      }
      if (path == '/v1/envelopes/ack' && method == 'POST') {
        final ids = ((await _body(req))['ids'] as List<dynamic>).cast<String>();
        queues[me.id]?.removeWhere((e) => ids.contains(e.id));
        return await _empty(req, 204);
      }
      if (path == '/v1/blobs' && method == 'POST') {
        final b = BlobCreateRequest.fromJson(await _body(req));
        if (b.size > 524288000 || b.recipients.isEmpty) {
          return await _error(req, 400, 'validation', 'bad blob');
        }
        final id = _id('blob');
        blobs[id] = _Blob(
          owner: me.id,
          size: b.size,
          recipients: b.recipients.toSet(),
        );
        return await _json(
          req,
          201,
          BlobCreateResponse(
            blobId: id,
            chunkSize: chunkSize,
            expiresAt: DateTime.utc(2026, 10, 6),
          ).toJson(),
        );
      }
      final chunk = RegExp(r'^/v1/blobs/([^/]+)/chunks/(\d+)$')
          .firstMatch(path);
      if (chunk != null && method == 'PUT') {
        final blob = blobs[chunk.group(1)];
        if (blob == null) {
          return await _error(req, 404, 'not_found', 'no blob');
        }
        final n = int.parse(chunk.group(2)!);
        final total = (blob.size + chunkSize - 1) ~/ chunkSize;
        if (n >= total) {
          return await _error(
            req,
            400,
            'chunk_out_of_range',
            'n=$n total=$total',
          );
        }
        final bytes = await _bytes(req);
        final expected = n == total - 1 ? blob.size - n * chunkSize : chunkSize;
        if (bytes.length != expected) {
          return await _error(
            req,
            400,
            'validation',
            'chunk $n: ${bytes.length} != $expected',
          );
        }
        blob.chunks[n] = bytes;
        return await _empty(req, 204);
      }
      final complete = RegExp(r'^/v1/blobs/([^/]+)/complete$').firstMatch(path);
      if (complete != null && method == 'POST') {
        final blob = blobs[complete.group(1)];
        if (blob == null) {
          return await _error(req, 404, 'not_found', 'no blob');
        }
        if (blob.owner != me.id) {
          return await _error(req, 403, 'forbidden', 'not owner');
        }
        final total = (blob.size + chunkSize - 1) ~/ chunkSize;
        if (blob.chunks.length != total) {
          return await _error(
            req,
            409,
            'incomplete_blob',
            '${blob.chunks.length}/$total',
          );
        }
        blob.complete = true;
        return await _json(
          req,
          200,
          BlobCompleteResponse(
            blobId: complete.group(1)!,
            size: blob.size,
          ).toJson(),
        );
      }
      final one = RegExp(r'^/v1/blobs/([^/]+)$').firstMatch(path);
      if (one != null && method == 'GET') {
        final blob = blobs[one.group(1)];
        if (blob == null || !blob.complete) {
          return await _error(req, 404, 'not_found', 'no blob');
        }
        if (blob.owner != me.id && !blob.recipients.contains(me.id)) {
          return await _error(req, 403, 'forbidden', 'not recipient');
        }
        final all = blob.bytes;
        var start = 0;
        final range = req.headers.value('range');
        if (range != null) {
          start = int.parse(
            RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!,
          );
        }
        req.response.statusCode = range == null ? 200 : 206;
        req.response.headers.contentType = ContentType.binary;
        req.response.headers.contentLength = all.length - start;
        req.response.add(all.sublist(start));
        blob.delivered.add(me.id);
        await req.response.close();
        return;
      }
      if (one != null && method == 'DELETE') {
        final blob = blobs[one.group(1)];
        if (blob == null) {
          return await _error(req, 404, 'not_found', 'no blob');
        }
        if (blob.owner != me.id) {
          return await _error(req, 403, 'forbidden', 'not owner');
        }
        blobs.remove(one.group(1));
        return await _empty(req, 204);
      }
      if (path == '/v1/admin/invites' && method == 'POST') {
        if (users[me.userId]!.role != UserRole.admin) {
          return await _error(req, 403, 'forbidden', 'admin only');
        }
        final r = InviteRequest.fromJson(await _body(req));
        final uid = r.userId ?? addUser(r.userName!).id;
        final code = addInvite(uid);
        return await _json(
          req,
          201,
          InviteResponse(
            code: code,
            userId: uid,
            expiresAt: DateTime.utc(2026, 9, 13),
          ).toJson(),
        );
      }
      final role = RegExp(r'^/v1/admin/users/([^/]+)/role$').firstMatch(path);
      if (role != null && method == 'POST') {
        if (users[me.userId]!.role != UserRole.admin) {
          return await _error(req, 403, 'forbidden', 'admin only');
        }
        final u = users[role.group(1)];
        if (u == null) {
          return await _error(req, 404, 'not_found', 'no user');
        }
        users[u.id] = User(
          id: u.id,
          name: u.name,
          role: RoleRequest.fromJson(await _body(req)).role,
        );
        return await _empty(req, 204);
      }
      return await _error(req, 404, 'not_found', 'no route $method $path');
    } catch (e) {
      log.add('handler error: $e');
      if (!_closed(req)) {
        return await _error(req, 500, 'internal', '$e');
      }
    }
  }

  bool _closed(HttpRequest req) {
    try {
      req.response.statusCode;
      return false;
    } catch (_) {
      return true;
    }
  }

  String? _auth(HttpRequest req) {
    if (rejectAllTokens) {
      return null;
    }
    final h = req.headers.value('authorization');
    var token = h != null && h.startsWith('Bearer ') ? h.substring(7) : null;
    token ??= req.uri.queryParameters['token'];
    final dev = tokens[token];
    return dev != null && devices.containsKey(dev) ? dev : null;
  }

  Future<void> _register(HttpRequest req) async {
    final r = RegisterRequest.fromJson(await _body(req));
    final uid = invites.remove(r.inviteCode);
    if (uid == null) {
      return await _error(
        req,
        400,
        'invalid_invite',
        'invite code expired or already used',
      );
    }
    final token = addDevice(
      uid,
      identityKey: r.identityKey,
      name: r.deviceName,
      platform: r.platform,
    );
    final dev = devices[tokens[token]]!;
    return await _json(
      req,
      201,
      RegisterResponse(device: dev, user: users[uid]!, token: token).toJson(),
    );
  }

  Directory _directory() => Directory(
    users: [
      for (final u in users.values)
        User(
          id: u.id,
          name: u.name,
          role: u.role,
          devices: [
            for (final d in devices.values.where((d) => d.userId == u.id))
              Device(
                id: d.id,
                name: d.name,
                platform: d.platform,
                identityKey: d.identityKey,
                createdAt: d.createdAt,
              ),
          ],
        ),
    ],
  );

  Future<void> _postEnvelopes(HttpRequest req, Device me) async {
    final r = EnvelopesPostRequest.fromJson(await _body(req));
    if (r.envelopes.length > 100) {
      return await _error(req, 400, 'validation', 'too many');
    }
    final accepted = <AcceptedEnvelope>[];
    for (final e in r.envelopes) {
      if (base64.decode(e.ciphertext).length > 65536) {
        return await _error(req, 413, 'payload_too_large', 'ciphertext');
      }
      if (!devices.containsKey(e.toDevice)) {
        return await _error(
          req,
          400,
          'validation',
          'unknown device ${e.toDevice}',
        );
      }
      final stored = await inject(e, fromDevice: me.id);
      accepted.add(AcceptedEnvelope(id: stored.id!, toDevice: e.toDevice));
    }
    return await _json(
      req,
      202,
      EnvelopesPostResponse(accepted: accepted).toJson(),
    );
  }

  // ── WS ────────────────────────────────────────────────────────────────────
  Future<void> _wsReject(HttpRequest req) async {
    final ws = await WebSocketTransformer.upgrade(req);
    ws.add(
      jsonEncode(
        WsError(ApiError(code: 'unauthorized', message: 'invalid token'))
            .toJson(),
      ),
    );
    await ws.close(4401);
  }

  Future<void> _ws(HttpRequest req, Device me) async {
    final ws = await WebSocketTransformer.upgrade(req);
    if (holdHandshake) {
      heldSockets[me.id] = ws;
      return;
    }
    await _activate(me.id, ws);
  }

  /// Termina de "ativar" um socket já upgradado: derruba a conexão anterior
  /// do mesmo device (4409), manda `hello` + pendentes e começa a escutar.
  /// Extraído de [_ws] para ser reusado por [releaseHeld].
  Future<void> _activate(String deviceId, WebSocket ws) async {
    final old = sockets[deviceId];
    if (old != null) {
      await old.close(4409);
    }
    sockets[deviceId] = ws;
    final pending = queues[deviceId] ?? const <Envelope>[];
    ws.add(
      jsonEncode(WsHello(deviceId: deviceId, pending: pending.length).toJson()),
    );
    for (final e in pending) {
      ws.add(jsonEncode(WsEnvelope(e).toJson()));
    }
    ws.listen(
      (data) {
        final frame = WsFrame.fromJson(
          jsonDecode(data as String) as Map<String, dynamic>,
        );
        log.add('ws $deviceId ← ${frame.type}');
        switch (frame) {
          case WsAck(:final ids):
            queues[deviceId]?.removeWhere((e) => ids.contains(e.id));
          case WsPing():
            ws.add(jsonEncode(const WsPong().toJson()));
          default:
            break;
        }
      },
      onDone: () {
        if (sockets[deviceId] == ws) {
          sockets.remove(deviceId);
        }
      },
      onError: (_) {},
    );
  }

  /// Libera um socket que ficou preso por [holdHandshake]: manda `hello` (e
  /// pendentes) e começa a escutar, como se o "handshake" tivesse acabado de
  /// completar agora — só que atrasado. Simula um handshake lento em vez de
  /// travado para sempre.
  Future<void> releaseHeld(String deviceId) async {
    final ws = heldSockets.remove(deviceId);
    if (ws == null) return;
    // De propósito, não mexe em `sockets`/não derruba a conexão atual do
    // device: o ponto do teste é uma resposta atrasada que não deveria mais
    // importar (o cliente, do seu lado, já abriu outra geração antes disso).
    // Se nada mais estiver escutando `ws` (nenhum `.listen` foi chamado
    // enquanto estava em `heldSockets`), o `add` só entrega ao stream do
    // cliente do outro lado do socket — é o que o teste quer observar.
    final pending = queues[deviceId] ?? const <Envelope>[];
    ws.add(
      jsonEncode(WsHello(deviceId: deviceId, pending: pending.length).toJson()),
    );
  }

  // ── util ──────────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> _body(HttpRequest req) async =>
      jsonDecode(await utf8.decoder.bind(req).join()) as Map<String, dynamic>;

  Future<Uint8List> _bytes(HttpRequest req) async {
    final b = BytesBuilder(copy: false);
    await for (final c in req) {
      b.add(c);
    }
    return b.takeBytes();
  }

  Future<void> _json(
    HttpRequest req,
    int status,
    Map<String, dynamic> body,
  ) async {
    req.response.statusCode = status;
    req.response.headers.contentType = ContentType.json;
    req.response.write(jsonEncode(body));
    await req.response.close();
  }

  Future<void> _empty(HttpRequest req, int status) async {
    req.response.statusCode = status;
    await req.response.close();
  }

  Future<void> _error(
    HttpRequest req,
    int status,
    String code,
    String message,
  ) => _json(
    req,
    status,
    ErrorResponse(
      error: ApiError(code: code, message: message),
    ).toJson(),
  );
}

class _Blob {
  _Blob({required this.owner, required this.size, required this.recipients});

  final String owner;
  final int size;
  final Set<String> recipients;
  final chunks = <int, Uint8List>{};
  final delivered = <String>{};
  bool complete = false;

  Uint8List get bytes {
    final b = BytesBuilder(copy: false);
    for (final k in chunks.keys.toList()..sort()) {
      b.add(chunks[k]!);
    }
    return b.takeBytes();
  }
}
