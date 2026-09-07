import '../domain/domain.dart';

/// Pede à fachada para reconectar. Usa `connect()` (idempotente: reabre o WS
/// e drena a outbox) até o app-core expor `ensureConnected()` na interface
/// real — trocar aqui quando existir (ver docs/status/app-ui.md).
Future<void> requestReconnect(ChatFacade facade) => facade.connect();
