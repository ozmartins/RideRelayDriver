# Tasks: Publicar ao passageiro a rota da corrida

**Input**: Design documents from `/specs/017-publicar-rota-ao-passageiro/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/README.md, quickstart.md

**Tests**: **obrigatórios** (Princípio II; nenhum teste toca rede ou relay). Assinatura do novo kind e redução/codificação dos pontos têm teste direto; o comportamento no mapa usa dublês já existentes (`test/support/fake_route_distance_service.dart`, gateway falso de `map_screen_test.dart`).

**Organization**: o gate do Princípio IV (contrato antes do código, nas duas cópias) vem primeiro e bloqueia o resto. US1 (publicar em "Em corrida", P1) → US2 (nada fora de "Em corrida", P1) → US3 (falha não publica, P2). US2 e US3 não exigem código novo além de US1: são testes que travam as condições da publicação.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: pode rodar em paralelo
- Caminhos relativos a `Prototipo/driver/`, salvo indicação (`../passenger/` = `Prototipo/passenger/`)

---

## Phase 1: Foundational — contrato (bloqueia todo o código, Princípio IV)

- [X] T001 Inserir a emenda 13 em `specs/002-nostr-relay-connection/contracts/nostr-events.md` conforme `specs/017-publicar-rota-ao-passageiro/contracts/README.md`: linha `20011` na tabela de kinds, linha 13 no *Histórico de emendas*, seção *Conteúdo do kind 20011* (depois da do `20010`, com o exemplo de `content` em bloco ```json) e o ajuste do parágrafo de *Forma da inscrição* (passageiro passa a incluir `20011`).
- [X] T002 Replicar a mesma alteração, na mesma alteração de commit que T001, em `../passenger/specs/002-nostr-relay-connection/contracts/nostr-events.md`, atualizando só o cabeçalho de procedência (data 2026-10-03, "emenda 13, kind 20011"). Conferir: `diff <(tail -n +11 ../passenger/specs/002-nostr-relay-connection/contracts/nostr-events.md) specs/002-nostr-relay-connection/contracts/nostr-events.md` vazio (ajustar o `tail` ao tamanho real do cabeçalho).

**Checkpoint**: contrato idêntico nas duas cópias; commitar T001+T002 juntos (contrato nas duas apps é uma mudança lógica só), antes de qualquer código.

---

## Phase 2: Foundational — domínio e assinatura (bloqueia as histórias)

- [X] T003 [P] Escrever `test/domain/ride_route_content_test.dart`: `reduce` devolve a lista intacta com ≤ 1000 pontos; com 2500 pontos devolve exatamente 1000, mantendo primeiro e último pontos originais e a ordem; com 1001 e com 1999 pontos devolve exatamente 1000 (nunca 1001); `encode` arredonda lat/lon a 5 casas, produz `{"points":[[lat,lon],...]}`, e o tamanho de `encode` de 1000 pontos de coordenadas realistas fica abaixo de 30 000 bytes; `encode` com menos de 2 pontos lança `ArgumentError`. Devem falhar antes de T005.
- [X] T004 [P] Acrescentar a `test/services/identity_service_test.dart` o grupo `signRideRoute (feature 017)`, no padrão de `signDestinationArrival`: kind `NostrEvent.kindRideRoute` (20011), assinatura válida, autor = chave pública da identidade, tags marcador + `["e", quoteId]` + `["p", passengerPubkey]`, `content` decodificável com `points` iguais aos de entrada (Princípio II). Deve falhar antes de T006.
- [X] T005 Criar `lib/domain/ride_route_content.dart` conforme `data-model.md` (`maxPoints = 1000`, `decimalPlaces = 5`, `reduce`, `encode`), usando só `latlong2` e `dart:convert`, até T003 passar.
- [X] T006 Acrescentar `static const int kindRideRoute = 20011;` em `lib/domain/nostr_event.dart` (doc comment no padrão dos vizinhos, citando emenda 13) e `signRideRoute({identity, quoteId, passengerPubkey, points})` em `lib/services/identity_service.dart`, que chama `_signCorrelatedEvent(kind: kindRideRoute, content: RideRouteContent.encode(points))`; atualizar o comentário de `_signCorrelatedEvent` para incluir o `20011`. T004 passa.

**Checkpoint**: `flutter test test/domain/ride_route_content_test.dart test/services/identity_service_test.dart` verde.

---

## Phase 3: User Story 1 — Passageiro recebe a rota até o destino (Priority: P1) 🎯 MVP

**Goal**: em "Em corrida", cada trajeto até o destino calculado com sucesso é publicado ao passageiro da corrida ativa, sem consulta extra ao serviço de rotas.

**Independent Test**: cenários 1, 2 e 5 de `quickstart.md`.

