/// Camada `crypto`: só primitivas de alto nível do libsodium (PROTOCOL.md §2).
///
/// Dart puro. Em produção o [Sodium] vem de `sodium_libs` (`SodiumInit.init()`
/// em `platform/`); nos testes, do binário nativo via `package:sodium`.
library;

export 'crypto_box.dart';
export 'file_cipher.dart';
export 'sodium_crypto_box.dart';
export 'sodium_file_cipher.dart';
