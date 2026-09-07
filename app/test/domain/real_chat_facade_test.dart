import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

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
  // cond() pode ler coleções ainda vazias (ex.: `.single` antes do 1º evento
  // assíncrono do stream) e lançar em vez de simplesmente ser falso: tratamos
  // isso como "ainda não" e re-tentamos, só propagando perto do timeout.
  bool tryCond() {
    try {
      return cond();
    } on Object {
      return false;
    }
  }

  while (!tryCond()) {
    if (DateTime.now().isAfter(end)) {
      fail('timeout${reason == null ? '' : ': $reason'}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 15));
  }
}

/// Um device: facade + dependências, tudo em memória.
class Peer {
  Peer(
    this.name,
    this.sodium,
    this.relay, {
    KeyStore? keyStore,
    ChatDatabase? db,
  }) : keyStore = keyStore ?? InMemoryKeyStore(),
       db = db ?? ChatDatabase(NativeDatabase.memory()) {
    facade = RealChatFacade(
      cryptoBox: SodiumCryptoBox(sodium),
      fileCipher: SodiumFileCipher(sodium),
      db: this.db,
      keyStore: this.keyStore,
      baseUrl: relay.baseUrl,
      wsBackoffBase: const Duration(milliseconds: 30),
      wsBackoffMax: const Duration(milliseconds: 200),
      log: logs.add,
    );
    facade.watchConversations().listen((c) => conversations = c);
  }

  final String name;
  final Sodium sodium;
  final FakeRelay relay;
  final KeyStore keyStore;
  final ChatDatabase db;
  final logs = <String>[];
  late final RealChatFacade facade;
  List<Conversation> conversations = const [];
  final _messages = <String, List<Message>>{};

  List<Message> messages(String convId) {
    _messages.putIfAbsent(convId, () {
      facade.watchMessages(convId).listen((m) => _messages[convId] = m);
      return const [];
    });
    return _messages[convId]!;
  }

  Future<Registered> register(
    String invite, {
    String platform = 'macos',
  }) async {
    await facade.register(
      inviteCode: invite,
      deviceName: '$name-$platform',
      platform: platform,
    );
    return await facade.session as Registered;
  }

  Future<void> dispose() async {
    await facade.dispose();
    await db.close();
  }
}

void main() {
  late Sodium sodium;
  late FakeRelay relay;
  late User felipe;
  late User mae;
  final peers = <Peer>[];

  setUpAll(() async => sodium = await loadSodium());

  setUp(() async {
    relay = FakeRelay(chunkSize: 32 * 1024);
    await relay.start();
    felipe = relay.addUser('Felipe', role: UserRole.admin);
    mae = relay.addUser('Mãe');
  });

  tearDown(() async {
    for (final p in peers) {
      await p.dispose();
    }
    peers.clear();
    await relay.stop();
  });

  Peer peer(String name, {KeyStore? keyStore, ChatDatabase? db}) {
    final p = Peer(name, sodium, relay, keyStore: keyStore, db: db);
    peers.add(p);
    return p;
  }

  Future<(Peer, Peer)> twoRegistered() async {
    final f = peer('felipe');
    final m = peer('mae');
    await f.register(relay.addInvite(felipe.id, code: 'AAAA-0001'));
    await m.register(
      relay.addInvite(mae.id, code: 'BBBB-0002'),
      platform: 'android',
    );
    await f.facade.refreshDirectory();
    await f.facade.connect();
    await m.facade.connect();
    await until(
      () =>
          f.facade.currentConnection == ConnectionState.online &&
          m.facade.currentConnection == ConnectionState.online,
    );
    return (f, m);
  }

  group('onboarding', () {
    test('registra, guarda sessão, cria grupo Família e restaura sem rede', () async {
      final f = peer('felipe');
      expect(await f.facade.session, isA<NotRegistered>());
      final states = <SessionState>[];
      f.facade.watchSession().listen(states.add);
      final reg = await f.register(
        relay.addInvite(felipe.id, code: 'AAAA-0001'),
      );
      expect(reg.user.name, 'Felipe');
      expect(reg.device.platform, 'macos');
      expect(await f.keyStore.readToken(), isNotNull);
      expect(
        (await f.keyStore.readIdentity())!.publicKey,
        base64.decode(reg.device.identityKey),
      );
      await until(() => f.conversations.any((c) => c.id == ConvId.family));
      expect(f.conversations.single.title, 'Família');
      expect(
        f.conversations.single.participantUserIds,
        containsAll([felipe.id, mae.id]),
      );
      final contacts = await f.facade.watchContacts().first;
      expect(contacts.map((c) => c.user.name), containsAll(['Felipe', 'Mãe']));
      expect(states.last, isA<Registered>());

      // Reinício: mesma KeyStore e DB, relay fora do ar → continua registrado.
      await f.facade.dispose();
      relay.rejectAllTokens = true;
      final again = RealChatFacade(
        cryptoBox: SodiumCryptoBox(sodium),
        fileCipher: SodiumFileCipher(sodium),
        db: f.db,
        keyStore: f.keyStore,
        baseUrl: relay.baseUrl,
      );
      await again.init();
      final s = await again.session;
      expect(s, isA<Registered>());
      expect((s as Registered).device.id, reg.device.id);
      await again.dispose();
      peers.remove(f);
      await f.db.close();
    });

    test(
      'convite inválido → invalid_invite; sem registro → not_registered',
      () async {
        final f = peer('felipe');
        await expectLater(
          f.register('ZZZZ-9999'),
          throwsA(
            isA<ChatException>().having(
              (e) => e.code,
              'code',
              'invalid_invite',
            ),
          ),
        );
        expect(await f.facade.session, isA<NotRegistered>());
        await expectLater(
          f.facade.sendText(ConvId.family, 'x'),
          throwsA(
            isA<ChatException>().having(
              (e) => e.code,
              'code',
              'not_registered',
            ),
          ),
        );
        await expectLater(
          f.facade.connect(),
          throwsA(
            isA<ChatException>().having(
              (e) => e.code,
              'code',
              'not_registered',
            ),
          ),
        );
      },
    );

    test('relay fora do ar → network', () async {
      final f = peer('felipe');
      await relay.stop();
      await expectLater(
        f.register('AAAA-0001'),
        throwsA(isA<ChatException>().having((e) => e.code, 'code', 'network')),
      );
      relay = FakeRelay();
      await relay.start();
    });
  });

  group('mensagens 1:1', () {
    test('texto chega, cria conversa, recibos delivered/read e safety number simétrico', () async {
      final (f, m) = await twoRegistered();
      final direct = await f.facade.openDirect(mae.id);
      expect(direct.title, 'Mãe');
      expect(direct.id, ConvId.direct(felipe.id, mae.id));
      await expectLater(
        f.facade.openDirect('usr_nope'),
        throwsA(
          isA<ChatException>().having((e) => e.code, 'code', 'not_found'),
        ),
      );

      await f.facade.sendText(direct.id, 'Oi! Chegou bem?');
      await until(
        () => m.messages(direct.id).length == 1,
        reason: 'mãe recebe',
      );
      final got = m.messages(direct.id).single;
      expect(got.body, 'Oi! Chegou bem?');
      expect(got.isMine, isFalse);
      expect(got.senderUserId, felipe.id);
      expect(got.status, MessageStatus.delivered);
      await until(
        () => m.conversations.any(
          (c) => c.id == direct.id && c.unreadCount == 1 && c.title == 'Felipe',
        ),
      );

      // recibo delivered chega no Felipe (a conversa também tem o aviso de
      // key_change do refresh de diretório em twoRegistered, então filtramos
      // pelo texto em vez de usar `.single`).
      Message sentByFelipe() => f.messages(direct.id).firstWhere((x) => x.kind == MessageKind.text);
      await until(
        () => sentByFelipe().status == MessageStatus.delivered,
        reason: 'delivered',
      );
      await m.facade.markRead(direct.id);
      await until(
        () => sentByFelipe().status == MessageStatus.read,
        reason: 'read',
      );
      expect(
        m.conversations.firstWhere((c) => c.id == direct.id).unreadCount,
        0,
      );

      // relay não guarda nada após os acks
      await until(() => relay.queues.values.every((q) => q.isEmpty));

      // safety number
      final fs = await f.facade.session as Registered;
      final ms = await m.facade.session as Registered;
      final a = await f.facade.safetyNumber(ms.device.id);
      final b = await m.facade.safetyNumber(fs.device.id);
      expect(a.digits, b.digits);
      expect(a.formatted.split(' '), hasLength(12));
      await expectLater(
        f.facade.safetyNumber('dev_nope'),
        throwsA(
          isA<ChatException>().having((e) => e.code, 'code', 'not_found'),
        ),
      );
    });

    test('fan-out inclui meus outros devices (isMine, sem não-lidas) e grupo chega a todos', () async {
      final (f, m) = await twoRegistered();
      final f2 = peer('felipe2');
      await f2.register(
        relay.addInvite(felipe.id, code: 'CCCC-0003'),
        platform: 'windows',
      );
      await f2.facade.connect();
      await f.facade.refreshDirectory();
      await m.facade.refreshDirectory();

      await f.facade.sendText(ConvId.family, 'Bem-vindos!');
      await until(
        () =>
            m.messages(ConvId.family).length == 1 &&
            f2.messages(ConvId.family).length == 1,
      );
      expect(f2.messages(ConvId.family).single.isMine, isTrue);
      // A Mãe manda recibo `delivered` para todos os devices do Felipe,
      // inclusive f2 (cópia própria): o status avança de sent para delivered.
      expect(f2.messages(ConvId.family).single.status.index, greaterThanOrEqualTo(MessageStatus.sent.index));
      expect(
        f2.conversations.firstWhere((c) => c.id == ConvId.family).unreadCount,
        0,
      );
      expect(
        m.conversations.firstWhere((c) => c.id == ConvId.family).unreadCount,
        1,
      );

      // Mãe responde no grupo: Felipe (2 devices) recebe
      await m.facade.sendText(ConvId.family, 'Que chique!');
      await until(
        () =>
            f.messages(ConvId.family).length == 2 &&
            f2.messages(ConvId.family).length == 2,
      );
      expect(f.messages(ConvId.family).last.senderUserId, mae.id);
    });

    test('offline: fica pending na outbox e sai ao reconectar', () async {
      final (f, m) = await twoRegistered();
      final direct = await f.facade.openDirect(mae.id);
      relay.failNext['POST /v1/envelopes'] = 3;
      await f.facade.sendText(direct.id, 'sem rede');
      // A conversa também tem o aviso de key_change de twoRegistered.
      Message sent() => f.messages(direct.id).firstWhere((x) => x.kind == MessageKind.text);
      // `messages()` inscreve o stream na 1ª chamada; aguarda o 1º evento.
      await until(() => f.messages(direct.id).any((x) => x.kind == MessageKind.text));
      expect(sent().status, MessageStatus.pending);
      expect(await f.db.outboxCountFor(sent().id), 1);
      relay.failNext.clear();
      await f.facade.connect();
      await until(
        () => sent().status.index >= MessageStatus.sent.index,
        reason: 'drenou',
      );
      await until(() => m.messages(direct.id).length == 1);
    });

    test('envelope adulterado é descartado com ack; remetente desconhecido força refresh do diretório', () async {
      final (f, m) = await twoRegistered();
      final ms = await m.facade.session as Registered;
      final fs = await f.facade.session as Registered;
      // lixo cifrado "vindo" do Felipe
      await relay.inject(
        Envelope(
          toDevice: ms.device.id,
          nonce: base64.encode(Uint8List(24)),
          ciphertext: base64.encode(Uint8List(40)),
        ),
        fromDevice: fs.device.id,
      );
      await until(() => m.logs.any((l) => l.contains('descartado')));
      await until(
        () => (relay.queues[ms.device.id] ?? []).isEmpty,
        reason: 'ack do lixo',
      );
      expect(m.messages(ConvId.direct(felipe.id, mae.id)), isEmpty);

      // device novo do Felipe, ainda desconhecido pela Mãe, manda mensagem real
      final box = SodiumCryptoBox(sodium);
      final kp = box.generateKeyPair();
      final newDev = relay.addDevice(
        felipe.id,
        identityKey: base64.encode(kp.publicKey),
        id: 'dev_novo',
        name: 'iPad',
      );
      expect(newDev, isNotEmpty);
      final payload = Payload(
        msgId: '11111111-1111-4111-8111-111111111111',
        convId: ConvId.direct(felipe.id, mae.id),
        kind: PayloadKind.text,
        sentAt: DateTime.utc(2026, 9, 6, 19),
        body: 'do iPad',
      );
      final sealed = box.seal(
        plaintext: utf8.encode(jsonEncode(payload.toJson())),
        recipientPk: base64.decode(ms.device.identityKey),
        senderSk: kp.secretKey,
      );
      await relay.inject(
        Envelope(
          toDevice: ms.device.id,
          nonce: base64.encode(sealed.nonce),
          ciphertext: base64.encode(sealed.ciphertext),
        ),
        fromDevice: 'dev_novo',
      );
      // Chega junto com o aviso de key_change do refresh de diretório (novo
      // device do Felipe), então a lista tem 2 itens, não 1.
      await until(
        () => m.messages(ConvId.direct(felipe.id, mae.id)).any((x) => x.body == 'do iPad'),
        reason: 'mensagem do device novo',
      );
      expect(
        (await m.facade.watchContacts().first)
            .firstWhere((c) => c.user.id == felipe.id)
            .devices
            .map((d) => d.id),
        contains('dev_novo'),
      );
    });

    test('key_change: diretório com chave trocada e payload key_change viram aviso na conversa', () async {
      final (f, m) = await twoRegistered();
      final fs = await f.facade.session as Registered;
      final ms = await m.facade.session as Registered;
      final direct = ConvId.direct(felipe.id, mae.id);
      // troca a chave do device do Felipe no relay
      relay.devices[fs.device.id] = Device(
        id: fs.device.id,
        userId: felipe.id,
        name: fs.device.name,
        platform: 'macos',
        identityKey: base64.encode(Uint8List(32)..[0] = 9),
        createdAt: fs.device.createdAt,
      );
      await m.facade.refreshDirectory();
      await until(
        () => m.messages(direct).any((x) => x.kind == MessageKind.keyChange),
        reason: 'aviso por diretório',
      );

      // payload key_change explícito da Mãe para o Felipe
      final box = SodiumCryptoBox(sodium);
      final mk = (await m.keyStore.readIdentity())!;
      final payload = Payload(
        msgId: '22222222-2222-4222-8222-222222222222',
        convId: direct,
        kind: PayloadKind.keyChange,
        sentAt: DateTime.utc(2026, 9, 6, 19),
      );
      final sealed = box.seal(
        plaintext: utf8.encode(jsonEncode(payload.toJson())),
        recipientPk: base64.decode(fs.device.identityKey),
        senderSk: mk.secretKey,
      );
      await relay.inject(
        Envelope(
          toDevice: fs.device.id,
          nonce: base64.encode(sealed.nonce),
          ciphertext: base64.encode(sealed.ciphertext),
        ),
        fromDevice: ms.device.id,
      );
      await until(
        () => f
            .messages(direct)
            .any((x) => x.kind == MessageKind.keyChange && !x.isMine),
        reason: 'aviso por payload',
      );
    });

    test('mensagem duplicada (reentrega) não duplica; recibo para msg desconhecida é ignorado', () async {
      final (f, m) = await twoRegistered();
      final direct = await f.facade.openDirect(mae.id);
      await f.facade.sendText(direct.id, 'uma vez');
      await until(() => m.messages(direct.id).length == 1);
      final ms = await m.facade.session as Registered;
      final fs = await f.facade.session as Registered;
      // reentrega o mesmo payload cifrado de novo
      final fk = (await f.keyStore.readIdentity())!;
      final box = SodiumCryptoBox(sodium);
      final p = Payload(
        msgId: m.messages(direct.id).single.id,
        convId: direct.id,
        kind: PayloadKind.text,
        sentAt: DateTime.utc(2026),
        body: 'uma vez',
      );
      final s = box.seal(
        plaintext: utf8.encode(jsonEncode(p.toJson())),
        recipientPk: base64.decode(ms.device.identityKey),
        senderSk: fk.secretKey,
      );
      await relay.inject(
        Envelope(
          toDevice: ms.device.id,
          nonce: base64.encode(s.nonce),
          ciphertext: base64.encode(s.ciphertext),
        ),
        fromDevice: fs.device.id,
      );
      final r = Payload(
        msgId: '33333333-3333-4333-8333-333333333333',
        convId: direct.id,
        kind: PayloadKind.receipt,
        sentAt: DateTime.utc(2026),
        receipt: Receipt(msgId: 'nope', status: ReceiptStatus.read),
      );
      final s2 = box.seal(
        plaintext: utf8.encode(jsonEncode(r.toJson())),
        recipientPk: base64.decode(ms.device.identityKey),
        senderSk: fk.secretKey,
      );
      await relay.inject(
        Envelope(
          toDevice: ms.device.id,
          nonce: base64.encode(s2.nonce),
          ciphertext: base64.encode(s2.ciphertext),
        ),
        fromDevice: fs.device.id,
      );
      await until(() => (relay.queues[ms.device.id] ?? []).isEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(m.messages(direct.id), hasLength(1));
    });
  });

  group('arquivos', () {
    test('sendFile cifra, sobe em chunks e a Mãe decifra byte a byte; remetente lê do cache', () async {
      final (f, m) = await twoRegistered();
      final data = Uint8List.fromList(
        List.generate(200 * 1024 + 7, (i) => (i * 31) & 0xff),
      );
      await f.facade.sendFile(
        ConvId.family,
        name: 'praia.jpg',
        mime: 'image/jpeg',
        size: data.length,
        data: Stream.value(data),
        caption: 'Fotos',
      );
      // `messages()` inscreve o stream na 1ª chamada; aguarda o 1º evento.
      await until(() => f.messages(ConvId.family).isNotEmpty);
      final mine = f.messages(ConvId.family).single;
      expect(mine.kind, MessageKind.file);
      expect(mine.attachments.single.name, 'praia.jpg');
      expect(mine.attachments.single.downloaded, isTrue);
      final blob = relay.blobs.values.single;
      expect(blob.complete, isTrue);
      expect(blob.bytes, isNot(equals(data)), reason: 'relay só vê cifra');
      expect(blob.size, SodiumFileCipher(sodium).cipherSize(data.length));

      await until(() => m.messages(ConvId.family).length == 1);
      final got = m.messages(ConvId.family).single;
      expect(got.body, 'Fotos');
      expect(got.attachments.single.downloaded, isFalse);
      final bytes = await m.facade
          .readAttachment(
            messageId: got.id,
            blobId: got.attachments.single.blobId,
          )
          .fold<BytesBuilder>(BytesBuilder(), (b, c) => b..add(c));
      expect(bytes.takeBytes(), data);
      await until(
        () => m.messages(ConvId.family).single.attachments.single.downloaded,
      );
      // segunda leitura vem do cache (relay não é chamado de novo)
      final downloads = relay.log
          .where((l) => l.startsWith('GET /v1/blobs/'))
          .length;
      final again = await m.facade
          .readAttachment(
            messageId: got.id,
            blobId: got.attachments.single.blobId,
          )
          .fold<int>(0, (n, c) => n + c.length);
      expect(again, data.length);
      expect(
        relay.log.where((l) => l.startsWith('GET /v1/blobs/')).length,
        downloads,
      );
      // remetente lê do próprio cache
      final own = await f.facade
          .readAttachment(
            messageId: mine.id,
            blobId: mine.attachments.single.blobId,
          )
          .fold<int>(0, (n, c) => n + c.length);
      expect(own, data.length);
      await expectLater(
        f.facade.readAttachment(messageId: 'x', blobId: 'blob_nope').toList(),
        throwsA(
          isA<ChatException>().having((e) => e.code, 'code', 'not_found'),
        ),
      );
    });

    test('falha de upload → ChatException, nada persistido', () async {
      final (f, _) = await twoRegistered();
      relay.failNext['POST /v1/blobs'] = 10;
      await expectLater(
        f.facade.sendFile(
          ConvId.family,
          name: 'x',
          mime: 'text/plain',
          size: 3,
          data: Stream.value([1, 2, 3]),
        ),
        throwsA(isA<ChatException>()),
      );
      expect(f.messages(ConvId.family), isEmpty);
    });
  });

  group('conexão', () {
    test('watchConnection reflete WS; disconnect volta a offline; connect é idempotente', () async {
      final (f, _) = await twoRegistered();
      final states = <ConnectionState>[];
      f.facade.watchConnection().listen(states.add);
      await f.facade.connect();
      await f.facade.disconnect();
      await until(() => states.last == ConnectionState.offline);
      expect(states.first, ConnectionState.online);
    });
  });
}
