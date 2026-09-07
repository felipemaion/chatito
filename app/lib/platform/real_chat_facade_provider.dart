import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sodium/sodium.dart';

import '../crypto/crypto.dart';
import '../domain/domain.dart';
import '../domain/real_chat_facade.dart';
import '../storage/storage.dart';
import 'server_config.dart';

/// Dependências pesadas da fachada real, montadas uma vez em `main.dart`
/// (inicialização do libsodium e abertura do banco são assíncronas).
class RealChatDeps {
  const RealChatDeps({
    required this.sodium,
    required this.db,
    required this.keyStore,
  });
  final Sodium sodium;
  final ChatDatabase db;
  final KeyStore keyStore;
}

final chatDepsProvider = Provider<RealChatDeps>(
  (_) => throw UnimplementedError('chatDepsProvider não foi sobrescrito'),
);

/// Fachada real. Reconstruída se [serverUrlProvider] mudar — só importa antes
/// do registro, já que depois a sessão persistida fixa o servidor usado.
final realChatFacadeProvider = Provider<ChatFacade>((ref) {
  final deps = ref.watch(chatDepsProvider);
  final baseUrl = ref.watch(serverUrlProvider);
  final facade = RealChatFacade(
    cryptoBox: SodiumCryptoBox(deps.sodium),
    fileCipher: SodiumFileCipher(deps.sodium),
    db: deps.db,
    keyStore: deps.keyStore,
    baseUrl: baseUrl,
  );
  ref.onDispose(() => unawaited(facade.dispose()));
  unawaited(facade.init());
  return facade;
});
