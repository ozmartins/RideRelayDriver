# Implementation Plan: Rota da corrida no mapa do motorista

**Branch**: `master` (commits diretos, sem branch de feature — Padrão de Commits da constituição) | **Date**: 2026-09-30 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/016-rota-no-mapa/spec.md`

## Summary

Nos estados "Deslocando-se até o passageiro" e "Em corrida", o mapa do motorista passa a mostrar o
ponto-alvo do trecho vigente (origem da solicitação ou destino, ambos já em `ActiveRide`) e o
trajeto rodoviário da posição atual até ele. O trajeto vem do mesmo serviço de roteamento já usado
pelas features 007/009 (`RouteDistanceService`/ORS), que ganha um segundo método devolvendo a
geometria. Recalcula na mudança de trecho e a cada 50 m de deslocamento (mesmo limiar da feature 007
do passageiro); falha é absorvida com um aviso discreto. Estritamente local: nenhum evento Nostr,
nenhum dado persistido novo, nenhuma mudança no passageiro.

## Technical Context

**Language/Version**: Dart 3 / Flutter (versão já fixada no `pubspec.yaml`)

**Primary Dependencies**: `flutter_map` (`PolylineLayer`, `CameraFit`), `latlong2`,
`open_route_service` — todas já instaladas; **nenhuma dependência nova** (D1 de `research.md`).

**Storage**: N/A — a rota é derivada e só em memória; o que a restaura após reinício é o
`ActiveRide`/`RideStateStore` já existente.

**Testing**: `flutter_test`, com dublê de `RouteDistanceService` e `LocationService`; nenhum teste
toca rede (Princípio II). A decisão de trecho e de recálculo é lógica pura em `domain/`, testada
diretamente.

**Target Platform**: Android (sem mudança)

**Project Type**: mobile-app (Flutter, Android apenas)

**Performance Goals**: trajeto visível em até 5 s da abertura do mapa; troca de trecho refletida em
até 2 s (SC-001, SC-002).

**Constraints**: ≤ 1 consulta de rota por 50 m + 1 por mudança de trecho (SC-004, limite do nível
gratuito do ORS); chamada só com as duas coordenadas, HTTPS, resposta só em memória.

**Scale/Scope**: uma corrida ativa por vez; um trajeto por vez.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Princípio / restrição | Avaliação |
|---|---|
| I. Segredo criptográfico não vaza | N/A — nada de chave toca esta feature. |
| II. Assinatura/verificação com teste | N/A — nenhum código de assinatura; testes sem rede. |
| III. Dependência exige decisão registrada | Passa — nenhuma dependência nova; reuso de `open_route_service` registrado em D1 de `research.md`. |
| IV. Contrato antes do código | Passa — nenhum evento criado/alterado (FR-007); sem contrapartida no passageiro. |
| V. Simplicidade e medição | Passa — reaproveita serviço, limiar e dados existentes; nada persistido. |
| Restrições de Segurança e Privacidade | Passa sem emenda — a exceção de roteamento (2.3.0/2.4.0) cobre posição atual + ponto de uma solicitação recebida; HTTPS, só coordenadas, resposta só na sessão (D2). Nenhuma permissão nova. |
| Identidade Visual e Design | Passa — rota `roxo` 5 px (já definida), marcadores no círculo de 44 px já definido; ícone não é token (D5). Sem emenda. |

Pós-design (Phase 1): inalterado.

## Project Structure

### Documentation (this feature)

```text
specs/016-rota-no-mapa/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── checklists/requirements.md
└── tasks.md             # /speckit-tasks
```

`contracts/` não existe: não há interface externa nova (FR-007).

### Source Code

```text
lib/
├── domain/
│   ├── ride_leg.dart            # NOVO: trecho vigente (alvo + tipo) derivado de status + ActiveRide; regra de recálculo
│   └── route_trace.dart         # NOVO: trajeto (pontos, distância, origem usada, alvo)
├── services/
│   └── route_distance_service.dart   # + trace(); ORS e Fallback implementam
└── screens/
    └── map_screen.dart          # PolylineLayer, marcador do alvo, enquadramento, faixa de aviso, orquestração

test/
├── domain/ride_leg_test.dart            # NOVO
├── services/route_distance_service_test.dart   # + casos de trace()
└── screens/map_screen_test.dart         # + cenários de rota
```

**Structure Decision**: mesma divisão `domain/` + `services/` + `screens/` das demais features. O
tipo de terceiro (`open_route_service`) continua confinado a `route_distance_service.dart`;
`flutter_map` continua confinado a `map_screen.dart`.

## Complexity Tracking

Sem violações.
