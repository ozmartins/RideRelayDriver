# Feature Specification: Formas de pagamento aceitas

**Feature Branch**: `005-formas-pagamento`

**Created**: 2026-09-20

**Status**: Draft

**Input**: User description: "Modifique o app do motorista. No formulário onde informa-se os dados do
motorista e do veículo, deve permitir a seleção das formas de pagamento aceitas pelo motorista:
Dinheiro, PIX e cartão."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Escolher as formas de pagamento aceitas no cadastro inicial (Priority: P1)

Como motorista que preenche o cadastro pela primeira vez, quero indicar quais formas de pagamento eu
aceito — dinheiro, PIX e/ou cartão —, para que essa informação fique registrada junto com meus dados e
os do meu veículo.

**Why this priority**: é o pedido central desta feature — sem ele, o formulário de cadastro continua
sem nenhuma forma de o motorista declarar o que aceita, condição para qualquer uso futuro dessa
informação (ex.: um passageiro escolher um motorista compatível com a forma de pagamento desejada).

**Independent Test**: preencher o formulário de cadastro pela primeira vez, marcar uma ou mais formas
de pagamento, enviar o formulário e verificar que a seleção feita é a que aparece ao consultar o
cadastro em seguida.

**Acceptance Scenarios**:

1. **Given** o formulário de cadastro aberto pela primeira vez, **When** o motorista marca "Dinheiro" e
   "PIX" e preenche os demais campos obrigatórios, **Then** o envio é aceito e as duas formas marcadas
   são persistidas.
2. **Given** o formulário de cadastro aberto pela primeira vez, **When** o motorista preenche todos os
   demais campos obrigatórios mas não marca nenhuma forma de pagamento, **Then** o envio é impedido e o
   motivo é indicado junto ao seletor de formas de pagamento.
3. **Given** o formulário de cadastro aberto pela primeira vez, **When** o motorista marca as três
   formas de pagamento (Dinheiro, PIX e Cartão), **Then** o envio é aceito e as três são persistidas.

---

### User Story 2 - Corrigir as formas de pagamento aceitas depois do cadastro (Priority: P2)

Como motorista já cadastrado, quero poder alterar quais formas de pagamento aceito — por exemplo, ao
passar a aceitar cartão —, para que meu cadastro continue correspondendo ao que realmente aceito, sem
precisar reinstalar o aplicativo.

**Why this priority**: é a mesma necessidade de correção já coberta para os demais campos do cadastro
(User Story 3 da feature 003) aplicada a este campo novo; não é pré-condição para demonstrar a User
Story 1.

**Independent Test**: com um cadastro já preenchido, abrir a tela de edição, alterar a seleção de
formas de pagamento e verificar que o novo conjunto é o que aparece na consulta seguinte.

**Acceptance Scenarios**:

1. **Given** o cadastro já preenchido com "Dinheiro" marcado, **When** o motorista abre a edição e
   também marca "Cartão", **Then** o cadastro passa a ter as duas formas marcadas.
2. **Given** a tela de edição aberta, **When** o motorista desmarca a única forma de pagamento
   restante, sem marcar nenhuma outra, **Then** a alteração é recusada com o motivo indicado, e a
   seleção anterior é preservada.

### Edge Cases

- O que acontece se o cadastro persistido antes desta feature não tiver nenhuma forma de pagamento
  registrada (dado de uma versão anterior do aplicativo)? Nenhuma forma de pagamento marcada é, por
  esta feature, um campo obrigatório vazio — a mesma regra já existente para qualquer outro campo
  obrigatório do cadastro (FR-010 da feature 003) se aplica: o cadastro é tratado como corrompido, e o
  formulário completo é exibido de novo. Não é um caso especial desta feature.
- O que acontece se os dados persistidos estiverem corrompidos ou ilegíveis, incluindo as formas de
  pagamento? Mesma regra já existente para o restante do cadastro (FR-010 da feature 003): tratado como
  ausência de cadastro, formulário exibido de novo por completo.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: O formulário de cadastro MUST oferecer três opções de seleção, não mutuamente exclusivas
  entre si: "Dinheiro", "PIX" e "Cartão".
