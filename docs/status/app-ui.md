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
## Plano de unificação (ChatFacade real do app-core, ainda não codado)

Fonte: `origin/feat/app-core` — `docs/status/app-core.md` + `app/lib/domain/{chat_facade,models}.dart`.
Interface real é Dart puro (`domain/domain.dart`), com `FakeChatFacade` própria do app-core
(`domain/fakes/fake_chat_facade.dart`). Ao mesclar, uso essa em vez da minha.

### Diferenças de forma (afetam tudo)
- **`Watchable<T>` (meu) → `Future<T> get` + `Stream<T> watch*()` (real)**. Não existe leitura síncrona
  de valor atual; a stream real "emite o valor atual imediatamente ao ouvir" — então todo provider vira
  `StreamProvider`/`StreamNotifier` em vez do meu `Notifier` com `bind()` síncrono.
- **`SessionState` vira sealed class** `NotRegistered | Registered(user, device)` em vez do meu
  `SessionState({me})` com `isRegistered`/`me` nullable. `me.user`/`me.device` → `registered.user`/`.device`.
- **`ConnectionState` já existe com esse nome exato** (`offline|connecting|online`) — não preciso mais do
  meu apelido `RelayState` (renomeei por colisão com `flutter/async.dart`); ao unificar, ou volto a usar
  o import escondido (`show ConnectionState`) ou mantenho o prefixo — decidir na hora, é find&replace.
- **`Conversation.kind: ConversationKind.direct|group`** em vez do meu `isGroup: bool`.
- **`Message.senderUserId`/`senderDeviceId`** em vez de `fromUserId`/`fromDeviceId`.
- **`Attachment` → `MessageAttachment`**, sem `localPath` nem `transfer` (progresso). Tem só `downloaded: bool`.
  **Progresso de upload/download não existe na interface real.** `sendFile`/`readAttachment` são
  `Future`/`Stream<List<int>>` opacos — preciso inferir estado (`uploading` enquanto o Future não resolve,
  `downloading` enquanto a Stream não fecha) e não tenho mais `%` a menos que eu conte bytes eu mesmo.
- **Sem `DeviceInfo` avulso**: devices vêm dentro de `User.devices` (protocolo) e de `Contact.devices`
  (domínio) — meu `DeviceInfo{id,userId,name,platform,identityKey,createdAt}` vira `protocol.Device`
  (mesmos campos, mas `userId` é nullable e pode faltar dentro de `directory`).
- **`UserInfo` → `Contact{user: protocol.User, devices: List<Device>}`**; `role` é enum `UserRole.admin|member`,
  não string — perco meu `UserInfo.isAdmin` getter, viro `contact.user.role == UserRole.admin`.
- **`safetyNumber` devolve `SafetyNumber{digits, formatted}`**, não `String` pronta — troco
  `f.safetyNumber(id)` por `(await f.safetyNumber(id)).formatted` nos usos de exibição.
- **`markRead` fecha (`Future<void>`)** igual; **`sync()` não existe** — vira `connect()`/`disconnect()`
  (WS + drena outbox) — meu `push wake → facade.sync()` vira `push wake → facade.connect()`.
- **`removeDevice` e `setPushToken` não existem na interface real** — ficam sem equivalente por ora
  (fora do escopo do app-core v1). Preciso remover a ação "remover aparelho" da tela de Ajustes ou
  deixá-la desabilitada com aviso, e não chamar mais `setPushToken` no `platform/push.dart`.
- **`register` não devolve `Identity`** (é `Future<void>`); depois de chamar, releio `session`/`watchSession()`
  para pegar o `Registered`. A tela de onboarding não usa mais o retorno para navegar — só aguarda sem erro
  e deixa o router redirecionar pela mudança de `SessionState`.
- **`openDirect(userId)`** é novo: hoje eu calculo `conv_id` 1:1 na mão (`_dmId` em
  `contact_detail_screen.dart`, ordenando os dois ids). Trocar pela chamada real (o núcleo sabe a regra
  `u:...` do protocolo) e apagar `_dmId`.
- **`dispose()`** é novo — chamar ao encerrar o app (não tenho hoje).
- **`ChatException` é quase igual** (`code`, `message`) — dá para reusar a lógica de exibição como está.

### Arquivo a arquivo

