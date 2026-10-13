# Tasks: Confirmar encontro e notificar chegada ao destino

**Input**: Design documents from `/specs/012-confirmar-encontro-destino/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/README.md, quickstart.md

**Tests**: **obrigatórias**, não opcionais (constituição, Princípio II) para
`IdentityService.signDestinationArrival` e para as decisões de agir (ou não) sobre uma confirmação
de encontro/destino recebida.

**Organization**: três user stories (todas P1, sequenciais no fluxo); tarefas em Setup →
Foundational → US1 → US2 → US3 → Polish.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: pode rodar em paralelo (arquivos diferentes, sem dependência entre si)
- Caminhos de arquivo sempre relativos a `Prototipo/driver/`, exceto onde indicado

---

## Phase 1: Setup — contrato antes do código (Princípio IV)

- [X] T001 Escrever a emenda 11 do contrato único em
  `specs/002-nostr-relay-connection/contracts/nostr-events.md`: nova linha na tabela "Histórico de
  emendas"; novas linhas na "Tabela de kinds do protótipo" para `20008`, `20009` e `20010`; novas
  seções *Conteúdo do kind 20008 — Encontro confirmado*, *Conteúdo do kind 20009 — Chegada ao
  destino* e *Conteúdo do kind 20010 — Destino confirmado* (tags conforme `data-model.md`);
  atualizar "Forma da inscrição" para incluir `20008` e `20010` na lista de kinds do motorista
- [X] T002 [P] Replicar a emenda 11 de forma idêntica em
  `../passenger/specs/002-nostr-relay-connection/contracts/nostr-events.md` (cabeçalho de
  procedência à parte; conferir os corpos por diff antes de prosseguir)
- [X] T003 Commit da emenda 11 (driver + passenger), separado de qualquer código desta feature

**Checkpoint**: contrato escrito e replicado — nenhuma tarefa de código abaixo pode começar antes
deste checkpoint.

---

## Phase 2: Foundational (Blocking Prerequisites)

- [X] T004 [P] Acrescentar `kindMeetingConfirmed = 20008`, `kindDestinationArrival = 20009` e
  `kindDestinationConfirmed = 20010` em `lib/domain/nostr_event.dart`
- [X] T005 [P] Acrescentar `DriverRideStatus.emCorrida` e as regras `canConfirmMeeting`/
  `canConfirmDestinationArrival` em `lib/domain/driver_ride_status.dart`; testes em
  `test/domain/driver_ride_status_test.dart`
- [X] T006 [P] Acrescentar `destinationLat`, `destinationLon` e `destinationArrivalNotified` a
  `ActiveRide` (`lib/domain/active_ride.dart`), atualizando `copyWith`/`==`/`hashCode`/`toString`;
  testes em `test/domain/active_ride_test.dart`
- [X] T007 Alterar `SentQuotesStore` (`lib/services/sent_quotes_store.dart`) para também guardar o
  destino de cada `id` registrado (`add` ganha `destinationLat`/`destinationLon` obrigatórios,
  novo método `destinationFor`); testes em `test/services/sent_quotes_store_test.dart` (depende de
  nada, mas quebra os call sites existentes — migrar todos no mesmo commit, mesmo cuidado já
  registrado pelo achado C1 do `/speckit-analyze` da feature 011)
- [X] T008 Atualizar `RideStateStore` (`lib/services/ride_state_store.dart`) para (de)serializar os
  dois campos novos de `ActiveRide`; testes em `test/services/ride_state_store_test.dart` cobrindo
  round-trip, inclusive `destinationArrivalNotified: true` (depende de T006)
- [X] T009 [P] `IdentityService.signDestinationArrival` (`kind: 20009`, tags `["e", quoteId]` +
  `["p", passengerPubkey]`, `content: ""`) em `lib/services/identity_service.dart`, por analogia a
  `signArrivalNotice`; teste em `test/services/identity_service_test.dart` (Princípio II)
- [X] T010 Acrescentar `NostrEvent.kindMeetingConfirmed` e `NostrEvent.kindDestinationConfirmed` ao
  conjunto `_consumedKinds` em `lib/main.dart` — única fonte já compartilhada por
  `EventFeed.acceptedKinds` **e** `RelayService.subscriptionKinds` desde a correção do achado da
  feature 010 (editar só esse conjunto já cobre os dois) (depende de T004)

**Checkpoint**: fundação pronta — as user stories podem começar.

---

## Phase 3: User Story 1 - Passar a "Em corrida" ao saber que o passageiro encontrou o motorista (Priority: P1) 🎯 MVP

**Goal**: confirmação de encontro válida transiciona de "Deslocando-se até o passageiro" para "Em
corrida" (FR-001, FR-002, FR-009).

**Independent Test**: com o motorista em "Deslocando-se até o passageiro", simular a chegada de
uma confirmação de encontro referenciando o orçamento aceito e verificar que o estado muda para
"Em corrida" e persiste.

### Tests for User Story 1

- [X] T011 [P] [US1] Widget test: confirmação de encontro (`kind: 20008`) referenciando o `quoteId`
  da corrida ativa, com o motorista em `deslocandoAtePassageiro`, transiciona para `emCorrida`
  (persistido em `RideStateStore`), em `test/screens/map_screen_test.dart`
- [X] T012 [P] [US1] Widget test: uma segunda confirmação de encontro (reentrega), com o motorista
  já `emCorrida`, não altera nada, em `test/screens/map_screen_test.dart`
- [X] T013 [P] [US1] Widget test: confirmação de encontro com o motorista em
  `aguardandoSolicitacao` (sem corrida ativa) é ignorada, em `test/screens/map_screen_test.dart`
- [X] T014 [P] [US1] Widget test: confirmação de encontro referenciando um `quoteId` diferente do
  da corrida ativa é ignorada, em `test/screens/map_screen_test.dart`

### Implementation for User Story 1

- [X] T015 [US1] `MapScreen._enviarOrcamento` passa a chamar `SentQuotesStore.add` também com
  `solicitacao.destination.latitude`/`longitude` (depende de T007)
- [X] T016 [US1] `MapScreen._iniciarCorrida` passa a ler `SentQuotesStore.destinationFor(quoteId)`
  e incluir `destinationLat`/`destinationLon` na `ActiveRide` construída (depende de T006, T007)
- [X] T017 [US1] `MapScreen` reconhece `kind: 20008`: se `_rideStatus ==
  deslocandoAtePassageiro` e `evento.referencedEventId == _activeRide?.quoteId`, transiciona para
  `emCorrida` e persiste via `RideStateStore.save` (dedup por `id`, mesmo padrão já usado para os
  demais kinds); fora dessas condições, ignora sem erro (depende de T005, T010)

**Checkpoint**: US1 completa e testável de forma independente.

---

## Phase 4: User Story 2 - Notificar automaticamente a chegada ao destino (Priority: P1)

**Goal**: durante "Em corrida", ao entrar num raio de 5 m do destino, publicar a chegada uma única
vez (FR-003 a FR-006, FR-011).

**Independent Test**: com o motorista "Em corrida" de uma corrida específica, simular uma posição
a 5 m ou menos do destino daquela corrida e verificar que a chegada ao destino é publicada, e só
uma vez.

### Tests for User Story 2

- [X] T018 [P] [US2] Widget test: posição a 5 m ou menos do destino, com o motorista `emCorrida`,
  publica `kind: 20009` com as tags corretas, em `test/screens/map_screen_test.dart`
- [X] T019 [P] [US2] Widget test: posição a mais de 5 m do destino não publica, em
  `test/screens/map_screen_test.dart`
- [X] T020 [P] [US2] Widget test: depois de publicada, permanecer ou voltar a entrar no raio não
  publica de novo, em `test/screens/map_screen_test.dart`
- [X] T021 [P] [US2] Widget test: com `RideStateStore` pré-carregado com
  `destinationArrivalNotified: true` (reinício), uma posição dentro do raio não publica de novo,
  em `test/screens/map_screen_test.dart`
- [X] T022 [P] [US2] Widget test: posição a 5 m ou menos do destino, fora do estado `emCorrida`
  (`deslocandoAtePassageiro` ou `aguardandoSolicitacao`), não publica, em
  `test/screens/map_screen_test.dart`

### Implementation for User Story 2

- [X] T023 [US2] `MapScreen._aoReceberPosicao` passa a chamar também um novo método
  `_talvezNotificarChegadaAoDestino` (por analogia a `_talvezNotificarChegada` da feature 011):
  quando `_rideStatus == emCorrida`, `_activeRide?.destinationArrivalNotified == false` e
  `metersBetween(posição, destino) <= 5`, assina (`signDestinationArrival`) e publica `kind:
  20009`, gravando `destinationArrivalNotified: true` via `RideStateStore.save` (depende de T006,
  T008, T009, T016)

**Checkpoint**: US1 + US2 completas e testáveis de forma independente.

---

## Phase 5: User Story 3 - Voltar a "Aguardando solicitação de corrida" ao saber que chegaram ao destino (Priority: P1)

**Goal**: confirmação de destino válida encerra a corrida ativa e volta o motorista a "Aguardando
solicitação de corrida" (FR-007, FR-008).

**Independent Test**: com o motorista "Em corrida" e a chegada ao destino já publicada, simular a
chegada de uma confirmação de destino referenciando o orçamento aceito e verificar que o motorista
volta a "Aguardando solicitação de corrida", sem corrida ativa.

### Tests for User Story 3

- [X] T024 [P] [US3] Widget test: confirmação de destino (`kind: 20010`) referenciando o `quoteId`
  da corrida ativa, com o motorista `emCorrida`, volta o estado a `aguardandoSolicitacao` com
  `ActiveRide` nula (persistido), em `test/screens/map_screen_test.dart`
- [X] T025 [P] [US3] Widget test: confirmação de destino com o motorista fora de `emCorrida`
  (`aguardandoSolicitacao` ou ainda `deslocandoAtePassageiro`) é ignorada, em
  `test/screens/map_screen_test.dart`
- [X] T026 [P] [US3] Widget test: confirmação de destino referenciando um `quoteId` diferente do
  da corrida ativa é ignorada, em `test/screens/map_screen_test.dart`
- [X] T027 [P] [US3] Widget test: depois de voltar a `aguardandoSolicitacao`, uma nova solicitação
  de corrida volta a abrir modal normalmente (US3 cenário 3 do `spec.md`), em
  `test/screens/map_screen_test.dart`

### Implementation for User Story 3

- [X] T028 [US3] `MapScreen` reconhece `kind: 20010`: se `_rideStatus == emCorrida` e
  `evento.referencedEventId == _activeRide?.quoteId`, transiciona para `aguardandoSolicitacao`,
  zera `_activeRide` e persiste via `RideStateStore.save(aguardandoSolicitacao, null)` (dedup por
  `id`); fora dessas condições, ignora sem erro (depende de T005, T010, T017)

**Checkpoint**: todas as três user stories completas e testáveis de forma independente.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [X] T029 `flutter analyze` sem apontamentos (gate 1 da constituição)
- [X] T030 `flutter test` — suíte completa passando, sem teste ignorado (gate 2 da constituição)
- [ ] T031 Executar os cenários de `quickstart.md`; relatar explicitamente os que não puderam ser
  executados (gate 3 da constituição)
- [X] T032 Verificação de não vazamento do Princípio I: inspecionar log e payload publicado do
  novo evento assinado (`kind: 20009`) e confirmar ausência de chave privada
- [X] T033 Commit de implementação desta feature (código + testes), separado do commit da emenda
  de contrato (T003) e do commit de documentação (T034)
- [X] T034 Atualizar `../../CLAUDE.md` (raiz do repositório) registrando a feature 012 do
  motorista, em commit próprio, separado do código (Padrão de Commits, item 6)

---

## Dependencies & Execution Order

- **Setup (Phase 1)**: sem dependências — bloqueia tudo abaixo (Princípio IV)
- **Foundational (Phase 2)**: depende do Setup — bloqueia todas as user stories
- **US1 (Phase 3)**: depende do Foundational
- **US2 (Phase 4)**: depende do Foundational **e** de T016 (US1, para `destinationLat`/`Lon`
  disponíveis em `ActiveRide`) — não plenamente independente de código, mesmo padrão já registrado
  nas features 010/011 para dependências entre user stories do mesmo fluxo
- **US3 (Phase 5)**: depende do Foundational **e** de T017 (US1, mesma ramificação de leitura dos
  kinds novos)
- **Polish (Phase 6)**: depende de todas as user stories completas

### Parallel Opportunities

- T001/T002 podem ser feitos em paralelo (arquivos diferentes), mas commitados juntos (T003)
- T004, T005, T006, T009 podem ser feitos em paralelo entre si (arquivos diferentes); T007 é
  independente mas seus call sites existentes precisam migrar no mesmo commit; T008 depende de T006
- T011-T014 (testes US1), T018-T022 (testes US2) e T024-T027 (testes US3) podem ser escritos em
  paralelo dentro de cada grupo

---

## Implementation Strategy

### MVP First (User Story 1)

1. Completar Phase 1 (contrato) e Phase 2 (fundação)
2. Completar Phase 3 (US1) — motorista já reconhece a confirmação de encontro
3. Validar US1 de forma independente

### Incremental Delivery

1. Setup + Foundational → base pronta
2. US1 → "Em corrida" (MVP)
3. US2 → chegada automática ao destino
4. US3 → retorno a "Aguardando", fechando o ciclo
5. Cada incremento soma valor sem quebrar o anterior

## Notes

- [P] = arquivos diferentes, sem dependência
- Commit separado para: emenda de contrato (T003), código (T033) e `CLAUDE.md` (T034) — Padrão de
  Commits, item 6
- Verificar que os testes falham antes de implementar (T011-T014, T018-T022, T024-T027)
