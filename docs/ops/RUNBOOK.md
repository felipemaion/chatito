# Runbook — Chatito no VPS Oracle

Checklist SERVER.md §9 (repo `OracleServer`) preenchido para o Chatito. Convenções: user de deploy
**`chatito01`**, diretório **`/home/<DOMINIO>/`** (nome = domínio, ex.: `chatito.exemplo.com.br`),
container **`chatito-relay`** na rede Docker externa **`proxy`**, porta interna **8080**.
Tudo abaixo roda como operador (`ubuntu`) salvo indicação. **Nada disto é executado na Fase 1**
— é preparação; execução na Fase 4.

> Substitua `<DOMINIO>` pelo domínio real em todos os comandos. Segredos sempre via `nano`
> (gotcha 12: heredoc/paste no tmux corrompe).

## 0. Antes de começar (fora do servidor)

| Item | Onde |
| --- | --- |
| Domínio decidido e zona na Cloudflare | Cloudflare → Websites |
| Chave de deploy | `ssh-keygen -t ed25519 -C 'github-actions-deploy@chatito' -f ~/.ssh/chatito-deploy -N ''` |
| Host key do servidor (uma vez, de máquina **não banida**) | `ssh-keyscan -t ed25519,ecdsa <IP_DO_SERVIDOR> > chatito-known_hosts` |
| Projeto Firebase + service account | [FIREBASE.md](FIREBASE.md) |

## 1. Escolher `<DOMINIO>` e `<APP_USER>`; confirmar que não existem

```bash
id chatito01 2>/dev/null && echo "JÁ EXISTE"; ls -d /home/<DOMINIO> 2>/dev/null && echo "JÁ EXISTE"
```

## 2. User de sistema + grupo docker (SERVER.md §2)

```bash
sudo groupadd --system chatito01
sudo useradd --system --gid chatito01 --home-dir /home/<DOMINIO> --shell /bin/bash --no-create-home chatito01
sudo passwd -l chatito01
sudo usermod -aG docker chatito01
```

## 3. Layout `/home/<DOMINIO>/` (§4)

```bash
DOMINIO="<DOMINIO>"; APP_USER="chatito01"
sudo install -d -o $APP_USER -g $APP_USER -m 0750 /home/$DOMINIO{,/repo,/data}
sudo install -d -o $APP_USER -g $APP_USER -m 0700 /home/$DOMINIO/secrets
```

O container roda como `nonroot` (uid **65532**, distroless) e escreve em `/app/data`:

```bash
sudo chown -R 65532:65532 /home/$DOMINIO/data
```

## 4. Chave de deploy → `authorized_keys` com forced-command

```bash
sudo install -d -m700 -o chatito01 -g chatito01 /home/<DOMINIO>/.ssh
sudo nano /home/<DOMINIO>/.ssh/authorized_keys   # colar a linha abaixo (uma linha só)
```

```
command="/home/<DOMINIO>/repo/cron/deploy.sh",no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty ssh-ed25519 AAAA... github-actions-deploy
```

```bash
sudo chmod 600 /home/<DOMINIO>/.ssh/authorized_keys && sudo chown chatito01:chatito01 /home/<DOMINIO>/.ssh/authorized_keys
```

## 5. `git clone` em `repo/` (Deploy Key read-only — repo privado)

```bash
sudo -u chatito01 -H ssh-keygen -t ed25519 -C 'deploy-key@chatito-server' -f /home/<DOMINIO>/.ssh/id_ed25519 -N ''
sudo cat /home/<DOMINIO>/.ssh/id_ed25519.pub
# na sua máquina:  gh repo deploy-key add chatito-server.pub --repo felipemaion/chatito --title oracle-chatito01
sudo -u chatito01 -H git clone git@github.com:felipemaion/chatito.git /home/<DOMINIO>/repo
```

`cron/deploy.sh` faz `git reset --hard origin/main` — nunca edite arquivos dentro de `repo/` no servidor.

## 6. `secrets/env` (0600)

```bash
sudo -u chatito01 cp /home/<DOMINIO>/repo/docker/env.example /home/<DOMINIO>/secrets/env
sudo -u chatito01 nano /home/<DOMINIO>/secrets/env
sudo chmod 600 /home/<DOMINIO>/secrets/env
```

| Variável | Valor |
| --- | --- |
| `RELAY_ADDR` | `:8080` |
| `RELAY_DATA_DIR` | `/app/data` |
| `RELAY_PUBLIC_URL` | `https://<DOMINIO>` |
| `FCM_SERVICE_ACCOUNT_B64` | `base64 -w0 service-account.json` (ver [FIREBASE.md](FIREBASE.md)); vazio = push desligado |

Mudou o env depois? `docker compose ... up -d --force-recreate` (gotcha 14; `restart` não relê).

## 7. `docker compose up -d --build` (sem `ports:`, rede `proxy`)

```bash
cd /home/<DOMINIO>/repo
export CHATITO_DOMAIN=<DOMINIO>
sudo -u chatito01 -E docker compose -f docker/docker-compose.yml up -d --build
docker inspect -f '{{.State.Health.Status}}' chatito-relay    # healthy
```

O compose lê `CHATITO_DOMAIN` para montar `/home/<DOMINIO>/data` e `secrets/env`. O `deploy.sh`
deriva a variável do diretório pai automaticamente. Build ARM64 nativo (~1 min, imagem ~3 MB).
Alternativa sem build no servidor: `docker pull ghcr.io/felipemaion/chatito-relay:<tag>` (gerada
pelo `release.yml`) e trocar `build:` por `image:` no compose — não é o padrão atual.

## 8. Bootstrap do admin (primeiro usuário)

Sem isto ninguém consegue registrar um device (PROTOCOL §3):

