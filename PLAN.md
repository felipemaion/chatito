# Chatito — Plano de Produto, Arquitetura e Orquestração

> Mensageiro privado da família (Felipe, filhos e a mãe deles). Clientes macOS, Windows e
> Android. Servidor de relay **cego** (E2E) que guarda envelopes só até serem entregues.
> Status: **aprovado em 2026-09-06 — Fase 0 concluída, Fase 1 em andamento (4 agentes).**

---

## 1. Decisões já tomadas

| Tema | Decisão | Motivo |
| --- | --- | --- |
| Cliente | **Flutter** (um código para macOS/Windows/Android) | 3 plataformas, ecossistema de chat maduro |
| Servidor | **Go** (binário único, sem CGO, ARM64 nativo) | Já instalado localmente; imagem Docker de ~15 MB; ideal para 2 vCPU |
| Criptografia | **E2E com libsodium** (X25519 + XChaCha20-Poly1305) | Servidor nunca lê conteúdo; casa com "não guarda mensagens" |
| Push Android | **FCM data-only ("acorda e busca")** | Sem conteúdo no Google; bateria normal |
| Domínio | Decidir depois — dev local com Docker | DNS/TLS entram na Fase 4 (deploy) |
| Cadastro | **Fechado**: admin (Felipe) gera convites; sem signup público | Grupo familiar, ~4 pessoas, N dispositivos por pessoa |
| Repo | **Monorepo privado** `felipemaion/chatito` | Protocolo compartilhado, CI única |
| Método | **TDD obrigatório** em todo código de produção | Pedido explícito; gates de cobertura no CI |

### Premissas (corrija se alguma estiver errada)

- iOS/iPhone **não** entra agora (sem conta Apple Developer).
- Distribuição familiar: APK por GitHub Releases (sideload) ou Play "teste interno"; macOS `.dmg`
  sem notarização (abrir com botão direito); Windows `.zip`/instalador sem assinatura (aviso SmartScreen).
- Retenção no servidor: envelope apagado no **ack** de todos os dispositivos destinatários;
  TTL de segurança de **30 dias** para o que nunca for entregue. Arquivos: mesmo critério.
- Tamanho máximo de arquivo: **500 MB**, enviado em **chunks de 8 MB** (Cloudflare proxy limita
  cada request a 100 MB — chunking resolve).
- Conversas: grupo "Família" + 1:1 entre quaisquer membros. Sem áudio/vídeo chamada.
- Testes reais: Felipe tem Mac + Android. Windows é validado no runner do GitHub Actions
  (build + testes) e por instalação manual quando houver máquina.

---

## 2. Arquitetura

```
┌──────────────┐  WSS/HTTPS   ┌─────────────────────┐   FCM v1    ┌─────────┐
│ App Flutter  │◄────────────►│  chatito-relay (Go) │────────────►│ Google  │──► Android
│ macOS/Win/And│  envelopes   │  SQLite + blobs FS  │  "ping"     └─────────┘   (acorda o app)
│ chaves locais│  cifrados    │  fila até o ack     │
└──────────────┘              └─────────────────────┘
        Cloudflare (Proxied) → Caddy → rede docker "proxy" → chatito-relay:8080
```

### 2.1 Servidor — `server/` (Go 1.23+)

- **Identidades**: `users` (nome, papel admin/membro), `devices` (chave pública de identidade,
  token bearer, fcm_token opcional), `invites` (código de uso único emitido pelo admin).
- **Fila**: `envelopes` (id, from_device, to_device, blob cifrado opaco, created_at). Um envelope
  **por dispositivo destinatário** (fan-out feito pelo cliente, que conhece as chaves de todos).
- **Arquivos**: `blobs` (id, owner, size, chunks recebidos, expires_at); chunk upload PUT
  `/v1/blobs/{id}/chunks/{n}`; download por stream. Conteúdo é cifrado no cliente; a chave viaja
  dentro do envelope da mensagem.
- **Tempo real**: WebSocket `/v1/ws` autenticado; servidor empurra envelopes pendentes ao
  conectar e novos em tempo real; cliente responde `ack` → delete imediato.
- **Push**: ao enfileirar para um device com `fcm_token`, envia mensagem **data-only** via FCM
  HTTP v1 (service account em `secrets/env`). Nunca envia conteúdo.
- **Diretório de chaves**: `GET /v1/directory` devolve users + devices + chaves públicas (só para
  autenticados). Verificação de chave é feita fora de banda (safety number / QR) no app.
- **Admin CLI**: `chatito-relay admin invite --user "Felipe"` gera código; rodado via
  `docker compose exec`.
- **Persistência**: SQLite (`modernc.org/sqlite`, sem CGO), WAL, em `/app/data`; blobs em
  `/app/data/blobs`. Job de expiração a cada hora.
- **Operacional**: `/healthz`, logs JSON, limites de tamanho, rate limit por device,
  graceful shutdown. Imagem `FROM gcr.io/distroless/static` multi-arch (arm64 + amd64).

