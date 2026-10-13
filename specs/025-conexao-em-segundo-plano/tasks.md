# Tarefas: 025-conexao-em-segundo-plano

**Entrada**: [spec.md](spec.md), [plan.md](plan.md), [research.md](research.md), [data-model.md](data-model.md),
[contracts/service-channel.md](contracts/service-channel.md) · **App**: `driver/` (caminhos relativos a
`Prototipo/driver/`, salvo indicação) · Testes incluídos (Princípio II + padrão do repositório).
Formato: `- [ ] ID [P?] [US?] descrição com caminho`. `[P]` = arquivos distintos, sem dependência pendente.

## Fase 1 — Gates e viabilidade (bloqueia tudo)

- [x] T001 Emendar a constituição para **2.14.0** (texto proposto em plan.md) em `.specify/memory/constitution.md`,
  `../passenger/.specify/memory/constitution.md` e conferir `../.specify/memory/constitution.md`; `diff` dos corpos
  driver × passenger; **commit separado**, antes de qualquer código (Governance).
- [x] T002 Spike descartável em `tool/spike_foreground_service/` (pasta não commitada; o projeto trabalha só na `master`): `flutter_foreground_task`
  11.0.3 com `TaskHandler` mantendo um WebSocket a um relay real + notificação `flutter_local_notifications`;
  tipo `specialUse` (fallback `dataSync`); provar em aparelho/emulador que sobrevive a deslizar dos recentes e à tela
  apagada. Decidir também se `WAKE_LOCK` é necessário. Registrar resultado em `research.md` (D3). **Feito em 2026-10-11:** viável (specialUse, tarefa removida, Doze forçado e queda de rede
  ok; resultado completo em `research.md` D3); `WAKE_LOCK` desnecessário; o app descartável ficou no scratchpad,
  fora do repositório.
- [x] T003 Adicionar `flutter_foreground_task: ^11.0.3` e `flutter_local_notifications: ^22.3.1` em `pubspec.yaml`
  (decisão já em `research.md` D2), ativar *core library desugaring* em `android/app/build.gradle.kts` (exigido por
  `flutter_local_notifications`; achado do spike) e rodar `flutter pub get`.
- [x] T004 Declarar em `android/app/src/main/AndroidManifest.xml` as permissões `FOREGROUND_SERVICE`,
  `FOREGROUND_SERVICE_SPECIAL_USE`, `POST_NOTIFICATIONS` (**sem** `WAKE_LOCK`: o spike provou que é desnecessário; usar `tools:node="remove"` para a permissão que o plugin mescla), o `<service>` do plugin com
  `foregroundServiceType="specialUse"` e a propriedade do subtipo; atualizar o comentário "Sem localização em segundo
  plano" (continua verdade: o serviço não lê localização).

## Fase 2 — Fundação (bloqueia as histórias)

- [x] T005 [P] Criar `lib/services/relay_connection.dart` com a interface `RelayConnection` (`relays`,
  `hasConnectedRelay`, `incoming`, `statusChanges`, `connectAll`, `addRelay`, `removeRelay`, `reconnectNow`,
  `publish`, `enableAutoRetry`, `dispose`).
- [x] T006 `lib/services/relay_service.dart`: `RelayService implements RelayConnection` sem mudar comportamento;
  trocar o tipo do parâmetro `relayService` para `RelayConnection` em `lib/screens/map_screen.dart`,
  `lib/screens/more_screen.dart`, `lib/main.dart` (`_Shell`). `flutter test` deve seguir verde (464).
- [x] T007 [P] Teste primeiro: `test/domain/ride_request_filter_test.dart` — aceita; recusa por offline, em corrida,
  `content` malformado, pagamento não aceito, `wireValue` desconhecido.
- [x] T008 Implementar `lib/domain/ride_request_filter.dart` (`RideRequestFilter.evaluate(NostrEvent, ServiceState)`)
  reutilizando `RideRequestReceived.fromNostrEvent`, `DriverProfile.acceptsPayment`, `PaymentMethod.fromWire`; e
  usá-lo em `MapScreen._processarSolicitacaoRecebida` e na repetição da checagem ao tirar da fila
  (`lib/screens/map_screen.dart`), sem mudar o comportamento (testes existentes verdes).
- [x] T009 [P] Teste primeiro: `test/services/background/service_messages_test.dart` — ida e volta de cada tipo do
  contrato, versão `v` desconhecida e tipo desconhecido ignorados, nenhum campo de chave/segredo no esquema.
- [x] T010 Implementar `lib/services/background/service_messages.dart` (`ServiceMessage` e fábricas) conforme
  [contracts/service-channel.md](contracts/service-channel.md); `ServiceState` em `lib/domain/service_state.dart`
  (persistência via `KeyValueStore`, chaves `background.*`).
