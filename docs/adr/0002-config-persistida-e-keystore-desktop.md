# ADR 0002 — Configuração persistida no KeyStore e chaves em arquivo no desktop
Data: 2026-09-08 · Status: aceito

**Contexto.** Em campo, o app voltava ao endereço padrão do emulador após reiniciar (URL só em
memória) e, no macOS, cada build com assinatura ad-hoc perdia acesso ao keychain (pedidos de senha,
identidade "sumia").

**Decisão.** (1) A URL do servidor é gravada no mesmo `KeyStore` da identidade e do token, lida antes
de construir a fachada, e editável em Ajustes. (2) Em macOS/Windows/Linux o `KeyStore` é um arquivo
JSON com permissão 0600 no diretório de suporte do app (`FileKeyStore`); Android continua no
Keystore via `flutter_secure_storage`.

**Consequências.** Sem dependência de assinatura Apple (Developer ID) para o app funcionar; a
proteção das chaves no desktop passa a ser a do sistema de arquivos do usuário (FileVault
recomendado). Migração automática do keychain para o arquivo quando os itens ainda existem.
