# Status — agente server
## Feito
- [x] 1. `internal/store` — SQLite (modernc, WAL, FK), schema embutido, users/invites/devices/envelopes/blobs
      (chunks em disco, assemble no complete, recipients/entrega, expiração). Cobertura ~79% no pacote.
- [x] 2. `internal/api` — bearer auth (SHA-256), erros JSON, rate limit 60/min/device (janela fixa), limites de
      tamanho, handlers devices/directory/envelopes/blobs(Range)/admin, contract tests com todas as fixtures. Cobertura ~91%.
## Em andamento
- [ ] 3. `internal/ws` — hello/flush/ack/ping, 1 conexão por device, fanout em tempo real
## Bloqueios
- Nenhum bloqueante. Decisões tomadas (contrato omisso), para validação do orquestrador:
  - Código de erro extra `conflict` (409) para PUT de chunk após `complete` — não está na lista da §3.
  - `to_device` desconhecido em `POST /v1/envelopes` → `400 validation` (lote inteiro rejeitado).
  - `GET /v1/blobs/{id}` só serve blobs completos e não expirados (senão `404`). Entrega de um recipient é
    marcada quando a resposta cobre o último byte (download completo ou `Range` até o fim) e todos os bytes foram
    escritos; owner baixar não conta.
  - Dono da rota `DELETE /v1/devices/{id}`: mesmo usuário ou admin; blobs do device são apagados junto.
## Próximo
- 3. `internal/ws`, 4. `internal/push`, 5. `internal/janitor`, 6. `cmd/relay`, 7. lint/cobertura/docker.
