# Feature Specification: Integridade das avaliações (Row Signing)

**Feature Branch**: `014-integridade-row-signing`

**Created**: 2026-09-23

**Status**: Draft

**Input**: User description: "Implementar um mecanismo de integridade de dados (Row Signing) para
a tabela de avaliações (ride_ratings) do app do motorista, usando o par de chaves assimétricas já
existente da identidade Nostr do usuário. Ao inserir uma avaliação, canonicalizar os campos da
linha de forma estrita, gerar o hash SHA-256 desse payload, assinar o hash com a chave privada
existente e salvar a assinatura junto do registro (novo campo signature). Ao ler, reconstruir o
mesmo payload a partir dos dados do banco, validar a assinatura com a chave pública, marcar uma
flag de violação no registro se a assinatura for inválida, e ignorar na leitura qualquer registro
violado — incluindo registros já existentes, gravados antes deste mecanismo existir, que não têm
assinatura nenhuma (tratados como violados). Mesmo mecanismo já especificado e implementado no app
do passageiro (passenger/specs/012-integridade-row-signing/), aplicado agora à própria tabela
local do motorista, sem nenhum dado compartilhado entre os dois apps."

> Esta é a metade do motorista de um pedido que também se aplica ao passageiro — a contrapartida
> dele já foi especificada em `passenger/specs/012-integridade-row-signing/`, sobre a própria
> tabela de avaliações local dele. As duas decisões de escopo abaixo (aplicar nos dois apps;
> tratar registro sem assinatura como violado) foram confirmadas pelo usuário antes da
> especificação irmã e reaplicadas aqui, então não aparecem como `[NEEDS CLARIFICATION]`.

## Clarifications

### Session 2026-09-23

- Q: A tabela `ride_ratings` existe separadamente em cada app; o mecanismo deve ser implementado
  nos dois apps, ou só em um? → A: Nos dois — cada app assina e valida sua própria tabela local
  com sua própria identidade Nostr já existente, sem nenhum acoplamento novo entre eles. (Resposta
  dada uma vez, antes da especificação da feature irmã do passageiro, e reaplicada aqui.)
- Q: Avaliações já gravadas antes deste mecanismo existir, sem assinatura, como tratar na leitura?
  → A: Tratadas como violadas/ignoradas — mesma regra de qualquer registro sem assinatura válida,
  sem exceção para dados legados.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Avaliação gravada com prova de integridade (Priority: P1)

Quando o motorista confirma uma nota (feature `013-avaliar-corrida`), o registro salvo no banco
local passa a carregar uma prova de que aqueles exatos valores foram gravados por este mesmo
usuário e não foram alterados desde então — sem que o motorista veja ou precise fazer nada
diferente ao avaliar.

**Why this priority**: é o próprio objetivo do pedido — sem isso, não há nenhuma forma de detectar
se um registro de avaliação foi adulterado depois de gravado (por exemplo, editado diretamente no
arquivo do banco, fora do app).

**Independent Test**: pode ser testado gravando uma avaliação através do fluxo já existente e
inspecionando o registro salvo, confirmando que ele carrega uma assinatura, e que essa assinatura
é válida para os valores exatamente como gravados.

**Acceptance Scenarios**:

1. **Given** o motorista confirma uma nota de 1 a 5 para uma corrida encerrada, **When** o
   registro é persistido, **Then** ele carrega, junto dos campos já existentes, uma assinatura
   digital calculada sobre esses mesmos campos com a chave privada da identidade do usuário.
2. **Given** um registro de avaliação foi salvo por este mecanismo, **When** ele é lido de volta
   sem qualquer alteração no banco, **Then** a assinatura é reconhecida como válida e o registro é
   devolvido normalmente.

---

### User Story 2 - Registro adulterado é detectado e descartado na leitura (Priority: P1)

Se algum valor de uma avaliação já gravada for alterado por fora do app (edição direta no arquivo
do banco, por exemplo), a próxima leitura desse registro precisa reconhecer que ele não confere
mais com a assinatura original, marcar isso permanentemente e parar de devolver aquele registro
como se fosse uma avaliação legítima.

