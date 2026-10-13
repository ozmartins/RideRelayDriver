# Data Model — Chegada periódica à origem (motorista)

| Entidade | Mudança |
|---|---|
| `ActiveRide` | − `arrivalNotified` (campo, `copyWith`, `==`, `hashCode`, `toString`); `destinationArrivalNotified` permanece |
| `RideStateStore` (JSON persistido) | − chave `arrivalNotified`; JSON antigo com a chave continua legível (ignorada) |
| `MapScreen` (estado em memória) | + `DateTime? _ultimaChegadaEm` — instante de captura da última posição que gerou o aviso `20007` |

Sem migração e sem entidade nova. Transições de `DriverRideStatus` inalteradas.
