> **Concluído** (Fase 1, 2026-09-06/07). Mantido como referência do escopo original.

# Tarefa — agente **server** (branch `feat/server`, escopo `server/**`)

Implementar o relay completo conforme `docs/PROTOCOL.md`, em Go 1.25, **TDD**, sem CGO.

## Entregas (nesta ordem; commit + status a cada item)
1. `internal/store` — SQLite via `modernc.org/sqlite` (WAL), migrations embutidas; tabelas
   `users, devices, invites, envelopes, blobs, blob_chunks/blob_recipients`. Testes com DB temporário.
2. `internal/api` — middleware de auth (bearer → SHA-256 lookup), erros JSON padrão, rate limit
   60/min por device, limites de tamanho. Handlers: devices (register/me/push/delete), directory,
   envelopes (post/get/ack), blobs (create/chunk/complete/get com Range/delete), admin (invites/role).
   **Contract tests** decodificando/encodando `docs/protocol/fixtures/*.json`.
3. `internal/ws` — `/v1/ws` (`github.com/coder/websocket`): hello + flush de pendentes, ack, ping 30s,
   uma conexão por device (4409), fanout em tempo real ao receber `POST /v1/envelopes`.
4. `internal/push` — FCM HTTP v1 data-only (`{"type":"wake"}`) com service account de
   `FCM_SERVICE_ACCOUNT_B64`; interface `Pusher` + fake nos testes; desligado se env vazia.
5. `internal/janitor` — expiração horária (envelopes/blobs 30 d, invites 7 d); blob apagado quando
   todos os recipients baixaram.
6. `cmd/relay` — flags: `-healthcheck` (GET local em `/healthz`, exit 0/1 — usado pelo Docker, que não tem curl),
   `admin bootstrap --name X` (cria admin + imprime convite), `admin invite --user X`. Graceful shutdown, logs JSON (`log/slog`).
7. `golangci-lint` limpo; cobertura ≥ 80%; `docker compose -f docker/docker-compose.dev.yml up --build` sobe e responde `/healthz`.

## Regras
- Vetor `docs/protocol/fixtures/crypto_box_vector.json`: o servidor **não** decifra nada, mas
  inclua um teste que só valida que `ciphertext`/`nonce` são base64 válidos com tamanhos coerentes
  (24 B nonce; ciphertext = plaintext+16).
- Não altere `docs/protocol/**`. Dúvidas de contrato → `docs/status/server.md` › Bloqueios.
