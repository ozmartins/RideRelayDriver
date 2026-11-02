# Implementation Plan: Receber solicitação de corrida e enviar orçamento

**Branch**: `007-receber-solicitacao-corrida` | **Date**: 2026-09-20 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/007-receber-solicitacao-corrida/spec.md`

**Note**: This template is filled in by the `/speckit-plan` command. See `.specify/templates/plan-template.md` for the execution workflow.

## Summary

O motorista passa a se inscrever no `kind: 20001` (Solicitação de corrida) além do `kind: 1`. Ao
chegar uma solicitação válida com o motorista online, uma modal é aberta com origem, destino, as
duas distâncias reais (motorista→origem, origem→destino, via `open_route_service`) e o total
(distância × preço por quilômetro, pré-preenchido do cadastro e editável só para esta corrida).
"Enviar orçamento" publica um novo evento (`kind: 20002`, definido na emenda 05 do contrato,
replicada no passageiro na mesma alteração); "Recusar corrida" só fecha a modal. Solicitações que
chegam com uma modal já aberta esperam em fila e são exibidas em sequência.

## Technical Context

**Language/Version**: Dart 3.x / Flutter (mesmo SDK do restante do `driver/`)

**Primary Dependencies**: `open_route_service ^1.2.9` (reinstalada nesta sessão — Princípio III, ver
`research.md` D1); `latlong2` (já usado pela feature 004, reuso de `LatLng` para as coordenadas);
`dart_nostr` (já usado pelo projeto, via `IdentityService`, para assinar o novo kind)

**Storage**: N/A — solicitação recebida, distâncias calculadas e orçamento existem só em memória
durante a sessão da modal; nada é persistido

**Testing**: `flutter_test`, dublês para `RouteDistanceService` (novo, análogo a
`GeocodingService`/`LocationService`) e para o transporte de relay (já existente) — nenhum teste
toca rede real (Princípio II aplicado por analogia)

**Target Platform**: Android (único suportado pelo projeto)

**Project Type**: mobile-app (Flutter), único projeto

**Performance Goals**: modal exibida em até 1 s após a solicitação chegar (SC-001); no máximo duas
chamadas ao serviço de rota por solicitação (motorista→origem, origem→destino) — sem recálculo
contínuo, ao contrário do throttle por deslocamento da feature 007 do passageiro, porque a modal
não acompanha a posição em tempo real

**Constraints**: uma solicitação só abre modal se o motorista estiver online no momento em que ela
chega (FR-001, FR-002); nunca mais de uma modal simultânea (FR-015); falha no cálculo de distância
MUST NOT impedir "Enviar orçamento" (FR-016); o preço editado na modal MUST NOT persistir no
cadastro (FR-007)

**Scale/Scope**: uma modal por solicitação, processadas em fila estritamente sequencial; sem
suporte a cancelamento de solicitação pelo passageiro nesta feature

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Avaliação contra `.specify/memory/constitution.md` v2.4.0:

| Princípio / Restrição | Avaliação |
|---|---|
| I. Segredo criptográfico não vaza | N/A direto — a chave privada assina o evento de orçamento como já assina o de teste; nenhum caminho novo de exposição é introduzido. |
| II. Assinatura e verificação nascem com teste | **Aplica-se.** `IdentityService.signRideQuote` (novo) e a recepção do `kind: 20001` (que passa a entrar no `acceptedKinds` do `EventFeed`) MUST ter teste cobrindo caso válido e inválido — a verificação de assinatura na recepção já é código existente e testado (feature 002); o teste novo cobre o parsing do conteúdo. **PASS**, cumprido em tasks.md. |
| III. Dependência de terceiros exige decisão registrada | **Aplica-se.** `open_route_service` volta ao `pubspec.yaml` do motorista. Decisão registrada em `research.md` D1, referenciando a decisão já tomada e testada na feature 007 do passageiro. **PASS.** |
| IV. O contrato de evento vem antes do código | **Aplica-se — é o cerne desta feature.** Novo `kind: 20002` (Orçamento de corrida) especificado na emenda 05 de `specs/002-nostr-relay-connection/contracts/nostr-events.md` **antes** de qualquer código desta feature, e replicado de forma idêntica em `Prototipo/passenger/specs/002-nostr-relay-connection/contracts/nostr-events.md` na mesma alteração (corpo conferido por diff). **PASS.** |
| V. Simplicidade proporcional e rastreabilidade acadêmica | **Aplica-se.** A fila de solicitações (FR-015) e a abstração `RouteDistanceService` (mais leve que o `RouteService` do passageiro — sem `points`/`Polyline`, que esta modal não usa) são decisões registradas em `research.md` D2/D3, com alternativas descartadas. **PASS.** |
| Restrições de Segurança e Privacidade — exceção de roteamento (emenda 2.4.0) | **Aplica-se e motivou a emenda 2.4.0.** A chamada motorista→origem usa a posição atual do motorista (coberta já pela 2.3.0); a chamada origem→destino usa duas coordenadas de terceiro (a solicitação recebida), coberta pela generalização da 2.4.0. Nenhuma chamada inclui `pubkey`, nome ou apelido de exibição — só coordenadas. **PASS**, condicionado à emenda 2.4.0 já commitada separadamente do código desta feature. |

**Resultado**: PASS. Nenhuma entrada em Complexity Tracking é necessária.

## Project Structure

### Documentation (this feature)

```text
specs/007-receber-solicitacao-corrida/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md         # Phase 1 output (/speckit-plan command)
├── contracts/            # Phase 1 output — aponta para a emenda 05 do contrato existente
├── quickstart.md        # Phase 1 output (/speckit-plan command)
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

### Source Code (repository root)

```text
lib/
├── domain/
│   ├── nostr_event.dart              # alterado — ganha kindRideRequest (20001) e kindRideQuote (20002)
│   ├── ride_request_received.dart    # novo — Entidade "Solicitação recebida" (data-model.md)
│   └── ride_quote.dart               # novo — Entidade "Orçamento" (data-model.md)
├── services/
│   ├── route_distance_service.dart   # novo — abstração RouteDistanceService + OrsRouteDistanceService
│   └── identity_service.dart         # alterado — ganha signRideQuote (kind 20002, tag "e")
├── screens/
│   ├── ride_request_modal.dart       # novo — a modal em si
│   └── map_screen.dart               # alterado — recebe eventFeed/relayService/cadastroStore/routeDistanceService/identity; fila de solicitações; abre a modal
└── main.dart                          # alterado — acceptedKinds do EventFeed ganha 20001; injeta as novas dependências em MapScreen

test/
├── domain/
│   ├── ride_request_received_test.dart  # novo
│   └── ride_quote_test.dart             # novo
├── services/
│   ├── route_distance_service_test.dart # novo
│   └── identity_service_test.dart       # alterado — cobre signRideQuote
└── screens/
    ├── ride_request_modal_test.dart     # novo
    └── map_screen_test.dart             # alterado — cobre fila, abertura condicionada ao status online
```

**Structure Decision**: segue o layout já existente (`domain/` + `services/` + `screens/`).
`RouteDistanceService` é uma abstração de projeto própria do motorista — não reaproveita a classe
`RouteService` do passageiro (apps não compartilham código), mas segue o mesmo padrão de
confinamento de `open_route_service` à camada de serviços (Princípio III). `ride_request_modal.dart`
é um arquivo de tela próprio, não um widget privado dentro de `map_screen.dart`, pela extensão do
formulário e da lógica assíncrona que carrega (mesmo critério que já separou `cadastro_screen.dart`
de `home_screen.dart`).

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

Nenhuma violação — seção não aplicável.
