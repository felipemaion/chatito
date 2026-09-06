# Chatito — Protocolo v1 (contrato cliente ↔ servidor)

Versão do protocolo: **1**. Mudanças passam pelo orquestrador e atualizam as fixtures em
`docs/protocol/fixtures/`. Servidor e app têm contract tests contra essas fixtures.

## 0. Princípios

- O servidor é um **relay cego**: só vê metadados de roteamento (de/para device, tamanhos, datas).
  Conteúdo de mensagens e arquivos é sempre cifrado no cliente.
- Um **envelope** é endereçado a **um device**. O remetente faz o fan-out: cifra o mesmo payload
  para cada device de cada usuário da conversa, **inclusive os próprios outros devices**.
- Envelope é apagado no `ack` do device destinatário. Blob é apagado quando todos os devices
  destinatários baixaram, ou no TTL. TTL de segurança: **30 dias** para ambos.
- Todos os binários em JSON são **base64 padrão (com padding)**. Datas em RFC 3339 UTC.
  IDs: `usr_`/`dev_`/`env_`/`blob_` + 22 chars base64url (128 bits aleatórios). `msg_id` e
  `conv_id` são gerados pelo cliente (UUID v4 / regra da §5).

## 1. Autenticação

`Authorization: Bearer <device_token>` em todo endpoint exceto `POST /v1/devices` e `/healthz`.
Token: 32 bytes aleatórios em base64url, emitido no registro, armazenado no servidor como
SHA-256. Papéis: `admin` | `member` (do usuário; herdado pelo device).

## 2. Criptografia (libsodium)

| Uso | Primitiva | Detalhe |
| --- | --- | --- |
| Identidade do device | X25519 (`crypto_box_keypair`) | Gerada no device; privada nunca sai (keychain/keystore) |
| Envelope | `crypto_box_easy(payload, nonce, pk_destino, sk_remetente)` | nonce 24 bytes aleatório; destino verifica autoria com `pk_remetente` obtida do diretório pelo `from_device` |
| Arquivos | `crypto_secretstream_xchacha20poly1305` | chave 32 B aleatória por arquivo; `header` 24 B; chunks de **cifra** de 64 KiB (`TAG_FINAL` no último). A chave e o header viajam no payload do envelope |
| Safety number | `SHA-256(sorted(pk_a ‖ pk_b))` → 60 dígitos decimais em grupos de 5 | Exibido para conferência presencial / QR |

Vetor de teste em `docs/protocol/fixtures/crypto_box_vector.json` (Go `nacl/box` ≡ `crypto_box_easy`).
Ambos os lados **devem** passar nele.

## 3. REST — prefixo `/v1`

Erros: status HTTP + `{"error":{"code":"<snake_case>","message":"..."}}` (fixture `error.json`).
Códigos: `unauthorized`, `forbidden`, `invalid_invite`, `validation`, `payload_too_large`,
`not_found`, `chunk_out_of_range`, `incomplete_blob`, `rate_limited`, `internal`.

| Método e rota | Corpo → Resposta | Notas |
| --- | --- | --- |
| `GET /healthz` | → `200 {"status":"ok"}` | sem auth |
| `POST /v1/devices` | `register_request.json` → `201 register_response.json` | consome o convite; cria o device; devolve token (única vez) |
| `GET /v1/me` | → `{user, device}` | |
| `GET /v1/directory` | → `directory.json` | todos os usuários e devices com `identity_key` |
| `PUT /v1/devices/me/push` | `{"fcm_token":"..."}` ou `{"fcm_token":null}` → `204` | |
| `DELETE /v1/devices/{id}` | → `204` | próprio usuário ou admin; apaga envelopes pendentes do device |
| `POST /v1/envelopes` | `envelopes_post_request.json` → `202 envelopes_post_response.json` | ≤ 100 envelopes; `ciphertext` ≤ 64 KiB cada; servidor preenche `from_device`, `id`, `created_at` e dispara push |
| `GET /v1/envelopes?limit=100` | → `{"envelopes":[envelope…]}` | pendentes do device chamador (fallback sem WS) |
| `POST /v1/envelopes/ack` | `{"ids":["env_…"]}` → `204` | apaga; ids desconhecidos são ignorados |
| `POST /v1/blobs` | `{"size":N,"recipients":["dev_…"]}` → `201 {"blob_id","chunk_size":8388608,"expires_at"}` | `size` ≤ 524288000 (500 MiB); recipients ≠ vazio |
| `PUT /v1/blobs/{id}/chunks/{n}` | corpo bruto (`application/octet-stream`) → `204` | `n` de 0 a `ceil(size/chunk_size)-1`; todos os chunks = `chunk_size` exceto o último; idempotente (re-PUT sobrescreve) |
| `POST /v1/blobs/{id}/complete` | → `200 {"blob_id","size"}` | `409 incomplete_blob` se faltar chunk; só o dono |
| `GET /v1/blobs/{id}` | → `200` stream `application/octet-stream`, `Content-Length` | só dono ou recipient; suporta `Range`; ao completar download de um recipient, marca entregue; apaga quando todos entregaram |
| `DELETE /v1/blobs/{id}` | → `204` | só o dono |
| `POST /v1/admin/invites` | `{"user_name":"Felipe"}` ou `{"user_id":"usr_…"}` → `201 {"code","user_id","expires_at"}` | admin; `user_name` novo cria usuário `member`; código `XXXX-XXXX` (Crockford base32), 7 dias, uso único |
| `POST /v1/admin/users/{id}/role` | `{"role":"admin"|"member"}` → `204` | admin |

