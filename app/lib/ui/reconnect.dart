import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/domain.dart';
import 'providers.dart';

/// Espera entre a 1ª falha de sessão e a tentativa de confirmação — protege
/// contra uma falha isolada/transitória (rede piscando) sem esperar tanto
/// que o usuário note.
const sessionInvalidRetryDelay = Duration(seconds: 2);

/// Pede à fachada para reconectar. `ensureConnected()` (ao contrário de
/// `connect()`) espera o carregamento inicial da sessão (`_ready` no
/// `RealChatFacade`) terminar antes de decidir, e cancela uma tentativa
/// travada/backoff em andamento — pensado exatamente para sinais explícitos
/// como este (botão, resume, push, rede voltando).
Future<void> requestReconnect(ChatFacade facade) => facade.ensureConnected();

/// `true` quando o erro de `requestReconnect` indica que a sessão local não é
/// mais utilizável (ex.: token ausente/expirado no keychain).
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
/// 1. **Só age se `sessionProvider` já emitiu "registrado"** — sem isto, um
///    aparelho que nunca foi registrado (`not_registered` genuíno, ex.:
///    resume enquanto ainda está no onboarding) acabaria mostrando "sua
///    sessão expirou" para quem nunca teve sessão nenhuma. `ensureConnected`
///    já protege contra a corrida de inicialização em si (espera `_ready` no
///    `RealChatFacade`); esta guarda é sobre *quem nunca se registrou*, um
///    caso diferente que continua legítimo.
/// 2. **Confirmação por persistência**: só marca `sessionInvalidProvider`
///    verdadeiro se o mesmo erro persistir numa 2ª tentativa,
///    [sessionInvalidRetryDelay] depois — uma falha isolada não é motivo
///    para mandar ninguém para o onboarding.
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
