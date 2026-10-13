# Tasks: Iniciar corrida após aceitação e deslocamento até o passageiro

**Input**: Design documents from `/specs/010-iniciar-corrida/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/README.md, quickstart.md

**Tests**: **obrigatórias**, não opcionais (constituição, Princípio II) para todo código que assina
eventos, verifica assinatura, deriva chave ou decide descartar mensagem recebida — cobrindo caso
válido e inválido, sem rede nem relay real. Aplica-se aqui a `IdentityService.signDriverLocation`,
`IdentityService.signRideNoLongerAvailable` e `QuoteAccepted.fromNostrEvent`.

**Organization**: tarefas agrupadas pelas quatro user stories de `spec.md` (US1-US4), na ordem de
prioridade (P1, P1, P2, P3).

**Nota de revisão**: esta versão incorpora as correções do `/speckit-analyze` desta feature —
achado C1 (CRITICAL: FR-011 sem forma de saber quais orçamentos foram realmente enviados,
inclusive após reinício — ver D6 de `research.md` e `SentQuotesStore` em `data-model.md`), C2
(FR-006 sem teste de regressão) e C3 (FR-009 — retomada da publicação de localização após reinício
sem teste). As tarefas novas resultantes são T009, T014, T015, T016, T020, T021 (parte) e T031;
todas as demais foram renumeradas a partir da versão anterior deste arquivo.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: pode rodar em paralelo (arquivos diferentes, sem dependência entre si)
- **[Story]**: a qual user story a tarefa pertence (US1-US4)
- Caminhos de arquivo sempre relativos a `Prototipo/driver/`, exceto onde indicado

---

## Phase 1: Setup — contrato antes do código (Princípio IV)

**Purpose**: especificar os dois kinds novos e a mudança na inscrição do motorista, replicados de
forma idêntica na app do passageiro, **antes** de qualquer código desta feature — e num commit
próprio, separado da implementação (Padrão de Commits, item 6).

- [X] T001 Escrever a emenda 08 do contrato único em
  `specs/002-nostr-relay-connection/contracts/nostr-events.md`: nova linha na tabela "Histórico de
  emendas"; nova linha na "Tabela de kinds do protótipo" para `20005` e `20006`; novas seções
  *Conteúdo do kind 20005 — Localização do motorista* e *Conteúdo do kind 20006 — Corrida não pode
  mais ser atendida* (tags `["e", "<id-do-orçamento>"]` + `["p", "<pubkey-do-passageiro>"]`,
  conteúdo conforme `data-model.md`); atualizar "Forma da inscrição" para incluir `20003` na lista
  de kinds do motorista
- [X] T002 [P] Replicar a emenda 08 de forma idêntica em
  `../passenger/specs/002-nostr-relay-connection/contracts/nostr-events.md` (cabeçalho de
  procedência à parte; conferir os corpos por diff antes de prosseguir)
- [X] T003 Commit da emenda 08 (driver + passenger), separado de qualquer código desta feature

**Checkpoint**: contrato escrito e replicado — nenhuma tarefa de código abaixo pode começar antes
deste checkpoint.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: infraestrutura de domínio/serviço compartilhada por mais de uma user story.

**⚠️ CRITICAL**: nenhuma user story começa antes desta fase.

- [X] T004 [P] Acrescentar `kindQuoteAccepted = 20003`, `kindDriverLocation = 20005` e
  `kindRideNoLongerAvailable = 20006` em `lib/domain/nostr_event.dart`
- [X] T005 [P] Criar `DriverRideStatus` (enum) e a regra de transição em
  `lib/domain/driver_ride_status.dart`, por analogia a `availability_status.dart`, com teste em
  `test/domain/driver_ride_status_test.dart`
- [X] T006 [P] Criar `ActiveRide` (quoteId + passengerPubkey) em `lib/domain/active_ride.dart`, com
  teste em `test/domain/active_ride_test.dart`
- [X] T007 [P] Criar `QuoteAccepted.fromNostrEvent` (leitura do `kind: 20003`, lançando
  `FormatException` se a tag `e` estiver ausente) em `lib/domain/quote_accepted.dart`, com teste
  cobrindo evento válido **e** malformado em `test/domain/quote_accepted_test.dart` (Princípio II —
  decide descartar mensagem recebida)
- [X] T008 Criar `RideStateStore` (abstração + implementação sobre `KeyValueStore`, JSON
  serializado) em `lib/services/ride_state_store.dart`, com dublê em memória e teste em
  `test/services/ride_state_store_test.dart` (depende de T005, T006)
- [X] T009 [P] Criar `SentQuotesStore` (abstração + implementação sobre `KeyValueStore`, lista de
  `id`s serializada em JSON) em `lib/services/sent_quotes_store.dart`, com dublê em memória e teste
  (`add`/`contains`, incluindo persistência entre instâncias simuladas) em
  `test/services/sent_quotes_store_test.dart` — corrige o achado C1/FR-011 do `/speckit-analyze`
  (D6 de `research.md`)
- [X] T010 Acrescentar `NostrEvent.kindQuoteAccepted` a `EventFeed.acceptedKinds` em `lib/main.dart`
  (depende de T004) — necessário para US1 e US4, que consomem o `kind: 20003`

**Checkpoint**: fundação pronta — as user stories podem começar.

---

## Phase 3: User Story 1 - Ser avisado que um orçamento foi aceito e iniciar a corrida (Priority: P1) 🎯 MVP

**Goal**: modal de aceitação com "Iniciar corrida"; toque transiciona e persiste o estado
"Deslocando-se até o passageiro" (FR-001 a FR-003, FR-011).

**Independent Test**: com o motorista em "Aguardando solicitação de corrida" e um orçamento já
enviado (registrado em `SentQuotesStore`), simular a chegada de um `kind: 20003` referenciando
aquele orçamento — a modal aparece; ao tocar "Iniciar corrida", o estado persistido muda e sobrevive
a uma reconstrução do widget.

### Tests for User Story 1

- [X] T011 [P] [US1] Widget test: aceitação recebida (`kind: 20003`) referenciando um `quoteId`
  presente em `SentQuotesStore`, com status `aguardandoSolicitacao`, abre `QuoteAcceptedModal` com
  a mensagem informativa e o botão "Iniciar corrida", em `test/screens/map_screen_test.dart`
- [X] T012 [P] [US1] Widget test: tocar "Iniciar corrida" grava `DriverRideStatus
  .deslocandoAtePassageiro` + `ActiveRide` correto no `RideStateStore` (dublê) e fecha a modal, em
  `test/screens/map_screen_test.dart`
- [X] T013 [P] [US1] Widget test: com o `RideStateStore` (dublê) pré-carregado em
  `deslocandoAtePassageiro`, a tela reconstruída não pede nova confirmação (estado restaurado), em
  `test/screens/map_screen_test.dart`
- [X] T014 [P] [US1] Widget test: aceitação referenciando um `quoteId` **ausente** de
  `SentQuotesStore` (nunca enviado por este motorista) é ignorada — sem modal, sem mudança de
  estado —, em `test/screens/map_screen_test.dart` (corrige C1/FR-011)
- [X] T015 [P] [US1] Widget test: aceitação referenciando um `quoteId` presente em `SentQuotesStore`
  **desde antes** da reconstrução do widget (simulando reinício entre o envio do orçamento e a
  chegada da aceitação) ainda abre a modal normalmente, em `test/screens/map_screen_test.dart`
  (corrige C1 — janela de reinício identificada pelo `/speckit-analyze`)
- [X] T016 [P] [US1] Widget test: enviar um orçamento com `_rideStatus ==
  deslocandoAtePassageiro` não altera o estado do motorista (regressão de FR-006), em
  `test/screens/map_screen_test.dart` (corrige C2)

### Implementation for User Story 1

- [X] T017 [US1] Criar `QuoteAcceptedModal` (mensagem informativa + botão "Iniciar corrida") em
  `lib/screens/quote_accepted_modal.dart`
- [X] T018 [US1] `MapScreen` passa a receber `RideStateStore` **e** `SentQuotesStore` por injeção de
  construtor; `main.dart` injeta as implementações reais (depende de T008, T009)
- [X] T019 [US1] `MapScreen` carrega o estado persistido (`RideStateStore.load()`) em `_iniciar()`,
  expondo `_rideStatus`/`_activeRide` no `State`
- [X] T020 [US1] `MapScreen._enviarOrcamento` grava o `id` do evento assinado em
  `SentQuotesStore.add` assim que ao menos um relay aceita a publicação (mesmo ponto em que a modal
  de solicitação já fecha, feature 007) — corrige C1/FR-011 (depende de T009)
- [X] T021 [US1] `MapScreen._aoAtualizarFeed` passa a reconhecer `kind: 20003`, convertendo via
  `QuoteAccepted.fromNostrEvent` (descartando malformado ou duplicado por `id`, regras 1-3 de
  recepção) **e** consultando `SentQuotesStore.contains(quoteId)` antes de prosseguir (descarta se
  ausente — corrige C1/FR-011), decidindo modal vs. recusa conforme `_rideStatus` (a ramificação de
  recusa é da US4; aqui só o caminho `aguardandoSolicitacao`)
- [X] T022 [US1] `QuoteAcceptedModal` entra na mesma fila sequencial de modal já usada por
  `RideRequestModal` (nunca duas modais simultâneas, D3 de `specs/007.../research.md`)
- [X] T023 [US1] Ao tocar "Iniciar corrida", `MapScreen` transiciona `_rideStatus` para
  `deslocandoAtePassageiro`, grava `ActiveRide` via `RideStateStore.save`, e fecha a modal

**Checkpoint**: US1 completa e testável de forma independente.

---

## Phase 4: User Story 2 - Deixar de ver novas solicitações fora do estado "Aguardando" (Priority: P1)

**Goal**: nenhuma modal de solicitação (`kind: 20001`) enquanto o motorista não estiver
"Aguardando solicitação de corrida"; fila pendente descartada na transição (FR-004, FR-005).

**Independent Test**: com o motorista em `deslocandoAtePassageiro`, simular uma nova solicitação —
nenhuma modal aparece; repetir em `aguardandoSolicitacao` — a modal volta a aparecer.

### Tests for User Story 2

- [X] T024 [P] [US2] Widget test: `kind: 20001` recebido com `_rideStatus ==
  deslocandoAtePassageiro` não abre modal nem entra na fila, em `test/screens/map_screen_test.dart`
- [X] T025 [P] [US2] Widget test: solicitações já enfileiradas em `_filaSolicitacoes` são
  descartadas no instante em que "Iniciar corrida" é tocado (T023), em
  `test/screens/map_screen_test.dart`

### Implementation for User Story 2

- [X] T026 [US2] `MapScreen._aoAtualizarFeed` passa a só aceitar `kind: 20001` quando `_rideStatus
  == aguardandoSolicitacao` (depende de T021)
- [X] T027 [US2] `MapScreen`, no mesmo passo de T023 (transição para `deslocandoAtePassageiro`),
  limpa `_filaSolicitacoes`

**Checkpoint**: US1 + US2 completas e testáveis de forma independente.

---

## Phase 5: User Story 3 - Compartilhar a localização atual durante o deslocamento (Priority: P2)

**Goal**: publicar `kind: 20005` a cada 50 m percorridos, só durante `deslocandoAtePassageiro`, com
retomada automática após reinício (FR-007 a FR-009).

**Independent Test**: com o motorista em `deslocandoAtePassageiro`, simular avanços de posição —
publica a cada ultrapassagem de 50 m, nunca abaixo disso, nunca fora do estado, e retoma sozinho
após uma reconstrução do widget com o estado já persistido.

### Tests for User Story 3

- [X] T028 [P] [US3] Unit test da fórmula de distância (`geo_distance.dart`) contra pares de
  coordenadas com distância conhecida, em `test/domain/geo_distance_test.dart`
- [X] T029 [P] [US3] Test de `IdentityService.signDriverLocation`: evento válido (`kind: 20005`,
  tags `e`/`p` corretas, `content` com `lat`/`lon`) **e** identidade inválida, em
  `test/services/identity_service_test.dart` (Princípio II)
- [X] T030 [P] [US3] Widget test: `MapScreen` publica `kind: 20005` ao avançar ≥ 50 m durante
  `deslocandoAtePassageiro`; não publica abaixo de 50 m; não publica em
  `aguardandoSolicitacao`, em `test/screens/map_screen_test.dart`
- [X] T031 [P] [US3] Widget test: com o `RideStateStore` (dublê) pré-carregado em
  `deslocandoAtePassageiro` (simulando reinício), um avanço de posição ≥ 50 m publica `kind: 20005`
  sem nenhuma ação do motorista, em `test/screens/map_screen_test.dart` (corrige C3/FR-009)

### Implementation for User Story 3

- [X] T032 [US3] Criar `metersBetween(lat1, lon1, lat2, lon2)` (Haversine, sem dependência de
  terceiros) em `lib/domain/geo_distance.dart`
- [X] T033 [US3] `IdentityService.signDriverLocation` (`kind: 20005`, tags `["e", quoteId]` +
  `["p", passengerPubkey]`, `content: {"lat":, "lon":}`) em `lib/services/identity_service.dart`
- [X] T034 [US3] `MapScreen._aoReceberPosicao`: quando `_rideStatus == deslocandoAtePassageiro` e
  `metersBetween` da última posição publicada ≥ 50 m, assina e publica via `relayService`,
  atualizando a última posição publicada (depende de T032, T033) — como `_rideStatus` já vem de
  `RideStateStore.load()` (T019), a retomada após reinício (T031) não exige nenhum código adicional
  além deste

**Checkpoint**: US1 + US2 + US3 completas e testáveis de forma independente.

---

## Phase 6: User Story 4 - Avisar o passageiro quando uma segunda aceitação não pode ser atendida (Priority: P3)

**Goal**: segunda aceitação chegando durante `deslocandoAtePassageiro` não abre modal; publica
`kind: 20006` ao autor daquela aceitação (FR-010).

**Independent Test**: com o motorista já em `deslocandoAtePassageiro`, simular uma segunda
aceitação — nenhuma modal aparece; um `kind: 20006` é publicado ao autor dela.

### Tests for User Story 4

- [X] T035 [P] [US4] Test de `IdentityService.signRideNoLongerAvailable`: evento válido (`kind:
  20006`, tags `e`/`p` corretas, `content` vazio) **e** identidade inválida, em
  `test/services/identity_service_test.dart` (Princípio II)
- [X] T036 [P] [US4] Widget test: segunda aceitação com `_rideStatus == deslocandoAtePassageiro`
  não abre `QuoteAcceptedModal` e publica `kind: 20006` dirigido ao `pubkey` da aceitação, em
  `test/screens/map_screen_test.dart`

### Implementation for User Story 4

- [X] T037 [US4] `IdentityService.signRideNoLongerAvailable` (`kind: 20006`, tags `["e", quoteId]`
  + `["p", passengerPubkey]`, `content: ""`) em `lib/services/identity_service.dart`
- [X] T038 [US4] Completa a ramificação de T021: quando `_rideStatus == deslocandoAtePassageiro` e
  chega outra `QuoteAccepted` (já validada contra `SentQuotesStore`), publica `kind: 20006` ao
  invés de abrir modal, sem alterar o estado (depende de T021, T037)

**Checkpoint**: todas as quatro user stories completas e testáveis de forma independente.

---

## Phase 7: Polish & Cross-Cutting Concerns

- [X] T039 `flutter analyze` sem apontamentos (gate 1 da constituição)
- [X] T040 `flutter test` — suíte completa passando, sem teste ignorado (gate 2 da constituição)
- [ ] T041 Executar os cenários de `quickstart.md`; relatar explicitamente os que não puderam ser
  executados (ex.: exigem dois aparelhos/emuladores) em vez de omiti-los (gate 3 da constituição)
- [X] T042 Verificação de não vazamento do Princípio I: inspecionar log e payloads publicados dos
  novos eventos (`kind: 20005`, `20006`) e confirmar ausência de chave privada
- [X] T043 Commit de implementação desta feature (código + testes), separado do commit da emenda de
  contrato (T003) e do commit de documentação (T044)
- [X] T044 Atualizar `../../CLAUDE.md` (raiz do repositório) registrando a feature 010 do motorista,
  em commit próprio, separado do código (Padrão de Commits, item 6)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: sem dependências — mas bloqueia tudo abaixo (Princípio IV: contrato antes do
  código)
- **Foundational (Phase 2)**: depende do Setup — bloqueia todas as user stories
- **US1 (Phase 3)**: depende só do Foundational
- **US2 (Phase 4)**: depende do Foundational **e** de T021/T023 (US1) — não é independente de
  código, ao contrário do padrão usual, porque estende a mesma ramificação de `_aoAtualizarFeed` e o
  mesmo passo de transição que a US1 introduz
- **US3 (Phase 5)**: depende do Foundational **e** de T019/T023 (US1, para `_rideStatus`
  disponível) — a fórmula de distância (T028/T032) em si é independente e pode ser feita em
  paralelo com US1/US2
- **US4 (Phase 6)**: depende do Foundational **e** de T021 (US1, mesma ramificação de leitura do
  `kind: 20003`, já validada contra `SentQuotesStore`)
- **Polish (Phase 7)**: depende de todas as user stories desejadas estarem completas

### Parallel Opportunities

- T001/T002 podem ser feitos em paralelo (arquivos diferentes), mas commitados juntos (T003)
- T004-T007, T009 podem ser feitos em paralelo entre si (arquivos diferentes, sem dependência); T008
  depende de T005/T006
- T011-T016 (testes da US1) podem ser escritos em paralelo entre si
- T028/T029 (US3) podem começar em paralelo com o restante da US1, já que não dependem de
  `_rideStatus`; só a integração final (T034) depende de T019/T023

---

## Implementation Strategy

### MVP First (User Story 1)

1. Completar Phase 1 (contrato) e Phase 2 (fundação)
2. Completar Phase 3 (US1)
3. Validar US1 de forma independente (modal + transição + persistência + validação de FR-011)

### Incremental Delivery

1. Setup + Foundational → base pronta
2. US1 → modal de aceitação e novo estado persistido (MVP)
3. US2 → bloqueio de novas solicitações fora de "Aguardando"
4. US3 → publicação de localização
5. US4 → aviso de indisponibilidade em aceitação concorrente
6. Cada incremento soma valor sem quebrar o anterior

## Notes

- [P] = arquivos diferentes, sem dependência
- Commit separado para: emenda de contrato (T003), código (T043) e `CLAUDE.md` (T044) — Padrão de
  Commits, item 6
- Verificar que os testes falham antes de implementar (T011-T016, T024-T025, T028-T031, T035-T036)
- Parar em qualquer checkpoint para validar a story isoladamente
