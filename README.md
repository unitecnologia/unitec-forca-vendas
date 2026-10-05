# Unitec Força de Vendas (app Android)

Aplicativo de força de vendas **offline-first** que conversa com o Unitec ERP local
pela API `/api/v1/forca-vendas`. Funciona sem internet e sincroniza a cada ~30s
(pull do catálogo/clientes/financeiro + push dos pedidos da fila).

## Como funciona

1. No app, toque em **Procurar servidor na rede** (ou digite o IP, porta padrão `8765`).
2. O app se registra e mostra um **código de autorização** + o nome do aparelho.
3. No ERP, em **Força de Vendas → Aparelhos**, o admin confere o código e pressiona
   <kbd>F2</kbd> para **autorizar** o aparelho (ou <kbd>F4</kbd> para revogar).
4. O vendedor entra com o **usuário do ERP** e a **senha do app** (campo
   "Senha App Força de Vendas" no cadastro de usuários).
5. O app baixa o catálogo e passa a funcionar offline. Pedidos ficam numa fila local
   (SQLite) e sobem automaticamente quando há rede.

> Não usa câmera/QR Code: a autorização é feita pelo administrador no ERP.

## Pré-requisitos

- Flutter SDK 3.3+ (com toolchain Android: Android SDK + JDK).
- Um dispositivo/emulador Android.

> Esta pasta contém apenas o código-fonte (`lib/`, `pubspec.yaml`). As pastas de
> plataforma (`android/`, `ios/`) são geradas pelo Flutter.

## Primeira configuração

```bash
cd apps/forca-vendas
flutter create .            # gera android/ e ios/ sem sobrescrever lib/
flutter pub get
```

### Permissões e HTTP em rede local (Android)

O ERP na LAN responde em **HTTP** (não HTTPS), então é preciso liberar tráfego "cleartext".
Edite `android/app/src/main/AndroidManifest.xml`:

```xml
<manifest ...>
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
    <uses-permission android:name="android.permission.ACCESS_WIFI_STATE"/>
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>

    <application
        ...
        android:usesCleartextTraffic="true">
        ...
    </application>
</manifest>
```

## Rodar em desenvolvimento

```bash
flutter run
```

## Gerar o APK (distribuição interna)

```bash
flutter build apk --release
# saída: build/app/outputs/flutter-apk/app-release.apk
```

Distribua o `app-release.apk` internamente (sem Play Store). Para 10 aparelhos por
loja, o servidor já roda com múltiplos workers (`PHP_CLI_SERVER_WORKERS`) e bind em
`0.0.0.0:8765`.

## Atualização oficial (GitHub Release)

O canal oficial é a [GitHub Release](https://github.com/unitecnologia/unitec-forca-vendas/releases)
deste repositório. O app consulta a Release mais recente ao abrir (no máximo uma vez
a cada 24 h) e também pelo botão **Atualizar**, ao lado de Online na tela de entrar.

Cada versão publicada leva o APK assinado e o arquivo `.sha256`. As notas precisam
citar o `versionCode` (o número depois do `+` no `pubspec.yaml`).

## Atualizar o app no celular (sem desinstalar)

O Android só aceita **atualização por cima** quando o novo APK tem:

1. **O mesmo pacote** — `com.unitec.unitec_forca_vendas`.
2. **A mesma assinatura digital** — `ci/unitecfv-release.p12` (alias `unitecfv`).
3. **`versionCode` maior** — o número após o `+` no `pubspec.yaml`
   (ex.: `1.4.31+83` → versionCode 83) e o mesmo valor em `lib/app_info.dart`.

Se aparecer *"entra em conflito com um pacote já existente"* ou pedir para
**desinstalar antes**, quase sempre é **assinatura diferente**: o APK antigo foi
gerado com outra chave (build antigo que criava keystore nova a cada vez,
APK de debug local, etc.).

**O que fazer uma vez:** desinstale o app antigo e instale o APK da GitHub Release.
Depois disso, as próximas versões instalam por cima normalmente (mesma chave).

> A keystore de release fica em `ci/unitecfv-release.p12`. Trocar essa chave exige
> desinstalar o app nos aparelhos **uma vez**.

## Estrutura

```
lib/
  main.dart            # roteia: conectar -> aguardando autorização -> login -> home
  config.dart          # configuração persistida (url, device uuid/nome, token)
  app_state.dart       # estado global (conexão, registro/autorização, login, sync)
  api/api_client.dart  # cliente HTTP da API do ERP
  net/discovery.dart   # busca automática do servidor na LAN (ping)
  db/local_db.dart     # SQLite (catálogo + fila de pedidos)
  sync/sync_service.dart # sync 30s (pull ETag + push idempotente)
  screens/
    connect_screen.dart          # procurar servidor / digitar IP
    waiting_approval_screen.dart # registro + código + espera de autorização
    login_screen.dart            # empresa + usuário + senha do app
    home_screen.dart             # status de sync + contadores
    novo_pedido_screen.dart      # criar pedido/orçamento offline (com GPS)
```

## Endpoints usados (ERP)

- `GET  /ping`, `POST /devices/register`, `GET /devices/status` (públicos)
- `GET  /info`, `GET /users?empresa_id=`, `POST /auth/login` (exigem aparelho autorizado)
- `POST /auth/logout`, `GET /auth/me`
- `GET  /sync/pull` (suporta `?since=` e `If-None-Match`/ETag → 304)
- `POST /sync/push` (idempotente por `uuid`)

O acesso é liberado pela **autorização do aparelho** (header `X-FV-Device: <uuid>`,
aprovado pelo admin no ERP). As rotas autenticadas usam `Authorization: Bearer <token>`
(Sanctum).
