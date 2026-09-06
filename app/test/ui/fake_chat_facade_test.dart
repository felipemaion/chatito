import 'package:chatito/ui/contracts.dart';
import 'package:chatito/ui/fake/fake_chat_facade.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FakeChatFacade', () {
    test('starts unregistered and registers with a valid invite', () async {
      final f = FakeChatFacade();
      expect(f.session.value.isRegistered, isFalse);
      final me = await f.register(
        inviteCode: '7K3M-9QZR',
        deviceName: 'MacBook',
        platform: 'macos',
      );
      expect(me.user.name, 'Felipe');
      expect(f.session.value.isRegistered, isTrue);
      expect(f.session.value.me, me);
    });

    test('rejects invalid invite', () async {
      final f = FakeChatFacade();
      expect(
        () => f.register(
          inviteCode: 'XXXX-0000',
          deviceName: 'x',
          platform: 'macos',
        ),
        throwsA(
          isA<ChatException>().having((e) => e.code, 'code', 'invalid_invite'),
        ),
      );
    });

    test('seeded facade exposes conversations and messages', () async {
      final f = FakeChatFacade.seeded();
      final convs = f.conversations.value;
      expect(convs.map((c) => c.id), contains('g:familia'));
      final msgs = f.messages('g:familia').value;
      expect(msgs, isNotEmpty);
    });

    test('sendText appends message and updates conversation preview', () async {
      final f = FakeChatFacade.seeded();
      await f.sendText('g:familia', 'Oi família');
      final msgs = f.messages('g:familia').value;
      expect(msgs.last.body, 'Oi família');
      expect(msgs.last.isMine, isTrue);
      expect(msgs.last.status, MessageStatus.sent);
      final conv = f.conversations.value.firstWhere((c) => c.id == 'g:familia');
      expect(conv.lastMessage?.body, 'Oi família');
    });

    test('sendText rejects empty body', () {
      final f = FakeChatFacade.seeded();
      expect(
        () => f.sendText('g:familia', '   '),
        throwsA(isA<ChatException>()),
      );
    });

    test('markRead zeroes unread count', () async {
      final f = FakeChatFacade.seeded();
      final before = f.conversations.value.firstWhere(
        (c) => c.id == 'g:familia',
      );
      expect(before.unreadCount, greaterThan(0));
      await f.markRead('g:familia');
      final after = f.conversations.value.firstWhere(
        (c) => c.id == 'g:familia',
      );
      expect(after.unreadCount, 0);
    });

    test('sendFile reports upload progress until done', () async {
      final f = FakeChatFacade.seeded(progressSteps: 4);
      final seen = <TransferState>[];
      final sub = f.messages('g:familia').stream.listen((msgs) {
        final a = msgs.last.attachments;
        if (a.isNotEmpty) seen.add(a.first.transfer.state);
      });
      await f.sendFile(
        'g:familia',
        '/tmp/praia.jpg',
        name: 'praia.jpg',
        size: 2048,
        mime: 'image/jpeg',
      );
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(seen, contains(TransferState.uploading));
      expect(
        f.messages('g:familia').value.last.attachments.first.transfer.state,
        TransferState.done,
      );
      expect(
        f.messages('g:familia').value.last.attachments.first.localPath,
        '/tmp/praia.jpg',
      );
    });

    test('downloadAttachment sets localPath and reports progress', () async {
      final f = FakeChatFacade.seeded(progressSteps: 2);
      final msg = f
          .messages('g:familia')
          .value
          .firstWhere((m) => m.attachments.isNotEmpty);
      final path = await f.downloadAttachment(
        msg.id,
        msg.attachments.first.blobId,
      );
      expect(path, isNotEmpty);
      final updated = f
          .messages('g:familia')
          .value
          .firstWhere((m) => m.id == msg.id);
      expect(updated.attachments.first.localPath, path);
      expect(updated.attachments.first.transfer.state, TransferState.done);
    });

    test('safetyNumber is 60 digits in 12 groups of 5 and symmetric', () async {
      final f = FakeChatFacade.seeded();
      final other = f.directory.value.firstWhere(
        (u) => u.id != f.session.value.me!.user.id,
      );
      final sn = await f.safetyNumber(other.devices.first.id);
      expect(sn.replaceAll(' ', ''), hasLength(60));
      expect(sn.split(' '), hasLength(12));
      expect(RegExp(r'^\d{60}$').hasMatch(sn.replaceAll(' ', '')), isTrue);
    });

    test('removeDevice removes from directory', () async {
      final f = FakeChatFacade.seeded();
      final me = f.session.value.me!;
      final myUser = f.directory.value.firstWhere((u) => u.id == me.user.id);
      final other = myUser.devices.firstWhere((d) => d.id != me.device.id);
      await f.removeDevice(other.id);
      final after = f.directory.value.firstWhere((u) => u.id == me.user.id);
      expect(after.devices.map((d) => d.id), isNot(contains(other.id)));
    });

    test('removing own device is refused', () async {
      final f = FakeChatFacade.seeded();
      expect(
        () => f.removeDevice(f.session.value.me!.device.id),
        throwsA(isA<ChatException>()),
      );
    });

    test('sync counts calls and simulateIncoming delivers a message', () async {
      final f = FakeChatFacade.seeded();
      await f.sync();
      expect(f.syncCalls, 1);
      f.simulateIncoming('g:familia', 'chegou');
      expect(f.messages('g:familia').value.last.body, 'chegou');
      expect(f.messages('g:familia').value.last.isMine, isFalse);
    });

    test('setPushToken stores token; connection state is observable', () async {
      final f = FakeChatFacade.seeded();
      await f.setPushToken('tok');
      expect(f.pushToken, 'tok');
      expect(f.connection.value, ConnectionState.online);
      f.setConnection(ConnectionState.offline);
      expect(f.connection.value, ConnectionState.offline);
    });

    test('autoReply echoes a reply and advances receipts', () async {
      final f = FakeChatFacade.seeded(autoReply: true);
      await f.sendText('u:usr_A:usr_B', 'oi');
      await Future<void>.delayed(Duration.zero);
      final msgs = f.messages('u:usr_A:usr_B').value;
      expect(msgs.where((m) => m.isMine).last.status, MessageStatus.read);
      expect(msgs.last.isMine, isFalse);
    });
  });
}
