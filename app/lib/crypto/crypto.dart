/// Camada `crypto`: só primitivas de alto nível do libsodium (PROTOCOL.md §2).
///
/// Dart puro. O [Sodium] vem de `package:sodium` (^4) via `SodiumInit.init()`,
/// com libsodium compilado por build hook (native assets) — mesmo caminho em
/// app e testes, sem `sodium_libs` nem biblioteca do sistema.
library;

export 'crypto_box.dart';
export 'file_cipher.dart';
export 'sodium_crypto_box.dart';
export 'sodium_file_cipher.dart';
