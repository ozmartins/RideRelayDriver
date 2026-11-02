# Phase 1 — Data Model: Detalhes do motorista e tempo estimado no orçamento

## `RouteEstimate` (novo, `lib/services/route_distance_service.dart`)

| Campo | Tipo | Observação |
|---|---|---|
| `distanceMeters` | `double` | Mesmo valor que `distanceMeters()` devolvia antes desta feature. |
| `durationSeconds` | `double` | Novo — duração do trajeto, direto do `summary` da resposta do OpenRouteService. |

`RouteDistanceService.distanceMeters(...)` é substituído por `estimate(...)`, que devolve este
tipo. Todo chamador que só precisava da distância (feature 007, chamada origem→destino) passa a
ler `.distanceMeters` do `RouteEstimate`.

## `RideQuote` (existente, `lib/domain/ride_quote.dart`) — ganha os campos do motorista

| Campo novo | Tipo | Observação |
|---|---|---|
| `driverName` | `String` | Copiado de `DriverProfile.nome` no momento do envio. |
| `carBrand` | `String` | Copiado de `DriverProfile.marcaVeiculo`. |
| `carModel` | `String` | Copiado de `DriverProfile.modeloVeiculo`. |
| `carYear` | `int` | Copiado de `DriverProfile.anoVeiculo` (feature 008). |
| `etaMinutes` | `int?` | Derivado de `RouteEstimate.durationSeconds` da chamada motorista→origem (D1 de `research.md`); `null` quando essa chamada falhou (D2) — nunca serializado como `0`. |

## `IdentityService.signRideQuote` — parâmetros novos

Ganha `driverName`, `carBrand`, `carModel`, `carYear` (obrigatórios) e `etaMinutes` (`int?`,
opcional) — monta o `content` JSON da emenda 06, omitindo a chave `etaMinutes` quando `null`.
