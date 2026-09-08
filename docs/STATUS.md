# Piriquito — estado do projeto (2026-09-08, Fase 4 no ar)

Fonte única de "onde estamos". Histórico por agente em `docs/status/<agente>.md`.

## Funciona hoje
- **Nome**: o projeto chamava-se Chatito até 2026-09-08 (PR #15). O repo antigo redireciona; imagens, volumes
  e apps instalados com o nome antigo não são migrados.
- **Relay em produção**: `https://piriquito.maionesys.com` (Oracle, container `piriquito-relay` atrás de
  Cloudflare + Caddy; CD pelo `deploy.yml` a cada push em `main` que toque `server/`, `docker/`, `cron/`).
  Operação do servidor: orquestrador da sessão tmux `Oracle` (regras em `~/Projects/OracleServer/SERVER.md`).
  Convites de produção: `docker compose -f docker/docker-compose.yml exec -T relay /relay admin invite --user NOME`
  em `/home/piriquito.maionesys.com/repo`, como `piriquito01`.
- **Relay local** (dev): Docker, projeto `piriquito`, `127.0.0.1:8080` (exposto na LAN via override quando
  necessário). Bootstrap/convites: `docker compose -f docker/docker-compose.dev.yml exec -T relay /relay admin invite --user NOME`.
- **App** (Flutter) em `main`: Android (APK arm64 release, `flutter build apk --release --split-per-abi`),
  macOS (build debug local; keychain substituído por arquivo), Windows (build na CI sob demanda).
- **Validado em campo** (2026-09-07/08): Galaxy A26, Galaxy S8 e Mac conectados ao mesmo tempo; texto,
  grupo "Família", arquivos, recibos; reconexão ao reabrir após segundo plano (A26) e conexão mantida
  com tela apagada (S8). Sem push ainda: mensagem chega ao abrir o app.
- **Testes**: servidor 85% de cobertura; app 207 testes (unit, widget, integração real Go↔Dart com
  `RELAY_URL`). CI: `ci-server`, `ci-app` (desktop só com label `build-desktop`), `ci-infra`.

## Como um aparelho novo entra
1. Admin gera convite (comando acima). 2. No app: código, nome do aparelho e **URL do servidor**
(release já vem com `https://piriquito.maionesys.com`). 3. Conferir safety number presencialmente. A URL pode ser
alterada depois em **Ajustes → Servidor** (aparelhos anteriores a 2026-09-07 precisam preencher
uma vez: a faixa "Servidor não configurado" leva até lá).

## Pendências
| Item | Dono | Observação |
| --- | --- | --- |
| Onboarding no app novo (A26, S8, Mac) em **produção** (2026-09-08) | Felipe | APK Piriquito instalado no A26 e no S8 (o Chatito antigo continua ao lado até desinstalar); Mac usa `Piriquito.app`. Build release já vem com `https://piriquito.maionesys.com` como servidor padrão. Convites: Felipe `A0QP-KYAN` (válido até 2026-09-15); Mãe: pedido ao orquestrador do Oracle |
| Release `v0.1.0` (APK assinado, `.dmg`, `.zip`) via `release.yml` | orquestrador | precisa de keystore Android (README › Release) |
| Firebase (push com app fechado) | Felipe + infra | `docs/ops/FIREBASE.md` |
| Remover aparelhos "Mac" órfãos | Felipe | Ajustes → Meus aparelhos |
| Rotação de chave (`key_change` emitido) | app-core | v1 só detecta troca pelo diretório |
| Histórico do git contém o IP do Oracle | Felipe decide | `git filter-repo` + force push, se quiser |

## Bugs de campo já corrigidos (para não regredir)
URL do servidor não persistida · corrida de boot (`_ready`) · sockets zumbis/4409 · três `RelayWs`
por `connect()` concorrente · keychain do macOS · Ajustes sem "voltar" · logs invisíveis em release.
Detalhes em `PLAN.md` §9.