- [X] T007 [US1] Escrever em `test/screens/map_screen_test.dart` o grupo "rota ao passageiro (feature 017)": com `emCorrida`, `ActiveRide` com destino válido e `FakeRouteDistanceService` devolvendo um `RouteTrace`, após o primeiro trajeto há exatamente 1 evento `NostrEvent.kindRideRoute` em `ambiente.gateway.publicados`, com tags `["e", quoteId]` e `["p", passengerPubkey]` da `ActiveRide` e `content` com os pontos do trajeto; após mover o motorista > 50 m, há um 2º evento com a rota recalculada; reconstruir o `MapScreen` já em `emCorrida` (com `ActiveRide` persistida em `RideStateStore`, simulando reinício do app) publica de novo um `kindRideRoute` assim que o trajeto é recalculado (Edge Case de reinício); o número de chamadas de `trace()` do dublê é igual ao de trajetos (nenhuma consulta extra, SC-003). Deve falhar antes de T008.
- [X] T008 [US1] Em `lib/screens/map_screen.dart`, no ramo de sucesso de `_calcularRota` (depois do `setState` e da checagem `RideLeg.of(_rideStatus, _activeRide) != leg`), se `_rideStatus == DriverRideStatus.emCorrida` e `_activeRide != null`, chamar `unawaited(_publicarRota(_activeRide!, trajeto))`; criar `_publicarRota(ActiveRide, RouteTrace)` no padrão de `_publicarChegadaAoDestino` (sem identidade ou sem relay conectado não publica; `identityService.signRideRoute(...)` + `relayService.publish(...).toList()`), cercado de `try`/`on Object` para que uma rota com < 2 pontos (`ArgumentError`) ou falha de publicação não afete o mapa nem a corrida (D5). T007 passa.
- [X] T009 [US1] Anotar no comentário-documento de `_calcularRota` que o trajeto bem-sucedido em "Em corrida" também é publicado ao passageiro (feature 017, D4), e conferir que `flutter analyze` não acusa nada.

**Checkpoint**: US1 funcional e testada; MVP.

---

## Phase 4: User Story 2 — Nada é enviado fora de "Em corrida" (Priority: P1)

**Goal**: garantir por teste que nenhum `kind: 20011` sai em "Deslocando-se até o passageiro", em "Aguardando solicitação" nem com resposta tardia.

**Independent Test**: cenário 3 de `quickstart.md`.

- [X] T010 [US2] Escrever em `test/screens/map_screen_test.dart` (mesmo grupo de T007): em `deslocandoAtePassageiro` com trajeto até a origem calculado com sucesso, `publicados` não contém `kindRideRoute`; em `aguardandoSolicitacao` idem; com a resposta de `trace()` ainda pendente (completer manual) e o destino confirmado (`kind: 20010`) antes de ela completar, a resposta tardia não gera `kindRideRoute`. Se algum falhar, corrigir a condição em `_calcularRota` (T008) — ela deve bastar.

---

## Phase 5: User Story 3 — Falha no cálculo não publica nada (Priority: P2)

**Goal**: garantir por teste que falhas de rota não publicam e não bloqueiam o resto da corrida.

**Independent Test**: cenário 4 de `quickstart.md`.

- [X] T011 [US3] Escrever em `test/screens/map_screen_test.dart` (mesmo grupo): em `emCorrida`, com `FakeRouteDistanceService` configurado para falhar, `publicados` não contém `kindRideRoute`, a faixa de aviso da feature 016 aparece, e a publicação de localização (`kindDriverLocation`) segue acontecendo; um `RouteTrace` com 1 só ponto também não publica e não derruba o mapa; sem relay conectado nada é publicado e nada lança.

---

## Phase 6: Polish & cross-cutting

- [X] T012 Rodar `flutter analyze` ("No issues found!") e `flutter test` (suíte completa; anotar o total) em `Prototipo/driver/`.
- [X] T013 Verificar na rede o tamanho e a aceitação (SC-004): publicar, com um script em `tool/` (estender `tool/verify_published.dart` ou criar `tool/publish_route_probe.dart`, sem alterar `lib/`), um `kind: 20011` com 1000 pontos de uma rota longa e conferir aceitação (OK) e entrega a uma 2ª conexão inscrita nos três relays padrão (o kind é efêmero, não há recuperação posterior); registrar o resultado em `quickstart.md` (cenário 5). Se algum relay recusar, reduzir `maxPoints` em `RideRouteContent`, no contrato (emenda 13) e em `research.md` D3, nas duas cópias do contrato, na mesma alteração.
- [X] T014 Atualizar `../CLAUDE.md` (raiz do repositório): entrada da feature `017-publicar-rota-ao-passageiro` do motorista e referência à contrapartida (018 do passageiro), em commit separado, no padrão das entradas anteriores; marcar a validação em aparelho como pendente.

---

## Dependencies & Execution Order

- Phase 1 (contrato, T001–T002) → bloqueia tudo; commit próprio com as duas cópias.
- Phase 2: T003 ∥ T004; T005 depois de T003; T006 depois de T004 e T005.
- Phase 3: T007 → T008 → T009 (depende de Phase 2).
- Phase 4 e 5 dependem de T008; T010 e T011 não dependem entre si (mesmo arquivo: sequenciar).
- Polish depois de tudo; T013 depende de T005/T006.

### Parallel opportunities
- T003 ∥ T004 (arquivos diferentes).
- T010 ∥ T011 se escritas em grupos separados e mescladas depois (mesmo arquivo → atenção).

## Implementation Strategy

1. Contrato nas duas apps (T001–T002) e commit.
2. MVP = Phase 2 + Phase 3 (T003–T009): o motorista já publica a rota correta em "Em corrida".
3. Phases 4–5 travam as condições negativas; Phase 6 mede o tamanho em relay real.
4. A feature `018` do passageiro (outra spec-kit, em `Prototipo/passenger/`) consome o `kind: 20011`; sem ela o ponta a ponta só é observável pelos eventos publicados.
