# Phase 1 — Data Model: Avaliar corrida (motorista)

## RideRating

Representa a avaliação de uma corrida feita pelo motorista (entidade nova, domínio puro — sem
dependência de Flutter/`sqflite`). Conceitualmente idêntica à `RideRating` do passageiro
(`passenger/specs/011-avaliar-corrida/data-model.md`), mas é um tipo próprio deste app — sem
relação de código entre os dois (não são espelho, ver `../../CLAUDE.md`).

| Campo     | Tipo       | Regras |
|-----------|------------|--------|
| `rideId`  | `String`   | Obrigatório. É o `ActiveRide.quoteId` da corrida avaliada — mesma referência já usada para correlacionar toda a corrida desde a feature 010. |
| `stars`   | `int`      | Obrigatório. Inteiro de 1 a 5 (FR-003); construtor recusa qualquer outro valor. |
| `ratedAt` | `DateTime` | Obrigatório. Momento em que a avaliação foi confirmada. |

**Identidade**: `rideId` — no máximo uma `RideRating` por corrida (FR-006).

**Ciclo de vida**: criada e persistida de uma vez, ao confirmar a nota na tela de avaliação; nunca
atualizada nem removida por esta feature (uso posterior fora de escopo, FR-007).

**Sem relação com nenhum evento Nostr**: `RideRating` nunca é serializada para publicação — existe
só na camada de domínio e no `RideRatingStore` (FR-005).

## Persistência (`RideRatingStore` / `SqfliteRideRatingStore`)

Ver D1/D2 de `research.md` para a decisão e o esquema (`ride_ratings.db`, tabela `ride_ratings`,
`ride_id` como chave primária). Interface mínima, mesma forma da equivalente do passageiro:

```dart
abstract class RideRatingStore {
  /// Persiste [rating]. Chamado uma vez por avaliação confirmada (FR-004).
  Future<void> save(RideRating rating);

  /// A avaliação já registrada para [rideId], ou null se a corrida ainda não
  /// foi avaliada.
  Future<RideRating?> forRide(String rideId);
}
```

`forRide` não é necessário para o fluxo principal desta feature (a tela só abre uma vez por
corrida, D3 de `research.md`), mas é a operação mínima que torna `RideRatingStore` testável e
consistente com a regra "no máximo uma avaliação por corrida" (FR-006) sem expor detalhes de
`sqflite` fora de `lib/services/`.

## Sem alteração a entidades existentes

`ActiveRide`/`RideStateStore` não ganham nenhum campo novo (D3 de `research.md`) — a correlação
usa o `quoteId` já existente, lido antes de a corrida ativa ser zerada.
