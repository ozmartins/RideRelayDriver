---

description: "Task list for 007-receber-solicitacao-corrida"

---

# Tasks: Receber solicitação de corrida e enviar orçamento

**Input**: Design documents from `specs/007-receber-solicitacao-corrida/`

**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md),
[data-model.md](./data-model.md), [contracts/README.md](./contracts/README.md),
[quickstart.md](./quickstart.md)

**Contrato de interoperabilidade**: a emenda 05 de
`specs/002-nostr-relay-connection/contracts/nostr-events.md` (novo `kind: 20002`, Orçamento de
corrida) já foi escrita e replicada de forma idêntica na app do passageiro durante o planejamento
desta feature (Princípio IV — contrato antes do código). Nenhuma tarefa abaixo a recria; T021
apenas confere que a replicação permanece íntegra antes de considerar a feature concluída.

**Tests**: incluídos, seguindo o mesmo padrão já usado pelas features 002–006 deste app (dublê de
transporte/serviço, nunca rede real nos testes automatizados — Princípio II, obrigatório para
`IdentityService.signRideQuote` e para o parsing de conteúdo recebido, por analogia à verificação
de assinatura).

**Organization**: tarefas agrupadas por user story do `spec.md` (US1 e US2 são P1, US3 é P2).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: pode rodar em paralelo (arquivos diferentes, sem dependência entre si)
- **[Story]**: US1, US2 ou US3, conforme `spec.md`
- Caminhos de arquivo exatos, relativos a `Prototipo/driver/`

## Path Conventions

Projeto mobile único (`lib/`, `test/`), estrutura já em uso pelas features 001–006: `lib/domain/`,
`lib/services/`, `lib/screens/`, espelhados em `test/domain/`, `test/services/`, `test/screens/`.

---

## Phase 1: Setup

- [x] T001 Adiciona `open_route_service: ^1.2.9` a `pubspec.yaml` e roda `flutter pub get`
  (já feito nesta sessão; decisão registrada em `research.md` D1)

---

## Phase 2: Foundational (bloqueante para todas as user stories)

- [x] T002 [P] Acrescenta `kindRideRequest = 20001` e `kindRideQuote = 20002` a
  `lib/domain/nostr_event.dart`
- [x] T003 [P] Cria `RideRequestReceived` (campos `requestId`, `origin`, `destination`, `payment`;
  fábrica `fromNostrEvent` que decodifica `content` e lança `FormatException` se malformado —
  `data-model.md`) em `lib/domain/ride_request_received.dart`
- [x] T004 [P] Cria `RideQuote` (campos `requestId`, `pricePerKm`, `total` — `data-model.md`) em
  `lib/domain/ride_quote.dart`
- [x] T005 [P] Cria a abstração `RouteDistanceService` (método
  `distanceMeters({origin, destination})`, lança em qualquer falha) em
  `lib/services/route_distance_service.dart`
- [x] T006 [US1] Implementa `OrsRouteDistanceService` (implementa `RouteDistanceService`,
  encapsula `open_route_service.OpenRouteService`, perfil `driving-car`, chave lida de
  `String.fromEnvironment('ORS_API_KEY')` — D1 de `research.md`) em
  `lib/services/route_distance_service.dart` (depende de T005)
- [x] T007 [P] Cria `FakeRouteDistanceService` (dublê controlável: sucesso com valor fixo, falha
  configurável) em `test/services/route_distance_service_test.dart`
- [x] T008 Acrescenta `signRideQuote({identity, requestId, pricePerKm, total})` a
  `lib/services/identity_service.dart` (monta `content` JSON e as tags `["t", ...]`/`["e", ...]`,
  assina com `kind: NostrEvent.kindRideQuote` — D4/D5 de `research.md`) (depende de T002, T004)
- [x] T009 [P] Testa `signRideQuote`: evento resultante tem `kind` correto, as duas tags, `content`
  decodificável com `pricePerKm`/`total` esperados, e assinatura válida (Princípio II) em
  `test/services/identity_service_test.dart` (depende de T008)
- [x] T010 Acrescenta `NostrEvent.kindRideRequest` ao `acceptedKinds` do `EventFeed` construído em
  `lib/main.dart` — sem isso, o app continua descartando toda solicitação recebida como kind
  desconhecido (contrato, regra 4) (depende de T002)

**Checkpoint**: `flutter analyze` e `flutter test` passam; o app já aceita e verifica o `kind:
20001`, mas nenhuma tela ainda reage a ele.

---

## Phase 3: User Story 1 — Ver a modal com origem, destino, distâncias e total (Priority: P1) 🎯 MVP