- [x] T011 [P] `lib/services/background/background_service.dart`: fronteira única com `flutter_foreground_task`
  (`start`, `stop`, `isRunning`, `send`, `messages`); interface `BackgroundServiceChannel` + implementação real +
  dublê em `test/support/fake_background_channel.dart`.
- [x] T012 Teste primeiro: `test/services/background/relay_host_core_test.dart` (o núcleo testável é `RelayHostCore`) com gateway falso — repassa
  `incoming` só após verificação de assinatura (inválido, adulterado, sem marcador e duplicado são descartados e
  contados), executa `connectAll/add/remove/reconnectNow/publish`, devolve `publishResult` e `relaysChanged`,
  `publish` sem relay → erro `no_relay`.
- [x] T013 Implementar `lib/services/background/relay_host_core.dart` (núcleo sem plugin) e
  `relay_task_handler.dart` (`TaskHandler` fino): hospeda `RelayService` + `NostrRelayGateway` (retentativa 15 s, sonda 30 s),
  `RelayRepository` com `reload()` — **no `onStart` lê a lista de relays e conecta sozinho** (`enableAutoRetry()` incluso) e envia `ready` —, `NostrEventVerifier`, `hasPrototypeMarker`, dedupe por `id`; entry point
  `@pragma('vm:entry-point')`. Não importa `IdentityService`/`KeyStore` (Princípio I).
- [x] T014 [P] Teste primeiro: `test/services/remote_relay_connection_test.dart` com canal falso — `connectAll`,
  `publish` devolve um `Stream<PublishOutcome>` correlacionado por `reqId`, `NoConnectedRelay` em `no_relay`,
  `statusChanges`/`relays` refletem `relaysChanged`, `incoming` alimenta o stream.
- [x] T015 Implementar `lib/services/remote_relay_connection.dart` (`implements RelayConnection`): enfileira
  comandos até receber `ready`/`helloAck`; ao detectar novo `ready` (serviço reiniciado) refaz `hello` e reenvia o
  `state` atual. Cobrir isso em `test/services/remote_relay_connection_test.dart` (T014).
- [x] T016 `lib/main.dart`: parâmetro injetável `relayConnection`; em produção compõe `RemoteRelayConnection` +
  `BackgroundService`; nos testes continua `RelayService` + gateway falso; `EventFeed` consome
  `relayConnection.incoming`. Todos os testes de `test/screens` seguem verdes.

**Ponto de verificação** (feito em 2026-10-12, emulador API 34): com o serviço rodando o app abre, o serviço sobe como
foreground `specialUse` e a tela Mais mostra "3 de 3 relays conectados", vindos do serviço. Orçamento e corrida
ponta a ponta ficam para os cenários de aparelho do quickstart.

## Fase 3 — US1 (P1): ser avisado com o app fechado

**Teste independente**: online, app removido dos recentes, `kind: 20001` válido → notificação → toque → modal.

- [x] T017 [P] [US1] Teste primeiro: `test/services/ride_request_notifier_test.dart` — título/corpo fixos, **nunca**
  contém endereço, coordenada, nome ou `pubkey` do evento (SC-003), id de notificação estável por evento.
- [x] T018 [US1] Implementar `lib/services/ride_request_notifier.dart` (canal `ride_requests` de alta importância,
  canal `service` de baixa, `onTap` abre `MainActivity`); interface + dublê para testes.
- [x] T019 [US1] Estender `test/services/background/relay_task_handler_test.dart` e `RelayHostCore`: com
  `foreground=false` e `RideRequestFilter` aceitando → chama o notificador uma vez por `id`; recusado → não chama;
  `foreground=true` → só repassa; guarda `PendingRequest` por 5 min; `helloAck.pending` reentrega e descarta as
  expiradas; o serviço conecta sozinho no `onStart`, sem `connectAll` da UI.
- [x] T020 [US1] `lib/screens/map_screen.dart` + `lib/main.dart`: enviar `state` ao serviço a cada mudança de
  `online`, `rideStatus`, `driverProfile.paymentMethods` (persistido em `KeyValueStore`); `hello` na abertura e ao
  voltar a primeiro plano; `WidgetsBindingObserver` em `_Shell` enviando `foreground`. Testes em
  `test/screens/map_screen_test.dart` com canal falso: mudança de status/pagamento gera `state`; reentrega do
  `helloAck.pending` chega pelo `incoming` da `RemoteRelayConnection` (mesmo caminho de verificação e dedupe de
  qualquer evento), abre a modal e respeita a fila sequencial; solicitação com mais de 5 min não entra; o mesmo
  `id` entregue duas vezes abre uma só modal.
