# Status — agente server
## Feito
- [x] 1. `internal/store` — SQLite (modernc, WAL, FK), schema embutido, users/invites/devices/envelopes/blobs
      (chunks em disco, assemble no complete, recipients/entrega, expiração). Cobertura ~79% no pacote.
## Em andamento
- [ ] 2. `internal/api` — auth, erros JSON, rate limit, handlers + contract tests
## Bloqueios
- Nenhum.
## Próximo
- 3. `internal/ws`, 4. `internal/push`, 5. `internal/janitor`, 6. `cmd/relay`, 7. lint/cobertura/docker.
