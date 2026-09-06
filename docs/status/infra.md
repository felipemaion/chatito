# Status — agente infra
## Feito
- [1] `docker/Dockerfile` validado: `buildx --platform linux/arm64,linux/amd64` OK (imagem ~3 MB, distroless), `hadolint` limpo; `docker-compose.dev.yml up --build` + `curl /healthz` → `{"status":"ok"}`.
- [1] `cron/deploy.sh` reescrito (testável por env, health via `docker inspect`, lock em `/home/<DOMINIO>/deploy.lock`) com 10 testes bats em `cron/test/deploy.bats` (git/docker mockados) — verde 3×, `shellcheck` limpo.
## Em andamento
- [2] `release.yml`
## Bloqueios
- Healthcheck de produção (`/relay -healthcheck`) e `admin bootstrap` dependem do agente **server**; até lá o container em prod ficaria `unhealthy` e o `deploy.sh` falharia no gate (esperado; não deployamos nesta fase).
## Próximo
- release.yml → deploy.yml → docs/ops → README → dependabot