- [x] T021 [US1] Cenários 2, 3, 4 e 9 do `quickstart.md` em aparelho; registrar resultado. **Feito no emulador em
  2026-10-12** (cenário 9 e a recusa em corrida ficaram só em teste automatizado); ver `quickstart.md`, Resultados.

## Fase 4 — US2 (P1): saber que está ouvindo e poder parar

**Teste independente**: ficar online mostra a notificação fixa; offline + sair do app a remove e encerra.

- [x] T022 [P] [US2] Teste primeiro: `test/services/background/service_controller_test.dart` — regra pura
  `shouldRun(foreground, online)`; início ao abrir o app, "Você está online" ao ficar online, encerra ao sair com
  offline, continua ao sair com online.
- [x] T023 [US2] Implementar o controlador de ciclo de vida em `lib/services/background/service_controller.dart`
  (usa `BackgroundServiceChannel`; textos das notificações fixas) e ligá-lo em `lib/main.dart`.
- [x] T024 [US2] FR-009: pedir `POST_NOTIFICATIONS` só ao ficar online pela primeira vez (`MapScreen._alternarStatus`);
  negada → aviso ao motorista ("não será avisado com o app fechado") e serviço mantido apenas com o app aberto.
  Teste em `test/screens/map_screen_test.dart`.
- [x] T025 [US2] FR-012: na abertura, `helloAck.online=true` → tentar posição (004) e entrar online sem toque; sem
  posição válida → offline e `state(online=false)`. Testes em `test/screens/map_screen_test.dart`.
- [x] T026 [US2] Cenários 5, 7, 8 e 10 do `quickstart.md` em aparelho; registrar resultado. **Feito no emulador em
  2026-10-12**, exceto "Forçar parada", permissão negada e retomada sem GPS (só testes automatizados).

## Fase 5 — US3 (P2): conexão sobrevive a quedas de rede

**Teste independente**: tela apagada 10 min + troca de rede, nova solicitação ainda chega.

- [x] T027 [P] [US3] Teste: em `relay_host_core_test.dart`, queda de relay no host dispara reconexão e **reenvio
  da inscrição** (gateway falso conta `subscribe`), sonda marca meio-aberto como caído, `relaysChanged` chega à UI.
- [x] T028 [US3] Ajustar `RelayHostCore` se o teste T027 revelar lacuna (timers do `RelayService` rodando no isolate
  do serviço, `enableAutoRetry()` ligado no `onStart`).
- [x] T029 [US3] Cenário 6 do `quickstart.md` (SC-004) em aparelho; registrar resultado e distribuição. **Feito no
  emulador (1 amostra de 10 min com queda de rede)**; falta repetir em aparelho real.

## Fase 6 — Acabamento

- [x] T030 Verificação de não vazamento (Princípio I): teste que varre as mensagens do canal em `test/services/background/`
  e `logcat` nos cenários do quickstart; registrar no `quickstart.md`.
- [ ] T031 Medições: SC-001 (10 amostras) e SC-006 (bateria/h) no `quickstart.md`, com aparelho e método. **SC-001
  feito no emulador (mediana 283 ms, máx. 503 ms, 10 amostras); SC-006 NÃO medido — exige aparelho real**, o método está
  no `quickstart.md`. Por isso a tarefa fica aberta.
- [x] T032 `flutter analyze` sem avisos e `flutter test` integral verde (464 + novos); anotar o total. **Feito:**
  `flutter analyze` sem apontamentos e 581 testes passando (464 anteriores + 117 novos).
- [x] T033 Atualizar `../../CLAUDE.md` (entrada da feature 025, limites: corrida com app fechado, fabricantes) e
  `../CLAUDE.md` se citar a lista de features, em commit separado; remover/arquivar o spike de T002.

## Dependências e ordem

`T001 → T002 → T003/T004` → Fundação `T005…T016` (T005→T006; T007→T008; T009→T010; T010→T011→T012→T013;
T014→T015; T013+T015→T016) → US1 (`T017…T021`) → US2 (`T022…T026`, pode começar após T016, independente de US1
exceto pelos testes de MapScreen que compartilham arquivo) → US3 (`T027…T029`, após T013) → Acabamento.

**Paralelo**: T005/T007/T009/T011/T014 (arquivos distintos); T017/T022/T027 (testes de histórias distintas).

## Estratégia

MVP = Fase 1 + 2 + US1 (aviso com app fechado). Entrega incremental: cada ponto de verificação roda em aparelho
antes da fase seguinte; o spike (T002) é o gate de viabilidade de toda a abordagem.
