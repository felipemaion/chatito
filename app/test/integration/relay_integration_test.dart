// Teste de integração real: app Dart (RealChatFacade) ↔ servidor Go (relay).
//
// Só roda se a variável de ambiente `RELAY_URL` existir (ex.:
// `http://127.0.0.1:8080` de um `docker compose -f docker/docker-compose.dev.yml
// up`); caso contrário todos os testes deste arquivo são pulados. Convites são
// gerados sob demanda via `docker exec <container> /relay admin invite --user
// <nome>` (configurável por `RELAY_ADMIN_CMD`/`RELAY_CONTAINER`), então cada
// execução usa usuários novos e não depende de um convite fixo já consumido.
// Se o processo do teste não tiver acesso ao Docker do host (ex.: rodando
// dentro de outro container), gere os 3 convites fora e passe-os em
// `RELAY_INVITE_A`, `RELAY_INVITE_A2`, `RELAY_INVITE_B`.
//
// Dart puro (sem `flutter_test`) — roda com `flutter test test/integration`
// (o runner do `flutter test` executa `package:test` normalmente) ou
// `dart test test/integration` fora da árvore Flutter.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:chatito/crypto/crypto.dart';
import 'package:chatito/domain/domain.dart';
import 'package:chatito/domain/real_chat_facade.dart';
import 'package:chatito/protocol/protocol.dart';
import 'package:chatito/storage/storage.dart';
import 'package:drift/native.dart';
import 'package:sodium/sodium.dart';
import 'package:test/test.dart';

final String? _relayUrl = Platform.environment['RELAY_URL'];

/// Convite para o "slot" [slot] (`A`, `A2` ou `B`). Se `RELAY_INVITE_<slot>`
/// estiver definido, usa esse código direto (útil quando o processo do teste
/// não tem acesso ao Docker do host, ex.: rodando dentro de um container —
/// gere os convites fora e passe por env var). Senão, chama o CLI admin do
/// relay via `docker exec` (ou `RELAY_ADMIN_CMD`, um comando por espaço, ex.:
/// `ssh relay-host docker exec relay /relay admin invite --user`).
Future<String> _freshInvite(String slot, String userName) async {
  final explicit = Platform.environment['RELAY_INVITE_$slot'];
  if (explicit != null && explicit.isNotEmpty) return explicit;

  final custom = Platform.environment['RELAY_ADMIN_CMD'];
  final container = Platform.environment['RELAY_CONTAINER'] ?? 'docker-relay-1';
  final cmd = custom != null && custom.isNotEmpty
      ? custom.split(' ')
      : ['docker', 'exec', container, '/relay', 'admin', 'invite', '--user'];
  final result = await Process.run(cmd.first, [...cmd.skip(1), userName]);
  if (result.exitCode != 0) {
    fail(
      'não consegui gerar convite via `${cmd.join(' ')} $userName` '
      '(exit ${result.exitCode}): ${result.stderr}\n'
      'Defina RELAY_INVITE_$slot (convite pronto) ou RELAY_CONTAINER/RELAY_ADMIN_CMD.',
    );
  }
  final match = RegExp(r'([0-9A-Z]{4}-[0-9A-Z]{4})')
      .firstMatch('${result.stdout}');
  if (match == null) {
    fail('convite não encontrado na saída do admin CLI: ${result.stdout}');
  }
  return match.group(1)!;
}

