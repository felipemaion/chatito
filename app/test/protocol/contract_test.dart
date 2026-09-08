import 'package:piriquito/protocol/protocol.dart';
import 'package:test/test.dart';

import '../support/fixtures.dart';

void main() {
  group('contract: round-trip exato com as fixtures', () {
    test('payload_text', () {
      final json = loadFixture('payload_text');
      final p = Payload.fromJson(json);
      expect(p.v, 1);
      expect(p.kind, PayloadKind.text);
      expect(p.body, 'Oi! Chegou bem?');
      expect(p.sentAt, DateTime.utc(2026, 9, 6, 18, 10));
      expect(p.toJson(), json);
    });

    test('payload_file', () {
      final json = loadFixture('payload_file');
      final p = Payload.fromJson(json);
      expect(p.kind, PayloadKind.file);
      expect(p.attachments, hasLength(1));
      final a = p.attachments!.single;
      expect(a.blobId, 'blob_YmxvYjAwMDAwMDAwMDAwMDAx');
      expect(a.size, 2457600);
      expect(a.chunkSize, 65536);
      expect(p.toJson(), json);
    });

    test('payload_receipt', () {
      final json = loadFixture('payload_receipt');
      final p = Payload.fromJson(json);
      expect(p.kind, PayloadKind.receipt);
      expect(p.receipt!.status, ReceiptStatus.read);
      expect(p.receipt!.msgId, '3f1e2d7c-8a4b-4c6d-9e0f-1a2b3c4d5e6f');
      expect(p.body, isNull);
      expect(p.toJson(), json);
    });

    test('directory', () {
      final json = loadFixture('directory');
      final d = Directory.fromJson(json);
      expect(d.users, hasLength(2));
      expect(d.users.first.role, UserRole.admin);
      expect(d.users.last.name, 'Mãe');
      expect(d.users.last.devices!.single.platform, 'android');
      expect(d.toJson(), json);
    });

    test('register_request', () {
      final json = loadFixture('register_request');
      final r = RegisterRequest.fromJson(json);
      expect(r.inviteCode, '7K3M-9QZR');
      expect(r.toJson(), json);
    });

    test('register_response', () {
      final json = loadFixture('register_response');
      final r = RegisterResponse.fromJson(json);
      expect(r.device.userId, 'usr_YWxpY2VhbGljZWFsaWNlMQ');
      expect(r.user.role, UserRole.admin);
      expect(r.token, isNotEmpty);
      expect(r.toJson(), json);
    });

    test('envelopes_post_request', () {
      final json = loadFixture('envelopes_post_request');
      final r = EnvelopesPostRequest.fromJson(json);
      expect(r.envelopes.single.toDevice, 'dev_YW5kcm9pZGRldmljZTAwMDE');
      expect(r.envelopes.single.id, isNull);
      expect(r.toJson(), json);
    });

    test('envelopes_post_response', () {
      final json = loadFixture('envelopes_post_response');
      final r = EnvelopesPostResponse.fromJson(json);
      expect(r.accepted.single.id, 'env_ZW52ZWxvcGUwMDAwMDAwMDAx');
      expect(r.toJson(), json);
    });

    test('error', () {
      final json = loadFixture('error');
      final e = ErrorResponse.fromJson(json);
      expect(e.error.code, 'invalid_invite');
      expect(e.toJson(), json);
    });

    test('ws_frames', () {
      final json = loadFixture('ws_frames');
      for (final entry in json.entries) {
        final frameJson = entry.value as Map<String, dynamic>;
        final frame = WsFrame.fromJson(frameJson);
        expect(frame.toJson(), frameJson, reason: entry.key);
      }
      final hello = WsFrame.fromJson(json['hello'] as Map<String, dynamic>);
      expect(hello, isA<WsHello>());
      expect((hello as WsHello).pending, 1);
      final env = WsFrame.fromJson(json['envelope'] as Map<String, dynamic>);
      expect(
        (env as WsEnvelope).envelope.fromDevice,
        'dev_Zm9vYmFyYmF6cXV4MTIzNA',
      );
      expect(env.envelope.createdAt, DateTime.utc(2026, 9, 6, 18, 10));
      final ack = WsFrame.fromJson(json['ack'] as Map<String, dynamic>);
      expect((ack as WsAck).ids, ['env_ZW52ZWxvcGUwMDAwMDAwMDAx']);
      expect(
        WsFrame.fromJson(json['ping'] as Map<String, dynamic>),
        isA<WsPing>(),
      );
      expect(
        WsFrame.fromJson(json['pong'] as Map<String, dynamic>),
        isA<WsPong>(),
      );
      final err = WsFrame.fromJson(json['error'] as Map<String, dynamic>);
      expect((err as WsError).error.code, 'unauthorized');
    });

    test('frame WS desconhecido lança FormatException', () {
      expect(() => WsFrame.fromJson({'type': 'nope'}), throwsFormatException);
    });
  });

  group('DTOs sem fixture: round-trip', () {
    test('BlobCreate request/response e complete', () {
      final req = BlobCreateRequest(size: 10, recipients: const ['dev_a']);
      expect(BlobCreateRequest.fromJson(req.toJson()).toJson(), req.toJson());
      final resJson = {
        'blob_id': 'blob_x',
        'chunk_size': 8388608,
        'expires_at': '2026-10-06T18:00:00Z',
      };
      final res = BlobCreateResponse.fromJson(resJson);
      expect(res.chunkSize, 8388608);
      expect(res.toJson(), resJson);
      final done = BlobCompleteResponse.fromJson({
        'blob_id': 'blob_x',
        'size': 10,
      });
      expect(done.toJson(), {'blob_id': 'blob_x', 'size': 10});
    });

    test('AckRequest, PushTokenRequest, MeResponse, Invite', () {
      expect(AckRequest(ids: const ['env_1']).toJson(), {
        'ids': ['env_1'],
      });
      expect(PushTokenRequest(fcmToken: null).toJson(), {'fcm_token': null});
      expect(PushTokenRequest(fcmToken: 'abc').toJson(), {'fcm_token': 'abc'});
      final me = {
        'user': {'id': 'usr_a', 'name': 'A', 'role': 'member'},
        'device': {
          'id': 'dev_a',
          'user_id': 'usr_a',
          'name': 'X',
          'platform': 'windows',
          'identity_key': 'AA==',
          'created_at': '2026-09-06T18:00:00Z',
        },
      };
      expect(MeResponse.fromJson(me).toJson(), me);
      expect(InviteRequest(userName: 'Felipe').toJson(), {
        'user_name': 'Felipe',
      });
      expect(InviteRequest(userId: 'usr_a').toJson(), {'user_id': 'usr_a'});
      final inv = {
        'code': '7K3M-9QZR',
        'user_id': 'usr_a',
        'expires_at': '2026-09-13T18:00:00Z',
      };
      expect(InviteResponse.fromJson(inv).toJson(), inv);
      expect(RoleRequest(role: UserRole.admin).toJson(), {'role': 'admin'});
    });

    test('datas com fração de segundo preservam milissegundos', () {
      final json = {'id': 'usr_a', 'name': 'A', 'role': 'member'};
      expect(User.fromJson(json).toJson(), json);
      final dev = Device(
        id: 'dev_a',
        name: 'X',
        platform: 'macos',
        identityKey: 'AA==',
        createdAt: DateTime.utc(2026, 1, 2, 3, 4, 5, 678),
      );
      expect(dev.toJson()['created_at'], '2026-01-02T03:04:05.678Z');
      expect(Device.fromJson(dev.toJson()).createdAt, dev.createdAt);
    });

    test('Payload.key_change sem body', () {
      final p = Payload(
        v: 1,
        msgId: 'm',
        convId: 'g:familia',
        kind: PayloadKind.keyChange,
        sentAt: DateTime.utc(2026),
      );
      expect(p.toJson()['kind'], 'key_change');
      expect(p.toJson().containsKey('body'), isFalse);
      expect(Payload.fromJson(p.toJson()).kind, PayloadKind.keyChange);
    });

    test('campos desconhecidos são ignorados', () {
      final json = loadFixture('payload_text')..['future_field'] = 42;
      expect(Payload.fromJson(json).body, 'Oi! Chegou bem?');
    });
  });
}
