# Status — agente app-core

## Feito
- [x] 1. `pubspec.yaml`: sodium/sodium_libs, drift/drift_flutter, flutter_secure_storage, web_socket_channel,
  dio, json_annotation/json_serializable, build_runner, drift_dev, uuid, path, test. (`sqlite3_flutter_libs`
  omitido: versão `0.6.0+eol` é obsoleta; `drift_flutter` 0.3 já embute `sqlite3` v3.)
- [x] 2. `lib/protocol` — modelos + `ConvId`; contract tests round-trip exato contra **todas** as fixtures.
  `.g.dart` commitados (CI não roda `build_runner`).
- [x] 7. `lib/domain` — interface `ChatFacade`, modelos de domínio e `FakeChatFacade` (memória, determinístico).
- [x] 3. `lib/crypto` — `CryptoBox`/`SodiumCryptoBox` (passa `crypto_box_vector.json`: ciphertext, open e
  safety number) e `FileCipher`/`SodiumFileCipher` (secretstream, chunks de 64 KiB, backpressure, `cipherSize`).
  SHA-256 do safety number via `package:crypto` (o pacote `sodium` não expõe `crypto_hash_sha256`).

- [x] 4. `lib/storage` — drift (`users, devices, conversations, messages, attachments, outbox`; datas como texto
  ISO para preservar ms) + `KeyStore` (interface, `MapKeyStore` base e `InMemoryKeyStore`). Impl real sobre
  `flutter_secure_storage` é 3 métodos (`read/write/delete`) estendendo `MapKeyStore` — fica em `platform/`.

- [x] 5. `lib/transport` — `RelayApi` (dio, todo o REST, erros → `RelayException{code,statusCode}`),
  `RelayWs` (hello/envelope/ping/error, ack automático após o handler, backoff exponencial com jitter,
  para em 4401/4409), `ChunkUploader` (chunks do tamanho do servidor, retentativa por chunk, progresso).
  Testes contra `test/support/fake_relay.dart` (relay em memória que fala o protocolo v1 — reutilizável
  pelo app-ui/integração).

- [x] 6. `lib/domain` real — casos de uso (`Onboarding`, `DirectorySync`, `SendMessage` com outbox/fan-out
  e drain, `ReceiveEnvelope` com open/persistir/ack implícito, `Files` para envio/recebimento cifrado) e
  `RealChatFacade` implementando a interface documentada abaixo. Teste de ponta a ponta
  (`test/domain/real_chat_facade_test.dart`) com 2+ peers reais, relay fake e libsodium de verdade:
  onboarding, mensagens 1:1 e grupo (fan-out para os próprios devices), offline/outbox, recibos
  delivered/read, safety number, key_change (diretório e payload), dedupe por `msg_id`, arquivos
  (cifra/decifra/cache) e reconexão.

## Todas as entregas do escopo concluídas

## PR #4 — correções da revisão (aplicadas)
- `RelayWs`: envelopes recebidos agora processam em fila FIFO sequencial (um por vez, na ordem
  de chegada), não mais em paralelo sem controle. Loga quando o ack não pode ser enviado por
  queda de conexão (relay reentrega ao reconectar). Ping/pong ficam fora da fila. Testes
  novos em `test/transport/relay_ws_test.dart`.
- `ReceiveEnvelope`: comentário no caso `key_change` deixando explícito que nenhum caso de uso
  do app-core emite esse payload no v1 — a detecção é só local, em `DirectorySync.apply`
  (compara `identity_key` do diretório antes/depois). O ramo existe por compatibilidade com
  o protocolo, caso um peer futuro emita.

## PR #4 — build Windows corrigido (migração sodium 3→4)
- Causa: `sodium_libs` 3.4.6 está descontinuado; seu `windows/CMakeLists.txt` legado falhava no passo
  `INSTALL.vcxproj` / `cmake_install.cmake` (MSB3073) no runner `windows-latest` (log do run 34073180683).
- Correção: `sodium: ^4.1.0` (native assets, compila libsodium 1.0.22 por build hook — mesmo binário em
  app e testes) e removido `sodium_libs`. `test/support/sodium.dart` agora só chama `SodiumInit.init()`
  sem argumento (a lib nativa não é mais localizada por caminho do sistema).
- **Vetor `crypto_box_vector.json` continua passando** — validado (ver Bloqueios: não rodei via
  `flutter test` local, mas via container Linux com `dart test`, cobrindo os mesmos arquivos de teste).
