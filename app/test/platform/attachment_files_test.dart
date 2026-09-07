import 'dart:io';

import 'package:chatito/platform/attachment_files.dart';
import 'package:test/test.dart';

void main() {
  test('materializa um stream em disco e reporta progresso', () async {
    final bytes = List.generate(200000, (i) => i % 256);
    final chunks = <List<int>>[];
    for (var i = 0; i < bytes.length; i += 65536) {
      chunks.add(
        bytes.sublist(i, i + 65536 > bytes.length ? bytes.length : i + 65536),
      );
    }
    final progress = <int>[];
    final path = await materializeAttachment(
      blobId: 'blob_test_${DateTime.now().microsecondsSinceEpoch}',
      name: 'a.bin',
      bytes: Stream.fromIterable(chunks),
      onProgress: progress.add,
    );
    addTearDown(() => File(path).delete());
    final written = await File(path).readAsBytes();
    expect(written, bytes);
    expect(progress.last, bytes.length);
    expect(progress, orderedEquals(progress.toList()..sort()));
  });

  test('stream vazio produz arquivo vazio', () async {
    final path = await materializeAttachment(
      blobId: 'blob_empty_${DateTime.now().microsecondsSinceEpoch}',
      name: 'a.bin',
      bytes: const Stream.empty(),
      onProgress: (_) {},
    );
    addTearDown(() => File(path).delete());
    expect(await File(path).readAsBytes(), isEmpty);
  });
}
