# Status — agente infra
## Feito
- APK release assinado pelo Gradle: `app/android/app/build.gradle.kts` lê `android/key.properties` (storeFile/storePassword/keyAlias/keyPassword) se existir; sem ele cai no signing de debug. Plugin `com.google.gms.google-services` declarado em `settings.gradle.kts` (`apply false`) e aplicado condicionalmente só se `google-services.json` existir.
- `release.yml`: decodifica `GOOGLE_SERVICES_JSON_B64` (se existir) para `android/app/google-services.json`; removido o contorno com `apksigner` — `flutter build apk --release` já sai assinado pelo Gradle.
- [1] `docker/Dockerfile` validado: `buildx --platform linux/arm64,linux/amd64` OK (imagem ~3 MB, distroless), `hadolint` limpo; `docker-compose.dev.yml up --build` + `curl /healthz` → `{"status":"ok"}`.
- [1] `cron/deploy.sh` reescrito (testável por env, health via `docker inspect`, lock em `/home/<DOMINIO>/deploy.lock`, ignora `SSH_ORIGINAL_COMMAND`) com 10 testes bats em `cron/test/deploy.bats` (git/docker mockados) — verde 3×, `shellcheck` limpo.
- [2] `.github/workflows/release.yml`: tag `v*` → APK (assinado via `apksigner` com secrets `ANDROID_*`; sem eles, debug), `.dmg` (create-dmg), `.zip` Windows, SHA256SUMS, `ghcr.io/felipemaion/chatito-relay:<tag>`+`:latest` multi-arch, `gh release create`.
- [3] `.github/workflows/deploy.yml`: template Ondulato — `workflow_dispatch` + push em `main` (`server/**`, `docker/**`, `cron/**`), SSH nativo, `DEPLOY_KNOWN_HOSTS` fixo, 1 conexão, gate `===DEPLOY_OK===`, smoke `/healthz`.
- [4] `docs/ops/RUNBOOK.md` (checklist §9 preenchido: `chatito01`, `/home/<DOMINIO>/`, bloco Caddy com WS/limites, secrets, `admin bootstrap`), `FIREBASE.md`, `BACKUP.md`.
- [5] `README.md` completo (rodar, testar, buildar, release, instalar por plataforma, deploy).
- [6] `.github/dependabot.yml`: gomod, pub, github-actions (+ docker), semanal, agrupado.
- Extra: `.github/workflows/ci-infra.yml` (bats + shellcheck + hadolint + actionlint + buildx + compose dev) e `.github/test/workflows.bats` (13 invariantes dos workflows). `actionlint` limpo em todos os workflows.
## Em andamento
- (nada) — PR aberto para `main`.
## Bloqueios
- **Ambiente local**: `flutter build apk --debug`/`--release` falha aqui por causa do SDK — `flutter_secure_storage 11.0.0` (dep. do app-core) exige `compileSdk=37`, mas o Android SDK só tem `platforms;android-37.0` instalado (naming novo, sem o alvo legado `android-37` que o AGP busca); confirmado pré-existente (falha idêntica com `git stash` das minhas mudanças em `app/android`). Não é causado por esta entrega; validado por leitura do Gradle + testes bats/actionlint/shellcheck, que passam. Sinalizar ao app-core/orquestrador: subir `compileSdk` do app para 37 (ou fixar `flutter_secure_storage` numa versão compatível com SDK 36) quando o ambiente de build tiver a platform certa.
- **server**: healthcheck de produção usa `/relay -healthcheck` (compose) e o RUNBOOK assume `/relay admin bootstrap --name X` e `admin invite --user X`. Até existirem, container em prod ficaria `unhealthy` e `deploy.sh` falharia no gate (não deployamos nesta fase).
- **app-ui**: para o APK release nascer assinado pelo Gradle, `app/android/app/build.gradle.kts` deve ler `android/key.properties` (o workflow já o escreve). Enquanto não ler, o `release.yml` re-assina com `apksigner` — funciona, mas é contorno. Também: aplicar `com.google.gms.google-services` + decodificar `GOOGLE_SERVICES_JSON_B64` no `release.yml` quando o plugin entrar.
- **Felipe**: domínio, projeto Firebase (FIREBASE.md), keystore Android (README → Release) e secrets do environment `production` (RUNBOOK §14). Nada foi executado no Oracle.
- Assumido sem confirmar: nome do `.app` macOS = `chatito.app` (PRODUCT_NAME atual); `.zip` Windows sem instalador; imagem ghcr publicada mas o compose de prod continua com `build:` local (RUNBOOK §7 explica a alternativa).
## Próximo
- Fase 4: executar RUNBOOK no Oracle quando o domínio existir; testar `release.yml` com uma tag `v0.0.1-rc` após o app buildar nas três plataformas.
