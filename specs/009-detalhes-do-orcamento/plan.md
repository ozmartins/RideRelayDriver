# Implementation Plan: Detalhes do motorista e tempo estimado no orçamento

**Branch**: `009-detalhes-do-orcamento` | **Date**: 2026-09-20 | **Spec**: [spec.md](./spec.md)

## Summary

`RouteDistanceService` passa a devolver distância **e** duração numa única chamada
(`RouteEstimate`). `RideQuote` e `IdentityService.signRideQuote` ganham
`driverName`/`carBrand`/`carModel`/`carYear` (sempre) e `etaMinutes` (opcional, da duração
motorista→origem). `MapScreen` passa o `DriverProfile` carregado para a modal montar o `RideQuote`
completo. Contrato (emenda 06) já escrito e replicado no passageiro.

## Constitution Check

Avaliação contra `.specify/memory/constitution.md` v2.4.0:

| Princípio | Avaliação |
|---|---|
| III. Dependência de terceiros | N/A — nenhuma dependência nova. |
| IV. Contrato antes do código | **Aplica-se.** Emenda 06 escrita e replicada antes desta implementação. **PASS.** |
| V. Simplicidade | **Aplica-se.** D1/D2 de `research.md` registram a decisão de reaproveitar a mesma chamada e de omitir o campo em vez de estimar. **PASS.** |

**Resultado**: PASS.

## Project Structure

```text
lib/
├── services/route_distance_service.dart   # alterado — RouteEstimate, estimate()
├── domain/ride_quote.dart                 # alterado — novos campos
├── services/identity_service.dart         # alterado — signRideQuote ganha parâmetros
└── screens/
    ├── ride_request_modal.dart            # alterado — usa estimate(), monta RideQuote completo
    └── map_screen.dart                    # alterado — passa DriverProfile à modal

test/
├── services/route_distance_service_test.dart
├── domain/ride_quote_test.dart
├── services/identity_service_test.dart
├── screens/ride_request_modal_test.dart
└── screens/map_screen_test.dart
```
