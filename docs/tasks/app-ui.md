> **Concluído** (Fase 1, 2026-09-06/07). Mantido como referência do escopo original.

# Tarefa — agente **app-ui** (branch `feat/app-ui`, escopo `app/lib/ui/**`, `app/lib/platform/**`, `app/lib/main.dart`, `app/test/ui/**`, assets)

UI Flutter para macOS, Windows e Android, consumindo a interface `ChatFacade` do app-core
(veja `docs/status/app-core.md`; até ela existir, defina um `ChatFacade` **provisório** em
`lib/ui/contracts.dart` com a mesma assinatura descrita lá e um fake próprio; o orquestrador
unifica no merge). **TDD com widget tests**; fluxos críticos cobertos.

## Entregas (nesta ordem; commit + status a cada item)
1. `pubspec.yaml` só se precisar (avise no status): `flutter_riverpod`, `go_router`,
   `flutter_local_notifications`, `window_manager`, `file_picker`, `qr_flutter`, `mobile_scanner`,
   `firebase_messaging` + `firebase_core` (Android; inicialização guardada por plataforma).
2. Tema e layout responsivo: desktop = lista de conversas à esquerda + chat à direita;
   Android = navegação em pilha. Material 3, modo escuro, pt-BR.
3. Telas: Onboarding (código de convite, nome do device), Lista de conversas, Chat (texto,
   anexos com progresso, recibos entregue/lido), Detalhe do contato com **safety number + QR**,
   Ajustes (devices, notificações, sobre).
4. Anexos: seleção de arquivo, preview de imagem, abrir com app do sistema, progresso de upload/download.
5. Notificações: locais no desktop; no Android, `firebase_messaging` recebe `{"type":"wake"}` e
   dispara sincronização via facade (sem `google-services.json` o app deve rodar normalmente).
6. Widget tests de cada tela com o fake; golden opcional.

## Regras
- Não toque em `lib/{crypto,protocol,transport,storage,domain}` nem em `docs/protocol/**`.
- Acessibilidade básica (semantics, contraste, tamanhos). Mantenha `flutter analyze --fatal-infos` limpo.
