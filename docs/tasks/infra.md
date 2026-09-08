> **Concluído** (Fase 1, 2026-09-06/07). Mantido como referência do escopo original.

# Tarefa — agente **infra** (branch `feat/infra`, escopo `docker/**`, `.github/**`, `cron/**`, `docs/ops/**`, `README.md`)

## Entregas (nesta ordem; commit + status a cada item)
1. Validar `docker/Dockerfile` multi-arch: `docker buildx build --platform linux/arm64,linux/amd64`
   (sem push) e `docker compose -f docker/docker-compose.dev.yml up --build` (o `-healthcheck`
   chega com o agente server; até lá, teste `/healthz` com `curl` de fora). Testes de shell para
   `cron/deploy.sh` com **bats** (mock de git/docker) — TDD também aqui.
2. `.github/workflows/release.yml`: em tag `v*`, builds: Android APK (assinado com keystore em
   secrets `ANDROID_KEYSTORE_B64`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`, `ANDROID_STORE_PASSWORD`; sem eles, APK debug),
   macOS `.dmg` (sem notarização; `create-dmg`), Windows `.zip` da pasta `build/windows/x64/runner/Release`;
   anexa tudo a um GitHub Release (privado). Imagem do servidor: `ghcr.io/felipemaion/chatito-relay:<tag>` multi-arch.
3. `.github/workflows/deploy.yml`: `workflow_dispatch` + push em `main` com mudanças em `server/**` ou `docker/**`;
   SSH nativo (não `appleboy`), host key fixa em `DEPLOY_KNOWN_HOSTS`, 1 conexão por deploy
   (SERVER.md §8). Template: igual ao do Ondulato.
4. `docs/ops/RUNBOOK.md`: passo a passo do checklist SERVER.md §9 preenchido para o Chatito
   (user `chatito01`, `/home/<DOMINIO>/`, bloco Caddy com `reverse_proxy chatito-relay:8080`
   e suporte a WebSocket, secrets, bootstrap do admin via `docker compose exec relay /relay admin bootstrap`),
   `docs/ops/FIREBASE.md` (como criar o projeto, baixar `google-services.json` e o service account, onde colocar),
   `docs/ops/BACKUP.md` (o servidor não guarda histórico; backup = só `data/relay.db` de metadados).
5. `README.md` completo: como rodar local, testar, buildar, instalar em cada plataforma.
6. Dependabot (`.github/dependabot.yml`) para gomod, pub e actions.

## Regras
- **Não** executar nada no servidor Oracle nesta fase; só preparar. Não toque em `server/` nem `app/`.
