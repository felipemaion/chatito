import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';

/// Arquivo escolhido pelo usuário.
class PickedFile {
  const PickedFile({
    required this.path,
    required this.name,
    required this.size,
    required this.mime,
  });
  final String path;
  final String name;
  final int size;
  final String mime;
}

/// Seleção de arquivo (abstração para testes).
abstract class FilePickerService {
  /// null se o usuário cancelar.
  Future<PickedFile?> pick();

  /// Fotos e vídeos da galeria (vários de uma vez); vazio se cancelar.
  Future<List<PickedFile>> pickMedia();
}

/// Abre um arquivo local com o app padrão do sistema.
abstract class FileOpener {
  Future<void> open(String path);
}

/// Lê os bytes de um arquivo já escolhido (abstração para testes — real I/O
/// de disco dentro de um widget test trava sob o relógio falso do
/// `flutter_test`, mesmo dentro de `tester.runAsync`).
abstract class FileReader {
  Stream<List<int>> openRead(String path);
}

class SystemFilePicker implements FilePickerService {
  const SystemFilePicker();

  @override
  Future<PickedFile?> pick() async {
    final f = await FilePicker.pickFile();
    final path = f?.path;
    if (f == null || path == null) return null;
    return PickedFile(
      path: path,
      name: f.name,
      size: await f.length(),
      mime: mimeFromName(f.name),
    );
  }

  @override
  Future<List<PickedFile>> pickMedia() async {
    final files = await FilePicker.pickFiles(type: FileType.media);
    final out = <PickedFile>[];
    for (final f in files) {
      final path = f.path;
      if (path == null) continue;
      out.add(
        PickedFile(
          path: path,
          name: f.name,
          size: await f.length(),
          mime: mimeFromName(f.name),
        ),
      );
    }
    return out;
  }
}

class SystemFileOpener implements FileOpener {
  const SystemFileOpener();

  @override
  Future<void> open(String path) async {
    final r = await OpenFilex.open(path);
    if (r.type != ResultType.done) {
      throw Exception(r.message);
    }
  }
}

class SystemFileReader implements FileReader {
  const SystemFileReader();

  @override
  Stream<List<int>> openRead(String path) => File(path).openRead();
}

/// MIME simples por extensão (o núcleo pode refinar).
String mimeFromName(String name) {
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  return switch (ext) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'gif' => 'image/gif',
    'webp' => 'image/webp',
    'heic' => 'image/heic',
    'mp4' => 'video/mp4',
    'mov' => 'video/quicktime',
    'mp3' => 'audio/mpeg',
    'm4a' => 'audio/mp4',
    'pdf' => 'application/pdf',
    'txt' => 'text/plain',
    'zip' => 'application/zip',
    _ => 'application/octet-stream',
  };
}

final filePickerProvider = Provider<FilePickerService>(
  (_) => const SystemFilePicker(),
);
final fileOpenerProvider = Provider<FileOpener>(
  (_) => const SystemFileOpener(),
);
final fileReaderProvider = Provider<FileReader>(
  (_) => const SystemFileReader(),
);
