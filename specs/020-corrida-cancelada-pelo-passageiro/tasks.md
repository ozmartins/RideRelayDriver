# Tasks: Corrida cancelada pelo passageiro (motorista)

**Input**: `specs/020-corrida-cancelada-pelo-passageiro/` (spec, plan, research, data-model, quickstart)
**Tests**: incluídos — Princípio II e o padrão do projeto (cada feature traz os seus).
**Convenção**: `[P]` = arquivos diferentes, sem dependência de tarefa incompleta; `[USn]` = história de `spec.md`.

## Phase 1: Setup

- [x] T001 Conferir que a emenda 19 está nas duas cópias do contrato e idênticas: `diff <(tail -n +12 ../passenger/specs/002-nostr-relay-connection/contracts/nostr-events.md) specs/002-nostr-relay-connection/contracts/nostr-events.md` não imprime nada, e `git log` mostra o commit `747f944` antes de qualquer código desta feature (Princípio IV, `contracts/README.md`).

## Phase 2: Foundational (bloqueia todas as histórias)

- [x] T002 [P] Acrescentar `static const int kindRideCancelledByPassenger = 20013;` com doc ao lado de `kindRideCancelled` em `lib/domain/nostr_event.dart`.
- [x] T003 [P] Acrescentar `DriverRideRules.canBeCancelledByPassenger(DriverRideStatus)` (`deslocandoAtePassageiro` ou `emCorrida`) em `lib/domain/driver_ride_status.dart`, com doc citando FR-002/FR-003; e testes em `test/domain/driver_ride_status_test.dart` (verdadeiro nos dois estados, falso em `aguardandoSolicitacao`).
- [x] T004 [P] Criar `lib/screens/ride_cancelled_by_passenger_modal.dart`: `RideCancelledByPassengerModal` apresentacional (`ModalTematizado`, título "Corrida cancelada", mensagem "O passageiro cancelou a corrida.", botão primário "OK" → `onClose`), no padrão de `lib/screens/cancel_ride_modal.dart`; e `test/screens/ride_cancelled_by_passenger_modal_test.dart` (exibe título e mensagem; "OK" chama `onClose`).
- [x] T005 Em `lib/main.dart`, incluir `NostrEvent.kindRideCancelledByPassenger` em `_consumedKinds` (alimenta `RelayService.subscriptionKinds` e `EventFeed.acceptedKinds`) e atualizar o comentário que enumera as features (depende de T002).
- [x] T006 Em `lib/screens/map_screen.dart`, extrair de `_cancelarCorrida` o bloco de efeito local (`setState` com `aguardandoSolicitacao`, `_activeRide = null`, `_ultimaPublicacaoEm = null`; `save(status, null)`; `_sincronizarRota()`) para `_encerrarCorridaLocalmente()` e fazer `_cancelarCorrida` usá-lo, **sem mudar comportamento**: os testes da 018 em `test/screens/map_screen_test.dart` continuam passando (D3 de `research.md`).

**Checkpoint**: `flutter analyze` limpo e a suíte existente verde.

## Phase 3: User Story 1 — Avisado a caminho do passageiro (P1) 🎯 MVP

**Objetivo**: em "Deslocando-se até o passageiro", um 20013 válido encerra a corrida e abre a modal.
**Teste independente**: entregar o aviso válido com o motorista nesse estado; conferir repouso, corrida descartada, `rideStateStore` zerado, sem `20005` depois e modal visível.

- [x] T007 [US1] Em `test/screens/map_screen_test.dart`, criar o helper do aviso (evento `20013` assinado pelo passageiro, `["e", quoteId]`, `["p", <motorista>]`, `content` cifrado a `{}` com a mesma `MessageCipher` dos testes de "recepção cifrada") e incluir o kind em `acceptedKinds` do `EventFeed` do cenário; escrever o teste de aceitação em "Deslocando-se" (estado `aguardandoSolicitacao`, `ActiveRide` nula e persistida, modal "O passageiro cancelou a corrida", "OK" fecha, nada publicado pelo `FakeGateway`).
- [x] T008 [US1] Em `lib/screens/map_screen.dart`, acrescentar o ramo `NostrEvent.kindRideCancelledByPassenger` em `_aoAtualizarFeed` (com `_idsProcessados.add`) chamando `_processarCancelamentoDoPassageiro(evento)`; implementá-lo: `_decifraSemDadoProprio`, `_activeRide != null`, `referencedEventId == quoteId`, `authorPublicKey == passengerPubkey`, `canBeCancelledByPassenger(_rideStatus)`; então `_encerrarCorridaLocalmente()` e `unawaited(_mostrarModalCancelamentoPeloPassageiro())`, que abre `RideCancelledByPassengerModal` por `showDialog` (`barrierDismissible: false`, fora de `_fila`/`_modalAtual`; padrão de `_mostrarModalAceitacao`).
- [x] T009 [US1] Teste em `test/screens/map_screen_test.dart`: depois do cancelamento, novas posições não geram `kind: 20005` (FR-004).

