import 'dart:convert';

import '../../crypto/crypto_box.dart';
import '../../protocol/protocol.dart';
import '../../storage/storage.dart';
import '../models.dart';
import 'context.dart';
import 'directory_sync.dart';

/// Convite → keypair → `POST /v1/devices` → diretório (PLAN §2.2).
class Onboarding {
  Onboarding(this._ctx, this._directory);

  final ChatContext _ctx;
  final DirectorySync _directory;

  Future<ActiveSession> register({
    required String inviteCode,
    required String deviceName,
    required String platform,
  }) => ChatContext.guard(() async {
    final keys = _ctx.cryptoBox.generateKeyPair();
    // Grava e RELÊ antes de registrar no servidor: bug de campo (macOS) tinha
    // a ordem invertida e, quando o keychain falhava depois do POST
    // /v1/devices, sobrava um device órfão no servidor e o app sem token.
    await _writeAndVerifyIdentity(keys);

    final RegisterResponse res;
    try {
      res = await _ctx.api.register(
        RegisterRequest(
          inviteCode: inviteCode,
          deviceName: deviceName,
          platform: platform,
          identityKey: base64.encode(keys.publicKey),
        ),
      );
    } on Object {
      // O registro falhou depois de já termos gravado a chave: não deixa
      // identidade órfã no keychain (ela não corresponde a nenhum device real).
      await _ctx.keyStore.deleteIdentity();
      rethrow;
    }

    await _ctx.keyStore.writeToken(res.token);
    await _ctx.keyStore.writeSession(
      StoredSession(
        userId: res.user.id,
        deviceId: res.device.id,
        baseUrl: _ctx.api.baseUrl,
      ),
    );
    _ctx.api.token = res.token;
    final session = ActiveSession(
      user: res.user,
      device: res.device,
      keys: keys,
    );
    try {
      await _directory.refresh(session);
    } on ChatException catch (e) {
      _ctx.log('diretório indisponível após registro: $e');
    }
    return session;
  });

  /// Grava [keys] no [KeyStore] e relê para confirmar que o que está gravado
  /// bate byte a byte com o que geramos — só então é seguro prosseguir para
  /// o `POST /v1/devices`. Lança `ChatException('storage', …)` se a escrita
  /// falhar ou se a releitura não conferir (keychain inconsistente).
  Future<void> _writeAndVerifyIdentity(IdentityKeyPair keys) async {
    try {
      await _ctx.keyStore.writeIdentity(keys);
    } on Object catch (e) {
      throw ChatException(
        'storage',
        'falha ao gravar a identidade no keychain: $e',
      );
    }
    final read = await _ctx.keyStore.readIdentity();
    if (read == null ||
        !_bytesEqual(read.publicKey, keys.publicKey) ||
        !_bytesEqual(read.secretKey, keys.secretKey)) {
      throw const ChatException(
        'storage',
        'a identidade gravada não confere ao reler (keychain inconsistente)',
      );
    }
  }

  static bool _bytesEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Restaura a sessão do [KeyStore] (sem rede). `null` se não registrado.
  Future<ActiveSession?> restore() async {
    final ks = _ctx.keyStore;
    final stored = await ks.readSession();
    final token = await ks.readToken();
    final keys = await ks.readIdentity();
    // ignore: avoid_print
    print(
      '[piriquito.boot] restore: session=${stored != null} '
      'token=${token != null} keys=${keys != null}',
    );
    if (stored == null || token == null || keys == null) {
      return null;
    }
    _ctx.api.token = token;
    final user =
        await _ctx.db.userById(stored.userId) ??
        User(id: stored.userId, name: '', role: UserRole.member);
    final device =
        await _ctx.db.deviceById(stored.deviceId) ??
        Device(
          id: stored.deviceId,
          userId: stored.userId,
          name: '',
          platform: '',
          identityKey: base64.encode(keys.publicKey),
          createdAt: _ctx.now(),
        );
    return ActiveSession(user: user, device: device, keys: keys);
  }
}
