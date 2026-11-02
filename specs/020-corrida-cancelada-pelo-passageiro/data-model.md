# Data Model — Corrida cancelada pelo passageiro (motorista)

Nenhuma entidade nova e nenhuma persistência nova.

## Entidades existentes tocadas

| Entidade | Mudança |
|---|---|
| `DriverRideStatus` | nenhuma — a transição nova é `deslocandoAtePassageiro`/`emCorrida` → `aguardandoSolicitacao`, a mesma da conclusão e do cancelamento do motorista |
| `ActiveRide` | nenhuma — `passengerPubkey` e `quoteId` (já existentes) são os campos conferidos; é zerada ao encerrar |
| `NostrEvent` (domínio) | + constante `kindRideCancelledByPassenger = 20013`; `referencedEventId`, `recipientPublicKey` e `authorPublicKey` já existem |
| `DriverRideRules` | + `canBeCancelledByPassenger(status)` = `deslocandoAtePassageiro` ou `emCorrida` (as mesmas fases de `canCancelRide`) |

## Transição

```text
deslocandoAtePassageiro ──(20013 válido)──► aguardandoSolicitacao   (ActiveRide → null, persistido)
emCorrida              ──(20013 válido)──► aguardandoSolicitacao   (ActiveRide → null, persistido)
aguardandoSolicitacao  ──(20013)────────► ignorado
```

## Riscos registrados (fora de escopo)

- `20008`/`20010` são aceitos pela referência `["e", quoteId]` sem conferir o autor; o `20013` confere. Alinhar
  os dois é trabalho de outra feature.
- Aviso perdido (motorista sem relay): sem reentrega nem relógio de silêncio no motorista.
