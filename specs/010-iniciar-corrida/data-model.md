# Data Model: Iniciar corrida após aceitação e deslocamento até o passageiro

## DriverRideStatus (domínio, `lib/domain/driver_ride_status.dart`)

Enum, por analogia a `AvailabilityStatus`, mas — ao contrário dele — **persistido** (FR-003):

| Valor | Significado |
|---|---|
| `aguardandoSolicitacao` | Default. Motorista pode ver e responder solicitações de corrida (`kind: 20001`), e reage normalmente a uma aceitação de orçamento (FR-001). |
| `deslocandoAtePassageiro` | Assumido só após o motorista tocar "Iniciar corrida" (FR-002). Bloqueia modais de novas solicitações (FR-004, FR-005) e ativa a publicação de localização (FR-007). |

Regra de transição (função pura, testável sem I/O, por analogia a `AvailabilityRules`):

- `aguardandoSolicitacao → deslocandoAtePassageiro`: só por ação explícita do motorista (toque em
  "Iniciar corrida"); nunca automática (FR-002).
- Não há transição de volta nesta feature (fora de escopo, ver Assumptions do `spec.md`).

## ActiveRide (domínio, `lib/domain/active_ride.dart`)

Valor imutável associado ao estado `deslocandoAtePassageiro` — não existe (é `null`) quando o
status é `aguardandoSolicitacao`.

| Campo | Tipo | Observação |
|---|---|---|
| `quoteId` | `String` | `id` do evento `kind: 20002` (orçamento) que foi aceito — mesma referência que os novos eventos (`kind: 20005`/`20006`) usam na tag `["e", ...]` (D2 de `research.md`). |
| `passengerPubkey` | `String` | Chave pública do passageiro que aceitou, lida do campo `pubkey` (autor) do evento de aceitação (`kind: 20003`) — destinatário de toda publicação desta feature (localização, recusa por corrida em andamento). |

## RideStateStore (serviço, `lib/services/ride_state_store.dart`)

Abstração de persistência, por analogia a `CadastroStore`/`RelayRepository`:

```dart
abstract class RideStateStore {
  /// (aguardandoSolicitacao, null) se nenhum estado foi salvo ainda.
  Future<(DriverRideStatus, ActiveRide?)> load();

  /// Grava o par status + corrida ativa (ActiveRide nulo quando o status
  /// volta/permanece aguardandoSolicitacao).
  Future<void> save(DriverRideStatus status, ActiveRide? active);
}
```

Implementação real sobre `KeyValueStore` (JSON serializado, decisão D1 de `research.md`); dublê em
memória para os testes, mesmo padrão de `CadastroStore`/`KeyStore`.

## SentQuotesStore (serviço, `lib/services/sent_quotes_store.dart`)

Persiste o conjunto de `id`s de orçamento (`kind: 20002`) que o próprio motorista publicou com
sucesso — necessário para FR-011 (ignorar aceitação que não corresponde a nenhum orçamento
efetivamente enviado) sobreviver a um reinício do app entre o envio do orçamento e a chegada da
aceitação, o mesmo tipo de janela que já motiva a persistência de `RideStateStore` (FR-003/FR-009).
Um conjunto só em memória seria insuficiente: se o app reiniciasse nesse intervalo, uma aceitação
**legítima** seria descartada como se fosse desconhecida.

```dart
abstract class SentQuotesStore {
  /// Registra que o orçamento com este `id` foi publicado com sucesso (ao
  /// menos um relay aceitou).
  Future<void> add(String quoteId);

  /// Verdadeiro se este `id` já foi registrado por [add].
  Future<bool> contains(String quoteId);
}
```

Implementação real sobre `KeyValueStore` (lista de `id`s serializada em JSON, mesmo mecanismo de
`RideStateStore`); dublê em memória para os testes. Escopo deliberadamente simples (Princípio V):
nenhuma poda ou expiração de entradas antigas — o protótipo não roda por tempo suficiente, entre
sessões de avaliação, para que o crescimento da lista seja um problema real.

## QuoteAccepted (domínio, `lib/domain/quote_accepted.dart`)

Representa a leitura do `kind: 20003` recebido, por analogia a `RideRequestReceived`:

| Campo | Tipo | Origem |
|---|---|---|
| `eventId` | `String` | `id` do próprio evento de aceitação — usado para deduplicação (FR-012). |
| `quoteId` | `String` | Da tag `["e", "<id-do-orçamento>"]`. |
| `passengerPubkey` | `String` | Campo `pubkey` (autor) do evento. |

Construtor `QuoteAccepted.fromNostrEvent(NostrEvent)` lança `FormatException` se a tag `e` estiver
ausente — tratado pelo chamador como conteúdo malformado, descartado sem modal nem erro (regra 3 de
recepção do contrato, mesmo padrão de `RideRequestReceived.fromNostrEvent`).

**FR-011**: mesmo com a tag `e` presente e bem formada, o chamador (`MapScreen`) MUST consultar
`SentQuotesStore.contains(quoteId)` antes de agir sobre a aceitação — um `quoteId` bem formado mas
nunca enviado por este motorista (ou de uma instalação anterior, dado que `SentQuotesStore` não é
limpo entre sessões) é descartado do mesmo jeito, sem modal nem notificação.

## Novos kinds no contrato único do protótipo (ver `contracts/README.md`)

| Kind | Nome | Direção | Tags | Content |
|---|---|---|---|---|
| `20005` | Localização do motorista | motorista → passageiro | marcador, `["e", quoteId]`, `["p", passengerPubkey]` | `{"lat": number, "lon": number}` |
| `20006` | Corrida não pode mais ser atendida | motorista → passageiro | marcador, `["e", quoteId]`, `["p", passengerPubkey]` | `""` (vazio — mesma convenção dos kinds 20003/20004: toda informação necessária já está nas tags) |

## Fluxo de estado (visão geral)

```text
[aguardandoSolicitacao] --(kind 20003 chega)--> modal "Iniciar corrida"
        |                                              |
        | (nenhuma ação / fecha app sem tocar)         | (toque em "Iniciar corrida")
        v                                              v
[aguardandoSolicitacao]                    [deslocandoAtePassageiro] --(persistido)
                                                        |
                                    +-------------------+-------------------+
                                    |                                       |
                        posição avança >= 50m                  chega outro kind 20003
                                    |                                       |
                                    v                                       v
                        publica kind 20005                     publica kind 20006
                        (ao passenger da ActiveRide)            (ao autor da 2ª aceitação,
                                                                  sem modal, sem mudar estado)
```