- `dart format` e `flutter analyze --fatal-infos`: limpos (não dependem do build hook).

## RealChatFacade — connect() single-flight (3 RelayWs concorrentes, bug de campo)
- **Evidência de logcat** (build com prints de diagnóstico): `[chatito.boot] restore: session=true
  token=true keys=true` seguido de **três** linhas `[chatito.ws] conectando (geração 1)` em 7ms,
  cada uma com seu próprio backoff (`reagendando em 1140ms/841ms/937ms`) — três `RelayWs`
  concorrentes brigando entre si (4409), causados pelo autoConnect do boot + gatilhos da UI
  chamando `connect()` quase ao mesmo tempo.
- **Causa**: `_ensureWs` checava `_ws == null` e só DEPOIS fazia `await keyStore.readToken()`
  antes de atribuir `_ws` — qualquer chamada concorrente que chegasse nessa janela via `_ws`
  ainda nulo e criava o seu próprio `RelayWs`.
- **Correção**: `_ensureWs` agora é single-flight com `Future<void>? _connecting` — a 1ª chamada
  cria (`_createWs`); qualquer outra que chegue enquanto isso está em andamento só espera o
  mesmo future e reusa o `_ws` que ele deixou pronto; `whenComplete` limpa `_connecting`.
- Teste novo em `test/domain/real_chat_facade_ready_test.dart`: 3 chamadas concorrentes de
  `connect()` reproduziam 4 conexões reais no relay fake (a 4ª vinha do autoConnect do próprio
  boot) antes da correção; depois, exatamente 1. 130/130 no total.

## RealChatFacade — autoConnect no boot (bug de boot no Android)
- **Relato**: quem chama `connect()` no boot é o observador de conectividade (`connectivity_plus`)
  em `app_services.dart` do app-ui, reagindo a `onOnline` — mas esse callback pode não emitir um
  evento inicial (só dispara em *mudanças* de estado). Se o device já estava online desde antes
  de o app abrir, ninguém nunca chama `connect()`, e o app fica para sempre offline até a rede
  mudar de estado por algum motivo.
- **Correção**: `_loadInitialSession()` (chamada sozinha no construtor, ver entrega anterior)
  agora, se restaurar uma sessão com token salvo, dispara `connect()` por conta própria em
  segundo plano — sem esperar nenhum sinal externo. Falhas de rede nesse autoConnect só viram
  log, nunca exceção não tratada.
- **Bug encontrado ao testar**: como o autoConnect é fire-and-forget, havia uma corrida com
  `dispose()` — se a fachada fosse descartada antes do autoConnect terminar de criar o `RelayWs`,
  esse WS nascia **depois**, órfão (não descartado), e continuava tentando conectar e mexendo no
  banco mesmo com a fachada já morta (`Bad state: Can't re-open a database after closing it` em
  outro teste que fecha o banco). Corrigido guardando a tarefa do autoConnect
  (`_autoConnectTask`) e fazendo `dispose()` esperar por ela antes de descartar o `RelayWs`.
- Testes novos em `test/domain/real_chat_facade_ready_test.dart` (2): com sessão salva conecta
  sozinha sem que ninguém chame `connect()`; sem sessão salva não tenta nada. 129/129 no total.

## RelayWs — ensureConnected() com gerações (cancela tentativa travada/backoff)
- `ensureConnected()` novo em `RelayWs` **e** no `ChatFacade`/`RealChatFacade`/`FakeChatFacade`
  (era o bloqueio do app-ui em `ui/reconnect.dart` — já podem trocar `connect()` por
  `ensureConnected()` lá). Diferença para `connect()`: nunca fica de refém de uma tentativa
  travada (handshake que não completa) nem de um backoff em andamento — se a tentativa atual
  já passou de `ensureConnectedGraceTime` (padrão 5s) ou há um retry agendado, cancela e abre
  outra na hora.
- Implementado com um contador de **geração**: cada tentativa de conexão carrega um número; os
  callbacks dela (`_onData`/`_onError`/`_onDone`) se auto-descartam (e fecham o canal, se ainda
  existir) se não forem mais a geração atual. Isso cobre exatamente os casos de teste pedidos:
  um `hello` atrasado de uma tentativa abandonada nunca "ressuscita" a conexão; um 4409 numa
  geração velha (causado por nós mesmos ao abandoná-la) é ignorado; um 4409 na geração **atual**
  passou a reconectar em vez de desistir para sempre (mudança de comportamento — antes 4409
  parava tudo, igual 4401; agora só 4401 é definitivo).
