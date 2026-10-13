# Data Model — Rota da corrida no mapa

Nada é persistido. Tudo abaixo vive em memória, na sessão.

## RouteTrace (novo, `lib/domain/route_trace.dart`)

| Campo | Tipo | Descrição |
|---|---|---|
| `points` | `List<LatLng>` | pontos do trajeto, da origem ao alvo; alimenta a polilinha |
| `distanceMeters` | `double` | distância rodoviária total |
| `originUsed` | `LatLng` | posição do motorista no cálculo — base do limiar de 50 m |
| `target` | `LatLng` | alvo usado — permite descartar resposta tardia de outro trecho |

Sem tipos de `open_route_service` (Princípio III).

## RideLeg (novo, `lib/domain/ride_leg.dart`)

Trecho vigente, função pura de `(DriverRideStatus, ActiveRide?)`:

| Status | Trecho | Alvo |
|---|---|---|
| `deslocandoAtePassageiro` | `pickup` | `(originLat, originLon)` |
| `emCorrida` | `dropoff` | `(destinationLat, destinationLon)` |
| `aguardandoSolicitacao`, `ActiveRide` nula, ou alvo `(0, 0)` (corrida anterior às features 011/012) | nenhum (`null`) | — |

Regra auxiliar `shouldRefresh({RouteTrace? last, LatLng? lastAttemptOrigin, RideLeg leg, LatLng current, double thresholdMeters = 50})`:
`true` se não há tentativa anterior, se o alvo da última tentativa ≠ alvo do trecho, ou se
`metersBetween(lastAttemptOrigin, current) ≥ threshold`.

## Estado novo em `_MapScreenState` (não persistido)

- `RouteTrace? _rota` — trajeto exibido; `null` limpa polilinha e marcador do alvo some junto
  com o trecho.
- `LatLng? _origemUltimaTentativa`, `RideLeg? _trechoDaUltimaTentativa` — base do recálculo (D3),
  inclusive após falha.
- `bool _rotaEmCalculo` — uma requisição em voo por vez.
- `bool _rotaIndisponivel` — liga a faixa de aviso.
- `bool _seguindoMotorista` (padrão `true`) — se o mapa recentraliza a cada posição; `false` desde o
  primeiro trajeto de um trecho até o botão "Centralizar" ser tocado ou o trajeto acabar (D5).

## Entidades existentes, inalteradas

`ActiveRide`, `DriverRideStatus`, `RideStateStore`, `SentQuotesStore`, `DriverPosition`.
