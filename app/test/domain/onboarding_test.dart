import 'dart:convert';
import 'dart:typed_data';

import 'package:chatito/crypto/crypto.dart';
import 'package:chatito/domain/models.dart';
import 'package:chatito/domain/use_cases/context.dart';
import 'package:chatito/domain/use_cases/directory_sync.dart';
import 'package:chatito/domain/use_cases/onboarding.dart';
import 'package:chatito/protocol/protocol.dart';
import 'package:chatito/storage/storage.dart';
import 'package:chatito/transport/transport.dart';
import 'package:drift/native.dart';
import 'package:sodium/sodium.dart';
import 'package:test/test.dart';

import '../support/fake_relay.dart';
import '../support/sodium.dart';

/// [KeyStore] de teste que pode ser configurado para falhar na escrita da
/// identidade, ou fazer a releitura "não bater" (simula um keychain
/// inconsistente que aceita o write mas devolve outra coisa/nada ao ler).
class FlakyKeyStore implements KeyStore {
  FlakyKeyStore(this._inner);

  final KeyStore _inner;
  bool failWriteIdentity = false;
  bool corruptReadBack = false;
  var writeIdentityCalls = 0;
  var deleteIdentityCalls = 0;

  @override
  Future<void> writeIdentity(IdentityKeyPair keyPair) async {
    writeIdentityCalls++;
    if (failWriteIdentity) {
      throw StateError('keychain indisponível (simulado)');
    }
    await _inner.writeIdentity(keyPair);
  }

  @override
  Future<IdentityKeyPair?> readIdentity() async {
    if (corruptReadBack) {
      return IdentityKeyPair(
        publicKey: Uint8List(32),
        secretKey: Uint8List(32),
      );
    }
    return _inner.readIdentity();
  }

  @override
  Future<void> deleteIdentity() async {
    deleteIdentityCalls++;
    await _inner.deleteIdentity();
  }

  @override
  Future<String?> readToken() => _inner.readToken();

  @override
  Future<void> writeToken(String token) => _inner.writeToken(token);

  @override
  Future<StoredSession?> readSession() => _inner.readSession();

  @override
  Future<void> writeSession(StoredSession session) =>
      _inner.writeSession(session);

  @override
  Future<void> clear() => _inner.clear();
}

void main() {
  late Sodium sodium;
  late FakeRelay relay;
  late ChatDatabase db;
  late FlakyKeyStore keyStore;
  late Onboarding onboarding;
  late String felipeId;

  setUpAll(() async => sodium = await loadSodium());

  setUp(() async {
    relay = FakeRelay();
    await relay.start();
    felipeId = relay.addUser('Felipe', role: UserRole.admin).id;
    db = ChatDatabase(NativeDatabase.memory());
    keyStore = FlakyKeyStore(InMemoryKeyStore());
    final ctx = ChatContext(
      cryptoBox: SodiumCryptoBox(sodium),
      fileCipher: SodiumFileCipher(sodium),
      db: db,
      keyStore: keyStore,
      api: RelayApi(baseUrl: relay.baseUrl),
      log: (_) {},
      now: () => DateTime.utc(2026, 9, 8),
      newId: () => 'id-fixo',
    );
    onboarding = Onboarding(ctx, DirectorySync(ctx));
  });

  tearDown(() async {
    await db.close();
    await relay.stop();
  });

  test(
    'caminho feliz: grava a identidade, relê para confirmar, só então registra',
    () async {
      final invite = relay.addInvite(felipeId);
      final session = await onboarding.register(
        inviteCode: invite,
        deviceName: 'Mac',
        platform: 'macos',
      );
      expect(session.user.id, felipeId);
      expect(await keyStore.readToken(), isNotNull);
      expect(
        (await keyStore.readIdentity())!.publicKey,
        base64.decode(session.device.identityKey),
      );
      expect(relay.devices.containsKey(session.device.id), isTrue);
    },
  );

  test('falha ao GRAVAR a chave: aborta antes de registrar, sem device órfão no servidor', () async {
    keyStore.failWriteIdentity = true;
    final invite = relay.addInvite(felipeId);

    await expectLater(
      onboarding.register(
        inviteCode: invite,
        deviceName: 'Mac',
        platform: 'macos',
      ),
      throwsA(isA<ChatException>().having((e) => e.code, 'code', 'storage')),
    );

    // Nada foi registrado no servidor: o convite continua válido e não há devices novos.
    expect(relay.devices, isEmpty);
    expect(relay.invites, contains(invite));
    expect(relay.log.where((l) => l.startsWith('POST /v1/devices')), isEmpty);
  });

  test('escrita "bem-sucedida" mas releitura não confere: aborta antes de registrar (keychain inconsistente)', () async {
    keyStore.corruptReadBack = true;
    final invite = relay.addInvite(felipeId);

    await expectLater(
      onboarding.register(
        inviteCode: invite,
        deviceName: 'Mac',
        platform: 'macos',
      ),
      throwsA(isA<ChatException>().having((e) => e.code, 'code', 'storage')),
    );

    expect(relay.devices, isEmpty);
    expect(relay.log.where((l) => l.startsWith('POST /v1/devices')), isEmpty);
  });

  test(
    'registro falha no servidor: apaga a chave que tinha acabado de gravar',
    () async {
      // Convite inválido → o relay recusa o registro depois que já gravamos a identidade.
      await expectLater(
        onboarding.register(
          inviteCode: 'ZZZZ-0000',
          deviceName: 'Mac',
          platform: 'macos',
        ),
        throwsA(
          isA<ChatException>().having((e) => e.code, 'code', 'invalid_invite'),
        ),
      );

      expect(keyStore.deleteIdentityCalls, 1);
      expect(
        await keyStore.readIdentity(),
        isNull,
        reason: 'não fica identidade órfã no keychain',
      );
      expect(await keyStore.readToken(), isNull);
    },
  );

  test('registro falha por rede: também limpa a chave gravada', () async {
    await relay.stop();
    await expectLater(
      onboarding.register(
        inviteCode: 'AAAA-0000',
        deviceName: 'Mac',
        platform: 'macos',
      ),
      throwsA(isA<ChatException>().having((e) => e.code, 'code', 'network')),
    );
    expect(keyStore.deleteIdentityCalls, 1);
    expect(await keyStore.readIdentity(), isNull);
  });
}
