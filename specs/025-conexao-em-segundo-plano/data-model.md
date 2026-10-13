# Modelo de dados: 025-conexao-em-segundo-plano

Sem tabela SQLite nova. Entidades são mensagens do canal e valores em `KeyValueStore`.

## ServiceState (UI → serviço; persistido em `KeyValueStore`)
| Campo | Tipo | Regra |
|---|---|---|
| `online` | bool | espelha `AvailabilityStatus.online` |
| `acceptedPayments` | lista de `wireValue` (`dinheiro`/`pix`/`cartao`) | de `DriverProfile.paymentMethods` |
| `rideStatus` | `DriverRideStatus` (nome) | só `aguardandoSolicitacao` permite notificar |
| `appInForeground` | bool | só em memória (não persistido: ao reiniciar o serviço, assume `false`) |

## RideRequestFilter (domain, puro)
Entrada: `NostrEvent` (kind 20001), `ServiceState`. Saída: `aceita` ou `recusa(motivo)` com motivos
`offline`, `emCorrida`, `malformada`, `pagamentoNaoAceito`. Reutiliza `RideRequestReceived.fromNostrEvent` e
`DriverProfile.acceptsPayment`/`PaymentMethod.fromWire`. Mesma função na UI (`_processarSolicitacaoRecebida`) e
no serviço.

## PendingRequest (serviço, em memória)
`{ payload (Map), receivedAt }`; descartada com 5 min; reentregue no `hello`.

## ServiceMessage (ver contracts/service-channel.md)
Tipos: `ready`, `hello`, `helloAck`, `state`, `connectAll`, `addRelay`, `removeRelay`, `reconnectNow`, `publish`,
`publishResult`, `relaysChanged`, `incoming`, `stop`.
