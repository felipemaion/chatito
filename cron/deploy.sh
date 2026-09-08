#!/usr/bin/env bash
# Deploy no VPS Oracle — alvo do forced-command da chave de deploy (SERVER.md §2/§8 no repo
# OracleServer). O GitHub Actions só abre 1 conexão SSH; este script faz todo o trabalho no
# servidor como <APP_USER> (piriquito01): git reset em origin/main + compose build + gate de health.
#
# Instalação (uma vez, como operador) — linha do authorized_keys do user de deploy:
#   command="/home/<DOMINIO>/repo/cron/deploy.sh",no-port-forwarding,no-X11-forwarding,\
#   no-agent-forwarding,no-pty ssh-ed25519 AAAA... github-actions-deploy
#
# Variáveis (todas opcionais; sobrescritas nos testes bats em cron/test):
#   PIRIQUITO_REPO_DIR          raiz do checkout (padrão: pai deste script)
#   PIRIQUITO_DOMAIN            usado pelo compose (padrão: nome do diretório pai do repo)
#   PIRIQUITO_LOCK_FILE         arquivo de lock (padrão: /home/<DOMINIO>/deploy.lock)
#   PIRIQUITO_HEALTH_TIMEOUT_S  espera máxima pelo healthcheck (padrão: 180)
#   PIRIQUITO_SLEEP_S           intervalo entre checagens (padrão: 5)
set -euo pipefail

REPO_DIR="${PIRIQUITO_REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
COMPOSE_FILE="docker/docker-compose.yml"
BRANCH="main"
CONTAINER="piriquito-relay"
HEALTH_TIMEOUT_S="${PIRIQUITO_HEALTH_TIMEOUT_S:-180}"
SLEEP_S="${PIRIQUITO_SLEEP_S:-5}"
# PIRIQUITO_DOMAIN = nome do diretório /home/<DOMINIO>/ (pai de repo/), convenção SERVER.md §4.
export PIRIQUITO_DOMAIN="${PIRIQUITO_DOMAIN:-$(basename "$(dirname "$REPO_DIR")")}"
# Lock fora de data/ (pertence ao uid do container) e fora de /tmp (limpo no boot).
LOCK_FILE="${PIRIQUITO_LOCK_FILE:-$(dirname "$REPO_DIR")/deploy.lock}"

log() { printf '[deploy %s] %s\n' "$(date -u +%FT%TZ)" "$*"; }
fail() {
  log "$*"
  log "últimas linhas de log de $CONTAINER:"
  docker logs --tail 50 "$CONTAINER" || true
  echo "===DEPLOY_FAIL==="
  exit 1
}

# O comando remoto enviado pelo Actions é ignorado de propósito (forced-command).
[ -n "${SSH_ORIGINAL_COMMAND:-}" ] && log "ignorando comando remoto: ${SSH_ORIGINAL_COMMAND}"

# Serializa deploys concorrentes; o segundo falha rápido em vez de enfileirar builds.
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  log "outro deploy em andamento (lock: $LOCK_FILE) — abortando"
  exit 1
fi

cd "$REPO_DIR"

log "atualizando repo para origin/$BRANCH (domínio: $PIRIQUITO_DOMAIN)"
git fetch --quiet origin "$BRANCH"
git reset --hard --quiet "origin/$BRANCH"
log "HEAD: $(git rev-parse --short HEAD) — $(git log -1 --format=%s)"

log "docker compose up -d --build"
docker compose -f "$COMPOSE_FILE" up -d --build

log "aguardando healthcheck de $CONTAINER (timeout ${HEALTH_TIMEOUT_S}s)"
deadline=$((SECONDS + HEALTH_TIMEOUT_S))
while true; do
  status="$(docker inspect -f '{{.State.Health.Status}}' "$CONTAINER" 2>/dev/null || echo unknown)"
  case "$status" in
    healthy) log "container healthy"; break ;;
    unhealthy) fail "container UNHEALTHY" ;;
  esac
  if ((SECONDS >= deadline)); then
    fail "timeout esperando health (status: $status)"
  fi
  sleep "$SLEEP_S"
done

# Camadas órfãs do build anterior; sem -a para preservar cache de stage.
docker image prune -f >/dev/null || true
log "deploy OK"
echo "===DEPLOY_OK==="
