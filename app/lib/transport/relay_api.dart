import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../protocol/protocol.dart';

/// Erro do relay. [code] é o `error.code` do servidor, ou `network` (sem
/// resposta) / `internal` (resposta inválida).
class RelayException implements Exception {
  const RelayException(this.code, this.message, {this.statusCode});

  final String code;
  final String message;
  final int? statusCode;

  @override
  String toString() =>
      'RelayException($code${statusCode == null ? '' : '/$statusCode'}): $message';
}

/// Cliente REST do `/v1` (PROTOCOL.md §3).
class RelayApi {
  RelayApi({
    required String baseUrl,
    this._token,
    Dio? dio,
    Duration connectTimeout = const Duration(seconds: 10),
    Duration receiveTimeout = const Duration(seconds: 30),
  }) : _dio =
           dio ??
           Dio(
             BaseOptions(
               baseUrl: baseUrl,
               connectTimeout: connectTimeout,
               receiveTimeout: receiveTimeout,
               responseType: ResponseType.json,
               validateStatus: (_) => true,
             ),
           );

  final Dio _dio;
  String? _token;

  String get baseUrl => _dio.options.baseUrl;

  set token(String? value) => _token = value;

  Options _opts({ResponseType? responseType, Map<String, Object?>? headers}) =>
      Options(
        responseType: responseType,
        headers: {
          if (_token != null) 'Authorization': 'Bearer $_token',
          ...?headers,
        },
      );

  Future<Map<String, dynamic>> _json(
    String method,
    String path, {
    Object? body,
    Map<String, Object?>? query,
    Set<int> ok = const {200, 201, 202, 204},
  }) async {
    final Response<dynamic> res;
    try {
      res = await _dio.request<dynamic>(
        path,
        data: body,
        queryParameters: query,
        options: _opts().copyWith(method: method),
      );
    } on DioException catch (e) {
      throw RelayException('network', e.message ?? e.type.name);
    }
    final status = res.statusCode ?? 0;
    final data = res.data;
    if (!ok.contains(status)) {
      throw _errorFrom(status, data);
    }
    return data is Map<String, dynamic> ? data : const {};
  }

  RelayException _errorFrom(int status, Object? data) {
    if (data is Map<String, dynamic> && data['error'] is Map<String, dynamic>) {
      final e = ApiError.fromJson(data['error'] as Map<String, dynamic>);
      return RelayException(e.code, e.message, statusCode: status);
    }
    return RelayException(
      status == 401 ? 'unauthorized' : 'internal',
      'HTTP $status',
      statusCode: status,
    );
  }

  // ── Sem auth ──────────────────────────────────────────────────────────────
  Future<void> healthz() => _json('GET', '/healthz');

  Future<RegisterResponse> register(RegisterRequest req) async =>
      RegisterResponse.fromJson(
        await _json('POST', '/v1/devices', body: req.toJson()),
      );

  // ── Device ────────────────────────────────────────────────────────────────
  Future<MeResponse> me() async =>
      MeResponse.fromJson(await _json('GET', '/v1/me'));

  Future<Directory> directory() async =>
      Directory.fromJson(await _json('GET', '/v1/directory'));

  Future<void> setPushToken(String? fcmToken) => _json(
    'PUT',
    '/v1/devices/me/push',
    body: PushTokenRequest(fcmToken: fcmToken).toJson(),
  );

  Future<void> deleteDevice(String id) => _json('DELETE', '/v1/devices/$id');

  // ── Envelopes ─────────────────────────────────────────────────────────────
  Future<EnvelopesPostResponse> postEnvelopes(List<Envelope> envelopes) async =>
      EnvelopesPostResponse.fromJson(
        await _json(
          'POST',
          '/v1/envelopes',
          body: EnvelopesPostRequest(envelopes: envelopes).toJson(),
        ),
      );

  Future<List<Envelope>> getEnvelopes({int limit = 100}) async =>
      EnvelopesListResponse.fromJson(
        await _json('GET', '/v1/envelopes', query: {'limit': limit}),
      ).envelopes;

  Future<void> ack(List<String> ids) =>
      _json('POST', '/v1/envelopes/ack', body: AckRequest(ids: ids).toJson());

  // ── Blobs ─────────────────────────────────────────────────────────────────
  Future<BlobCreateResponse> createBlob({
    required int size,
    required List<String> recipients,
  }) async => BlobCreateResponse.fromJson(
    await _json(
      'POST',
      '/v1/blobs',
      body: BlobCreateRequest(size: size, recipients: recipients).toJson(),
    ),
  );

  Future<void> putChunk(String blobId, int n, List<int> bytes) async {
    final Response<dynamic> res;
    try {
      res = await _dio.put<dynamic>(
        '/v1/blobs/$blobId/chunks/$n',
        data: Stream.value(
          bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
        ),
        options: _opts(
          headers: {
            Headers.contentTypeHeader: 'application/octet-stream',
            Headers.contentLengthHeader: bytes.length,
          },
        ),
      );
    } on DioException catch (e) {
      throw RelayException('network', e.message ?? e.type.name);
    }
    if (res.statusCode != 204) throw _errorFrom(res.statusCode ?? 0, res.data);
  }

  Future<BlobCompleteResponse> completeBlob(String blobId) async =>
      BlobCompleteResponse.fromJson(
        await _json('POST', '/v1/blobs/$blobId/complete'),
      );

  /// Stream de bytes do blob; [rangeStart] usa `Range: bytes=N-` para retomar.
  Stream<List<int>> downloadBlob(String blobId, {int? rangeStart}) async* {
    final Response<ResponseBody> res;
    try {
      res = await _dio.get<ResponseBody>(
        '/v1/blobs/$blobId',
        options: _opts(
          responseType: ResponseType.stream,
          headers: {if (rangeStart != null) 'Range': 'bytes=$rangeStart-'},
        ),
      );
    } on DioException catch (e) {
      throw RelayException('network', e.message ?? e.type.name);
    }
    final status = res.statusCode ?? 0;
    final body = res.data!;
    if (status != 200 && status != 206) {
      final bytes = await body.stream.fold<List<int>>(
        [],
        (a, b) => a..addAll(b),
      );
      Object? decoded;
      try {
        decoded = _decodeJson(bytes);
      } on Object {
        decoded = null;
      }
      throw _errorFrom(status, decoded);
    }
    yield* body.stream;
  }

  Future<void> deleteBlob(String blobId) =>
      _json('DELETE', '/v1/blobs/$blobId');

  // ── Admin ─────────────────────────────────────────────────────────────────
  Future<InviteResponse> createInvite(InviteRequest req) async =>
      InviteResponse.fromJson(
        await _json('POST', '/v1/admin/invites', body: req.toJson()),
      );

  Future<void> setRole(String userId, UserRole role) => _json(
    'POST',
    '/v1/admin/users/$userId/role',
    body: RoleRequest(role: role).toJson(),
  );

  static Object? _decodeJson(List<int> bytes) =>
      bytes.isEmpty ? null : jsonDecode(utf8.decode(bytes));
}
