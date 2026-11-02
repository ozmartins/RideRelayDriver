# Tasks: Cancelar corrida (motorista)

**Input**: Design documents from `/specs/018-cancelar-corrida-motorista/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/README.md, quickstart.md

**Tests**: **obrigatórios** (Princípio II; nenhum teste toca rede ou relay). Assinatura do novo kind e regra de transição têm teste direto; o comportamento no mapa usa os dublês já existentes em `test/screens/map_screen_test.dart` (gateway falso, `RideStateStore` em memória, `FakeRouteDistanceService`).

**Organization**: o gate do Princípio IV (contrato antes do código, nas duas cópias) vem primeiro e bloqueia o resto. US1 (cancelar a caminho, P1) entrega todo o caminho de código; US2 (cancelar em "Em corrida", P1) e US3 (reinício e isolamento, P2) acrescentam sobretudo testes que travam as condições (rota em voo, reinício, eventos tardios).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: pode rodar em paralelo
- Caminhos relativos a `Prototipo/driver/`, salvo indicação (`../passenger/` = `Prototipo/passenger/`)

---

## Phase 1: Foundational — contrato (bloqueia todo o código, Princípio IV)

- [X] T001 Inserir a emenda 14 em `specs/002-nostr-relay-connection/contracts/nostr-events.md` conforme `specs/018-cancelar-corrida-motorista/contracts/README.md`: linha `20012` na tabela de kinds, linha 14 no *Histórico de emendas*, parágrafo de *Forma da inscrição* (passageiro passa a incluir `20012`) e seção *Conteúdo do kind 20012* (depois da do `20011`).
- [X] T002 Replicar a mesma alteração em `../passenger/specs/002-nostr-relay-connection/contracts/nostr-events.md`, atualizando só o cabeçalho de procedência (data 2026-10-04, "emenda 14, kind 20012, publicado pelo motorista e consumido pela feature 019 do passageiro"). Conferir com `diff` ignorando o cabeçalho (ajustar o `tail` ao tamanho real dele): vazio.

**Checkpoint**: contrato idêntico nas duas cópias; commitar T001+T002 juntos, antes de qualquer código.

---

## Phase 2: Foundational — domínio e assinatura (bloqueia as histórias)

- [X] T003 [P] Acrescentar a `test/domain/driver_ride_status_test.dart` o grupo `canCancelRide (feature 018)`: `false` em `aguardandoSolicitacao`; `true` em `deslocandoAtePassageiro` e em `emCorrida`. Deve falhar antes de T005.
- [X] T004 [P] Acrescentar a `test/services/identity_service_test.dart` o grupo `signRideCancelled (feature 018)`, no padrão de `signDestinationArrival`: kind `NostrEvent.kindRideCancelled` (20012), assinatura válida, autor = chave pública da identidade, tags marcador + `["e", quoteId]` + `["p", passengerPubkey]`, `content` vazio (Princípio II). Deve falhar antes de T006.
- [X] T005 Acrescentar `DriverRideRules.canCancelRide(DriverRideStatus)` em `lib/domain/driver_ride_status.dart` (`true` só em `deslocandoAtePassageiro` e `emCorrida`; doc comment no padrão dos vizinhos). T003 passa.
- [X] T006 Acrescentar `static const int kindRideCancelled = 20012;` em `lib/domain/nostr_event.dart` (doc comment no padrão dos vizinhos, citando emenda 14) e `signRideCancelled({identity, quoteId, passengerPubkey})` em `lib/services/identity_service.dart`, que chama `_signCorrelatedEvent(kind: kindRideCancelled, content: '')`; atualizar o comentário de `_signCorrelatedEvent` para incluir o `20012`. T004 passa.
- [X] T007 [P] Escrever `test/screens/cancel_ride_modal_test.dart` e criar `lib/screens/cancel_ride_modal.dart` (`CancelRideModal`, apresentacional, `ModalTematizado`, título "Cancelar corrida?", texto explicando que o passageiro será avisado; ações "Voltar" — `estiloAcaoSecundaria` — e "Cancelar corrida" — `estiloAcaoPrimaria(altura: 48)` —, callbacks `onConfirm` e `onBack`, no padrão de `RideRatingModal`). Testes: mostra título e as duas ações; toque em cada uma chama só o callback correspondente.

**Checkpoint**: `flutter test test/domain/driver_ride_status_test.dart test/services/identity_service_test.dart test/screens/cancel_ride_modal_test.dart` verde.

---

## Phase 3: User Story 1 — Cancelar a corrida a caminho do passageiro (Priority: P1) 🎯 MVP

**Goal**: em "Deslocando-se até o passageiro", o motorista cancela com confirmação; volta ao repouso, a corrida é descartada e o passageiro é avisado por `kind: 20012`.

**Independent Test**: no `map_screen_test.dart`, com a corrida ativa em "Deslocando-se até o passageiro", tocar "Cancelar corrida" → "Cancelar corrida" (modal) e verificar estado, persistência e evento publicado.

- [X] T008 [US1] Escrever em `test/screens/map_screen_test.dart` o grupo `cancelar corrida (feature 018)`, falhando antes de T009/T010: (a) em "Deslocando-se até o passageiro" o botão "Cancelar corrida" existe; em "Aguardando solicitação de corrida" não existe (FR-001); (b) tocar no botão abre a modal; "Voltar" a fecha sem mudar estado, sem `ActiveRide` zerada e sem publicar nada (FR-002, SC-003); (c) confirmar volta o estado a `aguardandoSolicitacao`, `RideStateStore.load()` devolve `(aguardandoSolicitacao, null)` e exatamente um `kind: 20012` é publicado com `["e", quoteId]` e `["p", passengerPubkey]` da corrida (FR-003, FR-004, SC-002); (d) duplo toque em confirmar publica um só (FR-004); (e) marcador e rota somem do mapa e nenhuma localização (`kind: 20005`) é publicada depois (FR-005); (f) a modal de avaliação **não** abre (FR-006).
- [X] T009 [US1] Em `lib/screens/map_screen.dart`, implementar `_cancelarCorrida()` conforme `research.md` D3 — guarda `DriverRideRules.canCancelRide(_rideStatus)` e `_activeRide != null`; no mesmo `setState`, `_rideStatus = aguardandoSolicitacao`, `_activeRide = null`, `_ultimaPublicacaoEm = null`; `unawaited(widget.rideStateStore.save(_rideStatus, null))`; `_sincronizarRota()`; `unawaited(_publicarCancelamento(ativa))` — sem abrir `_mostrarModalAvaliacao` — e `_publicarCancelamento(ActiveRide)` no padrão de `_publicarChegada` (D4: sem identidade ou sem relay conectado não publica; `signRideCancelled`; `relayService.publish(...).toList()`; erro absorvido).
- [X] T010 [US1] Em `lib/screens/map_screen.dart`, adicionar o botão "Cancelar corrida" (`_BotaoCancelarCorrida`, no padrão de `_FaixaRotaIndisponivel`: `campo`, raio 16, ícone e texto em `Theme.of(context).colorScheme.error`, sem cor fixa) em `Positioned(left: 16, bottom: 112)`, visível só com `DriverRideRules.canCancelRide(_rideStatus)`; o toque chama `_mostrarModalCancelamento()`, que abre `CancelRideModal` via `showDialog` (`barrierDismissible: false`, mesmo padrão de `_mostrarModalAvaliacao`): "Voltar" fecha; "Cancelar corrida" fecha e chama `_cancelarCorrida()`. T008 passa.

**Checkpoint**: US1 funcional e testável sozinha.

---

## Phase 4: User Story 2 — Cancelar a corrida em andamento (Priority: P1)

**Goal**: mesmos efeitos em "Em corrida", com localização e rota deixando de ser publicadas.

**Independent Test**: com o motorista "Em corrida", cancelar e verificar estado, evento e ausência de publicações de rota/localização.

- [X] T011 [US2] Acrescentar ao grupo de T008, em `test/screens/map_screen_test.dart`: (a) em "Em corrida" o botão existe e cancelar produz os mesmos efeitos de T008(c) (FR-001, FR-003, FR-004); (b) o marcador de destino e o trajeto do mapa somem (US2, cenário 2); (c) depois de cancelar, um cálculo de rota ainda em voo (dublê com `Completer`) não publica `kind: 20011` nem redesenha o trajeto (FR-005); (d) a modal de avaliação não abre (FR-006). Se algum caso falhar, corrigir `_cancelarCorrida` em `lib/screens/map_screen.dart`.

**Checkpoint**: US1 e US2 verdes.

---

## Phase 5: User Story 3 — Cancelamento sobrevive a reinício e não vaza para outras corridas (Priority: P2)

**Goal**: o cancelamento é definitivo e vale só para a corrida cancelada.

- [X] T012 [US3] Acrescentar ao grupo de T008, em `test/screens/map_screen_test.dart`: (a) reabrir a tela com o mesmo `RideStateStore` depois de cancelar mostra "Aguardando solicitação de corrida", sem botão, sem marcador, sem publicar localização (FR-003, SC-004); (b) depois de cancelar, `kind: 20008` e `kind: 20010` com o `quoteId` cancelado são ignorados — estado continua `aguardandoSolicitacao` e a modal de avaliação não abre (FR-007); (c) depois de cancelar, aceitar e iniciar outra corrida (outro `quoteId`) funciona normalmente, e cancelar essa publica `kind: 20012` só com o `quoteId` dela (SC-005); (d) cancelar sem relay conectado deixa o motorista livre, nada é publicado e nenhuma exceção chega à tela (FR-008); (e) com o motorista offline/online como estava antes, solicitações voltam a ser recebidas conforme o status (FR-010).

---

## Phase 6: Polish & cross-cutting

- [X] T013 Rodar `flutter analyze` ("No issues found!") e `flutter test` (suíte completa; anotar o total) em `Prototipo/driver/`.
- [X] T014 Conferir contra a seção **Identidade Visual e Design** de `.specify/memory/constitution.md` o botão e a modal novos (raios, cores, tipografia, `ColorScheme.error`); corrigir divergências em `lib/screens/map_screen.dart`/`cancel_ride_modal.dart`.
- [X] T015 Registrar o estado da validação em aparelho em `specs/018-cancelar-corrida-motorista/quickstart.md` (cenários 1–6; ponta a ponta depende da feature 019 do passageiro; marcar pendente se não houver aparelho/emulador).
- [X] T016 Atualizar `../CLAUDE.md` (raiz do repositório): entrada da feature `018-cancelar-corrida-motorista` do motorista e referência à contrapartida (019 do passageiro), em commit separado, no padrão das entradas anteriores; marcar a validação em aparelho como pendente.

---

## Dependencies & Execution Order

- Phase 1 (contrato, T001–T002) → bloqueia tudo; commit próprio com as duas cópias.
- Phase 2: T003 ∥ T004 ∥ T007; T005 depois de T003; T006 depois de T004.
- Phase 3: T008 → T009 → T010 (dependem de T005, T006, T007).
- Phase 4 e 5 dependem de T010; T011 e T012 estão no mesmo arquivo: sequenciar.
- Polish depois de tudo.

### Parallel opportunities
- T003 ∥ T004 ∥ T007 (arquivos diferentes).

## Implementation Strategy

1. Contrato nas duas apps (T001–T002) e commit.
2. MVP = Phase 2 + Phase 3 (T003–T010): o motorista cancela a caminho do passageiro e publica o aviso.
3. Phases 4–5 travam "Em corrida", reinício e isolamento; Phase 6 fecha qualidade e documentação.
4. A feature `019` do passageiro (outra spec-kit, em `Prototipo/passenger/`) consome o `kind: 20012`; sem ela o ponta a ponta só é observável pelos eventos publicados.
