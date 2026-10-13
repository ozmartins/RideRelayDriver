# Feature Specification: Ano do veículo no cadastro

**Feature Branch**: `008-ano-do-veiculo`

**Created**: 2026-09-20

**Status**: Draft

**Input**: User description: decisão tomada na conversa que originou a feature 009 (detalhes do
orçamento) e a feature 008 do passageiro (receber orçamentos): a modal de orçamentos do passageiro
precisa exibir o ano do veículo do motorista, e o cadastro do motorista (`DriverProfile`) ainda não
tem esse campo. Prioridade explícita do usuário: "Criar feature no motorista para o campo ano",
nos mesmos moldes da feature 006 (preço por quilômetro).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Informar o ano do veículo no cadastro inicial (Priority: P1)

Como motorista que preenche o cadastro pela primeira vez, quero informar o ano do meu veículo, para
que passageiros vendo meu orçamento saibam que carro esperar.

**Why this priority**: sem isso, não há ano nenhum para incluir no orçamento publicado (feature 009)
nem para a modal do passageiro exibir (feature 008 do passageiro).

**Independent Test**: preencher o formulário de cadastro pela primeira vez, informar um ano válido,
enviar e verificar que o ano informado é o que aparece ao consultar o cadastro em seguida.

**Acceptance Scenarios**:

1. **Given** o formulário de cadastro aberto pela primeira vez, **When** o motorista informa um ano
   válido de 4 dígitos (ex.: 2018) e preenche os demais campos obrigatórios, **Then** o envio é
   aceito e o ano informado é persistido.
2. **Given** o formulário de cadastro aberto, **When** o motorista deixa o ano vazio, com menos ou
   mais de 4 dígitos, não numérico, ou fora de uma faixa razoável (antes de 1900 ou depois do ano
   corrente + 1, para admitir o ano-modelo do lançamento seguinte), **Then** o envio é impedido e o
   motivo é indicado junto ao campo.

---

### User Story 2 - Corrigir o ano do veículo depois do cadastro (Priority: P2)

Como motorista já cadastrado, quero poder corrigir o ano do meu veículo (troquei de carro, ou errei
ao digitar), para que meu orçamento continue mostrando o dado correto.

**Why this priority**: mesma necessidade de correção já coberta para os demais campos (features 003,
005, 006), aplicada a este campo novo; não é pré-condição para US1.

**Independent Test**: com um cadastro já preenchido, abrir a edição, alterar o ano e verificar que o
novo valor aparece na consulta seguinte.

**Acceptance Scenarios**:

1. **Given** o cadastro já preenchido com um ano, **When** o motorista abre a edição e informa um
   novo ano válido, **Then** o cadastro passa a ter o novo valor.
2. **Given** a tela de edição aberta, **When** o motorista tenta salvar um ano inválido, **Then** a
   alteração é recusada com o motivo indicado, e o valor anterior é preservado.

---

### Edge Cases

- Cadastro de uma instalação anterior a esta feature, sem ano registrado: tratado pela mesma regra
  já existente de campo obrigatório ausente (cadastro corrompido, formulário reaberto) — mesma
  decisão das features 005 e 006, sem caminho de migração especial (Princípio V).
- Ano igual ao ano corrente + 1 (veículo 0 km do ano-modelo seguinte, já comum no mercado brasileiro
  no fim de ano): aceito.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: O sistema MUST permitir informar o ano do veículo no formulário de cadastro (inicial e
  edição), como um número de 4 dígitos.
- **FR-002**: O sistema MUST recusar o envio quando o ano estiver vazio, não for um número de exatos
  4 dígitos, ou estiver fora da faixa 1900 até o ano corrente + 1, indicando o motivo junto ao campo.
- **FR-003**: O sistema MUST persistir o ano junto do restante do cadastro.
- **FR-004**: Um cadastro de uma instalação anterior a esta feature, sem ano registrado, MUST ser
  tratado pela mesma regra já existente de cadastro corrompido (campo obrigatório ausente).

### Key Entities

- **`DriverProfile.anoVeiculo`**: `int`, ano-modelo do veículo do motorista — mesmo objeto de domínio
  das features 003/005/006, um campo a mais.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Um motorista consegue completar o cadastro informando um ano válido, sem precisar de
  ajuda externa, medido pela ausência de erro de validação para qualquer ano de 4 dígitos dentro da
  faixa aceita.
- **SC-002**: Nenhum ano fora da faixa 1900–(ano corrente + 1) chega a ser persistido, em 100% dos
  casos testados.

## Assumptions

- "Ano" aqui significa ano-modelo (o mesmo conceito já usado no mercado de veículos brasileiro), sem
  distinção entre ano de fabricação e ano-modelo — simplificação proporcional ao escopo do protótipo
  (Princípio V).
- Este campo não participa de nenhuma validação cruzada com marca/modelo (não há checagem de que o
  ano é compatível com o modelo informado) — mesmo nível de simplicidade dos demais campos de texto
  livre do veículo.
