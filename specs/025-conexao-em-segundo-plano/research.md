# Pesquisa: 025-conexao-em-segundo-plano

## D1 — Mecanismo de manter a conexão viva (decisão do usuário)

**Decisão**: serviço em primeiro plano do Android com notificação local; **sem** FCM/UnifiedPush.
**Alternativas avaliadas**: (a) FCM — depende do Google e de um backend que publique o push, quebra "sem
intermediário"; (b) UnifiedPush/servidor próprio observando o relay — reintroduz componente central; (c) WorkManager
periódico — mínimo de 15 min e sem conexão contínua, inútil para solicitação efêmera; (d) engine em cache + serviço
nativo mantendo o isolate da UI vivo — zero refactor mas Kotlin próprio e frágil (renderização sem Activity).
**Risco assumido**: fabricantes com economia de bateria agressiva ainda podem matar o serviço.

## D2 — Pacotes (Princípio III)

| Critério | `flutter_foreground_task` | `flutter_background_service` | Kotlin próprio |
|---|---|---|---|
| Última versão / data | 11.0.3 · 2026-09-07 | 5.1.0 · 2024-12-21 | n/a |
| Isolate/handler Dart próprio | sim (`TaskHandler`) | sim | a escrever |
| Tipos de serviço (Android 14) | suportados | limitado | a escrever |
| Canal UI↔serviço | `sendDataToTask`/`addTaskDataCallback` | `invoke`/`on` | MethodChannel próprio |
| Manutenção | ativa (publicado há ~1 mês) | parada há ~10 meses | do autor |

**Decisão**: `flutter_foreground_task` 11.0.3. Para notificações: `flutter_local_notifications` 22.3.1 (2026-09-13),
padrão do ecossistema, canais com importância, ação de toque. `pub add --dry-run` (2026-10-11) resolve sem conflito
(`timezone` transitivo). **Acoplamento**: ambos só em `services/background/` e `ride_request_notifier.dart`;
`domain/` e telas usam tipos próprios (`ServiceMessage`, `RideRequestFilter`).

## D3 — Tipo do serviço em primeiro plano

`dataSync` sofre limite de execução no Android 15 (≈ 6 h por 24 h) e inconsistência semântica; `location` exigiria
permissão de localização que o serviço não usa (a constituição proíbe permissão "para o futuro");
`remoteMessaging` é descrito para mensagens entre dispositivos e tem restrições de política. **Decisão**:
`specialUse` com `PROPERTY_SPECIAL_USE_FOLLOWUP`/subtipo "conexão contínua com relays Nostr para receber
solicitações de corrida". Sem revisão de loja no escopo do TCC. **Confirmado no spike (T002), ver abaixo.**

### Resultado do spike (T002) — 2026-10-11, emulador `Pixel_6_API34_1` (Android 14, API 34)

App descartável fora do repositório (`flutter create`, mesma cadeia do motorista: AGP 9.1.0, Kotlin 2.4.0, Gradle
9.3.1) com `flutter_foreground_task` 11.0.3 + `flutter_local_notifications` 22.3.1, `serviceTypes: specialUse`,
`allowWakeLock: false`. O `TaskHandler` abre `dart:io` `WebSocket` a `wss://nos.lol`, assina `kind 1`
(`limit 0`, tráfego contínuo) e, com no máximo uma por minuto, mostra uma notificação de alta importância.

| Verificação | Resultado |
|---|---|
| Serviço inicia com `specialUse` no API 34 | OK — `isForeground=true`, `types=0x40000000` |
| WebSocket real e notificação a partir do isolate do serviço | OK — conectou em ~1,2 s; notificação em canal `importance=4` (alta) |
| App deslizado dos recentes (tarefa removida: 0 entradas em `dumpsys activity recents`) | OK — mesmo PID, serviço em primeiro plano, WebSocket aberto, batimentos a cada 5 s, 2ª notificação gerada depois |
| Tela apagada + `dumpsys deviceidle force-idle` (Doze profundo forçado) por ~4 min | Eventos continuaram chegando (≈ 1 a 10 por 20 s) e a notificação foi gerada em Doze. **Ressalva**: Doze forçado no emulador; em aparelho real o Doze só entra com o aparelho parado e sem carregar (o motorista dirigindo não entra). Cenário 6 do quickstart cobre o aparelho. |
| Queda de rede (`svc wifi/data disable` 25 s e volta) | Socket caiu (`Failed host lookup`), reconectou sozinho em ~10 s após a rede voltar e os eventos retomaram (no app de produção quem reconecta é o `RelayService`, 15 s) |
| `stopService` com o app reaberto | OK — `onDestroy`, `ServiceRecord` removido, notificação fixa removida |