| Arquivo | O que muda |
| --- | --- |
| `lib/ui/contracts.dart` | **Apagar inteiro.** `Watchable`/`ValueStream`/`ChatFacade`/`ChatException`/modelos ficam substituídos por `package:chatito/domain/domain.dart` + `package:chatito/protocol/protocol.dart` (para `User`/`Device`/`UserRole`). |
| `lib/ui/fake/fake_chat_facade.dart` | **Apagar.** Usar `FakeChatFacade` do app-core (`domain/fakes/fake_chat_facade.dart`) — já tem `g:familia` + 1:1 com a Mãe, autoReply configurável, `badInvite` para testar erro. Ajustar `main.dart` e `test/ui/helpers.dart` para importar de lá. |
| `lib/ui/providers.dart` | Reescrever todos os `Notifier`+`WatchableBinder` como `StreamNotifier`/`StreamProvider` sobre os `watch*()` reais. `sessionProvider` passa a expor `SessionState` sealed (pattern match `switch`); adicionar getter de conveniência (extension `isRegistered`/`me` se eu quiser manter a ergonomia nas telas sem reescrever tudo). |
| `lib/ui/format.dart` | `previewOf`: trocar `m.kind`/`m.attachments` pelos nomes reais (`MessageKind` já bate; `attachments.first.name` já bate). Nenhuma mudança de lógica, só tipos. |
| `lib/ui/screens/onboarding_screen.dart` | `register()` não devolve mais `Identity`; remover uso do retorno, manter só `try/on ChatException`. |
| `lib/ui/screens/conversations_screen.dart` | `conv.isGroup` → `conv.kind == ConversationKind.group`. |
| `lib/ui/screens/chat_screen.dart` | `m.fromUserId`→`senderUserId` etc. `sendFile`: preciso abrir o arquivo local como `Stream<List<int>>` (ex. `File(path).openRead()`) e passar `size` do `PickedFile`. `downloadAttachment` some — vira `readAttachment(messageId, blobId)` retornando bytes; preciso decidir onde gravar em disco (a UI passa a ser dona do cache local, já que `localPath`/`transfer` não existem mais no domínio) — provavelmente um novo `platform/attachment_cache.dart` que grava a stream em `/tmp/chatito/<blobId>` e reporta progresso por contagem de bytes recebidos vs `attachment.size`. Isso também cobre o "progresso" que a interface real não modela. |
| `lib/ui/screens/contact_detail_screen.dart` | Remover `_dmId`, usar `facade.openDirect(userId)`. `UserInfo`→`Contact`, `isAdmin`→`user.role == UserRole.admin`. `safetyNumber(id).formatted` no lugar da `String` direta. |
| `lib/ui/screens/settings_screen.dart` | Remover a ação de remover aparelho (sem equivalente) ou marcar como indisponível nesta versão; registrar isso como bloqueio novo se o usuário quiser a função de volta (pedir ao app-core para expor `removeDevice`, que existe no protocolo REST `DELETE /v1/devices/{id}` mas não na fachada). |
| `lib/platform/push.dart` | `facade.sync()` → `facade.connect()`; remover `facade.setPushToken` (sem equivalente — ou manter local só para lembrar o token, sem repassar ao núcleo, até o app-core expor `PUT /v1/devices/me/push` na fachada). |
| `lib/ui/widgets/attachment_tile.dart`, `message_bubble.dart` | Passam a receber o novo modelo de progresso (do `attachment_cache`, não mais `attachment.transfer`); ajustar props. |
| Todos os testes em `test/ui/*.dart` e `test/ui/helpers.dart` | Reescrever para a `FakeChatFacade` real e os novos tipos; `pumpApp`/`pumpScreen` trocam o import do fake. Muitos `expect` sobre `isGroup`, `fromUserId`, `attachment.transfer.state`, `safetyNumber` como `String` direta vão quebrar e precisam de ajuste mecânico. |

### Ordem sugerida de execução (quando app-core estiver em `main`)
1. Apagar `contracts.dart` + fake próprio; trocar imports por `domain/domain.dart` — deixa o projeto
   vermelho (esperado).
2. Reescrever `providers.dart` (streams reais) — é a peça que desbloqueia todas as telas.
3. Corrigir telas uma a uma na ordem dos testes (`format` → `onboarding` → `conversations` → `chat` →
   `contact_detail` → `settings`), rodando `flutter test test/ui/<tela>_test.dart` a cada uma.
4. Resolver progresso de anexo via `platform/attachment_cache.dart` novo (com teste próprio antes).
5. `platform/push.dart`: `sync()`→`connect()`, remover `setPushToken` do fluxo (ou isolar localmente).
6. `flutter analyze --fatal-infos` + suíte completa + `dart format` antes de commitar.
7. Registrar em Bloqueios o que ficou sem equivalente (remover aparelho, setPushToken) para o orquestrador
   decidir se pede ao app-core para estender a fachada.

## Próximo
- Aguardando app-core em `main` para executar o plano acima. PR #3 ainda aberto/aguardando review.
