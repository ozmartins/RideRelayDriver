# Feature Specification: Preço padrão por quilômetro

**Feature Branch**: `006-preco-por-km`

**Created**: 2026-09-20

**Status**: Draft

**Input**: User description: "Modifique o app do motorista. No formulário onde informa-se os dados do
motorista e do veículo, deve-se permitir informar o preço padrão por quilômetro. Um label deve
esclarecer que este valor pode ser modificado pelo usuário em cada corrida que ele decidir aceitar."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Informar o preço padrão por quilômetro no cadastro inicial (Priority: P1)

Como motorista que preenche o cadastro pela primeira vez, quero informar quanto cobro por quilômetro
rodado, para que esse valor sirva de referência quando eu for avaliar corridas.

**Why this priority**: é o pedido central desta feature — sem ele, o formulário de cadastro não tem
nenhum lugar para o motorista declarar sua referência de preço.

**Independent Test**: preencher o formulário de cadastro pela primeira vez, informar um preço por
quilômetro válido, enviar o formulário e verificar que o valor informado é o que aparece ao consultar
o cadastro em seguida.

**Acceptance Scenarios**:

1. **Given** o formulário de cadastro aberto pela primeira vez, **When** o motorista informa um preço
   por quilômetro válido (ex.: R$ 2,50) e preenche os demais campos obrigatórios, **Then** o envio é
   aceito e o preço informado é persistido.
2. **Given** o formulário de cadastro aberto pela primeira vez, **When** o motorista preenche todos os
   demais campos obrigatórios mas deixa o preço por quilômetro vazio, zero ou negativo, **Then** o
   envio é impedido e o motivo é indicado junto ao campo.
3. **Given** o formulário de cadastro aberto, **When** o motorista visualiza o campo de preço por
   quilômetro, **Then** um texto junto ao campo esclarece que esse valor pode ser alterado pelo
   motorista em cada corrida que ele decidir aceitar.

---

### User Story 2 - Corrigir o preço padrão por quilômetro depois do cadastro (Priority: P2)

Como motorista já cadastrado, quero poder alterar meu preço padrão por quilômetro — por exemplo, ao
reajustar meus valores —, para que meu cadastro continue correspondendo ao que realmente cobro, sem
precisar reinstalar o aplicativo.

**Why this priority**: é a mesma necessidade de correção já coberta para os demais campos do cadastro
(User Story 3 da feature 003, User Story 2 da feature 005) aplicada a este campo novo; não é
pré-condição para demonstrar a User Story 1.

**Independent Test**: com um cadastro já preenchido, abrir a tela de edição, alterar o preço por
quilômetro e verificar que o novo valor é o que aparece na consulta seguinte.

**Acceptance Scenarios**:

1. **Given** o cadastro já preenchido com um preço por quilômetro, **When** o motorista abre a edição
   e informa um novo valor válido, **Then** o cadastro passa a ter o novo valor.
2. **Given** a tela de edição aberta, **When** o motorista tenta salvar um preço por quilômetro vazio,
   zero ou negativo, **Then** a alteração é recusada com o motivo indicado, e o valor anterior é
   preservado.

### Edge Cases

- O que acontece se o motorista digitar um valor com formato inválido (texto não numérico, símbolo de
  moeda digitado à mão, mais de duas casas decimais)? O envio é impedido pela mesma regra de FR-002 —
  só um valor numérico positivo, com no máximo duas casas decimais, é aceito.
- O que acontece se o cadastro persistido antes desta feature não tiver nenhum preço por quilômetro
  registrado (dado de uma versão anterior do aplicativo)? Mesma regra já aplicada pela feature 005 a
  um campo obrigatório ausente: o cadastro é tratado como corrompido, e o formulário completo é
  exibido de novo — não é um caso especial desta feature.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: O formulário de cadastro MUST oferecer um campo para o motorista informar seu preço
  padrão por quilômetro, em reais, com até duas casas decimais.
- **FR-002**: O aplicativo MUST impedir o envio do formulário — tanto no cadastro inicial quanto na
  edição — enquanto o preço por quilômetro estiver vazio, igual a zero, negativo, ou em formato que
  não seja um número com no máximo duas casas decimais, indicando o motivo junto ao campo, na mesma
  linha das demais validações já existentes no formulário (FR-006 da feature 003).
