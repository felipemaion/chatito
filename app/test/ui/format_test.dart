import 'package:chatito/domain/domain.dart';
import 'package:chatito/ui/format.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() => initializeDateFormatting('pt_BR'));

  test('formatSize', () {
    expect(formatSize(512), '512 B');
    expect(formatSize(1024), '1,0 KB');
    expect(formatSize(2457600), '2,3 MB');
    expect(formatSize(3 * 1024 * 1024 * 1024), '3,0 GB');
  });

  test('formatTime: hora se hoje, dd/MM se outro dia', () {
    final now = DateTime(2026, 9, 6, 20, 0);
    expect(formatTime(DateTime(2026, 9, 6, 15, 7), now: now), '15:07');
    expect(formatTime(DateTime(2026, 9, 1, 15, 7), now: now), '01/09');
  });

  test('previewOf', () {
    Message m(
      MessageKind k, {
      String? body,
      List<MessageAttachment> att = const [],
    }) => Message(
      id: '1',
      convId: 'c',
      senderUserId: 'u',
      senderDeviceId: 'd',
      kind: k,
      sentAt: DateTime.utc(2026),
      isMine: false,
      body: body,
      attachments: att,
    );
    expect(previewOf(m(MessageKind.text, body: 'oi')), 'oi');
    const a = MessageAttachment(
      blobId: 'b',
      name: 'praia.jpg',
      size: 1,
      mime: 'image/jpeg',
    );
    expect(previewOf(m(MessageKind.file, att: const [a])), '📎 praia.jpg');
    expect(
      previewOf(m(MessageKind.file, body: 'legenda', att: const [a])),
      '📎 legenda',
    );
    expect(previewOf(m(MessageKind.keyChange)), contains('Chave'));
  });

  test('MessageAttachmentX.isImage', () {
    const img = MessageAttachment(
      blobId: 'b',
      name: 'a.png',
      size: 1,
      mime: 'image/png',
    );
    const doc = MessageAttachment(
      blobId: 'b',
      name: 'a.pdf',
      size: 1,
      mime: 'application/pdf',
    );
    expect(img.isImage, isTrue);
    expect(doc.isImage, isFalse);
  });
}
