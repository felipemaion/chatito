import 'dart:io';

/// Materializa em disco um anexo já decifrado (bytes vindos de
/// `ChatFacade.readAttachment`), para abrir com o app do sistema. Usa o
/// diretório temporário do SO (sem depender de `path_provider`).
Future<String> materializeAttachment({
  required String blobId,
  required String name,
  required Stream<List<int>> bytes,
  required void Function(int receivedBytes) onProgress,
}) async {
  final dir = Directory('${Directory.systemTemp.path}/piriquito');
  await dir.create(recursive: true);
  final file = File('${dir.path}/$blobId-$name');
  final sink = file.openWrite();
  var received = 0;
  try {
    await for (final chunk in bytes) {
      sink.add(chunk);
      received += chunk.length;
      onProgress(received);
    }
  } catch (_) {
    await sink.close();
    rethrow;
  }
  await sink.close();
  return file.path;
}
