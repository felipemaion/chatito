# Status — agente server
## Feito
- [x] 1. `internal/store` — SQLite (modernc, WAL, FK), schema embutido, users/invites/devices/envelopes/blobs
      (chunks em disco, assemble no complete, recipients/entrega, expiração). Cobertura ~79% no pacote.
- [x] 2. `internal/api` — bearer auth (SHA-256), erros JSON, rate limit 60/min/device (janela fixa), limites de
      tamanho, handlers devices/directory/envelopes/blobs(Range)/admin, contract tests com todas as fixtures. Cobertura ~91%.
- [x] 3. `internal/ws` — coder/websocket; hello + flush (até 1000 pendentes), ack, ping 30s (fecha após 2 sem pong),
      1 conexão por device (4409), fanout via `api.Notifier`, 4401 ao apagar device. Cobertura ~87%, `-race` ok.
- [x] 4. `internal/push` — FCM HTTP v1 via `golang.org/x/oauth2/google` (JWT do service account em `FCM_SERVICE_ACCOUNT_B64`;
      vazio = push desligado), `{"type":"wake"}` prioridade alta, sem `notification`; token UNREGISTERED é apagado. ~90%.
- [x] 5. `internal/janitor` — sweep horário: envelopes > 30 d, blobs expirados ou já entregues a todos, invites vencidos. ~98%.
- [x] 6. `cmd/relay` — `-healthcheck` (GET loopback `/healthz`), `admin bootstrap --name X` (recusa se já houver
      usuários), `admin invite --user X`, graceful shutdown (SIGINT/SIGTERM → fecha WS, `Shutdown` 15 s), logs JSON `slog`.
      `run()` testável; cobertura 83%. Total do módulo: **85,4%**; `golangci-lint` limpo (`.golangci.yml` ignora só `fmt.Fprint*`).
- [x] 7. Lint/cobertura ok. Docker: imagem builda; **com o Dockerfile atual o container morre** (ver Bloqueios).
      Com o patch proposto (validado localmente, sem commitar em `docker/`): `/healthz` → `{"status":"ok"}`,
      `/relay -healthcheck` exit 0, `/relay admin bootstrap --name Felipe` imprime convite, logs JSON.
## Em andamento
- Nada. Aguardando review/merge do PR `feat/server`.
## Correções da revisão do PR #2 (aplicadas)
- [x] ws: fecha após 2 intervalos de ping sem pong (~60s, era ~90s/3 pings) — `missed++` antes do check.
- [x] ws: dedupe por `env_id` entre o flush de pendentes no hello e `Notify` concorrente (evita entrega dupla).
- [x] store/blobs: `WriteChunk`/`assemble` usam `os.CreateTemp` + rename atômico (nomes fixos podiam colidir).
- [x] store: `blob_recipients.device_id` agora `ON DELETE CASCADE`; `DeleteDevice` reavalia blobs após o cascade
      (`DeleteDeliveredBlobs`) em vez de esperar o janitor horário.
- [x] api: rate limit por IP em `POST /v1/devices` (10/min, configurável via `RegisterRateLimit`) contra brute force de convite.
- [x] ws: removido `InsecureSkipVerify` do `Accept` — clientes nativos não mandam `Origin`, checagem padrão basta.
Testes novos cobrindo cada fix; `go test ./... -race` verde, cobertura total 85,4%, `golangci-lint` limpo.

## Bloqueios
- **`docker/Dockerfile` (escopo infra):** `distroless:nonroot` + `VOLUME /app/data` sem criar o diretório → volume nasce
  root e o relay falha com `mkdir /app/data/blobs: permission denied`. Patch verificado (arquivo fora do meu escopo):
  ```dockerfile
  # no estágio build, após o go build:
  RUN mkdir -p /out/data
  # no estágio final, ANTES de VOLUME /app/data:
  COPY --from=build --chown=nonroot:nonroot /out/data /app/data
  ```
- Sem outros bloqueantes. Decisões tomadas (contrato omisso), para validação do orquestrador:
  - Código de erro extra `conflict` (409) para PUT de chunk após `complete` — não está na lista da §3.
  - `to_device` desconhecido em `POST /v1/envelopes` → `400 validation` (lote inteiro rejeitado).
  - `GET /v1/blobs/{id}` só serve blobs completos e não expirados (senão `404`). Entrega de um recipient é
    marcada quando a resposta cobre o último byte (download completo ou `Range` até o fim) e todos os bytes foram
    escritos; owner baixar não conta.
  - Dono da rota `DELETE /v1/devices/{id}`: mesmo usuário ou admin; blobs do device são apagados junto.
## Próximo
- 3. `internal/ws`, 4. `internal/push`, 5. `internal/janitor`, 6. `cmd/relay`, 7. lint/cobertura/docker.
