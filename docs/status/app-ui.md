# Status — agente app-ui
## Feito
- **1. Dependências** (`app/pubspec.yaml` alterado): flutter_riverpod, go_router, flutter_local_notifications,
  window_manager, file_picker, qr_flutter, mobile_scanner, firebase_messaging, firebase_core,
  flutter_localizations (sdk), intl, open_filex (abrir anexo com app do sistema).
- **Contrato provisório** `app/lib/ui/contracts.dart` (Dart puro) + fake em memória
  `app/lib/ui/fake/fake_chat_facade.dart` com testes (`test/ui/fake_chat_facade_test.dart`).
- **2. Tema + layout responsivo**: `ui/theme.dart` (M3, claro/escuro), `ui/layout.dart` (breakpoint 720),
  `ui/app.dart` (pt-BR), `ui/providers.dart` (riverpod), `ui/router.dart` (go_router com redirect p/ onboarding),
  `screens/home_shell.dart` (desktop = lista + chat; celular = pilha), lista de conversas. Testes em `test/ui/app_test.dart`.
- **3a. Onboarding** (`screens/onboarding_screen.dart`): convite formatado `XXXX-XXXX`, nome do device
  sugerido pela plataforma (`platform/platform_info.dart`), erros do núcleo exibidos; redirect automático.
- **3b/4. Chat** (`screens/chat_screen.dart` + `widgets/{message_bubble,attachment_tile,composer,receipt_icon}.dart`):
  bolhas, nome do remetente em grupo, recibos (relógio/✓/✓✓/✓✓ azul/erro), anexos com preview de imagem,
  progresso de upload/download, Baixar/Abrir (via `platform/files.dart`: `file_picker` + `open_filex`,
  abstraídos em providers p/ teste), Enter envia no desktop, markRead ao abrir e ao receber.
  Testes: `test/ui/chat_test.dart`, `test/ui/onboarding_test.dart`, `test/ui/format_test.dart`.
- **3c. Contato + Ajustes**: `screens/contact_detail_screen.dart` (aparelhos do contato, safety number
  60 dígitos + QR via `qr_flutter`, leitura de QR via `platform/qr_scanner.dart` com `mobile_scanner`
  em Android/macOS, resultado conferem/não conferem, botão Conversar); `screens/settings_screen.dart`
  (meus aparelhos c/ remoção confirmada, switch de notificações em `ui/settings.dart`, sobre).
  Testes: `test/ui/contact_detail_test.dart`, `test/ui/settings_test.dart`.
- **5. Notificações + bootstrap**: `ui/notification_coordinator.dart` (Dart puro: notifica mensagens recebidas
  fora da conversa aberta/foreground, respeita preferência, toque abre a conversa), `platform/notifications.dart`
  (`flutter_local_notifications` macOS/Windows/Android/Linux), `platform/push.dart` (`FirebasePushWaker` só no
  Android: `Firebase.initializeApp()` em try/catch — sem `google-services.json` o app segue; `{"type":"wake"}`
  → `facade.sync()`; token → `facade.setPushToken`), `platform/app_services.dart` (liga tudo + sync ao voltar
  ao foreground), `platform/window.dart` (tamanho mínimo/título no desktop), `main.dart` real.
  Testes: `test/ui/notification_coordinator_test.dart`, `test/ui/push_test.dart`.
- **6. Widget tests**: 64 testes em `app/test/ui/` (+ smoke). `flutter analyze --fatal-infos` e
  `dart format --set-exit-if-changed` limpos. Cobertura total 83% (UI/plataforma incluídas); os wrappers
  de plugin (`platform/{notifications,push,files,qr_scanner,window}.dart`) ficam fora do gate do CI.
  Golden tests não feitos (opcional).
## Em andamento
- (nada) — PR aberto, aguardando review/merge.
## Bloqueios
- **Android não compila sem 1 ajuste fora do meu escopo** (`app/android/app/build.gradle.kts`):
  `flutter_local_notifications` exige core library desugaring. Patch (validado localmente com
  `flutter build apk --debug`, ver "Verificações" abaixo):
  ```kotlin
  android { compileOptions { /* … */ isCoreLibraryDesugaringEnabled = true } }
  dependencies { coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4") }
  ```
  Não apliquei porque `app/android/**` não está no escopo do app-ui. O CI de PR só builda desktop.
- **macOS não pôde ser buildado nesta máquina** (sem Xcode completo/CocoaPods; só command-line tools).
  O job `build-desktop` do CI (macos-latest/windows-latest) é a verificação. Riscos conhecidos:
  `mobile_scanner` no macOS precisa de entitlement de câmera (`com.apple.security.device.camera`)
  e `NSCameraUsageDescription` no `Info.plist` — só relevante quando o QR scanner for usado no Mac.
- **Push em background**: o handler de background do FCM roda em isolate separado, sem acesso à fachada;
  a sincronização acontece ao voltar ao primeiro plano (`AppServices`) ou por `onMessage` em foreground.
  Para sync headless, o app-core precisa expor uma inicialização sem UI (proposta p/ Fase 2).
- **Preferência de notificações** é em memória (`InMemorySettingsStore`); o storage do app-core pode
  fornecer implementação durável via override de `settingsStoreProvider`.
- `main.dart` roda com `FakeChatFacade.seeded(autoReply: true)` até o app-core expor a fachada real
  (trocar 1 linha no `ProviderScope`).
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