- Achado real ao escrever os testes: fechar o canal abandonado (`sink.close()`) podia disparar o
  `onDone` **dele mesmo**, síncrono ou via microtask, antes da geração ser incrementada —
  corrigido incrementando a geração *antes* de fechar o canal velho.
- Logs estruturados via `dart:developer log(name: 'chatito.ws')` (aparecem no logcat do Android,
  tag `flutter`, e no Console.app do macOS) em cada transição — conectando/geração N, hello,
  fechado com código+motivo, reagendando em Xms, ignorado por geração antiga, watchdog. Nunca
  inclui conteúdo de mensagem nem o token. Motivo: a APK release não emitia nenhum log visível
  (o callback `log:` antigo só é usado pelos testes, nada o conectava a um sink real).
- Testes novos em `test/transport/relay_ws_test.dart` (4): handshake que só responde bem depois
  do grace time (geração abandonada não pode ficar viva), 4409 numa geração velha (ignorado),
  4409 na geração atual (reconecta — teste antigo atualizado), ensureConnected durante backoff
  (conecta na hora, sem esperar o timer).

## RealChatFacade — corrida no carregamento inicial da sessão (bug de campo)
- **Relato** (visto por logcat Android e macOS): `connect()` era chamado pela UI (observador de
  conectividade) ANTES de `RealChatFacade` terminar de carregar a sessão do `KeyStore`;
  `_require()` via `_active == null` e lançava `not_registered` como exceção não tratada — o app
  nunca conectava.
- **Correção**: o carregamento da sessão (`_ready`) agora começa sozinho na construção (não
  depende mais de alguém chamar `init()` antes de usar a fachada — `init()` continua existindo,
  só que agora é `Future<void> init() => _ready;`, idempotente). Todo método que depende de
  sessão (`connect`, `ensureConnected`, `refreshDirectory`, `safetyNumber`, `openDirect`,
  `sendText`, `sendFile`, `readAttachment`, `markRead`, `register`) espera `_ready` primeiro
  (`_requireReady()`), só lançando `not_registered` se, depois do carregamento, ainda não houver
  sessão de verdade.
- `ensureConnected()` adicionado ao `ChatFacade`/`RealChatFacade`/`FakeChatFacade` nesta mesma
  entrega (delegando ao `RelayWs.ensureConnected()` novo, acima) — resolve o bloqueio do app-ui.
- Testes novos: `test/domain/real_chat_facade_ready_test.dart` (5) — inclusive o cenário exato
  do bug: `connect()` chamado logo após construir, com `KeyStore` já tendo identidade/token,
  conecta sem lançar.
- 127/127 testes verdes no total (via container Linux; `flutter test` local segue bloqueado
  nesta máquina, já documentado).

## Onboarding — bug de robustez em campo (macOS): device órfão no servidor
- **Relato**: registro completava no servidor e SÓ DEPOIS falhava ao gravar a chave privada no
  keychain (erro do SO), deixando um device órfão no servidor e o app sem token nem sessão.
- **Causa**: `Onboarding.register` chamava `POST /v1/devices` **antes** de gravar a identidade no
  `KeyStore`.
- **Correção**: inverte a ordem — gera o par de chaves, grava no `KeyStore` e **relê** para
  confirmar (byte a byte) que bateu, só então chama `POST /v1/devices`. Falha na escrita ou
  releitura que não confere → `ChatException('storage', …)`, sem tocar o servidor. Se o registro
  falhar depois (rede, `invalid_invite`, etc.), apaga a chave que acabou de gravar
  (`KeyStore.deleteIdentity()`, novo método na interface — implementado em `MapKeyStore`, então
  `SecureKeyStore` do app-ui já herda de graça).
- Testes novos em `test/domain/onboarding_test.dart` (5), com um `FlakyKeyStore` que simula
  falha de escrita e releitura inconsistente. 117/117 testes verdes no total.

## RelayWs — watchdog para handshake travado e socket mudo
- Testes novos em `test/transport/relay_ws_test.dart`, com dois recursos novos no `fake_relay`:
  `holdHandshake` (aceita o upgrade HTTP→WS mas nunca manda `hello`, fica em `heldSockets`) e
  `vanish(deviceId)` (some da bookkeeping sem mandar close/error — nem `onDone` nem `onError`
  chegam ao cliente, simulando NAT/rede que engole a conexão sem RST/FIN).