Future<void> _until(
  bool Function() cond, {
  Duration timeout = const Duration(seconds: 20),
  String? reason,
}) async {
  final end = DateTime.now().add(timeout);
  bool tryCond() {
    try {
      return cond();
    } on Object {
      return false;
    }
  }

  while (!tryCond()) {
    if (DateTime.now().isAfter(end)) {
      fail(
        'timeout aguardando integração real${reason == null ? '' : ': $reason'}',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

/// Um device real: `RealChatFacade` completo, banco e chaves em memória, mas
/// falando com o relay de verdade em [_relayUrl].
class _Peer {
  _Peer(Sodium sodium, {void Function(String)? log})
    : db = ChatDatabase(NativeDatabase.memory()) {
    facade = RealChatFacade(
      cryptoBox: SodiumCryptoBox(sodium),
      fileCipher: SodiumFileCipher(sodium),
      db: db,
      keyStore: InMemoryKeyStore(),
      baseUrl: _relayUrl!,
      log: log,
    );
    facade.watchConversations().listen((c) => conversations = c);
  }

  final ChatDatabase db;
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

  Future<void> dispose() async {
    await facade.dispose();
    await db.close();
  }
}

void main() {
  if (_relayUrl == null || _relayUrl!.isEmpty) {
    test(
      'integração real Go<->Dart (pulado: defina RELAY_URL, ex.: '
      'RELAY_URL=http://127.0.0.1:8080 flutter test test/integration)',
      () {},
      skip: 'RELAY_URL não definido',
    );
    return;
  }

  final tag = DateTime.now().microsecondsSinceEpoch;
  late Sodium sodium;
  late _Peer a; // dispositivo 1 do usuário A
  late _Peer a2; // 2º dispositivo do usuário A (para testar fan-out)
  late _Peer b; // dispositivo do usuário B
  late String userAId;
  late String userBId;
  late String directId;

  setUpAll(() async {
    sodium = await SodiumInit.init();
    // ignore: avoid_print
    a = _Peer(sodium, log: (m) => print('[A] $m'));
    // ignore: avoid_print
    a2 = _Peer(sodium, log: (m) => print('[A2] $m'));
    // ignore: avoid_print
    b = _Peer(sodium, log: (m) => print('[B] $m'));
  });

  tearDownAll(() async {
    await a.dispose();
    await a2.dispose();
    await b.dispose();
  });

  test('onboarding: convite real → registro → diretório', () async {
    final inviteA = await _freshInvite('A', 'IntA-$tag');
    await a.facade.register(
      inviteCode: inviteA,
      deviceName: 'IntA-desktop',
      platform: 'macos',
    );
    final sessionA = await a.facade.session as Registered;
    userAId = sessionA.user.id;
    expect(sessionA.device.platform, 'macos');

    // Mesmo nome do usuário A (não "IntA2-…"): `admin invite --user <nome>`
    // reaproveita o `user_id` existente quando o nome já foi usado, gerando
    // um convite para **outro device do mesmo usuário** (PROTOCOL.md §3).
    // Usar um nome novo criaria um usuário diferente, e o fan-out para os
    // próprios devices não se aplicaria a essa conversa 1:1.
    final inviteA2 = await _freshInvite('A2', 'IntA-$tag');
    await a2.facade.register(
      inviteCode: inviteA2,
      deviceName: 'IntA2-mobile',
      platform: 'android',
    );
    final sessionA2 = await a2.facade.session as Registered;
    expect(
      sessionA2.user.id,
      userAId,
      reason: 'A2 é o 2º device do mesmo usuário A',
    );
    expect(sessionA2.device.id, isNot(sessionA.device.id));

    final inviteB = await _freshInvite('B', 'IntB-$tag');
    await b.facade.register(
      inviteCode: inviteB,
      deviceName: 'IntB-desktop',
      platform: 'windows',
    );
    final sessionB = await b.facade.session as Registered;
    userBId = sessionB.user.id;

    directId = ConvId.direct(userAId, userBId);

    await a.facade.refreshDirectory();
    await a2.facade.refreshDirectory();
    await b.facade.refreshDirectory();

    final contactsA = await a.facade.watchContacts().first;
    expect(
      contactsA.any((c) => c.user.id == userBId),
      isTrue,
      reason: 'A vê B no diretório real',
    );
    expect(
      contactsA.any((c) => c.user.id == userAId && c.devices.isNotEmpty),
      isTrue,
      reason: 'A vê seus próprios devices',
    );
  });

  test('WS: conecta os 3 devices reais', () async {
    await a.facade.connect();
    await a2.facade.connect();
    await b.facade.connect();
    await _until(
      () =>
          a.facade.currentConnection == ConnectionState.online &&
          a2.facade.currentConnection == ConnectionState.online &&
          b.facade.currentConnection == ConnectionState.online,
      reason: 'todos online',
    );
  });

  test(
    'texto 1:1 nos dois sentidos, com fan-out para o 2º device e ack',
    () async {
      await a.facade.openDirect(userBId);
      await b.facade.openDirect(userAId);

      await a.facade.sendText(directId, 'Oi do device A ($tag)');
      await _until(
        () =>
            b.messages(directId).any((m) => m.body == 'Oi do device A ($tag)'),
        reason: 'B recebeu de A',
      );
      await _until(
        () => a2
            .messages(directId)
            .any((m) => m.body == 'Oi do device A ($tag)' && m.isMine),
        reason: 'A2 recebeu a cópia (fan-out para os próprios devices)',
      );

      await b.facade.sendText(directId, 'Oi de volta, sou B ($tag)');
      await _until(
        () => a
            .messages(directId)
            .any((m) => m.body == 'Oi de volta, sou B ($tag)'),
        reason: 'A recebeu de B',
      );

      // Recibo `delivered` chega de volta ao remetente (persistido no banco real).
      await _until(
        () =>
            a
                .messages(directId)
                .firstWhere((m) => m.body == 'Oi do device A ($tag)')
                .status
                .index >=
            MessageStatus.delivered.index,
        reason: 'delivered chegou em A',
      );
    },
    timeout: const Timeout(Duration(minutes: 1)),
  );

  test('recibo read real após markRead', () async {
    await b.facade.markRead(directId);
    await _until(
      () =>
          a
              .messages(directId)
              .firstWhere((m) => m.body == 'Oi do device A ($tag)')
              .status ==
          MessageStatus.read,
      reason: 'read chegou em A',
    );
  });

  test('grupo (g:familia): mensagem chega nos meus outros devices e no outro usuário', () async {
    await a.facade.sendText(ConvId.family, 'Mensagem de grupo real ($tag)');
    await _until(
      () => a2
          .messages(ConvId.family)
          .any((m) => m.body == 'Mensagem de grupo real ($tag)'),
      reason: 'A2 recebeu no grupo (fan-out)',
    );
    await _until(
      () => b
          .messages(ConvId.family)
          .any((m) => m.body == 'Mensagem de grupo real ($tag)'),
      reason: 'B recebeu no grupo',
    );
  }, timeout: const Timeout(Duration(minutes: 1)));

  test(
    'arquivo ~1 MiB: cifra, sobe em chunks reais, B decifra e recebe íntegro',
    () async {
      final size =
          1024 * 1024 + 777; // não múltiplo exato do chunk, de propósito
      final data = Uint8List.fromList(
        List.generate(size, (i) => (i * 131 + 7) & 0xff),
      );
      await a.facade.sendFile(
        directId,
        name: 'relatorio.bin',
        mime: 'application/octet-stream',
        size: data.length,
        data: Stream.value(data),
        caption: 'arquivo de integração ($tag)',
      );
      await _until(
        () => b
            .messages(directId)
            .any((m) => m.body == 'arquivo de integração ($tag)'),
        reason: 'B recebeu a mensagem de arquivo',
      );
      final fileMsg = b
          .messages(directId)
          .firstWhere((m) => m.body == 'arquivo de integração ($tag)');
      expect(fileMsg.attachments, hasLength(1));
      expect(fileMsg.attachments.single.size, data.length);

      final builder = BytesBuilder(copy: false);
      await b.facade
          .readAttachment(
            messageId: fileMsg.id,
            blobId: fileMsg.attachments.single.blobId,
          )
          .forEach(builder.add);
      final received = builder.takeBytes();
      expect(received.length, data.length);
      expect(
        received,
        data,
        reason: 'bytes decifrados batem byte a byte com o original',
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('reconexão do WS: derruba e volta a receber mensagens novas', () async {
    await b.facade.disconnect();
    expect(await b.facade.watchConnection().first, ConnectionState.offline);
    await b.facade.connect();
    await _until(
      () => b.facade.currentConnection == ConnectionState.online,
      reason: 'B reconectou',
    );

    await a.facade.sendText(directId, 'depois da reconexão ($tag)');
    await _until(
      () => b
          .messages(directId)
          .any((m) => m.body == 'depois da reconexão ($tag)'),
      reason: 'B recebeu após reconectar',
    );
  }, timeout: const Timeout(Duration(minutes: 1)));

  test('safety number: mesmo valor calculado pelos dois lados', () async {
    final sessionA = await a.facade.session as Registered;
    final sessionB = await b.facade.session as Registered;
    final snA = await a.facade.safetyNumber(sessionB.device.id);
    final snB = await b.facade.safetyNumber(sessionA.device.id);
    expect(snA.digits, snB.digits);
    expect(snA.digits, hasLength(60));
  });
}
