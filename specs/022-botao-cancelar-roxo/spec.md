# Feature Specification: Botões de cancelar corrida em roxo (motorista)

**Feature Branch**: `022-botao-cancelar-roxo` (sem branch git: trabalho direto na `master`)

**Created**: 2026-10-07

**Status**: Draft

**Input**: User description: "Modifique a aparência dos botões que permitem cancelar uma corrida no app do
motorista. Todos eles devem ter o fundo roxo e uma cor de fonte que contraste com o roxo (já existem
outros botões na aplicação com esta aparência). Hoje são dois: o botão "Cancelar corrida" sobre o mapa
(cartão de alerta em ColorScheme.error) e o botão de confirmação "Cancelar corrida" da CancelRideModal.
Puramente visual: sem mudança de contrato, de comportamento, de estado ou de persistência. A contrapartida
do passageiro será uma feature de spec-kit própria dentro de passenger/."

## Clarifications

### Session 2026-10-07 (decisões tomadas antes da especificação, a partir do que o código mostra)

- Q: Quais botões de cancelar corrida existem hoje no app do motorista? → A: dois. (1) "Cancelar corrida" no
  bloco "corrida em andamento" do cartão de status do mapa, hoje em vermelho cheio (`ColorScheme.error`,
  texto `onError`); (2) "Cancelar corrida" de confirmação da modal "Cancelar corrida?", que **já** usa o
  estilo de ação primária (fundo roxo, texto branco). "Voltar" na modal não cancela nada e fica como está.
- Q: Então o que muda de fato? → A: só o botão do mapa passa ao roxo; o da modal já cumpre o pedido e
  passa a ser protegido por teste, para que os dois nunca divirjam.
- Q: Qual é o "roxo com texto que contrasta" a usar? → A: o mesmo das demais ações primárias do app (fundo
  roxo da identidade visual, texto branco), o que o pedido descreve como "outros botões com esta
  aparência". Nenhum valor de cor novo.
- Q: A constituição permite? → A: não como está. O componente "Botão de ação destrutiva" da seção
  Identidade Visual e Design (emendas 2.10.0) manda fundo `ColorScheme.error`. Por regra da própria
  seção, a mudança exige emendar o componente nas **duas** constituições espelho (2.12.0), em commit
  separado e **antes** do código; esta spec depende dessa emenda.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Botão de cancelar do mapa em roxo (Priority: P1)

Como motorista em uma corrida aceita ("Deslocando-se até o passageiro" ou "Em corrida"), quero que o
botão "Cancelar corrida" do mapa tenha a mesma aparência das demais ações do app (fundo roxo, texto
legível), para que a tela siga um único visual.

**Why this priority**: é a única parte do pedido que muda a tela hoje.

**Independent Test**: levar o app a "Deslocando-se até o passageiro" e a "Em corrida" e conferir, no
botão "Cancelar corrida" do mapa, fundo roxo e texto e ícone claros.

**Acceptance Scenarios**:

1. **Given** o motorista em "Deslocando-se até o passageiro", **When** o mapa é exibido, **Then** o botão
   "Cancelar corrida" aparece com fundo roxo da identidade visual e texto e ícone brancos.
2. **Given** o motorista em "Em corrida", **When** o mapa é exibido, **Then** o botão tem a mesma
   aparência.
3. **Given** o botão em roxo, **When** é tocado, **Then** abre a mesma confirmação de antes; nada além
   da cor mudou.

---

### User Story 2 - Botão de confirmação da modal igual ao do mapa (Priority: P2)

Como motorista, quero que o botão "Cancelar corrida" da confirmação tenha a mesma aparência do botão do
mapa, para reconhecer os dois como a mesma ação.

**Why this priority**: já está em roxo; o valor é garantir que os dois fiquem iguais e assim permaneçam.

**Independent Test**: abrir a confirmação e comparar a cor de fundo e de texto do botão "Cancelar
corrida" dela com as do botão do mapa.

**Acceptance Scenarios**:

1. **Given** a confirmação "Cancelar corrida?" aberta, **Then** o botão "Cancelar corrida" tem fundo roxo
   e texto branco, iguais aos do botão do mapa.
2. **Given** os dois botões visíveis em momentos diferentes, **Then** têm o mesmo fundo e a mesma cor de
   texto.

---

### Edge Cases

- Botão desabilitado: não há hoje situação em que um dos dois fique desabilitado; se ocorrer, vale o estilo
  de desabilitado das ações primárias do app.
- Tema escuro ou claro do aparelho: a cor do botão não depende do tema do sistema (o roxo é fixo).
- Comportamento de duplo toque, publicação do aviso ao passageiro e encerramento local: inalterados.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: O botão "Cancelar corrida" do mapa MUST ter fundo roxo igual ao das demais ações primárias
  do app, em vez de vermelho de erro.
- **FR-002**: O texto e o ícone do botão do mapa MUST ter cor que contraste com o roxo, com razão mínima
  de 4,5:1 (texto branco sobre o roxo da identidade visual).
- **FR-003**: O botão "Cancelar corrida" da confirmação MUST manter fundo roxo e texto claro, e MUST ter
  exatamente a mesma cor de fundo e de texto do botão do mapa.
- **FR-004**: Todo botão do app do motorista que efetiva o cancelamento de uma corrida MUST seguir
  FR-001 a FR-003 (hoje: os dois citados; um botão futuro com essa função MUST seguir o mesmo).
- **FR-005**: Posição, tamanho, forma (largura total, altura 48, cantos arredondados), rótulo, ícone e
  chave de teste do botão do mapa MUST permanecer como estão; só as cores mudam.
- **FR-006**: Nenhum comportamento MUST mudar: quando o botão aparece, o que o toque faz, o que é
  publicado ao passageiro, o estado local e o que é persistido.
- **FR-007**: A mudança MUST ser precedida da emenda das duas constituições espelho que troca o
  componente "Botão de ação destrutiva" para o novo visual (Princípio IV e Governance).

### Key Entities

Nenhuma: a feature não cria nem altera dados.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Em 100 % das exibições do botão do mapa (nos dois estados em que ele aparece), o fundo é o
  roxo da identidade visual e o texto e o ícone são brancos.
- **SC-002**: A razão de contraste entre texto e fundo do botão é de pelo menos 4,5:1 (a combinação
  branco sobre o roxo da identidade visual dá cerca de 6:1).
- **SC-003**: Os dois botões de cancelamento têm cores idênticas de fundo e de texto, verificado por teste
  automatizado.
- **SC-004**: Nenhum teste de comportamento do cancelamento (guardas, publicação, encerramento local,
  confirmação) precisa de alteração além da cor esperada.
- **SC-005**: As duas constituições espelho têm o componente emendado com texto idêntico (conferido por
  diff) antes de o código mudar.

## Assumptions

- "Roxo" é o roxo da identidade visual já usado nas ações primárias; o pedido o descreve como a aparência
  de botões que já existem.
- "Cor de fonte que contrasta" é o branco, igual ao das ações primárias existentes.
- Sem mudança de contrato de eventos, sem contrapartida obrigatória no passageiro por contrato; o
  passageiro tem botões equivalentes e será tratado em feature própria dentro de `passenger/`, para as
  duas apps ficarem iguais (a mesma experiência vista de lados opostos, segundo a constituição).
- O botão "Voltar" da confirmação não cancela corrida e não é alterado.
- Sem alvo Android disponível garantido na sessão: a validação em aparelho pode ficar pendente, como em
  features anteriores; os testes de widget cobrem as cores.
