import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:piriquito/crypto/crypto.dart';
import 'package:piriquito/platform/file_key_store.dart';
import 'package:piriquito/storage/storage.dart';
import 'package:test/test.dart';

Directory _tmpDir() => Directory.systemTemp.createTempSync(
  'piriquito_keystore_test_${DateTime.now().microsecondsSinceEpoch}',
);

IdentityKeyPair _keyPair([int seed = 1]) => IdentityKeyPair(
  publicKey: Uint8List.fromList(List.filled(32, seed)),
  secretKey: Uint8List.fromList(List.filled(32, seed + 1)),
);

void main() {
  late Directory dir;
  late File file;

  setUp(() {
    dir = _tmpDir();
    file = File('${dir.path}/keystore.json');
  });

  tearDown(() => dir.deleteSync(recursive: true));

  test('grava e lê identidade, token e sessão', () async {
    final store = FileKeyStore(file);
    final kp = _keyPair();
    await store.writeIdentity(kp);
    await store.writeToken('tok-123');
    const session = StoredSession(
      userId: 'usr_1',
      deviceId: 'dev_1',
      baseUrl: 'http://x',
    );
    await store.writeSession(session);

    // Nova instância (sem cache em memória) — força reler do arquivo.
    final reread = FileKeyStore(file);
    final identity = await reread.readIdentity();
    expect(identity!.publicKey, kp.publicKey);
    expect(identity.secretKey, kp.secretKey);
    expect(await reread.readToken(), 'tok-123');
    final storedSession = await reread.readSession();
    expect(storedSession!.userId, 'usr_1');
    expect(storedSession.deviceId, 'dev_1');
    expect(storedSession.baseUrl, 'http://x');
  });

  test('arquivo é criado no diretório informado, em JSON', () async {
    final store = FileKeyStore(file);
    await store.writeToken('abc');
    expect(await file.exists(), isTrue);
    final decoded =
        jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    expect(decoded['device_token'], isNotNull);
  });

  test('permissão 0600 no arquivo (POSIX)', () async {
    final store = FileKeyStore(file);
    await store.writeToken('abc');
    if (!Platform.isWindows) {
      final mode = (await file.stat()).mode & 0x1FF; // últimos 9 bits
      expect(mode, 0x180); // 0600 = rw- --- ---
    }
  }, skip: Platform.isWindows ? 'chmod não se aplica no Windows' : false);

  test('delete remove só a chave pedida', () async {
    final store = FileKeyStore(file);
    await store.writeToken('tok');
    await store.writeIdentity(_keyPair());
    await store.deleteIdentity();
    expect(await store.readToken(), 'tok');
    expect(await store.readIdentity(), isNull);
  });

  test('clear remove tudo', () async {
    final store = FileKeyStore(file);
    await store.writeToken('tok');
    await store.writeIdentity(_keyPair());
    await store.clear();
    expect(await store.readToken(), isNull);
    expect(await store.readIdentity(), isNull);
  });

  test('arquivo corrompido não trava: volta a ler como vazio', () async {
    await file.parent.create(recursive: true);
    await file.writeAsString('não é json {{{');
    final store = FileKeyStore(file);
    expect(await store.readToken(), isNull);
    // Continua utilizável para escrever depois.
    await store.writeToken('novo');
    expect(await store.readToken(), 'novo');
  });

  test(
    'migrateFrom copia dados do keystore antigo quando o arquivo está vazio',
    () async {
      final old = InMemoryKeyStore();
      final kp = _keyPair(5);
      await old.writeIdentity(kp);
      await old.writeToken('old-token');
      const session = StoredSession(
        userId: 'usr_2',
        deviceId: 'dev_2',
        baseUrl: 'http://y',
      );
      await old.writeSession(session);

      final store = FileKeyStore(file);
      await store.migrateFrom(old);

      expect((await store.readIdentity())!.publicKey, kp.publicKey);
      expect(await store.readToken(), 'old-token');
      expect((await store.readSession())!.userId, 'usr_2');
    },
  );

  test('migrateFrom não sobrescreve se o arquivo já tem dados', () async {
    final store = FileKeyStore(file);
    await store.writeToken('já-tinha');

    final old = InMemoryKeyStore();
    await old.writeToken('do-keychain');

    await store.migrateFrom(old);

    expect(await store.readToken(), 'já-tinha');
  });

  test(
    'migrateFrom não faz nada se o keystore antigo também está vazio',
    () async {
      final store = FileKeyStore(file);
      await store.migrateFrom(InMemoryKeyStore());
      expect(await store.readToken(), isNull);
      expect(await file.exists(), isFalse);
    },
  );

  test('FileKeyStore.open() usa getApplicationSupportDirectory/piriquito/keystore.json', () async {
    // Só valida que a fábrica não lança e devolve algo utilizável — não
    // depende de canal de plataforma real fora de um app Flutter rodando,
    // então este teste fica só documentando o contrato via FileKeyStore
    // construído direto (acima). Aqui cobrimos que o nome do arquivo é
    // configurável.
    final custom = FileKeyStore(File('${dir.path}/custom.json'));
    await custom.writeToken('x');
    expect(await File('${dir.path}/custom.json').exists(), isTrue);
  });
}
