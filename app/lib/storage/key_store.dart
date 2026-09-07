import 'dart:convert';
import 'dart:typed_data';

import '../crypto/crypto_box.dart';

/// Dados de sessão (não secretos, mas guardados junto do token por conveniência).
class StoredSession {
  const StoredSession({
    required this.userId,
    required this.deviceId,
    required this.baseUrl,
  });

  factory StoredSession.fromJson(Map<String, dynamic> json) => StoredSession(
    userId: json['user_id'] as String,
    deviceId: json['device_id'] as String,
    baseUrl: json['base_url'] as String,
  );

  final String userId;
  final String deviceId;
  final String baseUrl;

  Map<String, dynamic> toJson() => {
    'user_id': userId,
    'device_id': deviceId,
    'base_url': baseUrl,
  };
}

/// Cofre de segredos do device (keychain/keystore em produção).
abstract interface class KeyStore {
  Future<IdentityKeyPair?> readIdentity();
  Future<void> writeIdentity(IdentityKeyPair keyPair);

  /// Remove só a identidade (chaves), sem tocar token/sessão. Usado quando o
  /// onboarding grava a chave mas o registro no servidor falha depois —
  /// não deve sobrar identidade órfã no keychain.
  Future<void> deleteIdentity();

  Future<String?> readToken();
  Future<void> writeToken(String token);

  Future<StoredSession?> readSession();
  Future<void> writeSession(StoredSession session);

  Future<void> clear();
}

/// [KeyStore] sobre um mapa `String → String`. Implementações reais
/// (ex.: `flutter_secure_storage`) só precisam de [read]/[write]/[delete].
abstract class MapKeyStore implements KeyStore {
  static const _identityPk = 'identity_pk';
  static const _identitySk = 'identity_sk';
  static const _token = 'device_token';
  static const _session = 'session';

  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);

  @override
  Future<IdentityKeyPair?> readIdentity() async {
    final pk = await read(_identityPk);
    final sk = await read(_identitySk);
    if (pk == null || sk == null) return null;
    return IdentityKeyPair(
      publicKey: base64.decode(pk),
      secretKey: base64.decode(sk),
    );
  }

  @override
  Future<void> writeIdentity(IdentityKeyPair keyPair) async {
    await write(_identityPk, base64.encode(keyPair.publicKey));
    await write(_identitySk, base64.encode(keyPair.secretKey));
  }

  @override
  Future<void> deleteIdentity() async {
    await delete(_identityPk);
    await delete(_identitySk);
  }

  @override
  Future<String?> readToken() => read(_token);

  @override
  Future<void> writeToken(String token) => write(_token, token);

  @override
  Future<StoredSession?> readSession() async {
    final raw = await read(_session);
    if (raw == null) return null;
    return StoredSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  @override
  Future<void> writeSession(StoredSession session) =>
      write(_session, jsonEncode(session.toJson()));

  @override
  Future<void> clear() async {
    for (final k in const [_identityPk, _identitySk, _token, _session]) {
      await delete(k);
    }
  }
}

class InMemoryKeyStore extends MapKeyStore {
  final _data = <String, String>{};

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, String value) async => _data[key] = value;

  @override
  Future<void> delete(String key) async => _data.remove(key);
}

/// Só para deixar explícito que a chave secreta é bytes crus.
typedef SecretBytes = Uint8List;
