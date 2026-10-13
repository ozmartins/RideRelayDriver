# Phase 0 — Research: Preço padrão por quilômetro

## D1 — Representação: `double`, validado por parsing próprio (atende FR-001, FR-002)

**Decision**: `DriverProfile` ganha o campo `double precoPorKm`. A conversão do texto digitado para
esse `double` fica em `DriverProfile.parsePrecoPorKm(String raw)`, que aceita vírgula ou ponto como
separador decimal e recusa (retorna `null`) qualquer texto que não seja um número positivo com no
máximo duas casas decimais.

**Contexto da decisão**: o público-alvo é brasileiro (mesmo domínio de UF/município da feature 003),
e o separador decimal usual em português é a vírgula (`2,50`), mas aceitar também o ponto (`2.50`)
evita rejeitar um motorista que digite no formato que o teclado numérico do aparelho sugerir. O
mesmo padrão de "normalizar antes de validar" já existe para a placa (`normalizePlaca`,
`isValidPlaca`, feature 003).

### Alternativas avaliadas

| Opção | Observação |
|-------|------------|
| `double` + parsing próprio (escolhida) | Reaproveita `double.tryParse` do Dart depois de normalizar o separador, sem dependência nova; a checagem de "no máximo duas casas decimais" é feita no texto original, antes da conversão, para não depender de arredondamento de ponto flutuante para *validar* a entrada. |
| `int` (centavos) | Evitaria qualquer imprecisão de ponto flutuante na E/S, mas exigiria uma camada de conversão (reais digitados ↔ centavos armazenados) só para um campo que nunca participa de soma nem de outra operação aritmética neste escopo — desproporcional (Princípio V, D2 abaixo mantém a mesma escolha para a coluna). |
| Pacote de formatação de moeda (ex.: `intl`, `money2`) | Resolveria formatação e parsing de moeda de forma mais completa, mas para um único campo, sem exibição em múltiplas moedas nem cálculo, seria estrutura sem consumidor (Princípio V). |

### Riscos assumidos e mitigação

- **Risco de imprecisão de ponto flutuante na exibição**: aceito — o valor nunca é somado nem
  multiplicado neste escopo (Assumptions do `spec.md`: o ajuste por corrida é feature futura), só
  armazenado e reexibido; qualquer erro de representação de `double` (ex.: `2.50` guardado como
  `2.4999999999999996`) é absorvido ao formatar a exibição com duas casas decimais
  (`toStringAsFixed(2)`), que arredonda de volta ao valor esperado.

## D2 — Persistência: nova coluna REAL + migração de esquema (atende FR-004)

**Decision**: acrescentar a coluna `preco_por_km REAL NOT NULL DEFAULT 0` à tabela `driver_profile`,
subindo a versão do banco de `SqfliteCadastroStore` de `2` para `3`, com `onUpgrade` executando o
`ALTER TABLE` correspondente — mesmo padrão já estabelecido pela feature 005 (D2 de
`specs/005-formas-pagamento/research.md`) para `payment_methods`.

**Contexto da decisão**: `DEFAULT 0` faz uma linha já existente (de uma instalação anterior a esta
feature) carregar com `precoPorKm == 0`, que `DriverProfile.isValido` já trata como inválido (FR-002:
preço deve ser maior que zero) — o mesmo cadastro cai na regra genérica de campo obrigatório ausente
(FR-006 do `spec.md`, FR-010 da feature 003), sem nenhum código de migração de dado além do `ALTER
TABLE`, replicando a decisão já tomada pela feature 005.

### Alternativas avaliadas

| Opção | Observação |
|-------|------------|
| Coluna `REAL` (escolhida) | SQLite tem tipo `REAL` nativo (IEEE 754 double), o mesmo tipo Dart de D1 — sem conversão na fronteira do banco. |
| Coluna `INTEGER` (centavos) | Mesma desproporção já descartada em D1: converteria só para armazenar, sem nenhuma consulta ou cálculo sobre a coluna que se beneficiasse de inteiros exatos. |
| Coluna `TEXT` (valor formatado como string) | Perderia a ordenação/comparação numérica nativa do SQLite sem nenhum ganho, já que a validação de formato acontece na camada de domínio (D1), não no banco. |

### Riscos assumidos e mitigação

- Mesmo risco de D1 (representação de ponto flutuante), aceito pela mesma razão — sem aritmética
  sobre o valor armazenado.

## D3 — Campo na interface: `TextField` com `TextInputType.numberWithOptions(decimal: true)` (atende
FR-001, FR-003)

**Decision**: um `TextField` de texto livre com teclado numérico decimal, abaixo da seção "Formas de
pagamento aceitas" (feature 005), com um `helperText` fixo explicando que o valor é uma sugestão
ajustável por corrida (FR-003) — sem widget nem pacote novo.

### Alternativas avaliadas

| Opção | Observação |
|-------|------------|
| `TextField` com teclado decimal (escolhida) | Mesmo padrão já usado por nome/marca/modelo/cor/placa (feature 003) — um campo de texto com validação própria e `errorText` condicional. |
| `Slider` ou `Stepper` numérico | Widgets pensados para faixas de valor conhecidas e incrementos fixos; preço por quilômetro não tem faixa nem incremento óbvios, e digitar diretamente é mais rápido para um valor específico (SC-002 do `spec.md`). |
