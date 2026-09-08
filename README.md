# Piriquito

Mensageiro privado da família — macOS, Windows e Android. Servidor de relay **cego** (E2E com
libsodium) em Go que guarda mensagens só até serem entregues; histórico vive nos dispositivos.

| Documento | O quê |
| --- | --- |
| [`PLAN.md`](PLAN.md) | plano, arquitetura, fases e orquestração |
| [`docs/PROTOCOL.md`](docs/PROTOCOL.md) | contrato cliente ↔ servidor (fixtures em `docs/protocol/fixtures/`) |
| [`docs/ops/RUNBOOK.md`](docs/ops/RUNBOOK.md) | provisionar e operar no VPS Oracle |
| [`docs/ops/FIREBASE.md`](docs/ops/FIREBASE.md) | push Android (FCM data-only) |
| [`docs/ops/BACKUP.md`](docs/ops/BACKUP.md) | backup/restauração (só `relay.db`) |
| [`CLAUDE.md`](CLAUDE.md) | regras para agentes (TDD, escopos, git) |

```
server/   relay em Go (SQLite, WebSocket, FCM)      docker/   Dockerfile multi-arch + compose dev/prod
app/      cliente Flutter (macOS/Windows/Android)   cron/     deploy.sh (forced-command no Oracle) + testes bats
docs/     protocolo, ops, status dos agentes        .github/  ci-server, ci-app, ci-infra, release, deploy, dependabot
```

## Pré-requisitos

| Ferramenta | Versão | Para |
| --- | --- | --- |
| Go | 1.25+ | `server/` |
| Flutter (stable) | 3.47.x (Dart 3) | `app/` — `flutter doctor` verde para o alvo desejado |
| Docker Desktop / Engine + buildx | 28+ | imagem e compose |
| bats, shellcheck, hadolint, actionlint | qualquer | testes de infra (`brew install bats-core shellcheck hadolint actionlint flock`) |
| Android SDK (via Android Studio) + JDK 17 | — | APK |
| Xcode + CocoaPods | — | macOS |
| Visual Studio "Desktop development with C++" | — | Windows |

## Rodar local

### Servidor

```bash
cd server && go run ./cmd/relay                     # http://localhost:8080/healthz
# ou em Docker (mesma imagem de produção, porta só em loopback):
docker compose -f docker/docker-compose.dev.yml up --build
curl -s http://127.0.0.1:8080/healthz              # {"status":"ok"}
```

Variáveis: `RELAY_ADDR` (`:8080`), `RELAY_DATA_DIR` (`/app/data`), `RELAY_PUBLIC_URL`,
`FCM_SERVICE_ACCOUNT_B64` (vazio = push desligado). Modelo em `docker/env.example`.

Primeiro usuário (o admin) e convite:

```bash
docker compose -f docker/docker-compose.dev.yml exec relay /relay admin bootstrap --name Felipe
```

### App

```bash
cd app && flutter pub get
flutter run -d macos          # ou: -d windows | -d <android-device-id>
```

Aponte o app para `http://127.0.0.1:8080` na tela de onboarding e cole o convite.
Push Android só com `app/android/app/google-services.json` (ver `docs/ops/FIREBASE.md`).

## Testar

```bash
# servidor (gate ≥ 80% de cobertura)
cd server && gofmt -l . && go vet ./... && golangci-lint run && go test ./... -race -cover

# app (gate ≥ 80% em crypto/protocol/transport/storage/domain)
cd app && dart format --set-exit-if-changed lib test && flutter analyze --fatal-infos && flutter test --coverage

# infra: deploy.sh com git/docker mockados + invariantes dos workflows
bats cron/test .github/test
shellcheck cron/deploy.sh && hadolint docker/Dockerfile && actionlint
```

Os contract tests dos dois lados usam `docs/protocol/fixtures/*.json`; mudanças no protocolo
passam pelo orquestrador (nunca edite uma fixture sozinho).

## Buildar

```bash
# imagem do relay, multi-arch (é o que a CI faz; sem push)
docker buildx build --platform linux/arm64,linux/amd64 -f docker/Dockerfile -t piriquito-relay:dev .

cd app
flutter build apk --release        # build/app/outputs/flutter-apk/app-release.apk
flutter build macos --release      # build/macos/Build/Products/Release/Piriquito.app
flutter build windows --release    # build/windows/x64/runner/Release/
```