- **FR-002**: O motorista MUST poder marcar qualquer combinação de uma, duas ou três dessas opções.
- **FR-003**: O aplicativo MUST impedir o envio do formulário — tanto no cadastro inicial quanto na
  edição — enquanto nenhuma forma de pagamento estiver marcada, indicando o motivo junto ao seletor,
  na mesma linha das demais validações já existentes no formulário (FR-006 da feature 003).
- **FR-004**: Ao enviar o formulário com ao menos uma forma de pagamento marcada e os demais campos
  válidos, o aplicativo MUST persistir o conjunto de formas marcadas junto com o restante do cadastro,
  de forma que sobreviva ao fechamento e reabertura do aplicativo.
- **FR-005**: O aplicativo MUST permitir consultar e corrigir, depois do cadastro inicial, o conjunto
  de formas de pagamento aceitas, pela mesma tela de edição já usada para os demais campos (User Story
  3 da feature 003), sujeito à mesma validação de FR-003.
- **FR-006**: Um cadastro persistido sem nenhuma forma de pagamento marcada — incluindo um cadastro
  salvo por uma versão do aplicativo anterior a esta feature — MUST ser tratado pela mesma regra já
  aplicada a qualquer outro campo obrigatório vazio do cadastro (FR-010 da feature 003): cadastro
  corrompido, formulário completo exibido de novo. Esta feature não introduz nenhum caminho de migração
  ou exceção adicional.

### Key Entities

- **Formas de pagamento aceitas**: subconjunto não vazio das três opções fixas (Dinheiro, PIX, Cartão),
  associado ao cadastro do motorista. Não é uma lista sujeita a atualização externa — as três opções
  são fixas e conhecidas de antemão, como a lista de UFs da feature 003.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% das tentativas de envio do formulário (cadastro inicial ou edição) sem nenhuma forma
  de pagamento marcada são recusadas antes de qualquer persistência.
- **SC-002**: Um motorista consegue marcar qualquer combinação das três formas de pagamento e enviar o
  formulário sem nenhum passo adicional além de marcar as opções desejadas.
- **SC-003**: As formas de pagamento marcadas permanecem idênticas após 5 ciclos consecutivos de fechar
  e reabrir o aplicativo.
- **SC-004**: Uma correção nas formas de pagamento feita na tela de edição é a que aparece na consulta
  seguinte, em 100% das tentativas.

## Assumptions

- As formas de pagamento aceitas **não são mutuamente exclusivas**: um motorista pode aceitar mais de
  uma. A descrição da feature nomeia três opções sem indicar exclusividade, e o domínio (um motorista
  real tipicamente aceita mais de uma forma) favorece seleção múltipla sobre escolha única.
- Ao menos uma forma de pagamento é **obrigatória**, pela mesma razão que os demais campos do
  formulário são obrigatórios (FR-002 da feature 003): um cadastro sem nenhuma forma de pagamento
  aceita não tem valor demonstrável para o protótipo.
- A seleção é apresentada como três opções de marcação independente (equivalente a três caixas de
  seleção), não como uma lista externa — mesmo padrão de simplicidade já usado para UF/cidade da
  feature 003, mas sem depender de nenhuma fonte de dados externa: as três opções são fixas.
- Esta feature não cria nem altera nenhum evento Nostr: as formas de pagamento aceitas são dado local
  do motorista, persistido apenas no cadastro (SQLite), sem contrapartida no contrato de eventos
  (`specs/002-nostr-relay-connection/contracts/nostr-events.md`) nem publicação em relay. O Princípio
  IV da constituição não se aplica; nada aqui precisa ser replicado em `Prototipo/passenger`.
- Usar essa informação para casar motoristas e passageiros pela forma de pagamento desejada (ver
  `kind: 20001`, "Solicitação de corrida", do contrato de eventos do passageiro) é trabalho de uma
  feature futura, fora de escopo aqui — esta feature só coleta e persiste a preferência do motorista.
- Um cadastro já existente, persistido por uma versão anterior do aplicativo sem nenhuma forma de
  pagamento, **não** é tratado como caso especial: cai na mesma regra de campo obrigatório ausente já
  aplicada a qualquer outro campo do cadastro (FR-006, FR-010 da feature 003). Introduzir um caminho de
  migração que preservasse esse cadastro parcialmente extrapolaria o que a feature pede, e o protótipo
  não tem base instalada de usuários reais a proteger (Princípio V — simplicidade proporcional).
