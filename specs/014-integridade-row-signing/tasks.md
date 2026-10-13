# Tasks: Integridade das avaliações (Row Signing, motorista)

**Input**: Design documents from `/specs/014-integridade-row-signing/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, quickstart.md

**Tests**: **obrigatórias**, não opcionais — Princípio II da constituição é NÃO NEGOCIÁVEL para
código que assina/verifica assinaturas, exigindo caso válido e caso inválido.

**Organization**: três user stories (US1/US2 P1, US3 P2); tarefas em Foundational → US1 → US2 →
US3 → Polish.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: pode rodar em paralelo (arquivos diferentes, sem dependência entre si)
- Caminhos de arquivo sempre relativos a `Prototipo/driver/`

---

## Phase 1: Foundational (Blocking Prerequisites)

- [X] T001 Criar `RideRatingSignature` (`canonicalPayload`, `sign`, `verify`, funções puras sobre
  `nostr.Nostr.instance.services.keys.sign`/`.verify`, D1/D2 de `research.md`) em
  `lib/services/ride_rating_signature.dart`; testes em
  `test/services/ride_rating_signature_test.dart` cobrindo: assinatura própria válida; dado
  adulterado depois de assinado (`verify` falso); assinatura de outra identidade (`verify` falso);
  `signature: null` (`verify` falso) — Princípio II, caso válido e inválido
- [X] T002 Migrar `SqfliteRideRatingStore` de v1 para v2 (`ALTER TABLE ride_ratings ADD COLUMN
  signature TEXT`, `ADD COLUMN tampered INTEGER NOT NULL DEFAULT 0`, D2 de `data-model.md`) e
  ampliar `RideRatingStore`/`SqfliteRideRatingStore` para que `save`/`forRide` recebam `Identity`
  por parâmetro (depende de T001)

**Checkpoint**: fundação pronta — as user stories podem começar.

---

## Phase 2: User Story 1 - Avaliação gravada com prova de integridade (Priority: P1) 🎯 MVP

**Goal**: ao gravar uma avaliação, ela carrega uma assinatura válida sobre seus próprios campos;
lida em seguida sem alteração, valida e é devolvida normalmente (FR-001, FR-002, FR-003, FR-008,
FR-009).

**Independent Test**: gravar uma avaliação pelo fluxo já existente (`save`) e verificar que o
registro persistido tem `signature` preenchida; ler pelo `forRide` e verificar que a mesma
avaliação é devolvida.

### Tests for User Story 1

- [X] T003 [P] [US1] Teste: `SqfliteRideRatingStore.save` persiste a linha com `signature`
  preenchida (não nula) e `tampered = 0` (FR-002), em `test/services/ride_rating_store_test.dart`
- [X] T004 [P] [US1] Teste: `forRide`, logo após `save` sem nenhuma alteração externa, devolve a
  mesma avaliação (`rideId`, `stars`, `ratedAt`) sem marcar violação (FR-003, US1 cenário 2), em
  `test/services/ride_rating_store_test.dart`

### Implementation for User Story 1

- [X] T005 [US1] `SqfliteRideRatingStore.save(rating, identity)` calcula
  `RideRatingSignature.sign(rating, identity)` e grava `ride_id`/`stars`/`rated_at`/`signature`
  (`tampered` fica no `DEFAULT 0`) (depende de T001, T002)
- [X] T006 [US1] `SqfliteRideRatingStore.forRide(rideId, identity)` lê a linha; se
  `tampered == 0` e `RideRatingSignature.verify(rating, signature, identity)` for verdadeiro,
  devolve a avaliação (depende de T001, T002, T005)
- [X] T007 [US1] `MapScreen._mostrarModalAvaliacao`: o callback `onConfirm` checa
  `widget.identity != null` antes de chamar `RideRatingStore.save` (D3 de `research.md`); se
  nulo, não persiste e só fecha a modal, em `lib/screens/map_screen.dart` (depende de T005)

**Checkpoint**: US1 completa e testável de forma independente.

---

## Phase 3: User Story 2 - Registro adulterado é detectado e descartado na leitura (Priority: P1)

**Goal**: um registro alterado por fora do app é reconhecido na leitura, marcado como violado de
forma persistida, e nunca mais devolvido — mesmo em leituras seguintes, sem repetir a validação
(FR-004, FR-005, FR-006).

**Independent Test**: gravar uma avaliação, alterar um campo diretamente no banco (simulando
adulteração fora do app), ler pelo `forRide` e verificar que devolve `null` e que a linha fica
marcada como violada; ler de novo e verificar que continua excluída.

### Tests for User Story 2

- [X] T008 [P] [US2] Teste: uma linha com `stars` alterado diretamente (mesma `signature` da
  gravação original, agora inconsistente) faz `forRide` devolver `null` (FR-004, FR-006), em
  `test/services/ride_rating_store_test.dart`
- [X] T009 [P] [US2] Teste: depois do cenário anterior, a linha correspondente tem `tampered = 1`
  persistido (FR-004), em `test/services/ride_rating_store_test.dart`
- [X] T010 [P] [US2] Teste: uma segunda chamada a `forRide` para a mesma linha já marcada como
  violada devolve `null` sem alterar `tampered` de novo nem invocar `RideRatingSignature.verify`
  outra vez (FR-005, US2 cenário 3), em `test/services/ride_rating_store_test.dart`

### Implementation for User Story 2

- [X] T011 [US2] `SqfliteRideRatingStore.forRide`: se `tampered == 1` já persistido, devolve
  `null` imediatamente, sem chamar `RideRatingSignature.verify` (FR-005) (depende de T006)
- [X] T012 [US2] `SqfliteRideRatingStore.forRide`: se a validação (T006) for falsa, executa
  `UPDATE ride_ratings SET tampered = 1 WHERE ride_id = ?` antes de devolver `null` (FR-004,
  FR-006) (depende de T006, T011)

**Checkpoint**: US1 + US2 completas e testáveis de forma independente.

---

## Phase 4: User Story 3 - Registros anteriores a este mecanismo são tratados como violados
(Priority: P2)

**Goal**: uma linha gravada antes desta feature (sem `signature`) é tratada exatamente como um
registro violado — mesmo caminho de US2, sem código adicional (FR-007).

**Independent Test**: inserir uma linha com `signature = null` (simulando dado pré-migração) e
verificar que `forRide` devolve `null` e marca `tampered = 1`.

### Tests for User Story 3

- [X] T013 [US3] Teste: uma linha com `signature = null` faz `forRide` devolver `null` e marcar
  `tampered = 1`, pelo mesmo caminho de T008/T009 (FR-007), em
  `test/services/ride_rating_store_test.dart` — depende só de T001/T002/T011/T012 (nenhuma
  implementação nova: `RideRatingSignature.verify` já devolve falso para `signature: null`, T001)

**Checkpoint**: US1 + US2 + US3 completas — feature inteira testável de forma independente.

---

## Phase 5: Polish & Cross-Cutting Concerns

- [X] T014 Verificação de não vazamento da chave privada (Princípio I, NÃO NEGOCIÁVEL): inspecionar
  que nenhum teste ou log imprime `Identity.privateKey` nem a assinatura resultante contém a chave
  em claro — relatar o resultado
- [X] T015 `flutter analyze` sem apontamentos (gate 1 da constituição)
- [X] T016 `flutter test` — suíte completa passando, sem teste ignorado (gate 2 da constituição)
- [ ] T017 Executar os cenários de `quickstart.md`; relatar explicitamente os que não puderam ser
  executados (gate 3 da constituição)
- [ ] T018 Commit de implementação desta feature (código + testes)
- [ ] T019 Atualizar `../../CLAUDE.md` (raiz do repositório) registrando a feature 014 do
  motorista, em commit próprio, separado do código (Padrão de Commits, item 6)

---

## Dependencies & Execution Order

- **Foundational (Phase 1)**: T002 depende de T001; nenhuma dependência externa a outra feature
- **US1 (Phase 2)**: depende do Foundational
- **US2 (Phase 3)**: depende do Foundational **e** de T006 (US1)
- **US3 (Phase 4)**: depende de US2 completa (T011/T012) — reaproveita o mesmo caminho de código
- **Polish (Phase 5)**: depende de US1 + US2 + US3 completas

### Parallel Opportunities

- T003, T004 (testes US1) em paralelo entre si
- T008, T009, T010 (testes US2) em paralelo entre si
- T011 e T012 são sequenciais

---

## Implementation Strategy

### MVP First (User Story 1)

1. Completar Phase 1 (fundação)
2. Completar Phase 2 (US1) — avaliações novas já saem assinadas e validam
3. Validar US1 de forma independente

### Incremental Delivery

1. Foundational → `RideRatingSignature` pronta, esquema migrado
2. US1 → gravação e leitura válida (MVP)
3. US2 → detecção e exclusão de adulteração
4. US3 → dados legados cobertos pela mesma regra, sem código extra

## Notes

- [P] = arquivos diferentes, sem dependência
- Commit separado para: código (T018) e `CLAUDE.md` (T019) — Padrão de Commits, item 6
- Verificar que os testes falham antes de implementar (T003, T004, T008-T010, T013)