Achados que mudam tarefas:
1. **`specialUse` funciona** (D3 confirmada; sem fallback para `dataSync`). Exige `FOREGROUND_SERVICE_SPECIAL_USE`
   e `<property android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE">` dentro do `<service>`.
2. **`flutter_local_notifications` exige *core library desugaring*** no `android/app/build.gradle.kts`
   (`isCoreLibraryDesugaringEnabled = true` + `coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")`);
   sem isso o build falha. Entra em T003/T004.
3. **`WAKE_LOCK` já vem mesclado pelo manifesto do plugin** (`granted=true`) mesmo sem declarar. Com
   `allowWakeLock: false` o serviço funcionou, inclusive em Doze forçado; portanto não declarar `WAKE_LOCK` no app
   e remover a mescla com `tools:node="remove"` se a permissão não for necessária (Restrições de Segurança).
4. **O serviço sobrevive a tarefa removida por padrão** (`stopWithTask` ausente = falso); não usar
   `android:stopWithTask="true"`.
5. Em Android 13+ é preciso conceder `POST_NOTIFICATIONS` antes (no spike, `pm grant`); no app, FR-009.
6. `flutter_local_notifications` 22.x usa parâmetros **nomeados** (`initialize(settings:)`, `show(id:, title:, body:,
   notificationDetails:)`).

Não testado no spike (fica para os cenários do quickstart em aparelho): fabricantes com economia de bateria
agressiva, `Forçar parada` (esperado: mata o serviço), morte do processo por falta de memória, bateria/hora.

## D4 — Onde a conexão vive

**Decisão (usuário)**: toda no isolate do serviço; UI via `RemoteRelayConnection`. Consequência: o serviço precisa
rodar também com o app visível e motorista offline (a UI não tem outra conexão) — ciclo de vida em plan.md.
**Alternativa descartada**: duas conexões (serviço só para 20001). Mais simples, mas o usuário preferiu uma única.

## D5 — O que cruza o canal

Só tipos primitivos (`Map`/`List`/`String`/`int`/`bool`), serializados em `service_messages.dart`. Eventos entram
na UI como `IncomingEvent` (payload bruto **já verificado** pelo serviço); a UI mantém `EventFeed` e sua própria
verificação (defesa em profundidade, custo desprezível; as regras 1/2/6 do contrato valem nos dois lados). Publicar:
a UI assina/cifra e envia `payload` + `id`; o serviço publica pelo gateway e devolve `PublishOutcome` por relay.
A chave privada nunca cruza o canal (FR-008, Princípio I).

## D6 — Estado que o serviço precisa

`online`, `acceptedPayments`, `rideStatus`, `appInForeground`. Origem: UI, por mensagem `state`; **persistido** em
`KeyValueStore` (chaves novas, prefixo `background.`) para o serviço reler ao ser reiniciado pelo sistema. O serviço
usa `SharedPreferences.reload()` ao iniciar (isolates não compartilham cache). A lista de relays segue em
`RelayRepository`.

## D7 — Reentrega e validade

O serviço guarda em memória as solicitações **aceitas pelo filtro** por 5 min (spec FR-007) e as reenvia no
handshake. O `id` evita duplicata (a UI já deduplica por `_idsProcessados`/`EventFeed`). Sem persistência em disco
(menos superfície; se o processo do serviço morrer, as pendentes se perdem — aceito).

## D8 — Notificação

Canal `ride_requests` (importância alta, som padrão), id por solicitação (hash do `id` do evento), título "Nova
solicitação de corrida", corpo "Toque para ver", sem dados de terceiros (SC-003). Canal `service` (baixa) para a
notificação fixa. `POST_NOTIFICATIONS` pedida ao ficar online pela primeira vez (FR-009). Toque abre `MainActivity`
(`launchMode=singleTop`).

## D9 — Retomada online (clarificação 1)

Na abertura a UI pergunta ao serviço (`hello`) se está ativo e `online`; se sim, tenta a posição (004) e entra em
online sem pedir toggle; sem posição válida, vai a offline e manda `state(online=false)`.

## D10 — Medições a registrar (Princípio V)

SC-001 (latência publicação→notificação, 10 amostras), SC-004 (10 min de tela apagada + troca de rede),
SC-006 (bateria/h). Método e aparelho descritos no `quickstart.md`; nenhum número entra no TCC sem ter sido medido.