## Release (binários para a família)

`git tag v0.1.0 && git push origin v0.1.0` → o workflow `release.yml` gera e anexa a um
**GitHub Release** (privado): `piriquito-<tag>-android.apk`, `piriquito-<tag>-macos.dmg`,
`piriquito-<tag>-windows.zip`, `SHA256SUMS`, e publica `ghcr.io/felipemaion/piriquito-relay:<tag>`
(amd64 + arm64).

APK **assinado** exige os secrets de repositório `ANDROID_KEYSTORE_B64`, `ANDROID_KEY_ALIAS`,
`ANDROID_KEY_PASSWORD`, `ANDROID_STORE_PASSWORD`; sem eles sai um APK **debug** (não atualiza
por cima de um assinado). Gerar a keystore uma vez e guardar no gerenciador de senhas:

```bash
keytool -genkey -v -keystore piriquito-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias piriquito
gh secret set ANDROID_KEYSTORE_B64 --repo felipemaion/piriquito --body "$(base64 -i piriquito-upload.jks | tr -d '\n')"
gh secret set ANDROID_KEY_ALIAS --repo felipemaion/piriquito --body piriquito
gh secret set ANDROID_KEY_PASSWORD --repo felipemaion/piriquito     # pede o valor
gh secret set ANDROID_STORE_PASSWORD --repo felipemaion/piriquito
```

## Instalar

| Plataforma | Como | Aviso esperado |
| --- | --- | --- |
| **Android** | Baixar o `.apk` no celular → abrir → permitir "instalar apps desconhecidos" para o navegador/Arquivos | Play Protect pode pedir confirmação ("instalar mesmo assim") |
| **macOS** | Abrir o `.dmg` → arrastar `Piriquito.app` para *Applications* → **botão direito → Abrir** na 1ª vez (não notarizado) | "não pode ser verificado" — Abrir mesmo assim; ou `xattr -dr com.apple.quarantine /Applications/Piriquito.app` |
| **Windows** | Extrair o `.zip` numa pasta (ex.: `C:\Piriquito`) → executar `piriquito.exe`; atalho manual | SmartScreen: *Mais informações → Executar assim mesmo* (sem assinatura) |

Atualizar = instalar a versão nova por cima (Android exige a **mesma** assinatura; macOS/Windows
substituir a pasta/app). Os dados ficam no perfil do usuário e sobrevivem.

Depois de instalar: peça um convite ao admin, cole na tela de onboarding, e **confira o safety
number** presencialmente com cada pessoa (Ajustes → Verificar chave).

## Configurar o servidor no app

No onboarding o app pede o código de convite, o nome do aparelho e a **URL do servidor**
(build release já vem com `https://piriquito.maionesys.com`; em dev, `http://<ip>:8080` na Wi-Fi local). A URL fica gravada e pode ser
trocada em **Ajustes → Servidor**. Se aparecer a faixa "Servidor não configurado", toque em Ajustes.

## Depuração em campo (Android por USB)

```bash
adb devices                                      # depuração USB ligada no aparelho
adb -s <serial> logcat -d | grep 'piriquito\.'     # [piriquito.boot] e [piriquito.ws] (também no release)
docker compose -f docker/docker-compose.dev.yml logs --since 5m relay | grep 'ws '
```

Estado atual e pendências: `docs/STATUS.md`. Lições de campo: `PLAN.md` §9.

## Deploy (VPS Oracle)

Push em `main` que toque `server/**`, `docker/**` ou `cron/**` (ou `workflow_dispatch`) roda
`deploy.yml`: uma conexão SSH com host key fixa → forced-command executa `cron/deploy.sh` no
servidor (reset em `origin/main`, `docker compose up -d --build`, espera `healthy`, imprime
`===DEPLOY_OK===`) → smoke em `https://<DOMINIO>/healthz`. Provisionamento completo e operação:
[`docs/ops/RUNBOOK.md`](docs/ops/RUNBOOK.md). Nada roda no servidor antes da Fase 4.

## Contribuir (agentes e humanos)

TDD obrigatório, Conventional Commits, branch por escopo e PR para `main` — detalhes em
[`CLAUDE.md`](CLAUDE.md). Status de cada frente em `docs/status/<agente>.md`.
