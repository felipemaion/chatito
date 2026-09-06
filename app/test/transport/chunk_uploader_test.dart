import 'dart:typed_data';

import 'package:chatito/protocol/protocol.dart';
import 'package:chatito/transport/transport.dart';
import 'package:test/test.dart';

import '../support/fake_relay.dart';

void main() {
  late FakeRelay relay;
  late RelayApi api;

  setUp(() async {
    relay = FakeRelay(chunkSize: 16);
    await relay.start();
    final u = relay.addUser('F');
    api = RelayApi(
      baseUrl: relay.baseUrl,
      token: relay.addDevice(u.id, identityKey: 'AA==', id: 'dev_me'),
    );
  });
  tearDown(() => relay.stop());

  Stream<List<int>> pieces(List<int> data, List<int> sizes) async* {
    var i = 0;
    for (final s in sizes) {
      if (i >= data.length) return;
      final end = (i + s).clamp(0, data.length);
      yield data.sublist(i, end);
      i = end;
    }
    if (i < data.length) yield data.sublist(i);
  }

  for (final n in [0, 1, 15, 16, 17, 40, 48]) {
    test(
      'sobe $n bytes em chunks de 16 com entrada irregular e completa',
      () async {
        final data = List.generate(n, (i) => i & 0xff);
        final progress = <int>[];
        final up = ChunkUploader(api, retryBase: Duration.zero);
        final blobId = await up.upload(
          data: pieces(data, [5, 7, 20, 3]),
          size: n,
          recipients: ['dev_me'],
          onProgress: progress.add,
        );
        expect(relay.blobs[blobId]!.complete, isTrue);
        expect(relay.blobs[blobId]!.bytes, data);
        if (n > 0) expect(progress.last, n);
      },
    );
  }

  test(
    'retenta chunk que falhou (500) e completa; log mostra o re-PUT',
    () async {
      relay.failNext['PUT /v1/blobs/'] = 2;
      final data = List.generate(40, (i) => i);
      final up = ChunkUploader(api, retryBase: Duration.zero);
      final blobId = await up.upload(
        data: Stream.value(data),
        size: 40,
        recipients: ['dev_me'],
      );
      expect(relay.blobs[blobId]!.bytes, data);
      expect(
        relay.log.where((l) => l.startsWith('PUT /v1/blobs/')).length,
        3 + 2,
      );
    },
  );

  test('esgota tentativas → RelayException e blob não completa', () async {
    relay.failNext['PUT /v1/blobs/'] = 100;
    final up = ChunkUploader(api, retryBase: Duration.zero, maxAttempts: 3);
    await expectLater(
      up.upload(
        data: Stream.value(List.filled(20, 1)),
        size: 20,
        recipients: ['dev_me'],
      ),
      throwsA(isA<RelayException>()),
    );
    expect(relay.blobs.values.single.complete, isFalse);
  });

  test(
    'tamanho declarado ≠ bytes lidos → ArgumentError antes de completar',
    () async {
      final up = ChunkUploader(api, retryBase: Duration.zero);
      await expectLater(
        up.upload(
          data: Stream.value(List.filled(10, 1)),
          size: 20,
          recipients: ['dev_me'],
        ),
        throwsA(isA<ArgumentError>()),
      );
    },
  );

  test('download em stream reconstrói o blob', () async {
    final data = Uint8List.fromList(List.generate(50, (i) => i));
    final up = ChunkUploader(api, retryBase: Duration.zero);
    final id = await up.upload(
      data: Stream.value(data),
      size: 50,
      recipients: ['dev_me'],
    );
    final got = await api.downloadBlob(id).expand((c) => c).toList();
    expect(got, data);
    expect(ConvId.family, 'g:familia');
  });
}