- **FR-003**: O formulário MUST exibir, junto ao campo de preço por quilômetro, um texto explicando
  que esse valor é o padrão sugerido e pode ser alterado pelo motorista em cada corrida que ele
  decidir aceitar.
- **FR-004**: Ao enviar o formulário com um preço por quilômetro válido e os demais campos válidos, o
  aplicativo MUST persistir esse valor junto com o restante do cadastro, de forma que sobreviva ao
  fechamento e reabertura do aplicativo.
- **FR-005**: O aplicativo MUST permitir consultar e corrigir, depois do cadastro inicial, o preço
  padrão por quilômetro, pela mesma tela de edição já usada para os demais campos, sujeito à mesma
  validação de FR-002.
- **FR-006**: Um cadastro persistido sem nenhum preço por quilômetro registrado — incluindo um
  cadastro salvo por uma versão do aplicativo anterior a esta feature — MUST ser tratado pela mesma
  regra já aplicada a qualquer outro campo obrigatório vazio do cadastro (FR-010 da feature 003):
  cadastro corrompido, formulário completo exibido de novo. Esta feature não introduz nenhum caminho
  de migração ou exceção adicional.

### Key Entities

- **Preço padrão por quilômetro**: valor monetário, em reais, maior que zero, com no máximo duas
  casas decimais, associado ao cadastro do motorista. É só uma referência inicial — a negociação de
  preço por corrida em si (o motorista efetivamente ajustando o valor ao aceitar uma corrida
  específica) é trabalho de uma feature futura, fora de escopo aqui (ver Assumptions).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% das tentativas de envio do formulário (cadastro inicial ou edição) com preço por
  quilômetro vazio, zero, negativo ou em formato inválido são recusadas antes de qualquer
  persistência.
- **SC-002**: Um motorista consegue informar seu preço por quilômetro e enviar o formulário sem nenhum
  passo adicional além de digitar o valor.
- **SC-003**: O preço por quilômetro cadastrado permanece idêntico após 5 ciclos consecutivos de
  fechar e reabrir o aplicativo.
- **SC-004**: Uma correção no preço por quilômetro feita na tela de edição é a que aparece na consulta
  seguinte, em 100% das tentativas.

## Assumptions

- O preço por quilômetro é **obrigatório**, pela mesma razão que os demais campos do formulário são
  obrigatórios (FR-002 da feature 003): um cadastro sem essa referência não tem valor demonstrável
  para o protótipo, que já trata o restante do formulário como bloqueante.
- O valor é expresso em **reais (R$)** — moeda do público-alvo do protótipo (motoristas brasileiros,
  mesmo domínio da placa/UF/município da feature 003) — com no máximo duas casas decimais, sem exigir
  seleção de moeda.
- Este é um **preço padrão/sugerido**, não um preço fixo: o rótulo explicativo (FR-003) já deixa claro
  que o motorista pode alterá-lo por corrida. Esta feature não implementa esse ajuste por corrida —
  não existe, ainda, nenhuma tela de "aceitar corrida" no protótipo (a solicitação de corrida do
  passageiro, feature 006 do passageiro, ainda não tem contrapartida de consumo no motorista). Esse
  ajuste é trabalho de uma feature futura.
- Esta feature não cria nem altera nenhum evento Nostr: o preço padrão é dado local do motorista,
  persistido apenas no cadastro (SQLite), sem contrapartida no contrato de eventos
  (`specs/002-nostr-relay-connection/contracts/nostr-events.md`) nem publicação em relay. O Princípio
  IV da constituição não se aplica; nada aqui precisa ser replicado em `Prototipo/passenger`.
- Um cadastro já existente, persistido por uma versão anterior do aplicativo sem nenhum preço por
  quilômetro, **não** é tratado como caso especial: cai na mesma regra de campo obrigatório ausente já
  estabelecida pela feature 005 (FR-006, Princípio V — simplicidade proporcional, sem base instalada
  de usuários reais a proteger).
