# Backup — o que existe para salvar (quase nada)

O relay é **cego e sem histórico**: envelopes são apagados no `ack` e blobs quando todos os
destinatários baixaram (TTL de 30 dias para o resto). O histórico de conversas vive **só nos
dispositivos**, cifrado. Perder o servidor **não perde mensagens já entregues**.

## O que há em `/home/<DOMINIO>/data/`

| Caminho | Conteúdo | Vale backup? |
| --- | --- | --- |
| `relay.db` (+ `-wal`, `-shm`) | SQLite: usuários, devices (chave pública + hash do token), convites, fila de envelopes, metadados de blobs | **Sim** — só isto |
| `blobs/` | chunks cifrados de arquivos ainda não entregues | Não (transitório; cliente reenvia se sumir) |
| `/home/<DOMINIO>/secrets/env` | envs + service account FCM em base64 | **Sim** (no seu gerenciador de senhas, não junto do db) |

Se `relay.db` for perdido, todos os devices precisam **registrar de novo** (novo convite via
`admin bootstrap`) — as identidades são recriadas e os safety numbers mudam. É chato, não é
catastrófico. Por isso o backup existe.

## Backup do `relay.db` (consistente, com WAL ativo)

Usar o **backup online do SQLite**, nunca `cp` do arquivo em uso. O container é distroless
(sem shell nem `sqlite3`); use o CLI do host ou um container efêmero:

```bash
# no host, como operador; sqlite3 via apt (uma vez): sudo apt install -y sqlite3
DOMINIO=<DOMINIO>
sudo sqlite3 /home/$DOMINIO/data/relay.db ".backup /home/$DOMINIO/relay-$(date -u +%F).db"
sudo gzip -f /home/$DOMINIO/relay-$(date -u +%F).db
```

Sem `sqlite3` no host:

```bash
docker run --rm -v /home/$DOMINIO/data:/data:ro -v /home/$DOMINIO:/out \
  alpine/sqlite sqlite3 /data/relay.db ".backup /out/relay-$(date -u +%F).db"
```

Tamanho esperado: **KB a poucos MB** (4 pessoas, N devices, fila curta).

## Agendar (opcional — cron do host, SERVER.md §8)

```bash
sudo tee /etc/cron.d/chatito-backup >/dev/null <<'EOF'
15 3 * * * root /usr/bin/sqlite3 /home/<DOMINIO>/data/relay.db ".backup /home/<DOMINIO>/backups/relay-$(date -u +\%F).db" && find /home/<DOMINIO>/backups -name 'relay-*.db' -mtime +14 -delete
EOF
sudo install -d -m 0700 /home/<DOMINIO>/backups
```

Copie para fora do servidor de vez em quando (`scp ubuntu@<IP_DO_SERVIDOR>:/home/<DOMINIO>/backups/relay-*.db ~/Backups/chatito/`).
O db contém apenas metadados (chaves públicas, hashes de token, fila cifrada); mesmo assim trate
como confidencial: quem tem o db + o env consegue **personificar o servidor**, não ler mensagens.

## Restaurar

```bash
cd /home/<DOMINIO>/repo && export CHATITO_DOMAIN=<DOMINIO>
docker compose -f docker/docker-compose.yml stop relay
sudo rm -f /home/<DOMINIO>/data/relay.db /home/<DOMINIO>/data/relay.db-wal /home/<DOMINIO>/data/relay.db-shm
sudo gunzip -c /home/<DOMINIO>/backups/relay-YYYY-MM-DD.db.gz | sudo tee /home/<DOMINIO>/data/relay.db >/dev/null
sudo chown 65532:65532 /home/<DOMINIO>/data/relay.db
docker compose -f docker/docker-compose.yml up -d
curl -sS https://<DOMINIO>/healthz
```

Envelopes enfileirados entre o backup e a restauração são perdidos (os remetentes não recebem
`ack` — a fila de saída do app reenvia). Blobs referenciados no db mas ausentes em `blobs/`
respondem `404`; o cliente reenvia o arquivo.

## Servidor novo (migração)

1. RUNBOOK §1–§7 no servidor novo.
2. Restaurar `relay.db` e `secrets/env` como acima.
3. Trocar o registro A na Cloudflare. Os devices seguem válidos (mesmo db, mesmos tokens).
