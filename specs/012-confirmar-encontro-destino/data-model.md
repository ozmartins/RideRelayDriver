# Data Model: Confirmar encontro e notificar chegada ao destino

## DriverRideStatus (domínio, `lib/domain/driver_ride_status.dart`) — alterado

Novo valor:

| Valor | Significado |
|---|---|
| `emCorrida` | Assumido depois que o passageiro confirma o encontro (FR-001). Bloqueia novas solicitações (mesma regra de `deslocandoAtePassageiro`, FR-004 da feature 010) e ativa a checagem de proximidade do destino (FR-003). |

Novas regras (`DriverRideRules`):

- `canConfirmMeeting(DriverRideStatus current) => current == deslocandoAtePassageiro`
- `canConfirmDestinationArrival(DriverRideStatus current) => current == emCorrida`

## ActiveRide (domínio, `lib/domain/active_ride.dart`) — alterado

Dois campos novos:

| Campo | Tipo | Observação |
|---|---|---|
| `destinationLat`, `destinationLon` | `double` | Coordenada de destino da solicitação respondida pelo orçamento aceito (D1/D2 de `research.md`) — mesmo par usado para a checagem do raio de 5 m. |
| `destinationArrivalNotified` | `bool` | Falso ao criar a `ActiveRide`; `true` depois que a chegada ao destino é publicada — controla FR-005, inclusive através de reinício (D2). |

## SentQuotesStore (serviço, `lib/services/sent_quotes_store.dart`) — alterado

Passa a guardar também o destino, junto da origem já existente:

```dart
abstract class SentQuotesStore {
  Future<void> add(
    String quoteId, {
    required double originLat,
    required double originLon,
    required double destinationLat,
    required double destinationLon,
  });
  Future<bool> contains(String quoteId);
  Future<(double lat, double lon)?> originFor(String quoteId);
  Future<(double lat, double lon)?> destinationFor(String quoteId);
}
```

`MapScreen._enviarOrcamento` passa a chamar `add` também com
`solicitacao.destination.latitude`/`longitude`.

## Fluxo (visão geral)

```text
[Deslocando-se até o passageiro] --(confirmação de encontro, kind 20008)--> [Em corrida]
                                                                                    |
                                                          [a cada posição em Em corrida]
                                                                                    |
                                                      metersBetween(posição, destino) <= 5m?
                                                                                    |
                                                    destinationArrivalNotified == false?
                                                                                    |
                                                              publica kind 20009
                                                              destinationArrivalNotified = true
                                                                                    |
                                                (confirmação de destino, kind 20010)
                                                                                    |
                                                                                    v
                                                          [Aguardando solicitação de corrida]
                                                          (ActiveRide encerrada, active: null)
```

## Novos kinds no contrato único do protótipo (ver `contracts/README.md`)

| Kind | Nome | Direção | Tags | Content |
|---|---|---|---|---|
| `20008` | Encontro confirmado | passageiro → motorista | marcador, `["e", quoteId]`, `["p", pubkey-motorista]` | `""` |
| `20009` | Chegada ao destino | motorista → passageiro | marcador, `["e", quoteId]`, `["p", pubkey-passageiro]` | `""` |
| `20010` | Destino confirmado | passageiro → motorista | marcador, `["e", quoteId]`, `["p", pubkey-motorista]` | `""` |
