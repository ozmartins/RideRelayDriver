# Feature Specification: Rota da corrida no mapa do motorista

**Feature Branch**: `016-rota-no-mapa` (trabalho direto na `master`; ver Padrão de Commits)

**Created**: 2026-09-30

**Status**: Draft

**Input**: User description: "Quando o app estiver no estado "Em corrida" ou "Deslocando-se ao passageiro", a rota deve ser tratada no mapa para que o motorista saiba qual caminho deve seguir."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Ver o caminho até o passageiro (Priority: P1)

Depois de iniciar a corrida, o motorista está em "Deslocando-se até o passageiro". Na tela do mapa ele
passa a ver, além da sua posição, o ponto de embarque (origem da solicitação) e o trajeto
rodoviário traçado entre a posição dele e esse ponto, para saber por onde seguir.

**Why this priority**: é o primeiro trecho da corrida e o que hoje deixa o motorista sem
orientação nenhuma dentro do app — ele só vê o próprio ponto no mapa.

**Independent Test**: com uma corrida ativa em "Deslocando-se até o passageiro" e posição
conhecida, abrir o mapa e confirmar que o trajeto até a origem e o marcador de embarque aparecem.

**Acceptance Scenarios**:

1. **Given** o estado "Deslocando-se até o passageiro" com posição válida, **When** o mapa é exibido,
   **Then** aparecem o marcador do ponto de embarque e o trajeto da posição atual até ele.
2. **Given** o mesmo estado, **When** o motorista se desloca o suficiente para a rota ficar
   desatualizada, **Then** o trajeto é recalculado a partir da nova posição.
3. **Given** o app é reiniciado durante esse estado, **When** o mapa reabre com posição válida,
   **Then** o trajeto volta a ser exibido sem nova ação do motorista.

---

### User Story 2 - Ver o caminho até o destino (Priority: P1)

Quando o passageiro confirma o encontro, o estado passa a "Em corrida". O mapa troca o trajeto:
agora mostra o destino da corrida e o caminho da posição atual do motorista até ele.

**Why this priority**: é o segundo trecho obrigatório do pedido; sem ele a orientação some
exatamente quando o passageiro já está no carro.

**Independent Test**: com uma corrida ativa em "Em corrida", abrir o mapa e confirmar que o
trajeto até o destino e o marcador de destino aparecem, e que o trajeto até a origem não.

**Acceptance Scenarios**:

1. **Given** a transição de "Deslocando-se até o passageiro" para "Em corrida", **When** a
   confirmação de encontro é processada, **Then** o trajeto e o marcador de embarque somem e
   surgem o trajeto e o marcador do destino.
2. **Given** "Em corrida", **When** o motorista avança, **Then** o trajeto restante é recalculado a
   partir da posição atual.

---

### User Story 3 - Mapa limpo fora da corrida (Priority: P2)

Fora desses dois estados (aguardando solicitação, corrida encerrada), nenhum trajeto nem marcador
de corrida é mostrado.

**Why this priority**: evita mostrar uma rota obsoleta; é complemento dos dois fluxos acima.

**Independent Test**: encerrar a corrida (confirmação de destino) e ver o mapa voltar a mostrar só a
posição do motorista.

**Acceptance Scenarios**:

1. **Given** uma corrida em andamento com trajeto exibido, **When** o destino é confirmado e o
   estado volta a "Aguardando solicitação de corrida", **Then** trajeto e marcadores somem.

---

### Edge Cases

- Serviço de rota indisponível (rede, chave ausente, limite excedido): o mapa continua útil, sem
  trajeto; o motorista vê o marcador do ponto-alvo e é informado de forma discreta de que a rota não
  pôde ser obtida. Nada bloqueia as demais ações da corrida (publicar localização, chegada,
  confirmações).
- Posição do motorista ainda indisponível: sem trajeto; ele aparece assim que a primeira posição
  válida chegar.
- Orçamento antigo sem coordenada de origem/destino persistida (corrida iniciada antes desta
  feature): sem trajeto, sem erro.
- Motorista parado ou com ruído de GPS: não gera uma nova consulta de rota a cada atualização de
  posição (respeita limite de requisições do nível gratuito do serviço).
- Posição já dentro do raio de chegada: o trajeto pode ser muito curto ou ausente; não é erro.
- Coordenada de origem/destino da corrida ausente ou zerada (corrida anterior às features 011/012):
  tratada como sem trajeto, sem consulta de rota.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Em "Deslocando-se até o passageiro", o mapa MUST exibir o ponto de embarque da corrida
  ativa e o trajeto rodoviário da posição atual do motorista até ele.
