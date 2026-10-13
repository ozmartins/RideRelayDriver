# Data Model — Publicar ao passageiro a rota da corrida

Nenhuma entidade persistida nova; nenhum campo novo em `ActiveRide`.

## `RideRouteContent` (`lib/domain/ride_route_content.dart`, novo)

Função pura/classe utilitária, sem dependência de Flutter nem de `dart_nostr`.

| Membro | Descrição |
|--------|-----------|
| `maxPoints = 1000` | Limite de pontos por evento (D3) |
| `decimalPlaces = 5` | Casas decimais de lat/lon (D2) |
| `reduce(List<LatLng>) → List<LatLng>` | Se `length ≤ maxPoints`, devolve como está; senão devolve exatamente `maxPoints` pontos, nos índices `round(i · (n − 1) / (maxPoints − 1))` para `i = 0..maxPoints − 1`. O primeiro (`i = 0`) e o último (`i = maxPoints − 1`) são os originais por construção; ordem preservada; nunca passa de `maxPoints` |
| `encode(List<LatLng>) → String` | `jsonEncode({'points': [[lat, lon], ...]})` com lat/lon arredondados a `decimalPlaces`, depois de `reduce` |

**Validação**: `points.length ≥ 2` (menos que isso, `encode` lança `ArgumentError` — o chamador não
publica; um `RouteTrace` com <2 pontos é tratado como falha de rota).

## Evento `kind: 20011` (ver `contracts/README.md`)

| Campo | Valor |
|-------|-------|
| `kind` | `20011` (`NostrEvent.kindRideRoute`) |
| `tags` | `["t","tcc-ufsc-caronas"]`, `["e", quoteId]`, `["p", passengerPubkey]` |
| `content` | `RideRouteContent.encode(trace.points)` |

## Entidades reaproveitadas

- `RouteTrace` (feature 016): fonte de `points`; não muda.
- `ActiveRide`: fornece `quoteId` e `passengerPubkey`; não muda.
- `DriverRideStatus.emCorrida`: condição de publicação.

## Transições de estado

Nenhuma nova. A publicação é efeito colateral do cálculo bem-sucedido do trecho `dropoff`.
