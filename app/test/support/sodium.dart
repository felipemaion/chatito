import 'dart:ffi';
import 'dart:io';

import 'package:sodium/sodium.dart';

Sodium? _cached;

/// Carrega o libsodium nativo para testes na VM (não usa `sodium_libs`).
/// Ordem: `LIBSODIUM_PATH` → caminhos padrão por SO.
Future<Sodium> loadSodium() async {
  if (_cached != null) return _cached!;
  final env = Platform.environment['LIBSODIUM_PATH'];
  final candidates = [
    ?env,
    if (Platform.isMacOS) ...[
      '/opt/homebrew/lib/libsodium.dylib',
      '/usr/local/lib/libsodium.dylib',
      'libsodium.dylib',
    ],
    if (Platform.isLinux) ...[
      '/usr/lib/x86_64-linux-gnu/libsodium.so.23',
      '/usr/lib/aarch64-linux-gnu/libsodium.so.23',
      '/usr/lib/libsodium.so.23',
      '/usr/lib/libsodium.so',
      'libsodium.so.23',
      'libsodium.so',
    ],
    if (Platform.isWindows) ...['libsodium.dll'],
  ];
  Object? lastError;
  for (final path in candidates) {
    try {
      final lib = DynamicLibrary.open(path);
      return _cached = await SodiumInit.init(() => lib);
    } on Object catch (e) {
      lastError = e;
    }
  }
  throw StateError(
    'libsodium não encontrado (tentei: $candidates). '
    'Instale (brew install libsodium / apt-get install libsodium23) '
    'ou defina LIBSODIUM_PATH. Último erro: $lastError',
  );
}
