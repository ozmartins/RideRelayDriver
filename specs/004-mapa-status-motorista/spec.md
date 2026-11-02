# Feature Specification: Mapa e Status de Disponibilidade do Motorista

**Feature Branch**: `004-mapa-status-motorista`

**Created**: 2026-09-17

**Status**: Draft

**Input**: User description: "A tela inicial do app do motorista deve ser uma mapa. O mapa deve
corresponder ao local real onde o motorista está. O mapa deve possuir um indicador da posição do
motorista no mapa (um ponto colorido, um "pin", o icone de um carro ou outro indicador qualquer. Ainda
nesta tela, o motorista deve ter acesso a um botão que lhe permmita ficar online ou offline. Se ele
estiver online, o app o notificará sobre solicitações de corrida, caso contrário nada será notificado.
Observação: Não se preocupe com a notificação de solicitação de corrida agora, pois ela será tratada em
detalhes em outra spec."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Ver a própria posição no mapa ao abrir o aplicativo (Priority: P1)

Como motorista, quero que a tela inicial do aplicativo mostre um mapa centrado onde eu realmente estou,
com um indicador visual da minha posição, para saber de imediato que o aplicativo sabe onde eu estou
antes de decidir se vou ficar disponível para corridas.

**Why this priority**: é a pré-condição de tudo o mais nesta feature — sem mapa e sem posição não há
como avaliar se ficar online faz sentido, nem como uma corrida futura seria roteada até o motorista.

**Independent Test**: abrir o aplicativo com localização disponível e verificar que a tela inicial é um
mapa centrado na posição real do aparelho, com um indicador nela.

**Acceptance Scenarios**:

1. **Given** o aplicativo instalado, com permissão de localização concedida e localização disponível,
   **When** o motorista o abre, **Then** a tela inicial exibe um mapa centrado na posição atual do
   aparelho, com um indicador visual naquele ponto.
2. **Given** a tela de mapa aberta, **When** o motorista se desloca fisicamente, **Then** o indicador de
   posição acompanha o deslocamento em um intervalo perceptível como "tempo real", sem exigir ação
   manual para atualizar.
3. **Given** o aplicativo aberto pela primeira vez, **When** a permissão de localização ainda não foi
   concedida, **Then** o aplicativo solicita a permissão, explicando por que ela é necessária.
4. **Given** a permissão de localização negada, ou a localização indisponível por qualquer motivo,
   **When** o motorista está na tela de mapa, **Then** uma mensagem compreensível explica a situação, sem
   travar o aplicativo nem exibir erro técnico cru.

---

### User Story 2 - Ficar online ou offline (Priority: P1)

Como motorista, quero um botão na própria tela de mapa para alternar entre ficar online e offline, para
controlar quando posso ser notificado sobre solicitações de corrida.

**Why this priority**: é o outro elemento explicitamente pedido para a tela inicial, e é a condição que
vai decidir, em feature futura, se uma solicitação de corrida chega a ser notificada — sem ela, "ficar
disponível" não tem significado no aplicativo.

**Independent Test**: com o mapa exibido e localização disponível, tocar no botão de status e verificar
que ele alterna entre online e offline, com o estado atual sempre visível na tela.

**Acceptance Scenarios**:

1. **Given** o motorista offline, com localização disponível, **When** ele toca no botão de status,
   **Then** o aplicativo passa a exibi-lo como online.
2. **Given** o motorista online, **When** ele toca no botão de status, **Then** o aplicativo passa a
   exibi-lo como offline.
3. **Given** o motorista offline, **When** ele reabre o aplicativo depois de tê-lo encerrado
   completamente, **Then** o status volta a ser offline — nunca online sozinho.
4. **Given** o motorista online, **When** a localização deixa de estar disponível (permissão revogada,
   sinal perdido), **Then** o aplicativo o coloca offline automaticamente e explica o motivo.
5. **Given** a localização indisponível, **When** o motorista tenta ficar online, **Then** o aplicativo
   impede a ação e explica que precisa saber a posição dele primeiro.

### Edge Cases

- O que acontece se o motorista negar a permissão de localização permanentemente (opção "não perguntar
  de novo")? A mensagem de localização indisponível permanece, com uma indicação de como conceder a
  permissão pelas configurações do aparelho — o aplicativo não insiste com o pedido a cada abertura.
- O que acontece se o aplicativo for encerrado (pelo sistema ou pelo motorista) enquanto ele estiver
  online? Na reabertura, o status volta a ser offline (cenário 3 da US2) — o motorista precisa ficar
  online de novo deliberadamente a cada sessão.
- O que acontece com o indicador de posição se a localização ficar temporariamente imprecisa (sinal
  fraco)? O indicador continua na última posição conhecida; não há requisito nesta feature de exibir o
  grau de precisão.
- O que acontece se o motorista tocar no botão de status repetidamente e rápido? O estado exibido
  reflete sempre a última ação confirmada, sem permitir dois pedidos de mudança simultâneos que
  produzam um estado inconsistente.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: O aplicativo MUST exibir um mapa como tela inicial, centrado na posição real do
  aparelho.
- **FR-002**: O mapa MUST exibir um indicador visual da posição atual do motorista.
- **FR-003**: O indicador de posição MUST acompanhar a posição real do motorista conforme ela mude,
  sem exigir atualização manual.
- **FR-004**: O aplicativo MUST solicitar a permissão de localização ao motorista quando ela ainda não
  tiver sido concedida, explicando por que é necessária.
- **FR-005**: Se a permissão de localização for negada ou a localização estiver indisponível por
  qualquer motivo, o aplicativo MUST exibir uma mensagem compreensível na própria tela de mapa, sem
  travar nem exibir erro técnico cru.
- **FR-006**: A mesma tela do mapa MUST oferecer um controle para o motorista alternar entre os status
  "online" e "offline".
- **FR-007**: O status atual (online ou offline) MUST estar sempre visível nessa tela, de forma
  inequívoca.
- **FR-008**: O aplicativo MUST impedir o motorista de ficar online sem uma localização válida
  disponível, explicando o motivo.
- **FR-009**: Se a localização deixar de estar disponível enquanto o motorista estiver online, o
  aplicativo MUST colocá-lo offline automaticamente e explicar o motivo.
- **FR-010**: O status ao abrir o aplicativo MUST ser sempre offline, independentemente de qual status
  estava ativo no encerramento anterior.
- **FR-011**: Enquanto online, o aplicativo MUST estar em condições de notificar o motorista sobre
  solicitações de corrida; enquanto offline, o aplicativo MUST NOT exibir nenhuma notificação desse
  tipo. (O formato e o mecanismo da notificação em si são definidos em feature futura — esta feature
  cuida apenas de o status ligar ou desligar essa possibilidade.)

### Key Entities

- **Posição do motorista**: coordenadas geográficas atuais do aparelho. Existe apenas em memória,
  atualizada continuamente enquanto o aplicativo está em uso; não é persistida entre execuções nem
  enviada a nenhum relay ou servidor nesta feature.
- **Status de disponibilidade**: online ou offline. Controla se solicitações de corrida podem ser
  notificadas (mecanismo definido em feature futura). Não é persistido entre execuções — toda abertura
  do aplicativo começa offline (FR-010).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Com localização disponível, o motorista vê sua posição real marcada no mapa em até 5
  segundos após abrir o aplicativo, em 9 de 10 tentativas.
- **SC-002**: O indicador de posição reflete um deslocamento real do aparelho em até 10 segundos, em
  9 de 10 tentativas.
- **SC-003**: Alternar entre online e offline reflete o novo status na tela em até 1 segundo, em 100%
  das tentativas.
- **SC-004**: Em 100% das tentativas de ficar online sem localização disponível, o aplicativo impede a
  ação e explica o motivo, sem travar.
- **SC-005**: Em 100% das reaberturas do aplicativo, o status exibido é offline, independentemente do
  status anterior ao fechamento.
- **SC-006**: Perder a localização enquanto online resulta em status offline e em uma explicação
  visível, em 100% das tentativas, sem travamento.

## Assumptions

- A tela de mapa passa a ser a **aba inicial** da navegação do aplicativo. As abas já existentes
  (Eventos, Relays, Identidade, Cadastro) continuam acessíveis, deslocadas para as posições seguintes —
  nenhuma delas é removida; a descrição da feature pede uma nova tela inicial, não a eliminação das
  demais.
- O indicador de posição é um ponto ou ícone simples (a descrição admite qualquer um: ponto colorido,
  pin, ícone de carro); a escolha exata do visual é decisão de implementação, sem impacto no
  comportamento exigido.
- Não há requisito, nesta feature, de exibir precisão de localização, rota, distância ou qualquer outro
  dado além da posição atual e do status de disponibilidade.
- O status online/offline e a posição do motorista **não são publicados em nenhum evento Nostr** nesta
  feature — permanecem locais ao aparelho. Uma feature futura, a mesma que tratará a notificação de
  solicitações de corrida, é que decidirá se e como essas informações trafegam entre motorista e
  passageiro.
- Local e acesso à localização do aparelho: esta feature é a que justifica, perante a constituição
  (Restrições de Segurança e Privacidade), o acesso a esse dado sensível — coleta a posição geográfica
  atual, usa-a apenas para centrar o mapa, mostrar o indicador e como pré-condição para ficar online, e
  mantém-na só em memória, nunca persistida nem enviada a terceiros nesta etapa.
- "Tempo real" no indicador de posição (US1 cenário 2) é interpretado como a atualização contínua e
  automática já coberta, de forma mensurável, por SC-002 — não há exigência adicional de frequência
  além da ali definida.