**Goal**: uma solicitação recebida com o motorista online abre uma modal com origem, destino, as
duas distâncias reais e o total, recalculado imediatamente ao editar o preço.

**Independent Test**: com o motorista online e posição disponível, simular o recebimento de um
evento `kind: 20001` e verificar que a modal aparece com os dados calculados a partir do preço
padrão do cadastro (quickstart.md, cenário 1).

### Tests para User Story 1

- [x] T011 [P] [US1] Teste: `RideRequestReceived.fromNostrEvent` decodifica um `content` válido e
  lança `FormatException` para um malformado, em `test/domain/ride_request_received_test.dart`
- [x] T012 [P] [US1] Teste: `RideQuote` guarda `requestId`/`pricePerKm`/`total` corretamente, em
  `test/domain/ride_quote_test.dart`
- [x] T013 [US1] Teste: `MapScreen` abre a modal quando uma solicitação chega com o motorista
  online e posição disponível, em `test/screens/map_screen_test.dart`
- [x] T014 [US1] Teste: `MapScreen` **não** abre modal quando uma solicitação chega com o motorista
  offline, em `test/screens/map_screen_test.dart`
- [x] T015 [P] [US1] Teste: a modal exibe origem, destino, as duas distâncias (a partir de
  `RouteDistanceService`) e o total, com o preço pré-preenchido do cadastro, em
  `test/screens/ride_request_modal_test.dart`
- [x] T016 [US1] Teste: editar o preço por quilômetro na modal recalcula o total imediatamente, sem
  nova chamada a `RouteDistanceService`, em `test/screens/ride_request_modal_test.dart`
- [x] T017 [US1] Teste: falha em uma das chamadas de distância mantém a modal utilizável, indicando
  a distância como não calculada, sem exceção não tratada, em
  `test/screens/ride_request_modal_test.dart`
- [x] T017b [P] [US1] Teste: editar o preço por quilômetro na modal não chama `CadastroStore.save`
  nem altera o `DriverProfile` de origem (FR-007), em `test/screens/ride_request_modal_test.dart`

### Implementação para User Story 1

- [x] T018 [US1] Cria `RideRequestModal` (recebe a `RideRequestReceived`, a posição atual do
  motorista, o preço padrão do cadastro e o `RouteDistanceService`; calcula as duas distâncias ao
  montar; exibe origem, destino, distâncias, campo de preço e total; botões "Enviar orçamento" e
  "Recusar corrida" — este apenas chama o callback de fechar por ora) em
  `lib/screens/ride_request_modal.dart` (depende de T003, T005, T006, T007)
- [x] T019 [US1] Adiciona a `MapScreen` (via `showDialog`) a fila de solicitações recebidas
  (`_filaSolicitacoes`/`_solicitacaoAtual` — D3 de `research.md`), populada a partir de
  `eventFeed.changes` filtrando `kind: NostrEvent.kindRideRequest` e só quando `_status == online`;
  abre `RideRequestModal` para `_solicitacaoAtual` em `lib/screens/map_screen.dart` (depende de
  T003, T010, T018)
- [x] T020 [US1] Passa `eventFeed`, `cadastroStore` (para o preço padrão) e um
  `RouteDistanceService` real para `MapScreen` em `lib/main.dart` (depende de T006, T019)

**Checkpoint**: US1 completa e testável de forma independente — modal exibida com os dados
calculados; "Enviar orçamento" e "Recusar corrida" ainda só fecham a modal sem publicar nada.

---

## Phase 4: User Story 2 — Enviar orçamento (Priority: P1)

**Goal**: tocar em "Enviar orçamento" publica o evento `kind: 20002`, referenciando a solicitação
original, com o preço e o total usados; falhas de validação ou de conexão são explicadas sem
fechar a modal sozinha.

**Independent Test**: com a modal aberta e um preço válido, tocar em "Enviar orçamento" e verificar
que o evento é publicado com as tags e o `content` corretos (quickstart.md, cenário 3).

### Tests para User Story 2

- [x] T021 [P] [US2] Teste: tocar em "Enviar orçamento" com preço válido e relay conectado publica
  o evento e fecha a modal, em `test/screens/ride_request_modal_test.dart`
- [x] T022 [US2] Teste: preço vazio, zero, negativo ou mal formatado impede o toque em "Enviar
  orçamento" (validação `DriverProfile.parsePrecoPorKm`), indicando o motivo, em
  `test/screens/ride_request_modal_test.dart`
- [x] T023 [US2] Teste: sem relay conectado, tocar em "Enviar orçamento" informa que não foi
  enviado, sem fechar a modal nem perder o preço editado, em
  `test/screens/ride_request_modal_test.dart`