**Why this priority**: é a outra metade do mesmo objetivo — gravar uma assinatura que ninguém
nunca confere não protege nada. A detecção na leitura é o que torna a assinatura útil.

**Independent Test**: pode ser testado alterando diretamente um valor de um registro já assinado
(por exemplo, a nota) e confirmando que uma leitura subsequente não devolve mais aquele registro,
e que o registro fica marcado como violado no banco.

**Acceptance Scenarios**:

1. **Given** um registro de avaliação tem algum campo alterado depois de gravado (fora do fluxo
   normal do app), **When** ele é lido, **Then** o sistema reconhece que a assinatura não confere
   com os valores atuais do registro.
2. **Given** a assinatura de um registro não confere na leitura, **When** essa leitura acontece,
   **Then** o registro é marcado como violado de forma permanente (persistida no banco), e essa
   leitura não devolve o registro como resultado válido.
3. **Given** um registro já está marcado como violado (de uma leitura anterior), **When** ele é
   lido de novo, **Then** continua sendo excluído do resultado, sem nova tentativa de validação
   necessária.

---

### User Story 3 - Registros anteriores a este mecanismo são tratados como violados (Priority: P2)

Avaliações já gravadas pela feature `013-avaliar-corrida` (motorista), antes deste mecanismo
existir, não têm assinatura nenhuma. Elas devem ser reconhecidas como não confiáveis e excluídas
da leitura, exatamente como um registro adulterado — sem tratamento especial de migração.

**Why this priority**: decisão explícita do usuário: a ausência de assinatura é, por si, motivo de
exclusão, para que a regra de integridade não tenha exceção silenciosa. Prioridade P2 porque é uma
consequência direta das User Stories 1/2, não um mecanismo novo.

**Independent Test**: pode ser testado inspecionando um registro gravado antes desta feature
(sem coluna `signature` preenchida) e confirmando que uma leitura o marca como violado e não o
devolve.

**Acceptance Scenarios**:

1. **Given** um registro de avaliação gravado antes deste mecanismo existir, sem nenhuma
   assinatura, **When** ele é lido, **Then** é tratado como violado (mesmo caminho da User Story
   2) e excluído do resultado.

---

### Edge Cases

- O que acontece se dois campos diferentes forem trocados entre si, mas os valores concatenados
  formarem o mesmo texto (ex.: um campo vazio movido para outro)? A canonicalização MUST produzir
  representações diferentes para conjuntos de valores diferentes, mesmo quando a concatenação
  ingênua coincidiria — ver FR-001 e a nota de canonicalização nas Assumptions.
- O que acontece se a chave privada do usuário mudar (reinstalação do app, nova identidade)?
  Avaliações assinadas pela identidade anterior deixam de validar contra a chave pública atual e
  passam a ser tratadas como violadas — mesma regra da User Story 2, sem exceção para troca de
  identidade (consequência aceita, não um requisito à parte).
- Uma avaliação recém-gravada por este próprio mecanismo nunca deve falhar a própria validação
  logo em seguida — coberto pela User Story 1, cenário 2.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: O sistema MUST calcular, para cada avaliação, uma representação canônica e
  determinística dos seus campos de dados (excluídos os campos de integridade em si — assinatura e
  flag de violação), de forma que valores diferentes produzam sempre representações diferentes e
  os mesmos valores produzam sempre a mesma representação.
- **FR-002**: Ao gravar uma nova avaliação, o sistema MUST assinar essa representação canônica com
  a chave privada da identidade do usuário e persistir a assinatura resultante junto do registro.
- **FR-003**: Ao ler uma avaliação, o sistema MUST reconstruir a mesma representação canônica a
  partir dos valores armazenados e validar a assinatura persistida contra a chave pública da
  identidade do usuário.
