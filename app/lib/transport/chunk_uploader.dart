import 'dart:async';
import 'dart:typed_data';

import 'relay_api.dart';

/// Upload de blob em chunks (8 MiB por padrão, valor vem do servidor) com
/// retentativa por chunk. A retomada é por chunk: um PUT que falha é
/// repetido com o mesmo buffer; o que já foi aceito (204) não sobe de novo.
class ChunkUploader {
  ChunkUploader(
    this._api, {
    this.maxAttempts = 5,
    this.retryBase = const Duration(seconds: 1),
  });

  final RelayApi _api;
  final int maxAttempts;
  final Duration retryBase;

  /// Sobe [data] (exatamente [size] bytes) e devolve o `blob_id` completo.
  /// [onProgress] recebe bytes confirmados pelo servidor.
  Future<String> upload({
    required Stream<List<int>> data,
    required int size,
    required List<String> recipients,
    void Function(int sentBytes)? onProgress,
  }) async {
    final created = await _api.createBlob(size: size, recipients: recipients);
    final chunkSize = created.chunkSize;
    final total = size == 0 ? 0 : (size + chunkSize - 1) ~/ chunkSize;
    var index = 0;
    var sent = 0;
    final buf = BytesBuilder(copy: false);

    Future<void> flush() async {
      final bytes = buf.takeBytes();
      if (index >= total) {
        throw ArgumentError('mais bytes do que o tamanho declarado ($size)');
      }
      await _putWithRetry(created.blobId, index, bytes);
      index++;
      sent += bytes.length;
      onProgress?.call(sent);
    }

    await for (final piece in data) {
      var offset = 0;
      while (offset < piece.length) {
        final room = chunkSize - buf.length;
        final take = piece.length - offset < room
            ? piece.length - offset
            : room;
        buf.add(
          piece is Uint8List
              ? Uint8List.sublistView(piece, offset, offset + take)
              : piece.sublist(offset, offset + take),
        );
        offset += take;
        if (buf.length == chunkSize) await flush();
      }
    }
    if (sent + buf.length != size) {
      throw ArgumentError(
        'tamanho declarado $size, lidos ${sent + buf.length}',
      );
    }
    if (buf.isNotEmpty) await flush();
    await _api.completeBlob(created.blobId);
    return created.blobId;
  }

  Future<void> _putWithRetry(String blobId, int n, Uint8List bytes) async {
    var attempt = 0;
    while (true) {
      attempt++;
      try {
        await _api.putChunk(blobId, n, bytes);
        return;
      } on RelayException catch (e) {
        final retriable =
            e.code == 'network' ||
            e.code == 'internal' ||
            e.code == 'rate_limited';
        if (!retriable || attempt >= maxAttempts) rethrow;
        await Future<void>.delayed(retryBase * (1 << (attempt - 1)));
      }
    }
  }
}