Rate limit: 60 req/min por device (`429 rate_limited`, header `Retry-After`).
O **primeiro** usuário é criado pelo CLI no servidor: `relay admin bootstrap --name Felipe`
(cria usuário `admin` e imprime o convite). Sem isso não há como registrar nada.

## 4. WebSocket — `GET /v1/ws`

Header `Authorization: Bearer …` (fallback: query `?token=` para clientes sem header).
Frames JSON (fixture `ws_frames.json`):

| Direção | Frame |
| --- | --- |
| S→C ao conectar | `{"type":"hello","device_id":"dev_…","pending":N}` e em seguida um frame `envelope` por pendente |
| S→C | `{"type":"envelope","envelope":{id,from_device,to_device,nonce,ciphertext,created_at}}` |
| C→S | `{"type":"ack","ids":["env_…"]}` |
| S↔C | `{"type":"ping"}` / `{"type":"pong"}` — servidor pinga a cada 30 s; fecha após 2 sem pong |
| S→C | `{"type":"error","error":{code,message}}` e fecha (ex.: token inválido → close 4401) |

Um device pode ter só **uma** conexão; a nova derruba a anterior (close 4409).
Push FCM (Android): mensagem **data-only**, `{"type":"wake"}`, prioridade `high`, sem conteúdo.
Ao acordar, o app faz `GET /v1/envelopes` ou abre o WS.

## 5. Payload (decifrado) — JSON dentro do envelope

```json
{
  "v": 1,
  "msg_id": "uuid-v4",
  "conv_id": "u:usr_A:usr_B" | "g:familia",
  "kind": "text" | "file" | "receipt" | "key_change",
  "sent_at": "2026-09-06T18:00:00Z",
  "body": "texto (kind=text; opcional em file = legenda)",
  "attachments": [ { "blob_id","name","size","mime","key","header","chunk_size":65536 } ],
  "receipt": { "msg_id": "uuid", "status": "delivered" | "read" }
}
```

- `conv_id` 1:1: `"u:" + os dois user_ids em ordem lexicográfica separados por ":"`. Grupo único
  no v1: `"g:familia"` (todos os usuários do diretório).
- `text`: `body` obrigatório (≤ 32 KiB UTF-8). `file`: `attachments` com ≥ 1 item; `key`/`header`
  base64. `receipt`: só `receipt`. `key_change`: informa que o remetente trocou de device/chave
  (app mostra aviso e novo safety number).
- Campos desconhecidos são ignorados (compat futura). Fixtures: `payload_text.json`,
  `payload_file.json`, `payload_receipt.json`.
- Autoria: o app confia no `from_device` do envelope **somente** porque `crypto_box_open_easy`
  com a `pk` desse device validou o MAC. Se falhar, descarta e loga.

## 6. Limites (resumo)

| Item | Limite |
| --- | --- |
| Ciphertext por envelope | 64 KiB |
| Envelopes por `POST` | 100 |
| Blob | 500 MiB; chunk de upload 8 MiB |
| Chunk de cifra (secretstream) | 64 KiB |
| Texto | 32 KiB |
| TTL envelopes/blobs | 30 dias |
| Convite | 7 dias, uso único |
