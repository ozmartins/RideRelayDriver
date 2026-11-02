# Tasks: Notificar chegada ao passageiro

**Input**: Design documents from `/specs/011-notificar-chegada/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/README.md, quickstart.md

**Tests**: **obrigatórias**, não opcionais (constituição, Princípio II) para todo código que assina
eventos — aplica-se aqui a `IdentityService.signArrivalNotice`.

**Organization**: única user story (P1); tarefas em Setup → Foundational → US1 → Polish.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: pode rodar em paralelo (arquivos diferentes, sem dependência entre si)
- Caminhos de arquivo sempre relativos a `Prototipo/driver/`, exceto onde indicado

---

## Phase 1: Setup — contrato antes do código (Princípio IV)

- [X] T001 Escrever a emenda 09 do contrato único em
  `specs/002-nostr-relay-connection/contracts/nostr-events.md`: nova linha na tabela "Histórico de
  emendas"; nova linha na "Tabela de kinds do protótipo" para `20007`; nova seção *Conteúdo do
  kind 20007 — Chegada do motorista* (tags `["e", "<id-do-orçamento>"]` +
  `["p", "<pubkey-do-passageiro>"]`, `content` vazio, conforme `data-model.md`)
- [X] T002 [P] Replicar a emenda 09 de forma idêntica em
  `../passenger/specs/002-nostr-relay-connection/contracts/nostr-events.md` (cabeçalho de
  procedência à parte; conferir os corpos por diff antes de prosseguir)
- [X] T003 Commit da emenda 09 (driver + passenger), separado de qualquer código desta feature

**Checkpoint**: contrato escrito e replicado — nenhuma tarefa de código abaixo pode começar antes
deste checkpoint.

---

## Phase 2: Foundational (Blocking Prerequisites)

- [X] T004 [P] Acrescentar `kindArrivalNotice = 20007` em `lib/domain/nostr_event.dart`
- [X] T005 Acrescentar `originLat`, `originLon` e `arrivalNotified` a `ActiveRide`
  (`lib/domain/active_ride.dart`), com `copyWith`, atualizando `==`/`hashCode`/`toString`; testes
  novos em `test/domain/active_ride_test.dart` (depende de nada, mas bloqueia T008/T011)
- [X] T006 Alterar `SentQuotesStore` (`lib/services/sent_quotes_store.dart`) para guardar a origem
  de cada `id` registrado (`add(quoteId, {required originLat, required originLon})`, novo método
  `originFor(quoteId)`), com a implementação sobre `KeyValueStore` serializando um mapa em vez de
  uma lista; testes em `test/services/sent_quotes_store_test.dart` cobrindo `originFor` presente,
  ausente, e sobrevivendo a uma nova instância sobre o mesmo armazenamento (depende de T005 não —
  é independente, mas altera a mesma interface que T009/T011 vão consumir)
- [X] T007 Atualizar `RideStateStore` (`lib/services/ride_state_store.dart`) para (de)serializar os
  três campos novos de `ActiveRide` no JSON persistido; testes em
  `test/services/ride_state_store_test.dart` cobrindo round-trip dos campos novos, inclusive
  `arrivalNotified: true` (depende de T005)
- [X] T008 `IdentityService.signArrivalNotice` (`kind: 20007`, tags `["e", quoteId]` +
  `["p", passengerPubkey]`, `content: ""`) em `lib/services/identity_service.dart`, por analogia a
  `signRideNoLongerAvailable`; teste em `test/services/identity_service_test.dart` (Princípio II)

**Checkpoint**: fundação pronta — a user story pode começar.

---

## Phase 3: User Story 1 - Avisar automaticamente que chegou ao ponto de encontro (Priority: P1) 🎯 MVP

**Goal**: ao entrar num raio de 10 m da origem da corrida ativa, publicar a chegada uma única vez
(FR-001 a FR-006).

**Independent Test**: com o motorista em "Deslocando-se até o passageiro" de uma corrida
específica, simular uma posição a menos de 10 m do ponto de origem daquela corrida e verificar que
uma mensagem de chegada é enviada ao passageiro correspondente, e só uma vez.

### Tests for User Story 1

- [X] T009 [P] [US1] Widget test: `MapScreen._enviarOrcamento` grava a origem da solicitação junto
  do `id` do orçamento em `SentQuotesStore` (`originFor` passa a devolver essa origem), em
  `test/screens/map_screen_test.dart`
- [X] T010 [P] [US1] Widget test: ao tocar "Iniciar corrida", a `ActiveRide` persistida carrega
  `originLat`/`originLon` da solicitação original e `arrivalNotified: false`, em
  `test/screens/map_screen_test.dart`
- [X] T011 [P] [US1] Widget test: posição do motorista a 10 m ou menos da origem da corrida ativa
  publica `kind: 20007` com as tags corretas, em `test/screens/map_screen_test.dart`
- [X] T012 [P] [US1] Widget test: posição a mais de 10 m da origem não publica `kind: 20007`, em
  `test/screens/map_screen_test.dart`
- [X] T013 [P] [US1] Widget test: depois de publicada, novas posições dentro do raio — inclusive
  saindo e voltando a entrar — não publicam uma segunda vez, em `test/screens/map_screen_test.dart`
- [X] T014 [P] [US1] Widget test: com `RideStateStore` (dublê) pré-carregado com
  `arrivalNotified: true` para a corrida ativa (simulando reinício após já ter avisado), uma nova
  posição dentro do raio não publica de novo, em `test/screens/map_screen_test.dart` (cobre o
  cenário de reinício de D2/research.md)
- [X] T015 [P] [US1] Widget test: posição a 10 m ou menos da origem, com o motorista em
  "Aguardando solicitação de corrida" (sem corrida ativa), não publica `kind: 20007`, em
  `test/screens/map_screen_test.dart`

### Implementation for User Story 1

- [X] T016 [US1] `MapScreen._enviarOrcamento` passa a chamar `SentQuotesStore.add` com a origem da
  `RideRequestReceived` respondida (depende de T006)
- [X] T017 [US1] `MapScreen._iniciarCorrida` passa a ler `SentQuotesStore.originFor(quoteId)` e
  construir a `ActiveRide` com `originLat`/`originLon`/`arrivalNotified: false` (depende de T005,
  T006)
- [X] T018 [US1] `MapScreen._talvezPublicarLocalizacao` (ou um método irmão dedicado) passa a
  também comparar a posição recebida com `_activeRide.originLat/originLon` via `metersBetween`
  (`geo_distance.dart`, já existente da feature 010); quando ≤ 10 m e `arrivalNotified == false`,
  assina e publica `kind: 20007` (depende de T008, T017)
- [X] T019 [US1] Após publicar a chegada, `MapScreen` regrava `ActiveRide` com
  `arrivalNotified: true` via `RideStateStore.save`, mantendo o mesmo `DriverRideStatus` (depende
  de T007, T018)

**Checkpoint**: US1 completa e testável de forma independente — única user story desta feature.

---

## Phase 4: Polish & Cross-Cutting Concerns

- [X] T020 `flutter analyze` sem apontamentos (gate 1 da constituição)
- [X] T021 `flutter test` — suíte completa passando, sem teste ignorado (gate 2 da constituição)
- [ ] T022 Executar os cenários de `quickstart.md`; relatar explicitamente os que não puderam ser
  executados (gate 3 da constituição)
- [X] T023 Verificação de não vazamento do Princípio I: inspecionar log e payload publicado do
  novo evento (`kind: 20007`) e confirmar ausência de chave privada
- [X] T024 Commit de implementação desta feature (código + testes), separado do commit da emenda
  de contrato (T003) e do commit de documentação (T025)
- [X] T025 Atualizar `../../CLAUDE.md` (raiz do repositório) registrando a feature 011 do
  motorista, em commit próprio, separado do código (Padrão de Commits, item 6)

---

## Dependencies & Execution Order

- **Setup (Phase 1)**: sem dependências — bloqueia tudo abaixo (Princípio IV)
- **Foundational (Phase 2)**: depende do Setup — bloqueia a user story
- **US1 (Phase 3)**: depende do Foundational; dentro dela, T016 depende de T006, T017 depende de
  T005/T006, T018 depende de T008/T017, T019 depende de T007/T018
- **Polish (Phase 4)**: depende de US1 completa

### Parallel Opportunities

- T001/T002 podem ser feitos em paralelo (arquivos diferentes), mas commitados juntos (T003)
- T004, T005, T006, T008 podem ser feitos em paralelo entre si (arquivos diferentes); T007 depende
  de T005
- T009-T015 (testes da US1) podem ser escritos em paralelo entre si

---

## Implementation Strategy

Única user story: completar Phase 1 (contrato) → Phase 2 (fundação) → Phase 3 (US1) → Phase 4
(polish). Não há incremento intermediário além deste — a feature inteira é o MVP.

## Notes

- [P] = arquivos diferentes, sem dependência
- Commit separado para: emenda de contrato (T003), código (T024) e `CLAUDE.md` (T025) — Padrão de
  Commits, item 6
- Verificar que os testes falham antes de implementar (T009-T015)