## Phase 4: User Story 2 — Avisado com a corrida em andamento (P1)

**Objetivo**: o mesmo, em "Em corrida", sem abrir avaliação.
**Teste independente**: com o motorista "Em corrida", entregar o aviso e conferir repouso, rota e marcador de destino removidos, modal de cancelamento e **nenhuma** modal de avaliação.

- [x] T010 [US2] Teste em `test/screens/map_screen_test.dart`: aceitação em "Em corrida" (estado, corrida descartada, marcador de destino/rota fora do mapa, nenhuma `RideRatingModal`, nada publicado).

## Phase 5: User Story 3 — Só o aviso legítimo cancela, e só uma vez (P2)

**Objetivo**: autoria, correlação, destinatário, cifra, estado e duplicata.
**Teste independente**: cada caso inválido deixa estado e telas intactos.

- [x] T011 [US3] Testes de rejeição em `test/screens/map_screen_test.dart`, um por caso: autor ≠ passageiro da corrida; `["e", ...]` de outra corrida; tag `p` de outro motorista; `content` em claro; `content` que decifra para outro texto; motorista em `aguardandoSolicitacao`. Em todos: estado e `ActiveRide` inalterados, nenhuma modal.
- [x] T012 [US3] Teste de duplicata: o mesmo evento (mesmo `id`) entregue duas vezes → um único efeito e a modal não reabre depois do "OK" (FR-007).
- [x] T013 [US3] Em `lib/screens/map_screen.dart`, guardar o `BuildContext` do diálogo de `_mostrarModalCancelamento` em `_contextoConfirmacaoCancelamento` (zerado ao fechar por qualquer caminho) e, em `_processarCancelamentoDoPassageiro`, fechar essa confirmação (`Navigator.of(ctx).pop()` se `mounted`) antes de abrir a modal informativa (D4 de `research.md`); teste: com "Cancelar corrida?" aberta, o aviso fecha a confirmação, abre a informativa e nada é publicado ao passageiro.

## Phase 6: User Story 4 — Sobrevive a reinício e não vaza (P2)

**Objetivo**: persistência e isolamento entre corridas.
**Teste independente**: reinício após o cancelamento reabre em repouso; nova corrida segue normal.

- [x] T014 [US4] Testes em `test/screens/map_screen_test.dart`: (a) reabrir o `MapScreen` sobre o mesmo `InMemoryRideStateStore` após o cancelamento → `aguardandoSolicitacao` sem corrida ativa; (b) confirmação de encontro e de destino atrasadas da corrida cancelada → ignoradas; (c) depois do cancelamento, aceitar e iniciar uma nova corrida com outro passageiro segue normalmente e um segundo `20013` do passageiro antigo não a afeta.

## Phase 7: Polish & cross-cutting

- [x] T015 `flutter analyze` ("No issues found!") e `flutter test` (suíte completa do motorista passando); anotar a contagem em `quickstart.md`, "Estado da validação".
- [x] T016 Marcar em `quickstart.md` a validação em aparelho como **pendente** e registrar a dependência da feature `023` do passageiro para o ponta a ponta.
- [x] T017 Conferir de novo, por `diff`, as duas cópias do contrato (T001) e que nenhum arquivo do passageiro foi tocado por esta feature.

## Dependências

- Phase 2 antes de tudo; T005 depende de T002; T006 só depende de existir a 018.
- US1 (T007–T009) é o MVP; US2 (T010) e US3 (T011–T013) dependem de T008; T013 altera `_mostrarModalCancelamento`/`_processarCancelamentoDoPassageiro`, logo vem depois de T008. US4 (T014) depois de T008.
- Polish por último.

## Paralelismo

- T002, T003 e T004 em paralelo (arquivos distintos).
- Os testes de T010, T011, T012 e T014 estão no mesmo arquivo; escrever em sequência, mas independentes quanto à lógica.

## Estratégia

MVP = Phases 1–3 (US1): já entrega o encerramento e a modal no estado mais comum. US2 só acrescenta o segundo estado e a ausência de avaliação; US3 e US4 endurecem. Cada fase fecha com `flutter analyze` e os testes do arquivo tocado.