### 2.2 App — `app/` (Flutter 3.2x, Dart 3)

Camadas (Clean-ish, testável sem UI):

| Camada | Pacotes | Responsabilidade |
| --- | --- | --- |
| `crypto` | `sodium_libs` | Identidade do device, `crypto_box` por mensagem (chave efêmera), cifra de arquivos em stream (`secretstream`), safety number |
| `protocol` | `json_serializable` | Modelos e (de)serialização dos envelopes/DTOs; **fixtures compartilhadas com o servidor** |
| `transport` | `web_socket_channel`, `dio` | Cliente REST + WS com reconexão, fila de saída offline, upload em chunks com retomada |
| `storage` | `drift` + `flutter_secure_storage` | Mensagens, conversas, anexos locais; chaves privadas no keychain/keystore |
| `domain` | Dart puro | Casos de uso: enviar mensagem, receber, fan-out por device, marcar lido, enviar arquivo |
| `ui` | `flutter_riverpod`, `go_router` | Telas: onboarding (convite + QR), lista de conversas, chat, anexos, verificação de chave, ajustes |
| `platform` | `firebase_messaging`, `flutter_local_notifications`, `window_manager` | Push Android, notificações desktop, bandeja |

Fluxo de onboarding: admin gera convite → novo device digita o código → gera par de chaves →
registra no servidor → recebe diretório → mostra safety numbers para conferir presencialmente.

### 2.3 Protocolo — `docs/PROTOCOL.md` (contrato, escrito **antes** do código paralelo)

- Endpoints REST/WS, códigos de erro, limites.
- Formato do envelope: `{v, type, from, to, nonce, ciphertext}`; payload decifrado:
  `{msg_id, conv_id, kind: text|file|receipt|key_change, body, sent_at, attachments[]}`.
- Fixtures JSON em `docs/protocol/fixtures/` usadas em **contract tests** dos dois lados.

---

## 3. TDD e qualidade — regras para todos os agentes

1. **Red → Green → Refactor**, sempre: nenhum arquivo de produção nasce sem um teste falhando antes.
2. Cobertura mínima: Go `go test -cover` ≥ 80%; Flutter `flutter test --coverage` ≥ 80% nas
   camadas `crypto/protocol/transport/storage/domain`; UI com widget tests dos fluxos críticos.
3. CI bloqueia merge: `go vet`, `golangci-lint`, `gofmt`; `dart analyze`, `dart format --set-exit-if-changed`.
4. Skills a usar: `ecc:tdd-workflow`, `ecc:golang-testing` + `ecc:golang-patterns`,
   `ecc:flutter-test` + `ecc:dart-flutter-patterns`, `ecc:security-review` (crypto e auth),
   `ecc:docker-patterns`, `ecc:git-workflow`. Revisão antes de merge: `ecc:go-review`,
   `ecc:flutter-review`, `ecc:security-reviewer`.
5. Commits pequenos, Conventional Commits, PR por feature; **nunca** commit direto em `main`.
6. Segredos nunca no repo: `.env.example` + `secrets/env` no servidor.

---

## 4. Estrutura do repositório

```
chatito/
├── PLAN.md  README.md  CLAUDE.md          ← CLAUDE.md = regras acima, para os agentes
├── docs/
│   ├── PROTOCOL.md
│   ├── protocol/fixtures/*.json
│   ├── adr/                              ← decisões (ADR curtos)
│   └── status/<agente>.md                ← quadro de progresso por agente
├── server/          (go.mod, cmd/relay, internal/{api,ws,store,push,crypto,admin})
├── app/             (pubspec.yaml, lib/{crypto,protocol,transport,storage,domain,ui,platform}, test/)
├── docker/          (Dockerfile, docker-compose.yml, docker-compose.dev.yml)
├── cron/deploy.sh   (alvo do forced-command no Oracle)
└── .github/workflows/{ci-server,ci-app,release,deploy}.yml
```

---

## 5. Fases e gates

| Fase | O quê | Quem | Gate para avançar |
| --- | --- | --- | --- |
| **0 — Fundação** (sequencial) | Repo privado no GitHub; scaffold; `CLAUDE.md`; `PROTOCOL.md` + fixtures; instalar Flutter + Android SDK; CI vazia verde; worktrees e janela tmux | Orquestrador (esta sessão) | CI verde; protocolo revisado por você |
| **1 — Núcleo** (paralelo, 4 agentes) | A: servidor completo com testes. B: app crypto+protocol+transport+storage. C: app UI com backend fake em memória. D: Docker ARM64, workflows, deploy.sh, docs de operação | 4 agentes em panes | Cada branch: testes ≥ 80%, review aprovado, merge em `main` |
| **2 — Integração** (2 agentes) | App real ↔ servidor em Docker local; teste E2E (2 devices trocando texto e arquivo); FCM (precisa do projeto Firebase) | A+B juntos; C ajusta UI | E2E verde; mensagem Mac→Android com push |
| **3 — Release** | Builds: APK assinado (keystore próprio), `.dmg`, `.zip` Windows via Actions; página de download privada (Releases) | D | Instalação em Mac e Android reais |
| **4 — Deploy Oracle** | User `chatito01`, `/home/<DOMINIO>/`, Caddy, Cloudflare, secrets, CD por forced-command | Agente de infra + pane SSH da sessão `Oracle` | Smoke externo; primeira conversa da família |

