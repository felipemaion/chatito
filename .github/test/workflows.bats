#!/usr/bin/env bats
# Invariantes dos workflows e do dependabot (SERVER.md §8, docs/tasks/infra.md).
# Rodar: bats .github/test  (requer actionlint no PATH)

GH="$BATS_TEST_DIRNAME/.."
REL="$GH/workflows/release.yml"
DEP="$GH/workflows/deploy.yml"
CI="$GH/workflows/ci-infra.yml"
BOT="$GH/dependabot.yml"

@test "actionlint aprova todos os workflows" {
  run actionlint "$GH"/workflows/*.yml
  [ "$status" -eq 0 ]
}

# ---------- release.yml ----------
@test "release: dispara em tag v*" {
  grep -q "tags:" "$REL"
  grep -q "'v\*'" "$REL"
}

@test "release: builda APK Android, .dmg macOS e .zip Windows" {
  grep -q 'flutter build apk' "$REL"
  grep -q 'create-dmg' "$REL"
  grep -q 'build/windows/x64/runner/Release' "$REL"
  grep -q 'flutter build macos --release' "$REL"
  grep -q 'flutter build windows --release' "$REL"
}

@test "release: APK assinado só com os 4 secrets; senão debug" {
  for s in ANDROID_KEYSTORE_B64 ANDROID_KEY_ALIAS ANDROID_KEY_PASSWORD ANDROID_STORE_PASSWORD; do
    grep -q "secrets.$s" "$REL"
  done
  grep -q 'flutter build apk --debug' "$REL"
}

@test "release: imagem ghcr.io/felipemaion/piriquito-relay:<tag> multi-arch" {
  grep -q 'ghcr.io/felipemaion/piriquito-relay' "$REL"
  grep -q 'linux/amd64,linux/arm64' "$REL"
  grep -q 'docker/Dockerfile' "$REL"
  grep -q 'packages: write' "$REL"
}

@test "release: anexa artefatos a um GitHub Release" {
  grep -q 'gh release create' "$REL"
  grep -q 'contents: write' "$REL"
}

@test "release: nenhum segredo vai para o log (set -x proibido, keystore só via env)" {
  ! grep -q 'set -x' "$REL"
  ! grep -qE '\$\{\{ *secrets\.ANDROID_[A-Z_]+ *\}\}[^$]*run:' "$REL"
}

# ---------- deploy.yml ----------
@test "deploy: workflow_dispatch + push em main filtrado por server/** e docker/**" {
  grep -q 'workflow_dispatch' "$DEP"
  grep -q "'server/\*\*'" "$DEP"
  grep -q "'docker/\*\*'" "$DEP"
  grep -q 'branches: \[main\]' "$DEP"
}

@test "deploy: SSH nativo com host key fixa, sem appleboy nem ssh-keyscan" {
  ! grep -q 'appleboy' "$DEP"
  ! grep -q 'ssh-keyscan' "$DEP"
  grep -q 'secrets.DEPLOY_KNOWN_HOSTS' "$DEP"
  grep -q 'secrets.DEPLOY_SSH_KEY' "$DEP"
  grep -q 'BatchMode=yes' "$DEP"
  grep -q 'environment: production' "$DEP"
}

@test "deploy: uma única conexão ssh por deploy e concorrência serializada" {
  [ "$(grep -cE '^\s+ssh ' "$DEP")" -eq 1 ]
  grep -q 'cancel-in-progress: false' "$DEP"
  grep -q '===DEPLOY_OK===' "$DEP"
}

@test "deploy: smoke externo em /healthz" {
  grep -q '/healthz' "$DEP"
}

# ---------- ci-infra.yml ----------
@test "ci-infra: roda bats, shellcheck, hadolint e actionlint" {
  grep -q 'bats' "$CI"
  grep -q 'shellcheck' "$CI"
  grep -q 'hadolint' "$CI"
  grep -q 'actionlint' "$CI"
  grep -q 'docker/setup-buildx-action' "$CI"
}

# ---------- dependabot.yml ----------
@test "dependabot: gomod, pub e github-actions" {
  grep -q 'package-ecosystem: gomod' "$BOT"
  grep -q 'package-ecosystem: pub' "$BOT"
  grep -q 'package-ecosystem: github-actions' "$BOT"
  grep -q 'directory: /server' "$BOT"
  grep -q 'directory: /app' "$BOT"
}
