#!/usr/bin/env bats
# Testes do cron/deploy.sh com git/docker mockados via PATH.
# Rodar: bats cron/test

setup() {
  TMP="$(mktemp -d)"
  export TMP
  export HOME_DIR="$TMP/home/piriquito.example.com"
  export REPO="$HOME_DIR/repo"
  mkdir -p "$REPO/docker" "$TMP/bin"
  cp "$BATS_TEST_DIRNAME/../deploy.sh" "$REPO/deploy.sh"
  chmod +x "$REPO/deploy.sh"
  export CALLS="$TMP/calls.log"
  : > "$CALLS"
  export HEALTH_SEQ="${TMP}/health_seq"
  printf 'healthy\n' > "$HEALTH_SEQ"

  # mock git: registra chamadas; falha se GIT_FAIL=1
  cat > "$TMP/bin/git" <<'MOCK'
#!/usr/bin/env bash
echo "git $*" >> "$CALLS"
[ -n "${GIT_FAIL:-}" ] && { echo "git mock failure" >&2; exit 128; }
case "$1" in rev-parse) echo abc1234;; log) echo "feat: x";; esac
exit 0
MOCK
  # mock docker: registra chamadas + PIRIQUITO_DOMAIN; inspect devolve a sequência de HEALTH_SEQ
  cat > "$TMP/bin/docker" <<'MOCK'
#!/usr/bin/env bash
echo "docker $* [PIRIQUITO_DOMAIN=${PIRIQUITO_DOMAIN:-}]" >> "$CALLS"
if [ "$1" = inspect ]; then
  status="$(head -n1 "$HEALTH_SEQ")"
  # consome a primeira linha, mantendo a última para sempre
  if [ "$(wc -l < "$HEALTH_SEQ")" -gt 1 ]; then sed -i.bak '1d' "$HEALTH_SEQ"; fi
  echo "$status"
fi
exit 0
MOCK
  chmod +x "$TMP/bin/git" "$TMP/bin/docker"
  export PATH="$TMP/bin:$PATH"
  export PIRIQUITO_REPO_DIR="$REPO"
  export PIRIQUITO_LOCK_FILE="$TMP/deploy.lock"
  export PIRIQUITO_HEALTH_TIMEOUT_S=5
  export PIRIQUITO_SLEEP_S=0
  unset PIRIQUITO_DOMAIN
}

teardown() { rm -rf "$TMP"; }

@test "atualiza o repo com fetch + reset em origin/main" {
  run "$REPO/deploy.sh"
  [ "$status" -eq 0 ]
  grep -q '^git fetch --quiet origin main$' "$CALLS"
  grep -q '^git reset --hard --quiet origin/main$' "$CALLS"
}

@test "sobe o compose de produção com --build e deriva PIRIQUITO_DOMAIN do diretório pai" {
  run "$REPO/deploy.sh"
  [ "$status" -eq 0 ]
  grep -q '^docker compose -f docker/docker-compose.yml up -d --build \[PIRIQUITO_DOMAIN=piriquito.example.com\]$' "$CALLS"
}

@test "respeita PIRIQUITO_DOMAIN já definido" {
  PIRIQUITO_DOMAIN=custom.test run "$REPO/deploy.sh"
  [ "$status" -eq 0 ]
  grep -q 'up -d --build \[PIRIQUITO_DOMAIN=custom.test\]' "$CALLS"
}

@test "container healthy → ===DEPLOY_OK===, exit 0 e prune de imagens" {
  run "$REPO/deploy.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"===DEPLOY_OK==="* ]]
  grep -q '^docker image prune -f' "$CALLS"
}

@test "espera enquanto starting e aceita healthy depois" {
  printf 'starting\nstarting\nhealthy\n' > "$HEALTH_SEQ"
  run "$REPO/deploy.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"===DEPLOY_OK==="* ]]
  [ "$(grep -c '^docker inspect' "$CALLS")" -eq 3 ]
}

@test "container unhealthy → logs, ===DEPLOY_FAIL===, exit 1" {
  printf 'unhealthy\n' > "$HEALTH_SEQ"
  run "$REPO/deploy.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"===DEPLOY_FAIL==="* ]]
  grep -q '^docker logs --tail 50 piriquito-relay' "$CALLS"
  ! grep -q '^docker image prune' "$CALLS"
}

@test "timeout sem healthy → ===DEPLOY_FAIL===, exit 1" {
  printf 'starting\n' > "$HEALTH_SEQ"
  PIRIQUITO_HEALTH_TIMEOUT_S=1 run "$REPO/deploy.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"===DEPLOY_FAIL==="* ]]
  [[ "$output" == *"timeout"* ]]
}

@test "falha no git → exit ≠ 0 e não sobe o compose" {
  GIT_FAIL=1 run "$REPO/deploy.sh"
  [ "$status" -ne 0 ]
  ! grep -q '^docker compose' "$CALLS"
}

@test "lock ocupado → aborta com exit 1 sem tocar em git" {
  exec 8>"$PIRIQUITO_LOCK_FILE"
  flock -n 8
  run "$REPO/deploy.sh"
  exec 8>&-
  [ "$status" -eq 1 ]
  [[ "$output" == *"em andamento"* ]]
  ! grep -q '^git' "$CALLS"
}

@test "ignora o comando remoto passado pelo forced-command (SSH_ORIGINAL_COMMAND)" {
  SSH_ORIGINAL_COMMAND="qualquer coisa" run "$REPO/deploy.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"===DEPLOY_OK==="* ]]
}
