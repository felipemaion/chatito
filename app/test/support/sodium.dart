import 'package:sodium/sodium.dart';

Sodium? _cached;

/// libsodium via native assets do pacote `sodium` 4.x (compilado por build
/// hook na primeira execução, igual em app e testes — não usa mais
/// `sodium_libs`, nem caminho de biblioteca do sistema).
Future<Sodium> loadSodium() async => _cached ??= await SodiumInit.init();
