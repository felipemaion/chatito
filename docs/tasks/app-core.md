# Tarefa — agente **app-core** (branch `feat/app-core`, escopo `app/lib/{crypto,protocol,transport,storage,domain}` + `app/test/**` correspondente + `app/pubspec.yaml`)

Núcleo do cliente Flutter em **Dart puro** (sem `import 'package:flutter/…'` nessas camadas, exceto
adaptadores de plataforma explicitamente marcados). **TDD**; cobertura ≥ 80%.

## Entregas (nesta ordem; commit + status a cada item)
1. `pubspec.yaml`: adicionar `sodium_libs`, `sodium`, `drift` + `drift_flutter`, `sqlite3_flutter_libs`,
   `flutter_secure_storage`, `web_socket_channel`, `dio`, `json_annotation`/`json_serializable`,
   `build_runner`, `uuid`, `path`. Rodar `flutter pub get` e manter `flutter analyze` limpo.
2. `lib/protocol` — modelos (`Envelope`, `Payload`, `Attachment`, `Device`, `User`, DTOs REST/WS)
   com `fromJson/toJson`; **contract tests** contra `docs/protocol/fixtures/*.json` (round-trip
   exato). `conv_id` helper (regra §5).
3. `lib/crypto` — interface `CryptoBox` (keypair, seal/open, safety number) + implementação
   `SodiumCryptoBox`; **deve passar** `crypto_box_vector.json` (reproduzir ciphertext e decifrar;
   safety number igual). `FileCipher` com `secretstream` em chunks de 64 KiB (encrypt/decrypt streams).
   Testes rodam na VM com `sodium` (não `sodium_libs`): use `SodiumInit`/binário nativo do
   pacote `sodium` para testes de desktop.
4. `lib/storage` — drift: `conversations, messages, attachments, contacts(devices), outbox`;
   `KeyStore` (interface + fake em memória; impl real usa `flutter_secure_storage` em `platform/`).
5. `lib/transport` — `RelayApi` (dio) cobrindo todo o REST; `RelayWs` com reconexão exponencial,
   ack automático após persistir; `ChunkUploader` (8 MiB, retomada). Testes com servidor fake (`shelf`/`HttpServer` local).
6. `lib/domain` — casos de uso: `Onboarding` (convite → keypair → registro → diretório),
   `SendMessage` (fan-out para todos os devices da conversa **incluindo os próprios**),
   `ReceiveEnvelope` (open → persistir → ack; falha de MAC = descartar + log), `SendFile`/`ReceiveFile`,
   `Receipts`, `KeyChange`. Expor um `ChatFacade` (interface) que a UI consome.
7. `lib/domain/fakes` — `FakeChatFacade` em memória, determinístico, com 2 usuários e mensagens de
   exemplo, para o agente **app-ui** usar antes da integração. **Entregue este item cedo (logo após o 2)**,
   pois o app-ui depende dele.

## Regras
- Não altere `docs/protocol/**` nem `lib/ui`/`lib/platform`. Interfaces públicas do domínio: documente em
  `docs/status/app-core.md` para o app-ui.