- **FR-002**: Em "Em corrida", o mapa MUST exibir o destino da corrida ativa e o trajeto rodoviário
  da posição atual até ele, e MUST deixar de exibir o ponto e o trajeto de embarque.
- **FR-003**: Em qualquer outro estado, o mapa MUST NOT exibir trajeto nem marcador de corrida.
- **FR-004**: O trajeto MUST ser recalculado ao mudar o trecho (transição de estado) e a cada 50 m
  de deslocamento, nunca a cada atualização de GPS (mesmo limiar da feature 007 do passageiro).
- **FR-005**: Falha na obtenção da rota MUST ser absorvida: sem trajeto, com aviso discreto, sem
  bloquear nenhuma outra ação nem a publicação de eventos da corrida.
- **FR-006**: O trajeto e os marcadores MUST ser restaurados após reinício do app durante a corrida,
  a partir do que `ActiveRide` já persiste; nenhum dado novo é persistido, e a resposta do serviço de
  rota fica só em memória (sessão).
- **FR-007**: Nenhum contrato de evento Nostr é criado ou alterado; nenhuma mudança no passageiro.
- **FR-008**: A chamada ao serviço de rota MUST usar HTTPS e enviar apenas as duas coordenadas, sem
  identificador do motorista, do passageiro ou da corrida (exceção de roteamento das Restrições de
  Segurança e Privacidade).
- **FR-009**: O estilo visual do trajeto e dos marcadores MUST seguir a seção Identidade Visual e
  Design da constituição, com o trajeto distinguível do mapa-base e dos marcadores.
- **FR-010**: Ao traçar o primeiro trajeto de um trecho (início da corrida ou troca de trecho), o
  mapa MUST enquadrar a posição atual e o ponto-alvo. Enquanto houver trajeto exibido, o mapa MUST
  NOT recentralizar sozinho na posição do motorista, para que o enquadramento não seja desfeito; o
  botão "Centralizar" existente devolve o foco ao motorista e volta a fazer o mapa segui-lo.
  Sem trajeto (fora dos dois estados, ou rota indisponível), o mapa segue o motorista como antes.

### Key Entities

- **Corrida ativa (`ActiveRide`, já existente)**: fornece coordenadas de origem e destino da corrida
  em andamento; nenhum atributo novo.
- **Trajeto**: sequência de pontos entre a posição atual e o ponto-alvo do trecho vigente; derivado,
  efêmero, só em memória.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Em 100 % das aberturas do mapa com corrida em "Deslocando-se até o passageiro" ou "Em
  corrida", posição válida e serviço de rota disponível, o trajeto do trecho correto aparece em até
  5 s.
- **SC-002**: Ao mudar de trecho (embarque → destino) ou encerrar a corrida, o mapa reflete o novo
  estado em até 2 s, sem sobra de trajeto do trecho anterior.
- **SC-003**: Com o serviço de rota indisponível, 100 % das demais ações da corrida (localização,
  chegada, confirmações) seguem funcionando.
- **SC-004**: Numa corrida de 10 km percorridos, o número de consultas de rota não passa de uma por
  50 m de deslocamento mais uma por mudança de trecho.
- **SC-005**: Um motorista, ao ver só a tela do mapa, consegue dizer para onde deve seguir (embarque
  ou destino) sem abrir outra tela.

## Assumptions

- O ponto-alvo de cada trecho já está em `ActiveRide` (origem desde a feature 011, destino desde a
  012); corridas anteriores a elas ficam sem trajeto (Edge Case).
- O cálculo de rota reutiliza o serviço e a chave de API já usados nas features 007/009 (ORS), agora
  também com a geometria do trajeto; a decisão de dependência vai para o `research.md`.
- A exceção de roteamento da constituição 2.9.0 cobre o caso (posição atual + origem/destino de
  solicitação recebida), sem exigir emenda; o `/speckit-plan` confirma isso.
- Navegação guiada por voz/curva a curva, reroteamento por desvio e estimativa de tempo na tela estão
  fora de escopo; é só traçado e marcadores.
- Mapa-base e tiles continuam os da feature 004; só o recentramento automático muda (FR-010).
- O status online/offline não altera esta exibição; vale em qualquer um deles.
