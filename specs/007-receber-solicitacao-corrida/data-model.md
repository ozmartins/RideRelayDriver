# Phase 1 — Data Model: Receber solicitação de corrida e enviar orçamento

## `RideRequestReceived` (novo, `lib/domain/ride_request_received.dart`)

Representa uma solicitação de corrida recebida e já verificada (assinatura válida, marcador
presente, deduplicada — regras de recepção do contrato, já aplicadas pelo `EventFeed` antes de
qualquer código desta feature existir).

| Campo | Tipo | Observação |
|---|---|---|
| `requestId` | `String` | O `id` do evento `kind: 20001` original — usado na tag `["e", ...]` do orçamento (FR-017) e para dedupe de apresentação. |
| `origin` | `LatLng` (`latlong2`) | `content.origin` do evento, conforme a emenda 04 do contrato. |
| `destination` | `LatLng` | `content.destination` do evento. |
| `payment` | `String` | `content.payment` do evento (`"dinheiro"`, `"pix"` ou `"cartao"`) — exibido na modal como dado, nunca interpretado. |

**Criação**: `RideRequestReceived.fromNostrEvent(NostrEvent event)` — decodifica `event.content`
como JSON; um `content` malformado (campo ausente, tipo errado) faz a fábrica lançar
`FormatException`, e quem chama descarta o evento sem exibir modal (mesma postura de "conteúdo é
dado, nunca instrução" da regra 3 do contrato — um dado malformado não é processado, não trava o
app).

**Ciclo de vida**: existe só em memória, enquanto está na fila de `MapScreen` ou sendo exibida na
modal; nunca persistida.

## `RideQuote` (novo, `lib/domain/ride_quote.dart`)

Representa o orçamento que o motorista está prestes a enviar (ou já enviou) para uma
`RideRequestReceived`.

| Campo | Tipo | Observação |
|---|---|---|
| `requestId` | `String` | Copiado de `RideRequestReceived.requestId` — vira a tag `["e", ...]` do evento publicado (FR-017). |
| `pricePerKm` | `double` | Preço usado nesta corrida — pode diferir do cadastro (FR-006, FR-007); validado por `DriverProfile.parsePrecoPorKm` antes de existir uma instância válida. |
| `total` | `double` | `pricePerKm * distanceOriginToDestinationMeters / 1000` — calculado por quem monta o `RideQuote`, não por este tipo (mantém a entidade um `value object` simples). |

**Publicação**: `IdentityService.signRideQuote` (D4 de `research.md`) consome os três campos para
montar o `content` JSON e as tags do `kind: 20002`.

## Estado de fila e modal (em `MapScreen`, sem entidade de domínio própria — D3 de `research.md`)

- `List<RideRequestReceived> _filaSolicitacoes`: solicitações recebidas, aceitas pelo `EventFeed`,
  ainda não apresentadas em modal.
- `RideRequestReceived? _solicitacaoAtual`: a que está na modal agora, ou `null` se nenhuma.

Transições: uma nova `RideRequestReceived` só é adicionada à fila se `_status == online`
(FR-001/FR-002); se `_solicitacaoAtual == null` no momento em que ela chega, ela é imediatamente
promovida a `_solicitacaoAtual` (abre modal) em vez de esperar na fila. Ao fechar a modal (enviado
ou recusado), se a fila não estiver vazia, o primeiro item sai da fila e se torna a nova
`_solicitacaoAtual`.

## Relação com entidades existentes

- **`DriverProfile.precoPorKm`** (feature 006) é o valor inicial do campo de preço da modal — a
  modal nunca escreve de volta nele (FR-007).
- **`AvailabilityStatus`** (feature 004) decide se uma `RideRequestReceived` chega a entrar na fila.
- **`DriverPosition`** (feature 004) é a origem da chamada motorista→origem (FR-004); esta feature
  não a altera.
