# Tasks: Avaliar corrida (motorista)

**Input**: Design documents from `/specs/013-avaliar-corrida/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, quickstart.md

**Tests**: **obrigatórias**, não opcionais (constituição, Princípio II via Fluxo de
Desenvolvimento e Gates — item 2, `flutter test` sem exceção).

**Organization**: uma única user story (P1); tarefas em Foundational → US1 → Polish.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: pode rodar em paralelo (arquivos diferentes, sem dependência entre si)
- Caminhos de arquivo sempre relativos a `Prototipo/driver/`

---

## Phase 1: Foundational (Blocking Prerequisites)

- [X] T001 [P] Criar entidade `RideRating` (`rideId`, `stars` 1-5, `ratedAt`) em
  `lib/domain/ride_rating.dart`, recusando `stars` fora de 1-5 no construtor (`ArgumentError`,
  mesmo padrão de `lib/domain/identity.dart`); testes em `test/domain/ride_rating_test.dart`
- [X] T002 Criar `RideRatingStore` (abstrata: `save`, `forRide`) e `SqfliteRideRatingStore`
  (tabela `ride_ratings`, banco `ride_ratings.db`, `ride_id` como chave primária, D1/D2 de
  `research.md`) em `lib/services/ride_rating_store.dart`, por analogia direta a
  `received_quote_store.dart` do passageiro (não ao estilo de exceções/migração de
  `SqfliteCadastroStore`, que resolve um problema diferente); sem teste de integração SQLite real
  (D1 de `research.md`, mesma situação de `SqfliteCadastroStore`) — dublê em memória para os
  testes de tela (depende de T001)

**Checkpoint**: fundação pronta — a user story pode começar.

---

## Phase 2: User Story 1 - Avaliar a corrida ao final (Priority: P1) 🎯 MVP

**Goal**: ao processar a confirmação de destino do passageiro (`kind: 20010`), que encerra a
corrida, exibir a tela de avaliação; confirmar uma nota de 1 a 5 persiste em `ride_ratings`;
pular fecha sem persistir nada; nunca reexibir para uma corrida já avaliada dentro da mesma sessão
(FR-001 a FR-009).

**Independent Test**: simular `_processarConfirmacaoDeDestino` (entrega de `kind: 20010`) e
verificar que a tela de avaliação aparece; tocar numa estrela e confirmar, e verificar a nota
persistida associada ao `quoteId` da corrida; em outro cenário, pular e verificar que nada é
persistido.

### Tests for User Story 1

- [X] T003 [P] [US1] Widget test: `kind: 20010` recebido no estado "Em corrida" (encerra a
  corrida) exibe `RideRatingModal` com cinco estrelas, nenhuma pré-selecionada (FR-001, FR-002),
  em `test/screens/map_screen_test.dart`
- [X] T004 [P] [US1] Widget test: tocar a estrela de posição N seleciona as estrelas 1..N e
  nenhuma das demais (FR-003), em `test/screens/map_screen_test.dart`
- [X] T005 [P] [US1] Widget test: selecionar uma nota e confirmar persiste `RideRating(rideId:
  quoteId, stars: nota)` via `RideRatingStore` e fecha a tela (FR-004, FR-005), em
  `test/screens/map_screen_test.dart`
- [X] T006 [P] [US1] Widget test: tocar pular/fechar sem selecionar nota fecha a tela sem chamar
  `RideRatingStore.save` (FR-008), em `test/screens/map_screen_test.dart`

### Implementation for User Story 1

- [X] T007 [US1] Criar `RideRatingModal` (cinco estrelas selecionáveis, botões "Confirmar" e
  "Pular", `onConfirm(int stars)`/`onSkip` callbacks) em `lib/screens/ride_rating_modal.dart`
- [X] T008 [US1] `MapScreen._processarConfirmacaoDeDestino` guarda `ativa.quoteId` antes de zerar
  `_activeRide`, e abre `RideRatingModal` via `showDialog` (`barrierDismissible: false`, mesmo
  padrão de `_mostrarModalAceitacao`) logo em seguida ao `setState` existente (depende de T007) —
  exigiu ajustar um teste pré-existente da feature 012
  (`test/screens/map_screen_test.dart`, "depois de voltar a Aguardando, uma nova solicitação de
  corrida volta a abrir modal normalmente") para dispensar a modal de avaliação (tocar "Pular")
  antes de continuar o cenário, já que ela agora aparece no mesmo instante
- [X] T009 [US1] `MapScreen` chama `RideRatingStore.save` ao confirmar uma nota (fecha a modal em
  seguida) e só fecha a modal, sem chamar `save`, ao pular (depende de T002, T008)

**Checkpoint**: US1 completa e testável de forma independente — MVP da feature.

---

## Phase 3: Polish & Cross-Cutting Concerns

- [X] T010 `flutter analyze` sem apontamentos (gate 1 da constituição)
- [X] T011 `flutter test` — suíte completa passando, sem teste ignorado (gate 2 da constituição)
- [ ] T012 Executar os cenários de `quickstart.md`; relatar explicitamente os que não puderam ser
  executados (gate 3 da constituição) — **pendente**: requer aparelho/emulador Android
- [ ] T013 Commit de implementação desta feature (código + testes)
- [ ] T014 Atualizar `../../CLAUDE.md` (raiz do repositório) registrando a feature 013 do
  motorista, em commit próprio, separado do código (Padrão de Commits, item 6)

---

## Dependencies & Execution Order

- **Foundational (Phase 1)**: T002 depende de T001; nenhuma dependência externa a outra feature
- **US1 (Phase 2)**: depende do Foundational
- **Polish (Phase 3)**: depende de US1 completa

### Parallel Opportunities

- T001 pode começar imediatamente; T002 depende dele
- T003-T006 (testes de US1) podem ser escritos em paralelo entre si

---

## Implementation Strategy

### MVP First (User Story 1)

1. Completar Phase 1 (fundação)
2. Completar Phase 2 (única user story) — já é a feature inteira
3. Validar de forma independente pelo `quickstart.md`

### Incremental Delivery

1. Foundational → `RideRating`/`RideRatingStore` prontos
2. US1 → tela de avaliação completa, encerrando o pedido do usuário para o lado do motorista
   (contrapartida do passageiro já implementada em `passenger/specs/011-avaliar-corrida/`)

## Notes

- [P] = arquivos diferentes, sem dependência
- Commit separado para: código (T013) e `CLAUDE.md` (T014) — Padrão de Commits, item 6
- Verificar que os testes falham antes de implementar (T003-T006)
