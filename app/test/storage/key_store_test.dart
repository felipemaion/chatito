import 'dart:typed_data';

import 'package:chatito/crypto/crypto.dart';
import 'package:chatito/storage/storage.dart';
import 'package:test/test.dart';

void main() {
  late KeyStore store;
  setUp(() => store = InMemoryKeyStore());

  test('vazio no início', () async {
    expect(await store.readIdentity(), isNull);
    expect(await store.readToken(), isNull);
    expect(await store.readSession(), isNull);
  });

  test('guarda e devolve identidade, token e sessão', () async {
    final kp = IdentityKeyPair(
      publicKey: Uint8List.fromList([1, 2]),
      secretKey: Uint8List.fromList([3, 4]),
    );
    await store.writeIdentity(kp);
    await store.writeToken('tok');
    await store.writeSession(
      const StoredSession(
        userId: 'usr_a',
        deviceId: 'dev_a',
        baseUrl: 'http://x',
      ),
    );
    final read = await store.readIdentity();
    expect(read!.publicKey, [1, 2]);
    expect(read.secretKey, [3, 4]);
    expect(await store.readToken(), 'tok');
    final s = await store.readSession();
    expect((s!.userId, s.deviceId, s.baseUrl), ('usr_a', 'dev_a', 'http://x'));
    expect(StoredSession.fromJson(s.toJson()).deviceId, 'dev_a');
  });

  test('clear apaga tudo', () async {
    await store.writeToken('tok');
    await store.clear();
    expect(await store.readToken(), isNull);
  });
}
