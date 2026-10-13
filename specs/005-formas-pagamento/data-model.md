# Phase 1 — Data Model: Formas de pagamento aceitas

## `PaymentMethod` (novo, `lib/domain/payment_method.dart`)

```text
enum PaymentMethod { cash, pix, card }
```

| Valor | Rótulo de exibição | Valor persistido (coluna `payment_methods`) |
|-------|---------------------|-----------------------------------------------|
| `PaymentMethod.cash` | "Dinheiro" | `cash` |
| `PaymentMethod.pix` | "PIX" | `pix` |
| `PaymentMethod.card` | "Cartão" | `card` |

Não há valor pré-selecionado por padrão: o formulário começa sem nenhuma marcação (diferente da
feature 006 do passageiro, onde "Dinheiro" vem pré-selecionado) — aqui o motorista está declarando um
fato sobre si mesmo (o que ele de fato aceita), não escolhendo uma preferência para uma única
transação, e presumir uma resposta seria impreciso.

## `DriverProfile` (existente, `lib/domain/driver_profile.dart`) — ganha `paymentMethods`

| Campo novo | Tipo | Observação |
|------------|------|------------|
| `paymentMethods` | `Set<PaymentMethod>` | Obrigatório no construtor; `isValido` passa a exigir `paymentMethods.isNotEmpty` (FR-002, FR-003), na mesma linha das demais regras já existentes (nome, marca, modelo, cor não vazios; placa e UF/cidade válidas) |

`toMap()`/`fromMap()` ganham a chave `payment_methods`, serializada como os nomes dos valores do enum
separados por vírgula (D2 de `research.md`), decodificados de volta ignorando qualquer valor
desconhecido (D2, Riscos assumidos). `copyWith` ganha o parâmetro `paymentMethods`. `==`/`hashCode`
passam a considerar o conjunto (comparação de `Set`, sem depender de ordem).

## Esquema SQLite — `driver_profile` (existente, `lib/services/sqflite_cadastro_store.dart`)

Versão do banco sobe de `1` para `2` (D2 de `research.md`):

```sql
-- onCreate (instalação nova, direto na versão 2)
CREATE TABLE driver_profile (
  id               INTEGER PRIMARY KEY CHECK (id = 1),
  nome             TEXT NOT NULL,
  uf               TEXT NOT NULL,
  cidade           TEXT NOT NULL,
  marca_veiculo    TEXT NOT NULL,
  modelo_veiculo   TEXT NOT NULL,
  cor_veiculo      TEXT NOT NULL,
  placa_veiculo    TEXT NOT NULL,
  payment_methods  TEXT NOT NULL DEFAULT ''
)

-- onUpgrade de 1 para 2 (instalação já existente da feature 003)
ALTER TABLE driver_profile ADD COLUMN payment_methods TEXT NOT NULL DEFAULT ''
```

Uma linha vinda da versão 1 (sem a coluna antes do upgrade) recebe `''` pelo `DEFAULT`, que
`PaymentMethod` decodifica como conjunto vazio — inválido por `DriverProfile.isValido`, tratado como
cadastro corrompido pela regra já existente (FR-010 da feature 003, FR-006 desta feature). Nenhum
código de migração de dado é necessário além do `ALTER TABLE`.
