#!/usr/bin/env bash
# Alvo do forced-command do user de deploy (SERVER.md §2/§8). Roda como <APP_USER> em /home/<DOMINIO>.
set -euo pipefail
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LOCK=/tmp/chatito-deploy.lock
exec 9>"$LOCK"; flock -n 9 || { echo "deploy já em andamento"; exit 1; }
cd "$REPO_DIR"
export CHATITO_DOMAIN="${CHATITO_DOMAIN:-$(basename "$(dirname "$REPO_DIR")")}"
git fetch --quiet origin main && git reset --hard --quiet origin/main
docker compose -f docker/docker-compose.yml up -d --build
for i in $(seq 1 20); do
  docker compose -f docker/docker-compose.yml exec -T relay /relay -healthcheck && { echo "===DEPLOY_OK==="; exit 0; }
  sleep 3
done
echo "===DEPLOY_FAIL==="; docker compose -f docker/docker-compose.yml logs --tail=50 relay; exit 1
