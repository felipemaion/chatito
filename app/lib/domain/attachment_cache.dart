import 'dart:async';
import 'dart:typed_data';

/// Cache local de anexos **decifrados**, por `blob_id`. Em produção deve ser
/// em disco (diretório privado do app); em testes, memória.
abstract interface class AttachmentCache {
  Future<bool> has(String blobId);
  Stream<List<int>>? openRead(String blobId);
  Future<AttachmentSink> openWrite(String blobId);
  Future<void> remove(String blobId);

  /// Renomeia (o id do blob só é conhecido depois do upload).
  Future<void> rename(String from, String to);
}

abstract interface class AttachmentSink {
  void add(List<int> chunk);

  /// Torna o anexo visível em [AttachmentCache.openRead].
  Future<void> close();

  /// Descarta o que foi escrito (ex.: download interrompido).
  Future<void> abort();
}

class InMemoryAttachmentCache implements AttachmentCache {
  final _data = <String, Uint8List>{};

  @override
  Future<bool> has(String blobId) async => _data.containsKey(blobId);

  @override
  Stream<List<int>>? openRead(String blobId) {
    final bytes = _data[blobId];
    if (bytes == null) return null;
    const chunk = 65536;
    return Stream.fromIterable([
      for (var i = 0; i < bytes.length; i += chunk)
        bytes.sublist(i, i + chunk > bytes.length ? bytes.length : i + chunk),
    ]);
  }

  @override
  Future<AttachmentSink> openWrite(String blobId) async =>
      _MemorySink(this, blobId);

  @override
  Future<void> remove(String blobId) async => _data.remove(blobId);

  @override
  Future<void> rename(String from, String to) async {
    final v = _data.remove(from);
    if (v != null) _data[to] = v;
  }
}

class _MemorySink implements AttachmentSink {
  _MemorySink(this._cache, this._blobId);

  final InMemoryAttachmentCache _cache;
  final String _blobId;
  final _buf = BytesBuilder(copy: false);

  @override
  void add(List<int> chunk) => _buf.add(chunk);

  @override
  Future<void> close() async => _cache._data[_blobId] = _buf.takeBytes();

  @override
  Future<void> abort() async => _buf.clear();
}
