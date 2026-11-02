# Phase 1 — Data Model: Preço padrão por quilômetro

## `DriverProfile` (existente, `lib/domain/driver_profile.dart`) — ganha `precoPorKm`

| Campo novo | Tipo | Observação |
|------------|------|------------|
| `precoPorKm` | `double` | Obrigatório no construtor; `isValido` passa a exigir `precoPorKm > 0` (FR-001, FR-002) |

Novo método estático `DriverProfile.parsePrecoPorKm(String raw)` (D1 de `research.md`):

- Normaliza `raw` trocando vírgula por ponto e removendo espaços das pontas.
- Retorna `null` se: vazio, não numérico, `<= 0`, ou com mais de duas casas decimais no texto
  original (antes da conversão) — a checagem de casas decimais é textual, não de ponto flutuante.
- Caso contrário, retorna o `double` correspondente.

`toMap()`/`fromMap()` ganham a chave `preco_por_km` (`double`, direto — sem serialização especial, ao
contrário de `payment_methods`). `copyWith` ganha o parâmetro `precoPorKm`. `==`/`hashCode` passam a
considerar o campo.

## Esquema SQLite — `driver_profile` (existente, `lib/services/sqflite_cadastro_store.dart`)

Versão do banco sobe de `2` para `3` (D2 de `research.md`):

```sql
-- onCreate (instalação nova, direto na versão 3)
CREATE TABLE driver_profile (
  id               INTEGER PRIMARY KEY CHECK (id = 1),
  nome             TEXT NOT NULL,
  uf               TEXT NOT NULL,
  cidade           TEXT NOT NULL,
  marca_veiculo    TEXT NOT NULL,
  modelo_veiculo   TEXT NOT NULL,
  cor_veiculo      TEXT NOT NULL,
  placa_veiculo    TEXT NOT NULL,
  payment_methods  TEXT NOT NULL DEFAULT '',
  preco_por_km     REAL NOT NULL DEFAULT 0
)

-- onUpgrade: cada versão aplica só a sua própria mudança (oldVersion < N),
-- para que uma instalação na versão 1 suba direto até a 3
-- oldVersion < 2 (já existente, feature 005):
ALTER TABLE driver_profile ADD COLUMN payment_methods TEXT NOT NULL DEFAULT ''
-- oldVersion < 3 (esta feature):
ALTER TABLE driver_profile ADD COLUMN preco_por_km REAL NOT NULL DEFAULT 0
```

Uma linha vinda da versão 1 ou 2 (sem a coluna antes do upgrade) recebe `0` pelo `DEFAULT`, que
`DriverProfile.isValido` já rejeita (FR-002: preço deve ser maior que zero) — tratado como cadastro
corrompido pela regra já existente (FR-010 da feature 003, FR-006 desta feature). Nenhum código de
migração de dado é necessário além do `ALTER TABLE`.