```bash
cd /home/<DOMINIO>/repo
docker compose -f docker/docker-compose.yml exec relay /relay admin bootstrap --name Felipe
# imprime o convite XXXX-XXXX (7 dias, uso único) → digitar no app
```

Convites seguintes: `docker compose -f docker/docker-compose.yml exec relay /relay admin invite --user "Nome"`
ou pelo app (`POST /v1/admin/invites`, papel admin).

## 9. Cloudflare

Registro **A** `<DOMINIO>` → `<IP_DO_SERVIDOR>`, **Proxied**, SSL/TLS = **Full (strict)**.
WebSocket já vem habilitado no plano Free (Network → WebSockets = On; conferir).
O proxy da Cloudflare limita cada request a **100 MB** — os chunks de blob são de 8 MiB, OK.

## 10. Token CF no Caddy (só na 1ª vez do servidor)

Se `acme_dns cloudflare` ainda estiver comentado em `/home/caddy.internal/Caddyfile`: colocar o
`CLOUDFLARE_API_TOKEN` real em `/home/caddy.internal/.env` (0600, via `nano`) e descomentar.
Token placeholder derruba o Caddy em crash-loop (gotcha 5).

## 11. Bloco no Caddyfile + reload

`reverse_proxy` do Caddy faz upgrade de WebSocket automaticamente; o bloco abaixo só aumenta
limites para os chunks de upload e mantém a conexão do `/v1/ws` viva.

```caddyfile
<DOMINIO> {
	encode zstd gzip
	request_body {
		max_size 9MB
	}
	reverse_proxy chatito-relay:8080 {
		flush_interval -1
		transport http {
			read_timeout 0
			write_timeout 0
		}
	}
	tls {
		resolvers 1.1.1.1
	}
}
```

```bash
cd /home/caddy.internal && sudo nano Caddyfile
docker compose exec caddy caddy validate --config /etc/caddy/Caddyfile
docker compose restart caddy        # editou com editor que troca inode → restart, não reload (gotcha 2)
```

## 12. Smoke externo (de FORA da VM — gotcha 3)

```bash
curl -sS https://<DOMINIO>/healthz            # {"status":"ok"}
curl -sSI https://<DOMINIO>/v1/ws -H 'Connection: Upgrade' -H 'Upgrade: websocket' | head -1   # 401 sem token = rota chega no relay
```

## 13. Smoke interno

```bash
cd /home/caddy.internal && docker compose exec caddy wget -qO- http://chatito-relay:8080/healthz
```

## 14. Secrets no GitHub (environment `production`) + workflow de deploy

```bash
gh secret set DEPLOY_HOST        --env production --repo felipemaion/chatito --body <IP_DO_SERVIDOR>
gh secret set DEPLOY_USER        --env production --repo felipemaion/chatito --body chatito01
gh secret set DEPLOY_SSH_KEY     --env production --repo felipemaion/chatito < ~/.ssh/chatito-deploy
gh secret set DEPLOY_KNOWN_HOSTS --env production --repo felipemaion/chatito < chatito-known_hosts
gh secret set PRODUCTION_SITE_URL --env production --repo felipemaion/chatito --body https://<DOMINIO>
gh workflow run deploy.yml --repo felipemaion/chatito     # dispatch manual
```

Secrets do `release.yml` (nível de repositório, não environment): `ANDROID_KEYSTORE_B64`,
`ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`, `ANDROID_STORE_PASSWORD` (ver README → Release).

## 15. Cron jobs

Nenhum. Expiração de envelopes/blobs (TTL 30 dias) é job interno do relay. Backup: [BACKUP.md](BACKUP.md).

## 16. Documentar

README do projeto (seção Deploy) + inventário SERVER.md §11 do `OracleServer`:
`Chatito | <DOMINIO> | /home/<DOMINIO>/, container chatito-relay (Go, interno :8080), user chatito01`.

---

## Operação do dia a dia

| Tarefa | Comando (em `/home/<DOMINIO>/repo`, `CHATITO_DOMAIN` exportado) |
| --- | --- |
| Logs | `docker compose -f docker/docker-compose.yml logs -f --tail 100 relay` |
| Health | `docker inspect -f '{{.State.Health.Status}}' chatito-relay` |
| Deploy manual (mesmo caminho do CI) | `sudo -u chatito01 -H /home/<DOMINIO>/repo/cron/deploy.sh` |
| Reiniciar | `docker compose -f docker/docker-compose.yml restart relay` |
| Novo convite | `docker compose -f docker/docker-compose.yml exec relay /relay admin invite --user "Nome"` |
| Uso de disco (blobs pendentes) | `sudo du -sh /home/<DOMINIO>/data/blobs` |

### Rollback

```bash
cd /home/<DOMINIO>/repo && sudo -u chatito01 -H git reset --hard <sha-bom> \
  && sudo -u chatito01 -E docker compose -f docker/docker-compose.yml up -d --build
```
O próximo push em `main` volta para `origin/main`; para rollback duradouro, reverta o commit no GitHub.

### Falhas conhecidas

| Sintoma | Causa provável | Ação |
| --- | --- | --- |
| `deploy` no Actions falha com "Permission denied (publickey)" | fail2ban baniu o runner ou chave errada | `sudo fail2ban-client status sshd`; nunca `ssh-keyscan` no workflow |
| Container `unhealthy` logo após deploy | binário sem `-healthcheck` (versão antiga) ou `data/` sem permissão para uid 65532 | `docker logs chatito-relay`; `chown -R 65532:65532 data/` |
| WebSocket cai a cada ~100 s | timeout do Cloudflare/Caddy | relay pinga a cada 30 s (PROTOCOL §4); conferir `read_timeout 0` no Caddyfile |
| `413` no upload de chunk | `max_size` no Caddy < 8 MiB | bloco do §11 |
