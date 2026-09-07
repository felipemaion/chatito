import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/domain.dart';
import 'providers.dart';

/// Espera entre a 1ª falha de sessão e a tentativa de confirmação. Curto o
/// bastante para não atrasar a UI, longo o bastante para não competir com a
/// corrida de inicialização do `RealChatFacade` (carregar o `KeyStore`).
const sessionInvalidRetryDelay = Duration(seconds: 2);

/// Pede à fachada para reconectar. Usa `connect()` (idempotente: reabre o WS
/// e drena a outbox) até o app-core expor `ensureConnected()` na interface
/// real — trocar aqui quando existir (ver docs/status/app-ui.md).
Future<void> requestReconnect(ChatFacade facade) => facade.connect();

/// `true` quando o erro de `connect()`/`requestReconnect` indica que a sessão
/// local não é mais utilizável (ex.: `RealChatFacade.connect()` lança
/// `not_registered` se o token sumiu do keychain apesar da sessão em memória
/// dizer "registrado"). Sozinho **não** é prova de sessão inválida: o mesmo
/// erro acontece na corrida normal de inicialização (a UI chama `connect()`
/// antes de o `RealChatFacade` terminar de carregar a sessão do `KeyStore`) —
/// ver `reconnectAndTrack` para a confirmação antes de agir sobre isto.
bool isSessionInvalid(Object error) =>
    error is ChatException &&
    (error.code == 'not_registered' || error.code == 'unauthorized');

/// Reconecta e classifica o resultado em `sessionInvalidProvider`, usado em
/// todo ponto de reconexão (resume, push, rede voltando, `sessionProvider`
/// registrando, botão manual).
///
/// Duas guardas contra falso positivo (identidade do device é dado real do
/// usuário — nunca a apaga automaticamente nem manda para onboarding sem ter
/// certeza):
/// 1. Só age se o stream de sessão **já emitiu** "registrado" — evita agir
///    durante a corrida de inicialização, antes do `RealChatFacade` carregar
///    o `KeyStore` (`not_registered` nesse momento é esperado, não é sessão
///    inválida).
/// 2. Só marca sessão inválida se o mesmo erro **persistir** numa 2ª
///    tentativa, [sessionInvalidRetryDelay] depois — uma falha isolada pode
///    ser só a mesma corrida ainda em curso.
Future<void> reconnectAndTrack(WidgetRef ref) async {
  if (!ref.read(sessionProvider).isRegistered) return;
  final facade = ref.read(chatFacadeProvider);
  final firstError = await _tryConnect(facade);
  if (firstError == null) {
    ref.read(sessionInvalidProvider.notifier).set(false);
    return;
  }
  if (!isSessionInvalid(firstError)) return;

  await Future<void>.delayed(sessionInvalidRetryDelay);
  if (!ref.read(sessionProvider).isRegistered) return;
  final secondError = await _tryConnect(facade);
  if (secondError == null) {
    ref.read(sessionInvalidProvider.notifier).set(false);
    return;
  }
  if (isSessionInvalid(secondError)) {
    ref.read(sessionInvalidProvider.notifier).set(true);
  }
}

/// `null` em sucesso; o erro caso contrário (sem relançar — quem chama decide).
Future<Object?> _tryConnect(ChatFacade facade) async {
  try {
    await requestReconnect(facade);
    return null;
  } catch (e) {
    return e;
  }
}
