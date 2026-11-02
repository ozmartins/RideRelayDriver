# Tasks: Rota da corrida no mapa do motorista

**Input**: Design documents from `/specs/016-rota-no-mapa/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, quickstart.md (sem `contracts/`: nenhum evento muda)

**Tests**: **obrigatórios** (Princípio II, nenhum teste toca rede) para a regra de trecho/recálculo, para `trace()` do serviço de rota e para o comportamento do mapa em cada estado.

**Organization**: US1 (embarque, P1) → US2 (destino, P1) → US3 (mapa limpo, P2). Setup vazio (nenhuma dependência nova).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: pode rodar em paralelo (arquivos diferentes, sem dependência entre si)
- Caminhos relativos a `Prototipo/driver/`

---

## Phase 1: Foundational — domínio e serviço (bloqueia todas as histórias)

- [X] T001 [P] Criar `lib/domain/route_trace.dart` com `RouteTrace` (`points`, `distanceMeters`, `originUsed`, `target`), conforme `data-model.md`; sem tipos de `open_route_service`.
- [X] T002 [P] Escrever os testes de `RideLeg` em `test/domain/ride_leg_test.dart`: `deslocandoAtePassageiro` → trecho `pickup` com alvo (originLat, originLon); `emCorrida` → `dropoff` com alvo (destinationLat, destinationLon); `aguardandoSolicitacao`, `ActiveRide` nula ou alvo `(0, 0)` → `null` (D4); `shouldRefresh` verdadeiro sem tentativa anterior, com alvo diferente, e a ≥ 50 m; falso a < 50 m com o mesmo alvo. Devem falhar antes de T003.
- [X] T003 Criar `lib/domain/ride_leg.dart` com `RideLeg` (tipo + alvo `LatLng`), `RideLeg.of(DriverRideStatus, ActiveRide?)` (alvo `(0, 0)` → `null`) e `shouldRefresh` (usando `metersBetween` de `lib/domain/geo_distance.dart`) até T002 passar.
- [X] T004 [P] Escrever em `test/services/route_distance_service_test.dart` os casos de `trace()`: `OrsRouteDistanceService` devolve pontos e distância a partir de uma resposta GeoJSON falsa; falha de cliente vira `RouteDistanceFailure`; a requisição carrega só as duas coordenadas (FR-008); `FallbackRouteDistanceService.trace` repassa o resultado e **propaga a falha sem nova tentativa e sem reta** (D1). Devem falhar antes de T005.
- [X] T005 Acrescentar `trace({origin, destination})` → `Future<RouteTrace>` a `RouteDistanceService` em `lib/services/route_distance_service.dart`; implementar em `OrsRouteDistanceService` (mesma chamada `directionsRouteGeoJsonGet`, geometria lida como no `OrsRouteService` do passageiro) e em `FallbackRouteDistanceService` (repasse puro, D1) até T004 passar.
- [X] T006 Atualizar os dublês de `RouteDistanceService` para o novo método: `FakeRouteDistanceService` em `test/screens/ride_request_modal_test.dart` e `_ServicoDeTeste` em `test/services/route_distance_service_test.dart`; criar o dublê reutilizável `FakeRouteDistanceService` de `trace()` (resultado/falha configuráveis, contador de chamadas, requisições registradas) em `test/support/fake_route_distance_service.dart`, importado por `map_screen_test.dart`. `flutter test` volta a compilar e passar.

**Checkpoint**: `flutter analyze` limpo e `flutter test` verde; nenhuma mudança visível ao usuário ainda.

---

## Phase 2: User Story 1 — Caminho até o passageiro (P1) 🎯 MVP

**Goal**: em "Deslocando-se até o passageiro", ver marcador de embarque e trajeto até ele.

**Independent Test**: corrida ativa em `deslocandoAtePassageiro` + posição conhecida → `PolylineLayer` e marcador de embarque no mapa.

### Tests (escrever primeiro; devem falhar)

- [X] T007 [P] [US1] Em `test/screens/map_screen_test.dart`, testes de `MapScreen` com `RideStateStore` já em `deslocandoAtePassageiro` + `ActiveRide` e posição do dublê: polilinha roxa de 5 px e marcador de embarque (ícone de pessoa) aparecem após a primeira posição; reinício (nova `MapScreen` sobre o mesmo store) mostra o trajeto sem ação (FR-006).
- [X] T008 [P] [US1] Mesmo arquivo: recálculo — segunda posição a < 50 m não chama `trace()` de novo; a ≥ 50 m chama com a nova origem (FR-004, SC-004); posições durante uma requisição em voo não geram requisição concorrente.
- [X] T009 [P] [US1] Mesmo arquivo: falha de `trace()` → sem polilinha, marcador do alvo presente, faixa "Não foi possível traçar a rota agora."; publicação de localização/chegada continua (FR-005); a tentativa falha conta para o limiar (sem nova chamada a < 50 m); uma tentativa seguinte bem-sucedida remove a faixa.

### Implementation

- [X] T010 [US1] Em `lib/screens/map_screen.dart`, acrescentar o estado de rota (`_rota`, `_origemUltimaTentativa`, `_trechoDaUltimaTentativa`, `_rotaEmCalculo`, `_rotaIndisponivel`; `data-model.md`) e `_sincronizarRota()`: deriva o trecho via `RideLeg.of`, aplica `shouldRefresh`, chama `widget.routeDistanceService.trace`, descarta resposta cujo alvo não é mais o do trecho vigente, absorve qualquer exceção (D3).
- [X] T011 [US1] Chamar `_sincronizarRota()` ao receber posição (`_aoReceberPosicao`) e ao concluir `_carregarEstadoCorrida` (restauração, FR-006), sem alterar `_talvezPublicarLocalizacao`/`_talvezNotificarChegada*`.
- [X] T012 [US1] Renderizar em `build()` a `PolylineLayer` (`IdentidadeVisual.roxo`, 5 px) e o marcador do alvo (círculo 44 px `fundo`, borda branca 2 px, ícone em `destaque`; pessoa no embarque), acima dos tiles e abaixo do marcador do motorista (D5).
- [X] T013 [US1] Enquadramento (FR-010, D5): acrescentar `_seguindoMotorista` (padrão `true`); `_aoReceberPosicao` só chama `_mapController.move` se for `true`; ao receber o primeiro trajeto de um trecho, `_mapController.fitCamera(CameraFit.coordinates(...))` com padding inferior ≥ 170 px e `_seguindoMotorista = false`; `_BotaoCentralizar` volta a `true`; sem trajeto, volta a `true`. Recálculo de 50 m não reenquadra.
- [X] T013a [P] [US1] (teste, antes de T013) Em `test/screens/map_screen_test.dart`: com trajeto exibido, uma nova posição **não** move a câmera para o motorista; sem trajeto, move como antes; tocar "Centralizar" com trajeto move a câmera e a posição seguinte volta a ser seguida; um recálculo de 50 m não reenquadra.
- [X] T014 [US1] Faixa de aviso discreta de falha (D5: cartão `campo`, raio 16, ícone/texto 13 px em `ColorScheme.error`) no topo do mapa, ligada a `_rotaIndisponivel`.

**Checkpoint**: T007–T009 e T013a passam; US1 validável sozinha (quickstart 1, 2, 5, 6).

---

## Phase 3: User Story 2 — Caminho até o destino (P1)

**Goal**: em "Em corrida", trocar embarque por destino.

**Independent Test**: corrida ativa em `emCorrida` → trajeto e bandeira do destino; nada do embarque.

- [X] T015 [P] [US2] Em `test/screens/map_screen_test.dart`: partindo de `emCorrida`, polilinha e marcador de destino (ícone de bandeira) aparecem, sem marcador de embarque; ao receber a confirmação de encontro (`kind: 20008`) em "Deslocando-se", o trajeto de embarque é substituído pelo do destino com nova chamada a `trace()` (alvo = destino) (FR-002, SC-002); resposta tardia do trecho anterior é descartada.
- [X] T016 [US2] Em `lib/screens/map_screen.dart`, chamar `_sincronizarRota()` em `_processarConfirmacaoDeEncontro` (após o `setState`), invalidando `_rota`/tentativa ao mudar de trecho; marcador de bandeira para `dropoff`; novo enquadramento ao receber o primeiro trajeto do trecho.

**Checkpoint**: T015 passa; quickstart 3.

---

## Phase 4: User Story 3 — Mapa limpo fora da corrida (P2)

**Goal**: sem trajeto/marcador de corrida fora dos dois estados.

**Independent Test**: confirmação de destino (`kind: 20010`) → mapa só com a posição do motorista.

- [X] T017 [P] [US3] Em `test/screens/map_screen_test.dart`: em `aguardandoSolicitacao` não há polilinha nem marcador de alvo nem faixa; após `kind: 20010` em "Em corrida", tudo some e nenhuma nova chamada a `trace()` ocorre; uma resposta em voo que chega depois do encerramento é descartada (FR-003).
- [X] T018 [US3] Em `lib/screens/map_screen.dart`, em `_processarConfirmacaoDeDestino` e quando `RideLeg.of` devolve `null`, limpar `_rota`, tentativa e aviso (`_sincronizarRota()` trata o caso `null`).

**Checkpoint**: T017 passa; quickstart 4.

---

## Phase 5: Polish & cross-cutting

- [X] T019 `flutter analyze` ("No issues found!") e `flutter test` integral verdes; confirmar na leitura do diff que nenhum evento Nostr, contrato, relay ou arquivo do `passenger/` mudou (FR-007).
- [X] T020 Confirmar que a requisição ao ORS contém apenas as duas coordenadas e é HTTPS (FR-008) e registrar no `research.md` (D2) a verificação feita.
- [ ] T020a (PENDENTE: sem aparelho nesta sessão; SC-004 tem teste em T008) Medir e registrar no `quickstart.md` (seção Medições): tempo da abertura do mapa até a polilinha (SC-001, alvo ≤ 5 s), tempo da confirmação de encontro até a troca de trecho (SC-002, ≤ 2 s) e nº de consultas de rota numa corrida simulada de ≥ 1 km (SC-004).
- [ ] T021 (PENDENTE: só o alvo `linux` disponível; registrado no quickstart) Executar o `quickstart.md` em aparelho/emulador; relatar no próprio arquivo o que passou e o que ficou pendente (Fluxo de Desenvolvimento e Gates, item 3). Sem aparelho, deixar "validação em aparelho pendente".
- [X] T022 Commit de implementação em português, direto na `master`, com trailer `Co-Authored-By:` (Padrão de Commits).
- [X] T023 Commit à parte atualizando `../CLAUDE.md` (raiz do TCC) com a feature `016-rota-no-mapa` do motorista: estados cobertos, reuso de `RouteDistanceService.trace`, recálculo a 50 m, sem contrato, sem emenda, testes passando, validação em aparelho pendente.

---

## Dependencies & Execution Order

- Phase 1 bloqueia tudo. Dentro dela: T001 ∥ T002 ∥ T004; T003 depois de T002 (e usa T001); T005 depois de T004 e T001; T006 depois de T005.
- US1 (Phase 2) depois da Phase 1. US2 e US3 dependem de T010–T012 (orquestração e renderização de US1) — não são independentes em código, mas cada uma é verificável sozinha.
- Tarefas de teste [P] de uma mesma história escrevem no mesmo arquivo: agrupar num só commit de edição, não rodar em paralelo de fato.

## Implementation Strategy

- **MVP**: Phase 1 + US1 (T001–T014): o motorista já vê o caminho até o passageiro.
- **Incremental**: US2 troca de trecho; US3 garante limpeza; Polish fecha.

## Notes

- Verificar que T002, T004, T007–T009, T013a, T015 e T017 falham antes de implementar.
- Commits separados: implementação (T022) e `CLAUDE.md` (T023). Sem emenda de constituição nesta feature.
