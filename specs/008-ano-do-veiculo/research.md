# Phase 0 — Research: Ano do veículo no cadastro

## D1 — Representação: `int`, validado por faixa (atende FR-001, FR-002)

**Decision**: `DriverProfile` ganha `int anoVeiculo`. `DriverProfile.parseAnoVeiculo(String raw)`
aceita só dígitos, exige exatamente 4 caracteres, e recusa (devolve `null`) fora da faixa 1900 até
`DateTime.now().year + 1`.

**Contexto da decisão**: mesmo padrão de "parsing próprio antes de validar" de `parsePrecoPorKm`
(feature 006) e `normalizePlaca` (feature 003). `int`, não `String`, porque o ano participa
naturalmente de uma comparação numérica (a faixa), e não há necessidade de formatação especial
como em `precoPorKm` (sem casas decimais, sem separador).

### Alternativas avaliadas

| Opção | Observação |
|-------|------------|
| `int` + parsing por faixa (escolhida) | `int.tryParse` depois de validar o formato textual (4 dígitos); comparação de faixa é numérica e direta. |
| `String` de 4 caracteres, sem conversão | Evitaria a conversão, mas perderia a comparação de faixa nativa — precisaria comparar strings ou converter de qualquer forma para validar, sem ganho real. |
| `DropdownButtonFormField` com anos pré-listados | Evita entrada de texto livre, mas uma lista de ~127 anos (1900 até o corrente+1) é desproporcional a um campo simples de 4 dígitos — um `TextField` numérico já resolve com o mesmo padrão dos demais campos (Princípio V). |

### Riscos assumidos e mitigação

- Nenhum risco além do já aceito para os demais campos numéricos do cadastro (D1 de
  `specs/006-preco-por-km/research.md`) — sem aritmética sobre o valor além da comparação de faixa.

## D2 — Persistência: nova coluna INTEGER + migração de esquema (atende FR-003, FR-004)

**Decision**: coluna `ano_veiculo INTEGER NOT NULL DEFAULT 0`, subindo a versão do banco de
`SqfliteCadastroStore` de `4` para... — subindo de `3` para `4`, com `onUpgrade` executando o
`ALTER TABLE` correspondente, empilhado ao lado dos passos já existentes (1→2 da feature 005, 2→3
da feature 006).

**Contexto da decisão**: `DEFAULT 0` faz uma linha de instalação anterior carregar com
`anoVeiculo == 0`, fora da faixa 1900–corrente+1, que `isValido` já rejeita — cai na mesma regra de
"cadastro corrompido" já usada para os dois campos anteriores (FR-004 do `spec.md`).

### Alternativas avaliadas

| Opção | Observação |
|-------|------------|
| Coluna `INTEGER` (escolhida) | Tipo nativo do SQLite, mesmo tipo Dart de D1 — sem conversão na fronteira. |
| Coluna `TEXT` | Perderia a comparação numérica nativa sem ganho, pela mesma razão já descartada em D1. |
