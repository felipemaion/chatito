# Chatito — regras para agentes

Leia `PLAN.md` (visão) e `docs/PROTOCOL.md` (contrato) antes de codar. Escopo de cada agente
está em `docs/status/<agente>.md`; **não edite arquivos fora do seu escopo** — peça ao orquestrador.

## TDD (obrigatório)
1. Teste falhando primeiro → implementação mínima → refactor. Sem exceção para código de produção.
2. Cobertura ≥ 80%: `server`: `go test ./... -cover`; `app`: `flutter test --coverage`.
3. Contract tests usam `docs/protocol/fixtures/*.json`. Se o protocolo precisar mudar, proponha ao
   orquestrador via `docs/status/<agente>.md` (seção "Bloqueios") — nunca mude a fixture sozinho.

## Qualidade
- Go: `gofmt`, `go vet`, `golangci-lint run`; erros sempre embrulhados com contexto; sem CGO.
- Dart: `dart format`, `dart analyze` sem warnings; camadas `crypto/protocol/transport/storage/domain`
  são Dart puro (sem `flutter` import) para testar na VM.
- Crypto: só primitivas de alto nível do libsodium. Nada caseiro.
- Segredos nunca no repo. `.env.example` sim.

## Git
- Branch própria por agente (já criada no seu worktree). Commits pequenos, Conventional Commits.
- `git fetch && git rebase origin/main` ao iniciar cada tarefa. Ao terminar um marco: `git push -u origin <branch>` e `gh pr create --fill`. **Nunca** commit em `main`.
- Termine cada commit com a linha `Claude-Session: <URL da sua sessão>` se souber; senão omita.

## Status (economia de tokens)
Atualize `docs/status/<agente>.md` ao concluir cada item: Feito / Em andamento / Bloqueios / Próximo.
O orquestrador lê esse arquivo, não o seu terminal. Respostas curtas; não reler arquivos para conferir.

## Skills recomendadas
`ecc:tdd-workflow`, `ecc:golang-testing`, `ecc:golang-patterns`, `ecc:flutter-test`,
`ecc:dart-flutter-patterns`, `ecc:security-review`, `ecc:docker-patterns`, `ecc:git-workflow`.

## Lições de campo (obrigatórias)
- **Logs em release**: `dart:developer log` não aparece no APK release. Transições importantes
  (boot, WebSocket) usam `print('[chatito.<área>] …')`, sem conteúdo de mensagem nem token.
- **Config persistida**: tudo que o usuário digita no onboarding (URL do servidor, nome) vai para o
  `KeyStore`; nunca dependa de estado em memória sobreviver a um reinício.
- **Sessão antes de rede**: qualquer método da fachada que precise de sessão aguarda `_ready`;
  `connect()` é single-flight; a UI nunca cria um segundo cliente.
- **Navegação**: tela que pode abrir sem pilha (banner, deep link) tem botão de voltar explícito;
  prefira `push` a `go` para telas secundárias.
- **Desktop**: chaves em `FileKeyStore`; não use keychain do macOS sem assinatura com Team ID.
- **Depuração em campo**: `adb -s <serial> logcat -d | grep 'chatito\.'` e o log do relay
  (`docker compose -f docker/docker-compose.dev.yml logs relay`). Antes de concluir "não conecta",
  confirme que o app está em primeiro plano com a tela ligada (`svc power stayon usb` nos testes).
- **Validação local**: `flutter test` no Mac exige Xcode completo; alternativa é a imagem
  `chatito-flutter:3.47.2` (Dockerfile no scratchpad da sessão, replicável a partir do `debian:bookworm-slim`).
