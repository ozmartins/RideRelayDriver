# Phase 0 — Research: Formas de pagamento aceitas

## D1 — Representação: enum `PaymentMethod` + `Set<PaymentMethod>` (atende FR-001, FR-002)

**Decision**: criar `enum PaymentMethod { cash, pix, card }` em `lib/domain/payment_method.dart`, com
um rótulo de exibição em português por valor, e estender `DriverProfile` com um campo
`Set<PaymentMethod> paymentMethods`.

**Contexto da decisão**: as três opções são fixas, conhecidas de antemão e não mutuamente exclusivas
(Assumptions do `spec.md`) — o mesmo formato de problema que o app do passageiro resolveu com um enum
equivalente na feature 006 (`PaymentMethod.cash/pix/card`), embora aqui a cardinalidade seja um
conjunto (0 a 3 marcadas), não um valor único. Os dois enums **não são compartilhados entre as apps**
— cada app tem o seu próprio tipo, como já é o padrão deste protótipo (código não é espelho, só o
contrato de eventos é) — e este enum não tem contrapartida no contrato, porque não é publicado em
relay (Assumptions do `spec.md`).

### Alternativas avaliadas

| Opção | Observação |
|-------|------------|
| `enum` + `Set<PaymentMethod>` (escolhida) | Tipagem forte, impossível representar um valor fora das três opções fixas; `Set` expressa naturalmente "zero ou mais, sem repetição, sem ordem relevante" — exatamente a forma de FR-002. |
| Três campos `bool` (`aceitaDinheiro`, `aceitaPix`, `aceitaCartao`) | Evita um tipo novo, mas cada novo campo obrigaria alterar `isValido`, `copyWith`, `toMap`, `==`/`hashCode` e a UI em três lugares em vez de um; adicionar uma quarta forma de pagamento no futuro exigiria mexer em mais pontos do que com um enum. |
| Lista de `String` livre (`List<String>`) | Permitiria valores fora das três opções fixas por engano (erro de digitação, ex.: `"pic"` em vez de `"pix"`), sem checagem em tempo de compilação — contradiz o mesmo cuidado já tomado com UF (`UF.isValida`) e placa (`isValidPlaca`) na feature 003. |

## D2 — Persistência: nova coluna TEXT + migração de esquema (atende FR-004)

**Decision**: acrescentar a coluna `payment_methods TEXT NOT NULL DEFAULT ''` à tabela
`driver_profile`, serializando o conjunto como os nomes dos valores do enum separados por vírgula (ex.:
`"cash,pix"`), e subir a versão do banco de `1` para `2` em `SqfliteCadastroStore`, com `onUpgrade`
executando o `ALTER TABLE` correspondente.

**Contexto da decisão**: a tabela já existe (feature 003, versão 1) com colunas fixas; este é o
primeiro caso de evolução de esquema do protótipo. `DEFAULT ''` faz uma linha já existente (sem
nenhuma forma de pagamento) carregar como string vazia — que `PaymentMethod` decodifica como conjunto
vazio, que por sua vez falha em `DriverProfile.isValido` (FR-002/FR-003 exigem ao menos uma marcada).
Esse cadastro passa a ser tratado como corrompido pela regra já existente (FR-010 da feature 003), sem
nenhum código de migração adicional além do `ALTER TABLE` — decisão deliberada de não introduzir um
caminho especial (FR-006, Assumptions do `spec.md`, Princípio V).

### Alternativas avaliadas

| Opção | Observação |
|-------|------------|
| Coluna TEXT com nomes separados por vírgula (escolhida) | `sqflite`/SQLite não tem tipo de coleção nativo; uma string simples, sem aninhamento, é suficiente para um conjunto de no máximo 3 elementos conhecidos, sem precisar de JSON nem de tabela associativa. |
| Tabela associativa (`driver_profile_payment_method`, uma linha por forma marcada) | Modelagem relacional "correta" para um relacionamento N:N, mas desproporcional: não há necessidade de consultar "todos os motoristas que aceitam PIX" nem qualquer outra consulta que justifique uma tabela própria (Princípio V) — o cadastro é lido e escrito inteiro, nunca por campo. |
| Coluna JSON (`TEXT` com `["cash","pix"]`) | Resolveria o mesmo problema com mais uma camada de serialização (`jsonEncode`/`jsonDecode`) sem ganho sobre a lista separada por vírgula, já que os valores nunca contêm vírgula nem precisam de estrutura aninhada. |
| Recriar a tabela do zero (`DROP TABLE` + `CREATE TABLE` na nova versão) | Mais simples de escrever, mas apagaria qualquer cadastro já salvo (inclusive os campos que nada têm a ver com esta feature) só para acrescentar uma coluna — desproporcional ao Princípio V, e pior para quem já teria testado a feature 003 em aparelho. |

### Riscos assumidos e mitigação

- **Risco de a serialização por vírgula ficar ambígua no futuro**: aceito — os três valores do enum
  (`cash`, `pix`, `card`) nunca contêm vírgula, e o enum é fechado (D1), então não há como um valor
  inesperado entrar na coluna por este aplicativo. Um valor desconhecido lido da coluna (ex.: banco
  editado manualmente) é ignorado na decodificação, o que pode resultar em conjunto vazio e, por D2,
  cadastro tratado como corrompido — comportamento seguro, não uma falha silenciosa.

## D3 — Seleção na interface: três `CheckboxListTile` (atende FR-001, FR-002, clarificação de UX)

**Decision**: três `CheckboxListTile` (Material, `package:flutter`, já dependência do projeto — nenhuma
dependência nova), um por forma de pagamento, na seção "Veículo" existente do formulário, com um
cabeçalho de seção próprio ("Formas de pagamento aceitas").

### Alternativas avaliadas

| Opção | Observação |
|-------|------------|
| Três `CheckboxListTile` (escolhida) | Cada opção é independente (FR-001: não mutuamente exclusivas); o widget já junta rótulo e caixa de marcação em uma única área tocável, sem código extra de layout. |
| `FilterChip` em `Wrap` | Também expressaria seleção múltipla independente, mas é mais comum para filtros de busca do que para um formulário de cadastro; `CheckboxListTile` mantém a mesma linguagem visual dos demais campos do formulário (linhas empilhadas, alinhadas à esquerda). |
| Um único `DropdownButtonFormField` com seleção múltipla | O widget padrão do Flutter (`DropdownButtonFormField`) não suporta seleção múltipla nativamente — exigiria um pacote de terceiros ou um `showModalBottomSheet` customizado, complexidade desproporcional a três opções fixas (Princípio V). |
