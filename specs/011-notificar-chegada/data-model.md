# Data Model: Notificar chegada ao passageiro

## ActiveRide (domínio, `lib/domain/active_ride.dart`) — alterado

Três campos novos, todos persistidos por `RideStateStore` junto dos já existentes
(`quoteId`, `passengerPubkey`):

| Campo | Tipo | Observação |
|---|---|---|
| `originLat`, `originLon` | `double` | Coordenada de origem da solicitação respondida pelo orçamento aceito (D1 de `research.md`) — mesmo par usado para a checagem do raio de 10 m. Mesmo estilo de `DriverPosition` (dois `double`, sem tipo de terceiro no domínio). |
| `arrivalNotified` | `bool` | Falso ao criar a `ActiveRide` (em `_iniciarCorrida`); `true` depois que a mensagem de chegada é publicada — controla FR-003 (nunca mais de uma mensagem por corrida), inclusive através de um reinício do app (D2 de `research.md`). |

`ActiveRide` ganha um `copyWith` para permitir `arrivalNotified: true` sem reconstruir os demais
campos manualmente em `MapScreen`.

## SentQuotesStore (serviço, `lib/services/sent_quotes_store.dart`) — alterado

Deixa de guardar só um conjunto de `id`s; passa a guardar, por `id` de orçamento, também a origem
da solicitação respondida:

```dart
abstract class SentQuotesStore {
  Future<void> add(String quoteId, {required double originLat, required double originLon});
  Future<bool> contains(String quoteId);

  /// Origem registrada para este `id`, ou `null` se ele nunca foi
  /// registrado (mesmo caso de `contains` devolver falso).
  Future<(double lat, double lon)?> originFor(String quoteId);
}
```

`MapScreen._enviarOrcamento` passa a chamar `add` com a origem da `RideRequestReceived` que gerou
aquele orçamento (disponível ali, é a mesma solicitação da modal).

## Fluxo (visão geral)

```text
[enviar orçamento] --grava id + origem--> SentQuotesStore
                                                |
                          [aceitação chega, quoteId conhecido]
                                                |
                                                v
                          _iniciarCorrida lê originFor(quoteId)
                                                |
                                                v
                    ActiveRide(quoteId, passengerPubkey, originLat, originLon,
                               arrivalNotified: false)  --persistida--> RideStateStore
                                                |
                          [a cada posição em Deslocando-se]
                                                |
                          metersBetween(posição, origem) <= 10m?
                                                |                     \
                                              sim                      não
                                                |                       |
                             arrivalNotified == false?          nada acontece
                              /                  \
                            sim                  não
                             |                     \
                  publica kind 20007          nada acontece
                  arrivalNotified = true
                  (persistido)
```

## Novo kind no contrato único do protótipo (ver `contracts/README.md`)

| Kind | Nome | Direção | Tags | Content |
|---|---|---|---|---|
| `20007` | Chegada do motorista | motorista → passageiro | marcador, `["e", quoteId]`, `["p", passengerPubkey]` | `""` (vazio) |
