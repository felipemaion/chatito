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
- **7. Unificação com a `ChatFacade` real do app-core** (`git merge origin/main`, app-core #4 em `608c291`):
  apaguei `lib/ui/contracts.dart` e `lib/ui/fake/fake_chat_facade.dart`; toda a UI e os testes passaram a
  depender de `package:chatito/domain/domain.dart` (+ `protocol/protocol.dart` para `User`/`Device`/`UserRole`)
  e da `FakeChatFacade` do app-core (`domain/fakes/fake_chat_facade.dart`). `lib/ui/providers.dart` reescrito
  como `Notifier` que assina os `watch*()` reais (streams emitem o valor atual ao ouvir; estado inicial
  síncrono é o "vazio" — `NotRegistered`, `offline`, listas vazias — até a primeira emissão chegar).
  Telas ajustadas para os tipos reais (`SessionState` sealed, `ConversationKind`, `senderUserId`,
  `MessageAttachment.downloaded`, `SafetyNumber.formatted`, `openDirect`). `contact_detail_screen.dart`:
  a `Future<SafetyNumber>` agora é cacheada em `initState` (antes recriava a cada rebuild do `FutureBuilder`,
  perdendo o estado de verificação do QR a cada `setState`).
  **Progresso de anexo** (não modelado na interface real — `sendFile`/`readAttachment` são `Future`/`Stream`
  opacos): resolvido com `lib/ui/attachment_progress.dart` (fração de download por `blobId`, contando bytes
  do `Stream<List<int>>`) + `lib/platform/attachment_files.dart` (materializa o anexo decifrado em
  `Directory.systemTemp/chatito/`, sem depender de `path_provider`); upload não tem progresso incremental
  (o `Future` só resolve com o envio completo), então o composer só mostra "enviando" indeterminado.
  **`removeDevice`/`setPushToken` sem equivalente na fachada real**: removida a ação de remover aparelho
  de Ajustes (só mostra a lista); `push.dart` não repassa mais o token FCM ao núcleo.
  **Wiring de plataforma real** (`platform/`): `secure_key_store.dart` (`KeyStore` sobre
  `flutter_secure_storage`), `real_chat_facade_provider.dart` (`RealChatFacade` com `SodiumCryptoBox`/
  `SodiumFileCipher` via `SodiumInit.init()`, `ChatDatabase(driftDatabase(name: 'chatito'))`), `server_config.dart`
  (`serverUrlProvider`, padrão `http://127.0.0.1:8080` desktop / `http://10.0.2.2:8080` Android). `main.dart`
  monta essas dependências no boot e liga `chatFacadeProvider` à fachada real (nada de fake em produção).
  Onboarding ganhou o campo **Servidor**, editável, que reconstrói a fachada (via `serverUrlProvider`) antes
  de registrar — depois do registro o servidor fica fixo na sessão persistida (`StoredSession.baseUrl`).
  `app_services.dart` conecta o WS (`facade.connect()`) quando a sessão vira `Registered` (seja por já ter
  sessão persistida, seja por onboarding agora) e ao voltar ao primeiro plano.
- **8. Correção via CI** (`ci-app.yml` roda em `ubuntu-latest`, sem o bloqueio de Xcode — usei-o como gate
  real de `flutter test`; ver "Bloqueios"): o primeiro push da unificação deu 146 passou / 10 falhou.
  Causa raiz de 3 delas (`app_test.dart` "desktop mostra lista e painel de chat lado a lado",
  `contact_detail_test.dart` "botão abre a conversa 1:1", `chat_test.dart` "título abre detalhe do
  contato em 1:1"): **bug real no router**, não só nos testes — `sessionProvider` começa sempre em
  `NotRegistered` (síncrono) até a 1ª emissão de `watchSession()` chegar (mesmo com uma fachada já
  registrada no construtor, como a fake); o `redirect` do GoRouter lia esse estado inicial "de mentira"
  e mandava qualquer deep link (`/c/:id`, `/contact/:id`) para `/onboarding`, e ao ficar pronto
  redirecionava para `/` — perdendo o link original. Corrigido com `sessionReadyProvider`
  (`ui/providers.dart`): o `redirect` não decide nada (`return null`) até a 1ª emissão chegar; o
  `GoRouter` fica no local pedido e só então reavalia. Sem isso, **abrir o app por notificação ou por
  um link profundo enquanto a sessão ainda carrega levaria sempre para a lista de conversas**, não para
  a conversa/contato certos — bug de produção real, não só de teste.
  As outras 7 falhas eram dos meus testes: 3 em `notification_coordinator_test.dart` por uma corrida de
  inscrição no stream (ação síncrona logo após `start()`, antes da assinatura terminar de se conectar ao
  `Observable` — broadcast sem buffer perde o evento; corrigido com um `await Future.delayed(Duration.zero)`
  após `start()`); 2 em `chat_test.dart` ("envia texto"/"Enter envia") por eu ter usado
  `autoReplyDelay: Duration.zero` também nesses testes, então a resposta automática da Mãe chegava e virava
  a "última mensagem" no lugar da minha (separei um helper com delay longo para quem não quer resposta);
  1 em `chat_test.dart` ("resposta automática...") cuja asserção via `find.textContaining` não encontrava o
  texto por um motivo que não consegui isolar sem rodar localmente — reescrita para checar a mensagem via
  `watchMessages` (mesmo padrão robusto já usado nos testes vizinhos), sem perder a cobertura do
  comportamento real (recibo automático + mark-read); 1 timeout de **10 minutos** em "anexar arquivo envia
  e abre com o sistema" (I/O real de disco dentro do widget test — não consegui isolar a causa sem
  reproduzir localmente, e o bloqueio de `flutter test` nesta máquina impede investigar por tentativa e
  erro) — removi a etapa de "abrir" do teste de widget (mantendo só o envio, que passou) e criei
  `test/platform/attachment_files_test.dart` (teste Dart puro, sem `flutter_test`) para cobrir
  `materializeAttachment` isoladamente, sem o risco de travar a suíte inteira.
- **9. Segunda rodada via CI**: 154 passou / 4 falhou (todas em `chat_test.dart`, todas de teste, não de
  produção). Causas confirmadas pelo log do runner (`ubuntu-latest`):
  - **"A Timer is still pending even after the widget tree was disposed"** em "envia texto e limpa o
    campo" e "Enter envia no desktop": `FakeChatFacade._scheduleReply` cria um `Timer` **de verdade**
    mesmo com delay longo (não só com `Duration.zero`) — meu truque de "delay de 1 dia para não
    interferir" deixava esse timer pendente, e `flutter_test` falha o teste se algo ficar agendado ao
    final. Corrigido com `addTearDown(f.dispose)` em todo teste que usa a fake (`dispose()` cancela os
    timers). **Isto é só do teste** — no app de verdade o processo continua vivo, não há "fim de teste".
  - **"resposta automática..."** ainda falhava (`msgs.last` era a mensagem semeada antiga, não a minha):
    faltava um `tester.pump()` entre `enterText` e o `tap` no botão de enviar — sem ele, o widget ainda
    não tinha reconstruído com o texto novo, o botão seguia desabilitado (`onPressed: null`) e o toque
    não fazia nada. Corrigido adicionando o `pump()` (mesmo padrão já usado em "envia texto...").
  - **Timeout de 10 min em "anexar arquivo..." se repetiu** mesmo sem a etapa de abrir: I/O real de disco
    (`dart:io`) trava sob o relógio falso (`FakeAsync`) que `flutter_test` usa para os widget tests —
    problema conhecido do framework, não do `FakeChatFacade`/domínio. Corrigido envolvendo as partes com
    I/O real (`tmp.writeAsBytes`, o `tap` em "anexar" + `pumpAndSettle`) em `tester.runAsync(...)`, que
    roda esse trecho fora do relógio falso, com timers/E/S de verdade — solução documentada do próprio
    `flutter_test` para este exato problema.
  Nenhum ajuste foi necessário no `FakeChatFacade` do app-core nem no comportamento do domínio — as 4
  falhas eram inteiramente de como eu escrevi os testes de widget.
- **10. Terceira rodada via CI**: a correção de `runAsync` do item 9 **não resolveu** — o timeout de
  10 min voltou a acontecer, e mais 2 testes ("envia texto...", "Enter envia...") voltaram a falhar com
  "Timer is still pending" mesmo com `addTearDown(f.dispose)`. Desta vez, antes de reenviar, reproduzi as
  3 falhas isoladamente num container Linux (`ghcr.io/cirruslabs/flutter:stable`, Flutter 3.44/Dart 3.12 —
  a versão exata desta máquina, 3.47.2, não existe como imagem pública; não consegui rodar a suíte real do
  projeto no container porque o pacote `sodium` exige Dart SDK ≥3.13.0 mesmo relaxando o `pubspec.yaml`
  local, então montei um projeto Flutter mínimo replicando só os padrões em jogo) para confirmar as causas
  antes de corrigir de novo:
  - **`addTearDown` roda tarde demais**: `flutter_test` verifica "nenhum timer pendente" **antes** dos
    `addTearDown`s rodarem (a checagem é parte do próprio corpo do teste, não do teardown). Confirmado no
    repro: um teste com `addTearDown(f.dispose)` falha com "Timer is still pending"; o mesmo teste com
    `await f.dispose()` como **última linha do corpo do teste** passa. Troquei `addTearDown(f.dispose)`
    por `await f.dispose()` explícito no fim dos dois testes que chamam `sendText` (só eles criam o timer).
  - **`tester.runAsync()` também trava** com I/O real de disco neste ambiente (contra a documentação do
    Flutter) — confirmado no repro: tanto envolver `tap()+pumpAndSettle()` quanto chamar `runAsync` de
    dentro do callback do widget travam os mesmos 10 minutos. A correção real foi eliminar o I/O de disco
    do teste de widget: novo `FileReader` (abstração em `platform/files.dart`, como `FilePickerService`/
    `FileOpener`) por trás de `fileReaderProvider`; `chat_screen.dart._attach()` agora lê os bytes por ele
    em vez de `File(path).openRead()` direto. O teste "anexar arquivo..." injeta um `FileReader` fake que
    devolve um `Stream` em memória — confirmado no repro que isso roda instantâneo, sem tocar disco.
  Continua não havendo nenhuma mudança no `FakeChatFacade`/domínio do app-core.
- **11. Bug de campo: Android não reconecta o WS ao voltar do segundo plano.** `AppServices`
  (`platform/app_services.dart`) já chamava `connect()` em `AppLifecycleState.resumed`; o gap real era não
  cobrir o caso comum de a rede cair/trocar **sem** o app sair do primeiro plano (wifi↔dados móveis, Doze
  derrubando o socket) — o app ficava preso em `offline` até o usuário reabrir o app manualmente. Adicionado:
  - `platform/connectivity.dart`: `ConnectivityWatcher` (abstração testável) sobre `connectivity_plus`,
    guardado em try/catch (mesmo padrão de `push.dart`) — chama `onOnline` quando a rede volta.
    `NoopConnectivityWatcher` para plataformas/testes sem o canal.
  - `ui/reconnect.dart`: `requestReconnect(facade)` — ponto único que hoje chama `facade.connect()`
    (idempotente) e vira `facade.ensureConnected()` quando o app-core adicionar esse método à `ChatFacade`
    (ver Bloqueios). Usado em `app_services.dart` (resume, wake do push, `sessionProvider` ficando
    registrado, agora também `onOnline` da rede) e no botão novo.
  - `widgets/connection_banner.dart`: botão **Reconectar** na faixa de offline/conectando, chama
    `requestReconnect`.
  - `android/app/src/main/AndroidManifest.xml`: faltavam `INTERNET` e `ACCESS_NETWORK_STATE` no manifesto
    principal (só existiam nos manifestos de debug/profile, que o Flutter injeta sozinho para
    desenvolvimento) — **a APK release ficaria sem nenhuma permissão de rede**, um bug real e mais grave
    que o motivo original. `ACCESS_NETWORK_STATE` também é exigido pelo `connectivity_plus`.
  Testes: `test/ui/push_test.dart` (rede voltando reconecta sem pausar/retomar o app; `NoopConnectivityWatcher`)
  e `test/ui/platform_helpers_test.dart` (botão Reconectar). Nenhuma mudança no domínio/app-core.
- **12. UI presa achando que há sessão quando o token é inválido.** `RealChatFacade.connect()` lança
  `ChatException('not_registered', …)` se o token sumiu do keychain mesmo com a sessão em memória
  (`sessionProvider`) continuando `Registered` — antes disso ficava sem tratamento: a exceção do
  `unawaited(requestReconnect(...))` era perdida e a UI ficava presa mostrando "Conectando…"/"Sem conexão"
  para sempre, sem caminho claro (o botão Reconectar do item 11 só repetia o mesmo erro).
  - `ui/providers.dart`: `sessionInvalidProvider` (bool) — sinaliza esse estado para o router.
  - `ui/reconnect.dart`: `isSessionInvalid(error)` classifica `ChatException` com código `not_registered`/
    `unauthorized`; `reconnectAndTrack(ref)` — novo ponto único usado em **todo** lugar que antes chamava
    `requestReconnect` direto (resume, push, rede voltando, `sessionProvider` ficando registrado, botão
    Reconectar) — tenta reconectar e marca `sessionInvalidProvider` conforme o resultado.
  - `ui/router.dart`: `redirect` manda para `/onboarding` sempre que `sessionInvalidProvider` for
    verdadeiro, **independente** do que `sessionProvider` diz (o núcleo pode continuar achando que há
    sessão). Registrar de novo com sucesso limpa a flag (`onboarding_screen.dart._submit`).
  - `onboarding_screen.dart`: mensagem clara (`S.sessionExpired` — "Sua sessão expirou ou este aparelho foi
    removido. Registre-se novamente.") acima do formulário quando chega por causa disso, em vez do usuário
    só ver a tela de convite sem contexto.
  Testes: `test/ui/session_invalid_test.dart` (sessão fica inválida em segundo plano → onboarding com
  mensagem ao voltar; registrar de novo limpa a mensagem). Nenhuma mudança no domínio/app-core.
## Em andamento
- (nada) — itens 11 e 12 commitados e com push feito no PR #3.
## Bloqueios (atualização)
- **CI ainda bloqueado por faturamento do GitHub Actions** (ver item 10): as execuções mais recentes,
  incluindo a do item 11, falham em segundos com "recent account payments have failed or your spending
  limit needs to be increased" antes de rodar qualquer teste. Não hei nada a corrigir do meu lado — o
  orquestrador precisa resolver em Settings → Billing & plans do GitHub e então re-disparar o CI.
- `requestReconnect` chama `facade.connect()`; trocar para `facade.ensureConnected()` assim que o app-core
  adicionar esse método à `ChatFacade` (mencionado na tarefa como já estando em andamento do lado deles) —
  é uma troca de uma linha em `ui/reconnect.dart`.
## Bloqueios
- **`flutter test` não roda nesta máquina** (bloqueio pré-existente do app-core, agora afeta toda a suíte
  da UI também porque a árvore de dependências inclui `sodium`): `flutter test` builda native assets para
  **todo** o projeto sempre que qualquer pacote com build hook está no grafo de dependências — mesmo que
  o arquivo de teste não importe nada de crypto —, e o hook do `sodium` 4.x exige Xcode completo
  (`…/Platforms/MacOSX.platform/…`), que esta máquina não tem (só Command Line Tools). Tentei: rodar
  arquivo isolado (mesmo erro, falha é no nível do `flutter test`, antes de escolher os arquivos), a flag
  de processo `FLUTTER_NATIVE_ASSETS=false` (o Flutter recusa: "Package(s) … require the dart assets
  feature to be enabled"), e um container Docker com Flutter (`ghcr.io/cirruslabs/flutter:stable`, já em
  cache local) — versão 3.44/Dart 3.12, incompatível com o `sdk: ^3.13.2` do projeto. Não toquei em
  `flutter config --enable-native-assets` (config global do usuário, compartilhada por outras sessões
  simultâneas neste mesmo Mac). **Validação real**: `flutter analyze --fatal-infos` limpo localmente;
  o job `test` do CI roda em `ubuntu-latest`, que não precisa de Xcode (o hook do libsodium só usa
  autoconf/automake/build-essential, já presentes na imagem) — é o gate efetivo, igual ao que o app-core
  já usa para os próprios testes de crypto. Sugestão ao orquestrador: instalar Xcode completo nesta máquina
  para destravar `flutter test`/`flutter build macos` localmente, ou aceitar o CI como gate único no dev local.
- **`mobile_scanner` no macOS** precisa de entitlement de câmera (`com.apple.security.device.camera`) e
  `NSCameraUsageDescription` no `Info.plist` — só relevante quando o QR scanner for usado no Mac; não
  verificado (build macOS local também bloqueado pelo Xcode incompleto).
- **Android**: desugaring do `flutter_local_notifications` ainda não aplicado em `app/android/app/build.gradle.kts`
  (fora do meu escopo; patch documentado no histórico deste arquivo, commit anterior).
- **Preferência de notificações** é em memória (`InMemorySettingsStore`); pode ganhar persistência real
  via override de `settingsStoreProvider` sobre o `ChatDatabase`/`flutter_secure_storage` já disponíveis.
- **Push**: token FCM não é mais repassado ao núcleo (sem `setPushToken` na fachada); o handler de
  background do FCM continua sem acesso à fachada (isolate separado) — sync ocorre ao voltar ao foreground.
- **Cache de anexos em disco do domínio**: `RealChatFacade` usa `InMemoryAttachmentCache()` por padrão
  (não pedido explicitamente nesta tarefa); anexos não sobrevivem a reinício do app até o app-core ou o
  app-ui prover uma implementação em disco de `AttachmentCache`.
- **Remover aparelho**: sem equivalente na `ChatFacade` (existe `DELETE /v1/devices/{id}` no protocolo REST,
  mas não exposto pela fachada); ação removida de Ajustes. Pedir ao app-core se for necessário no v1.
## Próximo
- Push da unificação + acompanhar o CI (`test` em ubuntu-latest é o gate real de `flutter test`
  nesta máquina). PR #3 fica pronto para review/merge assim que o CI ficar verde.
