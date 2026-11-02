# Data Model — Cancelar corrida (motorista)

Nenhuma entidade persistida nova; nenhum campo novo em `ActiveRide`, nenhuma migração.

## `DriverRideRules.canCancelRide` (`lib/domain/driver_ride_status.dart`)

| Estado atual | `canCancelRide` |
|---|---|
| `aguardandoSolicitacao` | `false` |
| `deslocandoAtePassageiro` | `true` |
| `emCorrida` | `true` |

Função pura, no padrão de `canConfirmMeeting`. A transição resultante é sempre
`→ aguardandoSolicitacao` com `ActiveRide = null`.

## Transições de `DriverRideStatus` depois desta feature

```text
aguardandoSolicitacao ──iniciar──▶ deslocandoAtePassageiro ──20008──▶ emCorrida
        ▲                                  │                            │
        │◀────────── cancelar (018) ───────┘                            │
        │◀────────────────────── cancelar (018) ────────────────────────┤
        └◀──────────────────────── 20010 (conclusão) ───────────────────┘
```

Só a conclusão (`20010`) abre a modal de avaliação.

## Evento `kind: 20012` (ver `contracts/README.md`)

| Campo | Valor |
|-------|-------|
| `kind` | `20012` (`NostrEvent.kindRideCancelled`) |
| `tags` | `["t","tcc-ufsc-caronas"]`, `["e", quoteId]`, `["p", passengerPubkey]` |
| `content` | `""` |

## Entidades reaproveitadas

- `ActiveRide`: fornece `quoteId` e `passengerPubkey` (capturados antes de zerá-la); não muda.
- `RideStateStore`: `save(aguardandoSolicitacao, null)`; não muda.
