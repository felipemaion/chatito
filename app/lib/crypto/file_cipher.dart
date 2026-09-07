import 'dart:typed_data';

/// Resultado de [FileCipher.encrypt]. [key] e [header] viajam no payload
/// (`attachments[].key/header`); [ciphertext] sobe como blob.
class FileEncryption {
  const FileEncryption({
    required this.key,
    required this.header,
    required this.ciphertext,
  });

  /// 32 bytes.
  final Uint8List key;

  /// 24 bytes.
  final Uint8List header;

  /// Um evento por chunk cifrado (≤ [FileCipher.chunkSize] + [FileCipher.overheadPerChunk]).
  final Stream<List<int>> ciphertext;
}

/// `crypto_secretstream_xchacha20poly1305` em chunks de 64 KiB (PROTOCOL.md §2).
abstract interface class FileCipher {
  /// Bytes de texto claro por chunk.
  static const chunkSize = 65536;

  /// `crypto_secretstream_xchacha20poly1305_ABYTES`.
  static const overheadPerChunk = 17;

  static const keyBytes = 32;
  static const headerBytes = 24;

  /// Gera chave e header; consome [plaintext] uma vez, com backpressure.
  Future<FileEncryption> encrypt(Stream<List<int>> plaintext);

  /// Erros de MAC/truncamento chegam como [CryptoFailure] no stream.
  Stream<List<int>> decrypt({
    required Stream<List<int>> ciphertext,
    required Uint8List key,
    required Uint8List header,
  });

  /// Tamanho do blob cifrado para um arquivo de [plainSize] bytes (para `POST /v1/blobs`).
  int cipherSize(int plainSize);
}
