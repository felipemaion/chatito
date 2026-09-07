/// Camada `storage`: banco local (drift/SQLite) e cofre de chaves.
///
/// Dart puro. Em produção: `ChatDatabase(driftDatabase(...))` de `drift_flutter`
/// e um `KeyStore` sobre `flutter_secure_storage` (ambos instanciados em `platform/`).
library;

export 'chat_database.dart';
export 'key_store.dart';
