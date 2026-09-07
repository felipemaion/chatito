import 'dart:convert';

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
    final res = await _ctx.api.register(
      RegisterRequest(
        inviteCode: inviteCode,
        deviceName: deviceName,
        platform: platform,
        identityKey: base64.encode(keys.publicKey),
      ),
    );
    await _ctx.keyStore.writeIdentity(keys);
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

  /// Restaura a sessão do [KeyStore] (sem rede). `null` se não registrado.
  Future<ActiveSession?> restore() async {
    final ks = _ctx.keyStore;
    final stored = await ks.readSession();
    final token = await ks.readToken();
    final keys = await ks.readIdentity();
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