### Implementação para User Story 2

- [x] T024 [US2] Implementa o envio de "Enviar orçamento" em `RideRequestModal`: valida o preço
  (`DriverProfile.parsePrecoPorKm`), monta `RideQuote`, chama o callback de publicação injetado
  (que usa `IdentityService.signRideQuote` + `RelayService.publish`), fecha a modal só se ao menos
  um relay aceitar, em `lib/screens/ride_request_modal.dart` (depende de T004, T008, T018)
- [x] T025 [US2] Conecta o callback de publicação de `RideRequestModal` a `identity`/`relayService`
  reais em `lib/screens/map_screen.dart`/`lib/main.dart` (depende de T024)

**Checkpoint**: US1 + US2 completas — orçamento efetivamente enviado e publicado.

---

## Phase 5: User Story 3 — Recusar corrida (Priority: P2)

**Goal**: tocar em "Recusar corrida" fecha a modal sem publicar nada, e libera a próxima
solicitação da fila.

**Independent Test**: com a modal aberta, tocar em "Recusar corrida" e verificar que ela fecha sem
publicar evento (quickstart.md, cenário 4).

### Tests para User Story 3

- [x] T026 [P] [US3] Teste: tocar em "Recusar corrida" fecha a modal e não publica nenhum evento,
  em `test/screens/ride_request_modal_test.dart`
- [x] T027 [US3] Teste: com duas solicitações recebidas em sequência antes de qualquer resposta,
  recusar (ou enviar orçamento para) a primeira abre a modal da segunda imediatamente depois — nunca
  duas simultâneas, em `test/screens/map_screen_test.dart`

### Implementação para User Story 3

- [x] T028 [US3] Confirma, a partir de T026/T027, que "Recusar corrida" (já esboçado em T018) e a
  promoção do próximo item da fila em `MapScreen` (T019) cobrem os dois testes; ajustar se
  encontrarem lacuna (depende de T018, T019, T026, T027)

**Checkpoint**: US1 + US2 + US3 completas — feature 007 do motorista pronta ponta a ponta.

---

## Phase 6: Polish

- [x] T029 [P] Roda `flutter analyze` e corrige qualquer apontamento
- [ ] T030 Executa os seis cenários do `quickstart.md` em dois aparelhos/emuladores (motorista e
  passageiro, relay em comum) com chave de API válida via `--dart-define=ORS_API_KEY=...`, e
  relata resultado no próprio `quickstart.md`
- [x] T031 Confere que nenhum dado além das coordenadas de origem/destino/motorista é enviado ao
  serviço de roteamento (verificação da exceção da constituição 2.4.0), e que o evento `kind:
  20002` publicado só contém `pricePerKm`/`total` no `content` e as duas tags esperadas (emenda 05
  do contrato)

---

## Dependencies

- **Phase 1 → Phase 2**: T001 já concluída; Phase 2 pode começar imediatamente.
- **Phase 2 → todas as user stories**: T002–T010 bloqueiam T011 em diante.
- **US1 → US2**: US2 depende da modal e da fila que US1 cria (T018, T019); "Enviar orçamento" só
  ganha comportamento real depois.
- **US1 → US3**: US3 depende da mesma modal e fila de US1; "Recusar corrida" e a promoção da fila
  já existem em esboço desde T018/T019, confirmados em T028.
- **US2 e US3 entre si**: independentes uma da outra — podem ser feitas em qualquer ordem depois
  de US1.

## Parallel Execution Examples

- Dentro da Phase 2: T002, T003, T004, T005, T007 tocam arquivos diferentes e podem ser feitas em
  paralelo; T006 depende de T005, T008 depende de T002/T004, T010 depende de T002.
- Dentro da Phase 3: T011, T012, T015 tocam arquivos diferentes ([P]); T013, T014, T016, T017
  tocam arquivos já usados por outra tarefa da mesma fase e por isso não são [P] entre si.
- T029 (Phase 6) pode rodar em paralelo com T030/T031, que dependem de dois aparelhos/emuladores.

## Implementation Strategy

**MVP** = Phase 1 + Phase 2 + Phase 3 (User Story 1): modal exibida com os dados calculados,
"Enviar orçamento" e "Recusar corrida" apenas fecham a modal sem publicar. Entrega o valor de ver a
solicitação com informação suficiente para decidir, demonstrável isoladamente.

**Incremento seguinte** = Phase 4 (US2): orçamento efetivamente publicado — o valor de negócio
completo da feature.

**Fechamento** = Phase 5 (US3) + Phase 6: recusa formalizada, fila confirmada com duas
solicitações, e validação em aparelho real com a app do passageiro do outro lado.
