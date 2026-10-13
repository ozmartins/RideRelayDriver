---

description: "Task list for 009-detalhes-do-orcamento"

---

# Tasks: Detalhes do motorista e tempo estimado no orçamento

**Contrato**: emenda 06 já escrita e replicada no passageiro (Princípio IV).

## Phase 1: Foundational

- [x] T001 [P] Cria `RouteEstimate` (`distanceMeters`, `durationSeconds`) e troca
  `RouteDistanceService.distanceMeters(...)` por `estimate(...)` devolvendo `RouteEstimate`, em
  `lib/services/route_distance_service.dart`; atualiza `OrsRouteDistanceService` para ler
  `summary.duration` da mesma resposta já usada para `summary.distance`
- [x] T002 [P] Atualiza `test/services/route_distance_service_test.dart` para `estimate()`,
  cobrindo `distanceMeters` e `durationSeconds` da mesma resposta (depende de T001)
- [x] T003 [P] Acrescenta `driverName`, `carBrand`, `carModel`, `carYear` (obrigatórios) e
  `etaMinutes` (`int?`) a `RideQuote`, em `lib/domain/ride_quote.dart`
- [x] T004 [P] Atualiza `test/domain/ride_quote_test.dart` para os novos campos (depende de T003)
- [x] T005 Acrescenta os mesmos parâmetros a `IdentityService.signRideQuote`, omitindo a chave
  `etaMinutes` do `content` quando `null` (D2 de `research.md`), em
  `lib/services/identity_service.dart` (depende de T003)
- [x] T006 Atualiza `test/services/identity_service_test.dart`: `content` traz os novos campos
  quando `etaMinutes` não é nulo, e omite a chave quando é (depende de T005)

## Phase 2: Integração na modal e no fluxo de envio

- [x] T007 Atualiza `RideRequestModal` para usar `routeDistanceService.estimate(...)` nas duas
  chamadas (motorista→origem guarda também a duração; origem→destino só usa a distância), montando
  o `RideQuote` completo (com dados do motorista recebidos via novo parâmetro) ao enviar, em
  `lib/screens/ride_request_modal.dart` (depende de T001, T003)
- [x] T008 Atualiza `MapScreen` para passar o `DriverProfile` carregado (`_carregarPrecoPadrao` já
  o lê — passa a guardar o perfil inteiro, não só o preço) para `RideRequestModal`, em
  `lib/screens/map_screen.dart` (depende de T007)
- [x] T009 Atualiza `test/screens/ride_request_modal_test.dart`/`FakeRouteDistanceService` para o
  novo método `estimate`, e cobre que o `RideQuote` enviado a `onSendQuote` traz os dados do
  motorista e `etaMinutes` (presente e omitido nos dois casos) (depende de T007)
- [x] T010 Atualiza `test/screens/map_screen_test.dart`/`FakeRouteDistanceService` para `estimate`
  e confere que o evento publicado (`kind: 20002`) traz os campos novos no `content` (depende de
  T008)

## Phase 3: Polish

- [x] T011 [P] `flutter analyze`
- [x] T012 `flutter test` completo
- [x] T013 Registra a feature no `CLAUDE.md` da raiz, em commit separado
