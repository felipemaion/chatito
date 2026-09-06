import 'dart:async';
import 'dart:typed_data';

import 'package:sodium/sodium.dart';

import 'crypto_box.dart';
import 'file_cipher.dart';

class SodiumFileCipher implements FileCipher {
  SodiumFileCipher(this._sodium);

  final Sodium _sodium;

  SecretStream get _ss => _sodium.crypto.secretStream;

  @override
  Future<FileEncryption> encrypt(Stream<List<int>> plaintext) async {
    final key = _ss.keygen();
    final keyBytes = key.extractBytes();
    final pushed = _ss.pushChunked(
      messageStream: plaintext,
      key: key,
      chunkSize: FileCipher.chunkSize,
    );

    final header = Completer<Uint8List>();
    final out = StreamController<List<int>>();
    void finish() {
      key.dispose();
      if (!out.isClosed) out.close();
    }

    late final StreamSubscription<List<int>> sub;
    sub = pushed.listen(
      (chunk) {
        if (!header.isCompleted) {
          header.complete(Uint8List.fromList(chunk));
        } else {
          out.add(chunk);
        }
      },
      onError: (Object e, StackTrace st) {
        // Antes do header: `encrypt` falha. Depois: o erro vai pelo stream.
        if (!header.isCompleted) {
          header.completeError(e, st);
        } else {
          out.addError(e, st);
        }
        finish();
      },
      onDone: finish,
      cancelOnError: true,
    );
    out
      ..onPause = sub.pause
      ..onResume = sub.resume
      ..onCancel = () {
        sub.cancel();
        finish();
      };

    return FileEncryption(
      key: keyBytes,
      header: await header.future,
      ciphertext: out.stream,
    );
  }

  @override
  Stream<List<int>> decrypt({
    required Stream<List<int>> ciphertext,
    required Uint8List key,
    required Uint8List header,
  }) {
    if (key.length != FileCipher.keyBytes ||
        header.length != FileCipher.headerBytes) {
      return Stream.error(
        const CryptoFailure('chave ou header com tamanho inválido'),
      );
    }
    final secure = _sodium.secureCopy(key);
    Stream<List<int>> withHeader() async* {
      yield header;
      yield* ciphertext;
    }

    return _ss
        .pullChunked(
          cipherStream: withHeader(),
          key: secure,
          chunkSize: FileCipher.chunkSize,
        )
        .handleError((Object e) => throw CryptoFailure('decrypt: $e'))
        .transform(
          StreamTransformer.fromHandlers(
            handleDone: (sink) {
              secure.dispose();
              sink.close();
            },
          ),
        );
  }

  @override
  int cipherSize(int plainSize) {
    // pushChunked marca TAG_FINAL no último chunk parcial; se o tamanho for
    // múltiplo exato (inclusive 0), emite um chunk final vazio (só o overhead).
    final full = plainSize ~/ FileCipher.chunkSize;
    return plainSize + (full + 1) * FileCipher.overheadPerChunk;
  }
}
