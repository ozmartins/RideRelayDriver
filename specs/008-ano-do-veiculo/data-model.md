# Phase 1 — Data Model: Ano do veículo no cadastro

## `DriverProfile` (existente) — ganha `anoVeiculo`

| Campo novo | Tipo | Observação |
|------------|------|------------|
| `anoVeiculo` | `int` | Obrigatório no construtor; `isValido` passa a exigir `1900 <= anoVeiculo <= anoCorrente + 1` |

Novo método estático `DriverProfile.parseAnoVeiculo(String raw)` (D1 de `research.md`):
exatamente 4 dígitos, dentro da faixa; caso contrário `null`.

`toMap()`/`fromMap()` ganham a chave `ano_veiculo` (`int`, direto). `copyWith` ganha o parâmetro
`anoVeiculo`. `==`/`hashCode` passam a considerar o campo.

## Esquema SQLite — `driver_profile` (existente)

Versão do banco sobe de `3` para `4` (D2 de `research.md`):

```sql
-- onCreate (instalação nova, direto na versão 4)
CREATE TABLE driver_profile (
  ...colunas já existentes...,
  ano_veiculo      INTEGER NOT NULL DEFAULT 0
)

-- onUpgrade, oldVersion < 4:
ALTER TABLE driver_profile ADD COLUMN ano_veiculo INTEGER NOT NULL DEFAULT 0
```

Uma linha vinda de versão anterior recebe `0`, que `isValido` rejeita — cadastro corrompido, mesma
regra já existente (FR-004).
