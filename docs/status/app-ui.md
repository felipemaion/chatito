# Status — agente app-ui
## Feito
- **1. Dependências** (`app/pubspec.yaml` alterado): flutter_riverpod, go_router, flutter_local_notifications,
  window_manager, file_picker, qr_flutter, mobile_scanner, firebase_messaging, firebase_core,
  flutter_localizations (sdk), intl, open_filex (abrir anexo com app do sistema).
- **Contrato provisório** `app/lib/ui/contracts.dart` (Dart puro) + fake em memória
  `app/lib/ui/fake/fake_chat_facade.dart` com testes (`test/ui/fake_chat_facade_test.dart`).
## Em andamento
- 2. Tema + layout responsivo.
## Bloqueios
- `docs/status/app-core.md` ainda vazio: `ChatFacade` provisória definida por mim (ver `contracts.dart`,
  doc no topo do arquivo). Resumo: `Watchable<T>` (value + stream) para `session`, `connection`,
  `conversations`, `directory`, `messages(convId)`; métodos `register`, `sendText`, `sendFile`,
  `downloadAttachment`, `markRead`, `safetyNumber(deviceId)`, `removeDevice`, `setPushToken`, `sync`.
  Progresso de anexo vai dentro de `Message.attachments[].transfer`. Orquestrador unifica no merge.
- CI `ci-app.yml`: o gate de cobertura exclui `lib/ui/*` e `lib/main.dart`; nesta branch o
  `core.info` fica vazio (não há código de core) e o `lcov --summary` pode falhar. Sugiro ao infra
  tolerar tracefile vazio (`|| true` no summary) até o merge do app-core.
## Próximo
- Telas (onboarding, conversas, chat, contato, ajustes), anexos, notificações, widget tests.