Dependências externas que só você pode fazer (aviso antecipado):
- **Firebase**: criar projeto e baixar `google-services.json` + service account (Fase 2). Posso guiar pelo Chrome.
- **Domínio** (Fase 4) e registro A na Cloudflare.
- **Senhas/segredos** colados no servidor via `nano` (gotcha 12 do SERVER.md).

---

## 6. Orquestração — agentes paralelos em tmux

### 6.1 Layout

Nova janela `dev` na sessão `Chatito`, 5 panes (cada `claude` interativo, sem `-p`):

| Pane | Agente | Worktree / branch | Escopo |
| --- | --- | --- | --- |
| `dev.0` | **A · server** | `~/Projects/chatito-wt/server` · `feat/server` | `server/**` |
| `dev.2` | **B · app-core** | `~/Projects/chatito-wt/app-core` · `feat/app-core` | `app/lib/{crypto,protocol,transport,storage,domain}` |
| `dev.1` | **C · app-ui** | `~/Projects/chatito-wt/app-ui` · `feat/app-ui` | `app/lib/ui`, `app/lib/platform`; usa interfaces do B com fakes |
| `dev.3` | **D · infra** | `~/Projects/chatito-wt/infra` · `feat/infra` | `docker/`, `.github/`, `cron/`, docs |
| `dev.4` | shell | `~/Projects/Chatito` (main) | testes/merges/logs do orquestrador |

O **orquestrador** é esta sessão (`Chatito:2.1`): escreve o contrato, distribui tarefas, faz
review e merge, resolve conflitos e fala com você.

### 6.2 Isolamento e integração

- **Git worktrees**: um por agente, branch própria; evita conflito de arquivo. Escopos de
  diretório disjuntos; B expõe interfaces (`abstract class`) que C consome via fakes.
- **Merge**: agente abre PR (`gh pr create`); orquestrador roda review (`ecc:go-review` /
  `ecc:flutter-review` / `ecc:security-reviewer`) e faz `gh pr merge --squash`. Agentes fazem
  `git rebase main` ao começar cada tarefa.
- **Comunicação** (convenções do SERVER.md §12): `tmux send-keys -t Chatito:dev.N` com **texto e
  `Enter` em chamadas separadas**; leitura por `capture-pane`; cada agente mantém
  `docs/status/<agente>.md` (feito / em andamento / bloqueios) que o orquestrador lê em vez de
  ler o pane inteiro (economia de tokens).
- **Regra de validação**: antes de agir sobre pedido de outro agente, conferir a premissa
  (ler o commit/arquivo citado).

### 6.3 Custo estimado (para aprovar antes de disparar)

Cada agente interativo carrega ~22k tokens de ambiente por turno (medido neste setup). Fase 1
com 4 agentes por ~3–5 h de trabalho autônomo cada tende a consumir na ordem de **alguns
milhões de tokens no total** (estimativa grosseira: 4 agentes × 150–300 turnos × ~25–40k).
Para reduzir: escopos bem fechados, `CLAUDE.md` curto no repo, status em arquivo em vez de
conversa, e agentes de revisão rodando com Sonnet quando a tarefa for mecânica.
Fases 0, 2, 3 e 4 são bem menores (1–2 agentes).

---

## 7. Riscos e mitigação

| Risco | Mitigação |
| --- | --- |
| Crypto caseira errada | Só primitivas libsodium de alto nível (`crypto_box_seal`/`secretstream`); sem ratchet custom; `ecc:security-review` obrigatório; vetores de teste fixos |
| Android matando o app / push atrasado | FCM data-only com prioridade alta; app busca fila ao acordar; WS quando em foreground |
| Builds Flutter desktop na CI lentos/quebrando | Cache de pub e SDK; matriz `macos-latest`/`windows-latest`/`ubuntu-latest`; builds só em tag |
| Servidor 2 vCPU | Binário Go leve; build multi-arch na CI (não no servidor) |
| Perda de chaves ao trocar de celular | Backup cifrado das chaves com frase (fase 2+); histórico é local por design |
| Conflitos entre agentes | Worktrees + escopos disjuntos + contrato de interfaces antes da Fase 1 |

---

## 8. Próximo passo

Com sua aprovação deste plano, a Fase 0 começa: criar o repo privado, instalar Flutter/Android
SDK (download grande, ~2–3 GB), escrever `PROTOCOL.md` e abrir a janela `dev` com os 4 agentes.
