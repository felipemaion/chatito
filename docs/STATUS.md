# Piriquito — estado do projeto (2026-09-08)

Fonte única de "onde estamos". Histórico por agente em `docs/status/<agente>.md`.

## Funciona hoje
- **Relay** (Go) em Docker local, projeto `piriquito`, `127.0.0.1:8080` (exposto na LAN via override
  quando necessário). Bootstrap/convites: `docker compose -f docker/docker-compose.dev.yml exec -T relay /relay admin invite --user NOME`.
- **App** (Flutter) em `main`: Android (APK arm64 release, `flutter build apk --release --split-per-abi`),
  macOS (build debug local; keychain substituído por arquivo), Windows (build na CI sob demanda).
- **Validado em campo** (2026-09-07/08): Galaxy A26, Galaxy S8 e Mac conectados ao mesmo tempo; texto,
  grupo "Família", arquivos, recibos; reconexão ao reabrir após segundo plano (A26) e conexão mantida
  com tela apagada (S8). Sem push ainda: mensagem chega ao abrir o app.
- **Testes**: servidor 85% de cobertura; app 207 testes (unit, widget, integração real Go↔Dart com
  `RELAY_URL`). CI: `ci-server`, `ci-app` (desktop só com label `build-desktop`), `ci-infra`.

## Como um aparelho novo entra
1. Admin gera convite (comando acima). 2. No app: código, nome do aparelho e **URL do servidor**
(`http://<ip-ou-domínio>:8080`). 3. Conferir safety number presencialmente. A URL pode ser
alterada depois em **Ajustes → Servidor** (aparelhos anteriores a 2026-09-07 precisam preencher
uma vez: a faixa "Servidor não configurado" leva até lá).

## Pendências
| Item | Dono | Observação |
| --- | --- | --- |
| Release `v0.1.0` (APK assinado, `.dmg`, `.zip`) via `release.yml` | orquestrador | precisa de keystore Android (README › Release) |
| Firebase (push com app fechado) | Felipe + infra | `docs/ops/FIREBASE.md` |
| Domínio + deploy no Oracle (Fase 4) | Felipe + infra | `docs/ops/RUNBOOK.md`; sem isso o app só funciona na Wi-Fi do Mac |
| Remover aparelhos "Mac" órfãos | Felipe | Ajustes → Meus aparelhos |
| Rotação de chave (`key_change` emitido) | app-core | v1 só detecta troca pelo diretório |
| Histórico do git contém o IP do Oracle | Felipe decide | `git filter-repo` + force push, se quiser |

## Bugs de campo já corrigidos (para não regredir)
URL do servidor não persistida · corrida de boot (`_ready`) · sockets zumbis/4409 · três `RelayWs`
por `connect()` concorrente · keychain do macOS · Ajustes sem "voltar" · logs invisíveis em release.
Detalhes em `PLAN.md` §9.