- **Gap real encontrado**: `RelayWs` não tinha nenhum mecanismo para detectar essas duas
  situações — ficava preso em `connecting` para sempre (handshake nunca completa) ou continuava
  "online" indefinidamente sobre uma conexão morta (socket sumiu). Corrigido com um watchdog:
  um timer (`staleTimeout`, padrão 75 s — folga sobre os 30 s × 2 de ping do servidor,
  PROTOCOL.md §4) que reseta a cada frame recebido (mesmo malformado) e, se expirar, fecha a
  conexão e agenda reconexão como se tivesse caído.
- 119/119 testes verdes (via container Linux).

## RelayWs — testes de queda/corrida (fake_relay)
- Testes novos em `test/transport/relay_ws_test.dart`: `closeSocket(code: 1001)` (queda de rede,
  reconecta sozinho e zera tentativas), `closeSocket(code: 4409)` simulado direto pelo relay (sem
  precisar de uma 2ª conexão real) e duas chamadas concorrentes de `connect()`.
- **Bug real encontrado e corrigido**: `connect()` checava `_channel != null || _retry != null`
  antes de abrir, mas esses campos só deixam de ser nulos **depois** do `await ch.ready` dentro de
  `_open()` — duas chamadas concorrentes (ex.: `initState` + um retry externo) passavam a checagem
  e abriam **duas conexões reais**, e a 2ª derrubava a 1ª com 4409 sozinha. Corrigido com um future
  compartilhado (`_connecting`): a 2ª chamada aguarda a mesma tentativa em vez de abrir outra.
- 112/112 testes verdes (validado via container Linux, mesmo procedimento de sempre nesta máquina).

## Fase 2 — integração real Go↔Dart (feito)
- `app/test/integration/relay_integration_test.dart` (Dart puro): só roda se `RELAY_URL` existir, senão
  pula. Convite gerado sob demanda via `docker exec <container> /relay admin invite --user <nome>`
  (configurável por `RELAY_ADMIN_CMD`/`RELAY_CONTAINER`; ou passe prontos em `RELAY_INVITE_A`/`_A2`/`_B`
  se o processo do teste não tiver acesso ao Docker do host). Cobre com `RealChatFacade` de verdade:
  onboarding com convite real, 2 devices do mesmo usuário (mesmo nome no `admin invite` reaproveita o
  `user_id`, é assim que se ganha um 2º device no v1), diretório, texto 1:1 nos dois sentidos com
  fan-out para o 2º device e ack, recibo `read`, grupo `g:familia`, arquivo de ~1 MiB cifrado/decifrado
  byte a byte, reconexão do WS e safety number simétrico calculado pelos dois lados.
- **Rodado de verdade contra o relay real** (`docker-relay-1`, `http://127.0.0.1:8080`): **8/8 testes
  verdes**. Como `flutter test` local está bloqueado nesta máquina (ver bloqueio abaixo), rodei via a
  mesma cópia standalone Dart-puro num container Linux, com `RELAY_URL=http://host.docker.internal:8080`
  (Docker Desktop expõe o host assim) e os 3 convites gerados antes no host.
- **Nenhum bug de interoperabilidade Go↔Dart encontrado** — protocolo, crypto e transporte bateram com
  o servidor real de primeira. O único problema foi de desenho do próprio teste (corrigido antes do
  commit): pedi um 2º "device" com nome de usuário diferente, o que cria um **usuário** diferente no
  relay (não um 2º device do mesmo usuário) — corrigido reaproveitando o nome no `admin invite`.
- Para reproduzir: `docker exec docker-relay-1 /relay admin invite --user "Foo-$(date +%s)"` (2×, mesmo
  nome, para os 2 devices de A; 1× outro nome para B) → exportar como `RELAY_INVITE_A`/`_A2`/`_B` (ou
  deixar o teste gerar sozinho, se tiver Docker à mão) → `RELAY_URL=http://127.0.0.1:8080 flutter test
  test/integration` (numa máquina com Xcode completo; nesta aqui, ver bloqueio).

## Bloqueios
- **`flutter test` local quebrado nesta máquina**: o hook de build nativo do `sodium` 4.x roda para
  **todo** `flutter test` (não só testes de crypto), e no macOS exige Xcode completo
  (`…/Platforms/MacOSX.platform/Developer/SDKs`) — esta máquina só tem Command Line Tools, então
  `configure` do libsodium falha antes de qualquer teste. **Não é regressão desta mudança**: já era assim
  com `sodium` 3.x/`sodium_libs` para os testes de `crypto` especificamente; agora afeta a suíte inteira,
  porque o hook nativo passou a rodar para todo o pacote. Sem solução de contorno no pacote (a API antiga
  que aceitava um `DynamicLibrary` explícito não existe mais em 4.x).
