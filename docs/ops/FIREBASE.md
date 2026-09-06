# Firebase — push Android (FCM data-only)

O relay envia ao Android apenas `{"type":"wake"}` via FCM HTTP v1 (PROTOCOL §4). Nenhum conteúdo
passa pelo Google. Sem Firebase o app segue funcionando por WebSocket em primeiro plano; o push só
acorda o app em segundo plano. Precisa ser feito **por você** (conta Google); leva ~10 min.

## 1. Criar o projeto

1. <https://console.firebase.google.com> → **Adicionar projeto** → nome `chatito` → desative o
   Google Analytics (não é usado) → Criar.
2. Menu ⚙ → **Configurações do projeto** → guarde o **ID do projeto** (ex.: `chatito-a1b2c`).

## 2. Registrar o app Android e baixar `google-services.json`

1. Na visão geral → ícone **Android** → *Nome do pacote Android*: **`br.com.maion.chatito`**
   (é o `applicationId` em `app/android/app/build.gradle.kts`; tem que bater exatamente).
2. Apelido: `Chatito Android`. Certificado SHA-1: opcional (só para Auth/Dynamic Links — não usamos).
3. **Baixar `google-services.json`** → colocar em **`app/android/app/google-services.json`**.
   O arquivo está no `.gitignore`; não commitar. Cada dev que builda Android precisa de uma cópia.
4. Pule os passos de Gradle do assistente: o plugin `com.google.gms.google-services` é aplicado pelo
   agente **app-ui** (`app/android/app/build.gradle.kts`) junto com `firebase_messaging`.

Para a CI (`release.yml`) gerar um APK com push: crie o secret `GOOGLE_SERVICES_JSON_B64`
(`base64 -w0 app/android/app/google-services.json`) — o passo que o decodifica entra quando o
app-ui aplicar o plugin (registrado em `docs/status/infra.md` → Bloqueios).

## 3. Service account para o servidor (FCM HTTP v1)

1. ⚙ → **Configurações do projeto** → guia **Contas de serviço** → *Firebase Admin SDK* →
   **Gerar nova chave privada** → baixa `chatito-xxxx-firebase-adminsdk-....json`.
2. Confirme que a API **Firebase Cloud Messaging API (V1)** está ativada
   (guia *Cloud Messaging*; se aparecer "desativada", clique em *Gerenciar API no Google Cloud* → Ativar).
3. Converta e coloque no servidor (`/home/<DOMINIO>/secrets/env`, via `nano` — gotcha 12):

```bash
base64 -w0 chatito-xxxx-firebase-adminsdk-....json   # macOS: base64 -i arquivo.json | tr -d '\n'
# → FCM_SERVICE_ACCOUNT_B64=<saída>
```

4. Apague o JSON da sua máquina depois (ou guarde no gerenciador de senhas). Nunca no repo
   (`service-account*.json` está no `.gitignore`).
5. Recrie o container para reler o env: `docker compose -f docker/docker-compose.yml up -d --force-recreate`.

Dev local: exporte `FCM_SERVICE_ACCOUNT_B64` no shell antes do `docker compose ... up`, ou deixe
vazio (push desligado, log avisa uma vez).

## 4. Verificar

| Onde | Como |
| --- | --- |
| Servidor | log do relay ao subir: `push: fcm enabled (project chatito-xxxx)` |
| App | Ajustes → Diagnóstico → "token FCM registrado"; `PUT /v1/devices/me/push` retorna 204 |
| Ponta a ponta | app Android em segundo plano; envie mensagem do Mac; o Android deve buscar a fila em segundos |

## 5. Rotação / revogação

Console → Contas de serviço → *Gerenciar permissões da conta de serviço* (Google Cloud IAM) →
chave antiga → **Excluir**. Gere nova, atualize `FCM_SERVICE_ACCOUNT_B64`, `--force-recreate`.
