import 'dart:convert';

import 'package:piriquito/protocol/protocol.dart';
import 'package:piriquito/transport/transport.dart';
import 'package:test/test.dart';

import '../support/fake_relay.dart';

void main() {
  late FakeRelay relay;
  late RelayApi api;
  late String token;
  late User admin;

  setUp(() async {
    relay = FakeRelay(chunkSize: 16);
    await relay.start();
    admin = relay.addUser('Felipe', role: UserRole.admin);
    token = relay.addDevice(admin.id, identityKey: 'AA==', id: 'dev_me');
    api = RelayApi(baseUrl: relay.baseUrl, token: token);
  });

  tearDown(() => relay.stop());

  test('healthz sem auth', () async {
    await RelayApi(baseUrl: relay.baseUrl).healthz();
  });

  test(
    'register consome o convite e devolve token; convite ruim → invalid_invite',
    () async {
      final code = relay.addInvite(admin.id);
      final anon = RelayApi(baseUrl: relay.baseUrl);
      final res = await anon.register(
        RegisterRequest(
          inviteCode: code,
          deviceName: 'X',
          platform: 'macos',
          identityKey: 'BB==',
        ),
      );
      expect(res.user.id, admin.id);
      expect(res.device.identityKey, 'BB==');
      expect(res.token, isNotEmpty);
      await expectLater(
        anon.register(
          RegisterRequest(
            inviteCode: code,
            deviceName: 'X',
            platform: 'macos',
            identityKey: 'BB==',
          ),
        ),
        throwsA(
          isA<RelayException>()
              .having((e) => e.code, 'code', 'invalid_invite')
              .having((e) => e.statusCode, 'status', 400),
        ),
      );
    },
  );

  test('me, directory, push token, delete device', () async {
    final me = await api.me();
    expect(me.device.id, 'dev_me');
    final dir = await api.directory();
    expect(dir.users.single.devices!.single.id, 'dev_me');
    await api.setPushToken('fcm123');
    expect(relay.pushTokens['dev_me'], 'fcm123');
    await api.setPushToken(null);
    expect(relay.pushTokens['dev_me'], isNull);
    final other = relay.addDevice(
      admin.id,
      identityKey: 'CC==',
      id: 'dev_other',
    );
    expect(other, isNotEmpty);
    await api.deleteDevice('dev_other');
    expect(relay.devices.containsKey('dev_other'), isFalse);
  });

  test('token inválido → unauthorized', () async {
    final bad = RelayApi(baseUrl: relay.baseUrl, token: 'nope');
    await expectLater(
      bad.me(),
      throwsA(
        isA<RelayException>().having((e) => e.code, 'code', 'unauthorized'),
      ),
    );
  });

  test('envelopes: post, get, ack', () async {
    relay.addDevice(admin.id, identityKey: 'DD==', id: 'dev_b');
    final res = await api.postEnvelopes([
      Envelope(
        toDevice: 'dev_b',
        nonce: 'bm9uY2U=',
        ciphertext: base64.encode([1, 2, 3]),
      ),
    ]);
    expect(res.accepted.single.toDevice, 'dev_b');
    final bApi = RelayApi(
      baseUrl: relay.baseUrl,
      token: relay.tokens.entries.firstWhere((e) => e.value == 'dev_b').key,
    );
    final pending = await bApi.getEnvelopes();
    expect(pending.single.fromDevice, 'dev_me');
    expect(pending.single.id, res.accepted.single.id);
    await bApi.ack([pending.single.id!]);
    expect(await bApi.getEnvelopes(), isEmpty);
    await expectLater(
      api.postEnvelopes([
        Envelope(toDevice: 'dev_zzz', nonce: 'x', ciphertext: 'AA=='),
      ]),
      throwsA(
        isA<RelayException>().having((e) => e.code, 'code', 'validation'),
      ),
    );
  });

  test(
    'blobs: create, chunks, complete, download (com Range), delete',
    () async {
      final data = List.generate(40, (i) => i);
      final created = await api.createBlob(
        size: data.length,
        recipients: ['dev_me'],
      );
      expect(created.chunkSize, 16);
      await api.putChunk(created.blobId, 0, data.sublist(0, 16));
      await api.putChunk(created.blobId, 1, data.sublist(16, 32));
      await expectLater(
        api.completeBlob(created.blobId),
        throwsA(
          isA<RelayException>().having(
            (e) => e.code,
            'code',
            'incomplete_blob',
          ),
        ),
      );
      await api.putChunk(created.blobId, 2, data.sublist(32));
      final done = await api.completeBlob(created.blobId);
      expect(done.size, 40);
      final all = await api
          .downloadBlob(created.blobId)
          .expand((c) => c)
          .toList();
      expect(all, data);
      final tail = await api
          .downloadBlob(created.blobId, rangeStart: 35)
          .expand((c) => c)
          .toList();
      expect(tail, data.sublist(35));
      await api.deleteBlob(created.blobId);
      await expectLater(
        api.downloadBlob(created.blobId).toList(),
        throwsA(
          isA<RelayException>().having((e) => e.code, 'code', 'not_found'),
        ),
      );
      await expectLater(
        api.putChunk(created.blobId, 9, [1]),
        throwsA(isA<RelayException>()),
      );
    },
  );

  test('admin: invites e role', () async {
    final inv = await api.createInvite(InviteRequest(userName: 'Mãe'));
    expect(inv.code, isNotEmpty);
    expect(relay.users[inv.userId]!.name, 'Mãe');
    await api.setRole(inv.userId, UserRole.admin);
    expect(relay.users[inv.userId]!.role, UserRole.admin);
  });

  test('erro de rede → RelayException(network)', () async {
    final dead = RelayApi(
      baseUrl: 'http://127.0.0.1:1',
      connectTimeout: const Duration(milliseconds: 300),
    );
    await expectLater(
      dead.healthz(),
      throwsA(isA<RelayException>().having((e) => e.code, 'code', 'network')),
    );
  });

  test('resposta 500 sem corpo JSON válido → internal', () async {
    relay.failNext['GET /v1/me'] = 1;
    await expectLater(
      api.me(),
      throwsA(isA<RelayException>().having((e) => e.code, 'code', 'internal')),
    );
    expect((await api.me()).device.id, 'dev_me');
    expect(
      const RelayException('x', 'y', statusCode: 1).toString(),
      contains('x'),
    );
  });
}
