# Status — agente app-core

## Feito
- [x] 1. `pubspec.yaml`: sodium/sodium_libs, drift/drift_flutter, flutter_secure_storage, web_socket_channel,
  dio, json_annotation/json_serializable, build_runner, drift_dev, uuid, path, test. (`sqlite3_flutter_libs`
  omitido: versão `0.6.0+eol` é obsoleta; `drift_flutter` 0.3 já embute `sqlite3` v3.)
- [x] 2. `lib/protocol` — modelos + `ConvId`; contract tests round-trip exato contra **todas** as fixtures.
  `.g.dart` commitados (CI não roda `build_runner`).
- [x] 7. `lib/domain` — interface `ChatFacade`, modelos de domínio e `FakeChatFacade` (memória, determinístico).

## Em andamento
- [ ] 3. `lib/crypto` (CryptoBox + FileCipher, vetor de teste).

## Bloqueios
- **CI (infra):** testes de `crypto` rodam na VM com o pacote `sodium` e precisam de `libsodium` nativo.
  Localmente: `brew install libsodium`. No `ci-app.yml` (ubuntu) falta `sudo apt-get install -y libsodium23`
  antes de `flutter test`. O helper de teste procura `LIBSODIUM_PATH`, depois caminhos padrão
  (`/opt/homebrew/lib`, `/usr/lib/x86_64-linux-gnu`, `/usr/lib`). Peço ao infra incluir o passo.

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