- **Como validei mesmo assim**: montei uma cópia standalone de `lib/`+`test/`+fixtures (Dart puro, sem
  `flutter`/`flutter_test`) e rodei `dart test` num container Linux (`dart:3.13.2` + build-essential/
  autoconf/automake/libtool/pkg-config) — **109/109 testes verdes**, incluindo o vetor de crypto. Isso
  espelha o job `test` do CI (`ubuntu-latest`, que já vem com essas ferramentas de build por padrão).
  Os jobs `build-desktop` (windows-latest/macos-latest) rodam com Visual Studio e Xcode completos nos
  runners hospedados pelo GitHub, então o hook deve funcionar neles sem ajuste — é só nesta máquina de
  desenvolvimento (CLT-only) que fica bloqueado.
- Ação sugerida para o próximo agente/sessão nesta máquina: instalar o Xcode completo (não só Command
  Line Tools) para voltar a rodar `flutter test`/`flutter build macos` localmente.

## Próximo
- 3 → 4 (storage) → 5 (transport) → 6 (domain real: `RealChatFacade`).

---

## Interface pública para o **app-ui** (`import 'package:chatito/domain/domain.dart'`)

Tudo Dart puro. A UI depende só de `domain/domain.dart` (+ `protocol/protocol.dart` para `User`/`Device`).
Para desenvolver sem servidor: `import 'package:chatito/domain/fakes/fake_chat_facade.dart'`.

```dart
abstract interface class ChatFacade {
  // Sessão
  Future<SessionState> get session;                 // NotRegistered | Registered(user, device)
  Stream<SessionState> watchSession();
  Future<void> register({required String inviteCode, required String deviceName, required String platform});
  // Conexão
  Stream<ConnectionState> watchConnection();        // offline | connecting | online
  Future<void> connect();  Future<void> disconnect();
  // Diretório
  Stream<List<Contact>> watchContacts();            // Contact{User user, List<Device> devices}
  Future<void> refreshDirectory();
  Future<SafetyNumber> safetyNumber(String deviceId); // .digits (60) / .formatted ("12345 67890 …")
  // Conversas
  Stream<List<Conversation>> watchConversations();  // ordenadas por updatedAt desc
  Stream<List<Message>> watchMessages(String convId); // cronológica
  Future<Conversation> openDirect(String userId);
  Future<void> sendText(String convId, String body);
  Future<void> sendFile(String convId, {required String name, required String mime, required int size,
                        required Stream<List<int>> data, String? caption});
  Stream<List<int>> readAttachment({required String messageId, required String blobId});
  Future<void> markRead(String convId);
  Future<void> dispose();
}
```

Modelos (`domain/models.dart`):
- `Conversation{id, kind: direct|group, title, participantUserIds, updatedAt, lastMessage?, unreadCount}`
- `Message{id, convId, senderUserId, senderDeviceId, kind: text|file|keyChange, sentAt, isMine, body?,
  attachments: [MessageAttachment{blobId, name, size, mime, downloaded}], status: pending|sent|delivered|read|failed}`
- `ChatException{code, message}` — códigos do servidor (`invalid_invite`, `not_found`, `unauthorized`, …)
  + locais (`not_registered`, `network`, `crypto`).

Contratos:
- Todo `watch*` é broadcast e **emite o valor atual imediatamente** ao ouvir (bom para `StreamBuilder`).
- Erros vêm como `ChatException` (nunca exceções cruas de rede/crypto).
- `platform` em `register`: `macos` | `windows` | `android`.

`FakeChatFacade(startRegistered: true, autoReplyDelay: 400ms)`:
- Eu = Felipe (admin, `FakeChatFacade.felipeId`), contato = Mãe (`maeId`); ids iguais às fixtures.
- Já vem com grupo `g:familia` (3 msgs) e 1:1 com a Mãe (2 msgs, 1 não lida).
- Cada `sendText` recebe resposta automática da Mãe após `autoReplyDelay` (use `Duration.zero` em testes).
- `register` aceita qualquer `XXXX-XXXX`; `FakeChatFacade.badInvite` (`0000-0000`) lança `invalid_invite`.
- `sendFile` guarda os bytes em memória; `readAttachment` devolve em chunks de 64 KiB.
- Determinístico: ids sequenciais (`msg_0001`…), relógio fixo (`now:` injetável).