- **FR-004**: Quando a validação de um registro falhar (assinatura ausente ou que não confere com
  os valores atuais), o sistema MUST persistir uma marca de violação nesse registro.
- **FR-005**: Um registro já marcado como violado MUST permanecer marcado (a marca não é revertida
  por uma leitura posterior, mesma ou não a assinatura voltando a validar).
- **FR-006**: Um registro marcado como violado (recém-detectado ou já marcado antes) MUST NOT ser
  devolvido como resultado de uma leitura de avaliações.
- **FR-007**: Um registro sem nenhuma assinatura gravada (incluindo os já existentes antes deste
  mecanismo) MUST ser tratado pelas mesmas regras de FR-004/FR-006 — como violado, não como um
  caso à parte.
- **FR-008**: O mecanismo de assinatura e validação MUST operar inteiramente dentro do
  dispositivo do usuário — a chave privada, a assinatura e o processo de validação MUST NOT ser
  transmitidos a nenhum relay nem a qualquer serviço externo.
- **FR-009**: Do ponto de vista do motorista, gravar uma avaliação MUST continuar funcionando
  exatamente como hoje (mesma tela, mesma interação) — este mecanismo é uma garantia interna,
  invisível durante o uso normal.
- **FR-010**: O uso do resultado de uma leitura de avaliações (o que é feito com os registros não
  violados) está fora do escopo desta feature — já era e continua sendo definido fora dela (mesmo
  limite já estabelecido pela feature `013-avaliar-corrida`).

### Key Entities *(include if feature involves data)*

- **RideRating** (ampliada): a entidade já existente (`013-avaliar-corrida`) ganha uma assinatura
  digital dos seus campos de dados e uma marca de violação — nenhum campo de negócio novo, só os
  dois campos de integridade. Estrutura conceitualmente idêntica à contrapartida do passageiro,
  mas persistida separadamente, sem nenhuma relação de armazenamento entre as duas.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% das avaliações gravadas por este mecanismo têm uma assinatura que valida com
  sucesso numa leitura imediatamente seguinte, sem nenhuma alteração externa ao registro.
- **SC-002**: 100% dos registros com qualquer campo de dado alterado por fora do fluxo normal do
  app são identificados como violados na primeira leitura seguinte à alteração, e nunca mais
  aparecem num resultado de leitura depois disso.
- **SC-003**: 100% dos registros gravados antes deste mecanismo existir (sem assinatura) são
  identificados como violados na primeira leitura depois desta feature entrar em vigor.
- **SC-004**: Nenhuma informação da chave privada do usuário aparece em nenhum dado persistido,
  log ou saída deste mecanismo.

## Assumptions

- A canonicalização "de forma estrita" pedida pelo usuário é interpretada como: concatenar os
  valores dos campos de dados em uma ordem fixa e documentada, com um separador que não pode
  aparecer dentro de nenhum dos valores (evitando a ambiguidade citada no Edge Case sobre campos
  trocados) — decisão técnica registrada em `research.md`, não repetida aqui por já estar fora do
  nível de abstração desta spec.
- A representação canônica nunca inclui a própria assinatura nem a flag de violação — só os campos
  de dado da avaliação (a mesma regra que qualquer assinatura digital precisa seguir, para não
  criar uma dependência circular).
- A validação acontece a cada leitura (não há cache do resultado "válido" fora do que já está
  persistido como violado ou não) — decisão de simplicidade, já que o volume de avaliações do
  protótipo é pequeno (Princípio V da constituição).
- Este mecanismo se aplica à mesma operação de leitura já existente (`RideRatingStore.forRide`,
  introduzida pela feature `013-avaliar-corrida`) — nenhuma nova forma de consultar avaliações é
  criada por esta feature.
- A contrapartida do passageiro (mesmo mecanismo, sobre a tabela de avaliações dele) já está
  especificada em `passenger/specs/012-integridade-row-signing/`, sem nenhum dado ou assinatura
  compartilhados entre as duas — cada app assina e valida só os próprios registros, com a própria
  identidade.
