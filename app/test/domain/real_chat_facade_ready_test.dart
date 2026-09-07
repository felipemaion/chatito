// Bug de campo (Android/macOS, visto por logcat): `connect()` era chamado
// pela UI (observador de conectividade) ANTES de `RealChatFacade` terminar
// de carregar a sessão do `KeyStore`. `_require()` via `_active == null` e
// lançava `not_registered` como exceção não tratada — o app nunca conectava.
import 'dart:convert';

import 'package:chatito/crypto/crypto.dart';
import 'package:chatito/domain/domain.dart';
import 'package:chatito/domain/real_chat_facade.dart';
import 'package:chatito/protocol/protocol.dart';
import 'package:chatito/storage/storage.dart';
import 'package:drift/native.dart';
import 'package:sodium/sodium.dart';
import 'package:test/test.dart';

import '../support/fake_relay.dart';
import '../support/sodium.dart';

Future<void> until(
  bool Function() cond, {
  Duration timeout = const Duration(seconds: 5),
  String? reason,
}) async {
  final end = DateTime.now().add(timeout);
  while (!cond()) {
    if (DateTime.now().isAfter(end)) {
      fail('timeout${reason == null ? '' : ': $reason'}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  late Sodium sodium;
  late FakeRelay relay;
  late User user;
  late KeyStore keyStore;
  late ChatDatabase db;

  setUpAll(() async => sodium = await loadSodium());

  /// Um `KeyStore` já com identidade/token/sessão salvos, como um usuário
  /// que reabre o app (não é o 1º onboarding).
  Future<void> seedReturningUser() async {
    final box = SodiumCryptoBox(sodium);
    final keys = box.generateKeyPair();
    user = relay.addUser('Felipe', role: UserRole.admin);
    final token = relay.addDevice(
      user.id,
      identityKey: base64.encode(keys.publicKey),
      id: 'dev_me',
    );
    await keyStore.writeIdentity(keys);
    await keyStore.writeToken(token);
    await keyStore.writeSession(
      StoredSession(
        userId: user.id,
        deviceId: 'dev_me',
        baseUrl: relay.baseUrl,
      ),
    );
  }

  setUp(() async {
    relay = FakeRelay();
    await relay.start();
    keyStore = InMemoryKeyStore();
    db = ChatDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
    await relay.stop();
  });

  RealChatFacade build() => RealChatFacade(
    cryptoBox: SodiumCryptoBox(sodium),
    fileCipher: SodiumFileCipher(sodium),
    db: db,
    keyStore: keyStore,
    baseUrl: relay.baseUrl,
  );

  test('connect() chamado imediatamente após construir (sessão já salva) conecta sem lançar', () async {
    await seedReturningUser();
    final facade = build();

    // A chamada crítica: sem awaitar `init()` antes — exatamente o que a
    // UI fazia em campo.
    await facade.connect();

    await until(
      () => facade.currentConnection == ConnectionState.online,
      reason: 'deveria conectar assim que a sessão carregasse',
    );
    expect(await facade.session, isA<Registered>());

    await facade.dispose();
  });

  test('ensureConnected() chamado imediatamente após construir também conecta sem lançar', () async {
    await seedReturningUser();
    final facade = build();

    await facade.ensureConnected();

    await until(() => facade.currentConnection == ConnectionState.online);
    await facade.dispose();
  });

  test('demais métodos que dependem de sessão (refreshDirectory, sendText) também esperam o carregamento', () async {
    await seedReturningUser();
    final facade = build();

    await facade.refreshDirectory();
    final contacts = await facade.watchContacts().first;
    expect(contacts.any((c) => c.user.id == user.id), isTrue);

    await facade.sendText(ConvId.family, 'oi');
    final msgs = await facade.watchMessages(ConvId.family).first;
    expect(msgs, hasLength(1));

    await facade.dispose();
  });

  test('sem sessão salva: connect() ainda lança not_registered (depois de esperar o carregamento)', () async {
    final facade = build(); // keyStore vazio: nenhuma sessão salva
    await expectLater(
      facade.connect(),
      throwsA(
        isA<ChatException>().having((e) => e.code, 'code', 'not_registered'),
      ),
    );
    await facade.dispose();
  });

  test(
    'init() continua funcionando para quem ainda chama explicitamente',
    () async {
      await seedReturningUser();
      final facade = build();
      await facade.init();
      expect(await facade.session, isA<Registered>());
      await facade.dispose();
    },
  );
}
