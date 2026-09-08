import 'dart:typed_data';

import 'package:piriquito/crypto/crypto.dart';
import 'package:test/test.dart';

import '../support/sodium.dart';

Uint8List pattern(int n) =>
    Uint8List.fromList(List.generate(n, (i) => (i * 7 + 3) & 0xff));

/// Divide em pedaços irregulares para provar que a entrada pode vir em qualquer granularidade.
Stream<List<int>> irregular(Uint8List data) async* {
  var i = 0;
  var step = 1;
  while (i < data.length) {
    final end = (i + step).clamp(0, data.length);
    yield data.sublist(i, end);
    i = end;
    step = (step * 3 + 1) % 100000 + 1;
  }
}

Future<Uint8List> collect(Stream<List<int>> s) async {
  final b = BytesBuilder(copy: false);
  await for (final c in s) {
    b.add(c);
  }
  return b.takeBytes();
}

void main() {
  late FileCipher cipher;

  setUpAll(() async => cipher = SodiumFileCipher(await loadSodium()));

  for (final n in [
    0,
    1,
    100,
    FileCipher.chunkSize - 1,
    FileCipher.chunkSize,
    FileCipher.chunkSize + 1,
    3 * FileCipher.chunkSize + 5,
  ]) {
    test('round-trip $n bytes; tamanho cifrado previsto bate', () async {
      final plain = pattern(n);
      final enc = await cipher.encrypt(irregular(plain));
      expect(enc.key, hasLength(32));
      expect(enc.header, hasLength(24));
      final chunks = await enc.ciphertext.toList();
      for (final c in chunks) {
        expect(
          c.length,
          lessThanOrEqualTo(FileCipher.chunkSize + FileCipher.overheadPerChunk),
        );
      }
      final cipherBytes = Uint8List.fromList(chunks.expand((c) => c).toList());
      expect(cipherBytes.length, cipher.cipherSize(n));
      expect(cipherBytes, isNot(equals(plain)));

      final dec = await collect(
        cipher.decrypt(
          ciphertext: irregular(cipherBytes),
          key: enc.key,
          header: enc.header,
        ),
      );
      expect(dec, plain);
    });
  }

  test('chaves diferentes por arquivo', () async {
    final a = await cipher.encrypt(Stream.value(pattern(10)));
    final b = await cipher.encrypt(Stream.value(pattern(10)));
    await a.ciphertext.drain<void>();
    await b.ciphertext.drain<void>();
    expect(a.key, isNot(b.key));
    expect(a.header, isNot(b.header));
  });

  test(
    'chave errada, header errado ou stream truncado falham com CryptoFailure',
    () async {
      final enc = await cipher.encrypt(Stream.value(pattern(200000)));
      final bytes = await collect(enc.ciphertext);
      final wrongKey = Uint8List(32)..[0] = 1;
      expect(
        collect(
          cipher.decrypt(
            ciphertext: Stream.value(bytes),
            key: wrongKey,
            header: enc.header,
          ),
        ),
        throwsA(isA<CryptoFailure>()),
      );
      final wrongHeader = Uint8List.fromList(enc.header)..[0] ^= 1;
      expect(
        collect(
          cipher.decrypt(
            ciphertext: Stream.value(bytes),
            key: enc.key,
            header: wrongHeader,
          ),
        ),
        throwsA(isA<CryptoFailure>()),
      );
      final truncated = bytes.sublist(0, bytes.length - 40);
      expect(
        collect(
          cipher.decrypt(
            ciphertext: Stream.value(truncated),
            key: enc.key,
            header: enc.header,
          ),
        ),
        throwsA(isA<CryptoFailure>()),
      );
      final flipped = Uint8List.fromList(bytes)..[100] ^= 1;
      expect(
        collect(
          cipher.decrypt(
            ciphertext: Stream.value(flipped),
            key: enc.key,
            header: enc.header,
          ),
        ),
        throwsA(isA<CryptoFailure>()),
      );
    },
  );

  test('erro na fonte propaga pelo stream cifrado', () async {
    Stream<List<int>> failing() async* {
      yield pattern(10);
      throw StateError('disco falhou');
    }

    // O erro pode chegar antes do header (encrypt falha) ou depois (stream falha).
    await expectLater(() async {
      final enc = await cipher.encrypt(failing());
      await collect(enc.ciphertext);
    }, throwsA(isA<StateError>()));
  });

  test('backpressure: pausar o consumidor pausa a fonte', () async {
    var produced = 0;
    Stream<List<int>> src() async* {
      for (var i = 0; i < 50; i++) {
        produced++;
        yield pattern(FileCipher.chunkSize);
      }
    }

    final enc = await cipher.encrypt(src());
    final sub = enc.ciphertext.listen(null);
    sub.pause();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(produced, lessThan(50));
    sub.resume();
    await sub.asFuture<void>();
    expect(produced, 50);
  });
}
