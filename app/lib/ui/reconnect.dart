import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/domain.dart';
import 'providers.dart';

/// Pede à fachada para reconectar. Usa `connect()` (idempotente: reabre o WS
/// e drena a outbox) até o app-core expor `ensureConnected()` na interface
/// real — trocar aqui quando existir (ver docs/status/app-ui.md).
Future<void> requestReconnect(ChatFacade facade) => facade.connect();

/// `true` quando o erro de `connect()`/`requestReconnect` indica que a sessão
/// local não é mais utilizável (ex.: `RealChatFacade.connect()` lança
/// `not_registered` se o token sumiu do keychain apesar da sessão em memória
/// dizer "registrado"). Nesse caso a UI deve mandar para o onboarding com uma
/// mensagem clara, em vez de insistir em reconectar.
bool isSessionInvalid(Object error) =>
    error is ChatException &&
    (error.code == 'not_registered' || error.code == 'unauthorized');

/// Reconecta e classifica o resultado em `sessionInvalidProvider`: usado em
/// todo ponto de reconexão (resume, push, rede voltando, botão manual) para
/// que o router saiba mandar para o onboarding em vez de deixar a UI presa em
/// "Conectando…"/"Sem conexão" quando o problema é a sessão, não a rede.
Future<void> reconnectAndTrack(WidgetRef ref) async {
  final facade = ref.read(chatFacadeProvider);
  try {
    await requestReconnect(facade);
    ref.read(sessionInvalidProvider.notifier).set(false);
  } catch (e) {
    if (isSessionInvalid(e)) {
      ref.read(sessionInvalidProvider.notifier).set(true);
    }
  }
}
