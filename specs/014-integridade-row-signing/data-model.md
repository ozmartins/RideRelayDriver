# Phase 1 — Data Model: Integridade das avaliações (Row Signing)

## `RideRating` (domínio) — sem alteração

A entidade de domínio (`lib/domain/ride_rating.dart`, feature 013) não ganha campos novos. Os
campos de integridade (`signature`, `tampered`) são detalhe de persistência de
`SqfliteRideRatingStore`, não do domínio — `forRide` já expressa "violado" devolvendo `null`, o
mesmo tipo de retorno já usado para "não encontrado" (D4 de `research.md`, Princípio V).

## Esquema (`ride_ratings`, migração v1 → v2)

```sql
-- v1 (feature 013)
CREATE TABLE ride_ratings (
  ride_id   TEXT PRIMARY KEY,
  stars     INTEGER NOT NULL CHECK (stars BETWEEN 1 AND 5),
  rated_at  TEXT NOT NULL
);

-- v2 (esta feature)
ALTER TABLE ride_ratings ADD COLUMN signature TEXT;
ALTER TABLE ride_ratings ADD COLUMN tampered  INTEGER NOT NULL DEFAULT 0;
```

- `signature`: hexadecimal da assinatura Schnorr sobre o payload canônico (D1/D2 de
  `research.md`). `NULL` para linhas gravadas antes desta feature (v1) — tratado como ausência de
  assinatura, mesma regra de FR-007.
- `tampered`: `0`/`1`. Começa em `0` para linhas novas e `0` por `DEFAULT` para linhas antigas
  migradas — a violação só é constatada e persistida na primeira leitura (FR-004), não calculada
  retroativamente na migração.

## `RideRatingSignature` (funções puras, `lib/services/ride_rating_signature.dart`)

```dart
String canonicalPayload(RideRating rating);          // D2 de research.md
String sign(RideRating rating, Identity identity);    // D1 de research.md
bool verify(RideRating rating, String? signature, Identity identity);
```

`verify` devolve `false` para `signature == null` (mesmo caminho de uma assinatura adulterada —
FR-007 não é um caso à parte no código, só na origem do dado).

## `RideRatingStore` (contrato ampliado)

```dart
abstract class RideRatingStore {
  /// Assina [rating] com [identity] e persiste, incluindo a assinatura
  /// (FR-002).
  Future<void> save(RideRating rating, Identity identity);

  /// A avaliação para [rideId], validada contra [identity] — `null` se não
  /// existe, se a assinatura não confere (marca a violação, FR-004/FR-006),
  /// ou se já estava marcada como violada (FR-005).
  Future<RideRating?> forRide(String rideId, Identity identity);
}
```

Mudança em relação à feature 013: as duas operações passam a receber `Identity`. No ponto de
chamada (`MapScreen._mostrarModalAvaliacao`), isso exige checar `widget.identity != null`
primeiro — `Identity?` no motorista, diferente do passageiro (D3 de `research.md`).
