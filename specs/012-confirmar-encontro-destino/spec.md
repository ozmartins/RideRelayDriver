# Feature Specification: Confirmar encontro e notificar chegada ao destino

> **Atualização (2026-10-12, emenda 22 do contrato):** o raio de chegada ao destino passou de 5 m para **30 m**
> (`_raioDeChegadaAoDestinoMetros` em `driver/lib/screens/map_screen.dart`), pelo mesmo motivo da emenda 21: 5 m fica
> abaixo do erro típico de GPS real (5–15 m) e dos marcadores de 44 px, que parecem sobrepostos a ~22 m. Os "5 metros"
> abaixo são o texto original desta feature, mantido como histórico.
>
> **Atualização (2026-10-13, emenda 23 do contrato):** o raio subiu de 30 m para **1 km**, a pedido do autor: a busca de
> endereço (Photon) nem sempre localiza o destino com precisão, e o ponto gravado pode ficar a centenas de metros do
> local real. Os "30 m" e "5 metros" são histórico.

**Feature Branch**: `012-confirmar-encontro-destino`

**Created**: 2026-09-21

**Status**: Draft

**Input**: User description (pedido original, que também toca o app do passageiro — ver
Assumptions abaixo para a divisão de escopo): "Modifique o app do passageiro de modo que, quando
ele receber a mensagem informando que motorista chegou no ponto de partida da corrida, uma modal
seja exibida informando o passageiro sobre este fato. A modal deve possuir uma mensagem informativo
e um botão 'Confirmo que encontrei o motorista'. Quando este último botão for pressionado, uma
mensagem deve ser enviada ao app do motorista informando tal fato. quando o app do motorista
receber a mensagem, deve mudar o status do motorista para Em corrida'. Quando o veículo chegar a 5
metros do destino da corrida, o app do motorista deve enviar uma mensagem ao app do passageiro
informando tal fato. O app do passageiro deve exibir uma modal informativa que deve conter o botão
'Confirmo que chegamos ao destino'. quando este ultimo botão for pressionado, uma mensagem deve ser
enviada ao app do motorista. O app do motorista, então, deve mudar o status do motorista para o
estado inicial ('Aguardando solicitação de corrida', se não me engano)."

## Clarifications

### Session 2026-09-21 (decisões tomadas antes da especificação, na conversa que a originou)

- Q: O pedido descreve um fluxo que toca as duas apps de forma bidirecional (diferente de toda
  feature anterior, sempre "uma app publica, a outra fica de fora"). Como dividir em specs de
  spec-kit, já que cada app tem seu próprio diretório `specs/`? → A: duas features, uma por app —
  esta (`driver`) cobre o que o motorista publica e consome: recebe a confirmação de encontro
  (estado "Em corrida") e detecta/publica a chegada ao destino, recebendo depois a confirmação de
  destino (volta a "Aguardando solicitação de corrida"). A contrapartida do passageiro (consumir a
  chegada à origem — `kind: 20007`, já existente — com um botão de confirmação, e consumir a
  chegada ao destino desta feature com outro botão de confirmação) é uma segunda feature, do
  passageiro, especificada em seguida — mesmo padrão de divisão já usado por todas as features
  anteriores que tocam o contrato de eventos.
- Q: Esta feature introduz dois eventos novos que o motorista consome, publicados pelo passageiro
  (confirmação de encontro, confirmação de destino) — formato ainda inexistente no contrato. Quem
  define o formato, já que o publicador de cada um é o passageiro? → A: esta feature (motorista)
  define os três kinds novos do fluxo inteiro na mesma emenda (confirmação de encontro, chegada ao
  destino, confirmação de destino) — o motorista precisa entender a máquina de estados completa
  para implementar as duas transições dele, e a feature do passageiro, especificada em seguida,
  implementa a publicação/consumo do lado dele contra esse mesmo contrato já escrito. Nenhuma regra
  do Princípio IV exige que só o app publicador defina o formato de um kind (só exige que seja
  especificado antes do código e replicado na mesma alteração), e o projeto já tem precedente de um
  único evento definido numa feature e consumido só numa posterior (`kind: 20005`, definido pela
  feature 010 do motorista, consumido só pela feature 009 do passageiro).
- Q: De onde vem a coordenada de destino usada para a checagem dos 5 metros, já que `ActiveRide`
  hoje só guarda a origem? → A: mesmo mecanismo já usado para a origem (feature 011, D1): captada
  no momento do envio do orçamento (a partir de `RideRequestReceived.destination`, já disponível
  ali) e persistida junto do restante do estado da corrida ativa.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Passar a "Em corrida" ao saber que o passageiro encontrou o motorista (Priority: P1)

Como motorista que já avisou que chegou ao ponto de partida (feature 011), quando o passageiro
confirma que me encontrou, quero que o app mude meu status para "Em corrida", para refletir que a
corrida efetivamente começou.

**Why this priority**: sem essa transição, não há "Em corrida" nem, depois, checagem de chegada ao
destino — é o gatilho de todo o resto desta feature.

**Independent Test**: com o motorista no estado "Deslocando-se até o passageiro", simular o
recebimento da confirmação de encontro referenciando o orçamento aceito e verificar que o estado
muda para "Em corrida".

**Acceptance Scenarios**:

1. **Given** o motorista no estado "Deslocando-se até o passageiro", **When** chega a confirmação
   de encontro do passageiro daquela corrida, **Then** o estado muda para "Em corrida".
2. **Given** o motorista já em "Em corrida", **When** chega uma nova confirmação de encontro
   (reentrega ou duplicata), **Then** nada muda — o motorista permanece em "Em corrida".
3. **Given** o motorista no estado "Aguardando solicitação de corrida" (sem corrida ativa),
   **When** chega uma confirmação de encontro, **Then** é ignorada, sem mudança de estado.

---

### User Story 2 - Notificar automaticamente a chegada ao destino (Priority: P1)

Como motorista "Em corrida", quando meu veículo chega a 5 metros do destino da corrida, quero que
o app avise automaticamente o passageiro, sem que eu precise tocar em nada.

**Why this priority**: mesma centralidade das features 010/011 — é o próximo marco automático do
trajeto, e o gatilho da User Story 3.

**Independent Test**: com o motorista no estado "Em corrida" de uma corrida específica, simular uma
posição do motorista a 5 metros ou menos do destino daquela corrida e verificar que uma mensagem de
chegada ao destino é publicada ao passageiro correspondente, uma única vez.

**Acceptance Scenarios**:

1. **Given** o motorista "Em corrida", a mais de 5 metros do destino, **When** a posição do
   motorista se atualiza para um ponto a 5 metros ou menos do destino, **Then** uma mensagem de
   chegada ao destino é publicada ao passageiro daquela corrida.
2. **Given** a mensagem de chegada ao destino já foi publicada para a corrida ativa, **When** o
   motorista permanece dentro do raio, ou sai e volta a entrar, **Then** nenhuma mensagem adicional
   é publicada.
3. **Given** o motorista fora do estado "Em corrida" (aguardando, ou ainda deslocando-se até o
   passageiro), **When** a posição do motorista se atualiza, **Then** nenhuma mensagem de chegada
   ao destino é publicada, independentemente da distância.

---

### User Story 3 - Voltar a "Aguardando solicitação de corrida" ao saber que chegaram ao destino (Priority: P1)

Como motorista que avisou a chegada ao destino, quando o passageiro confirma que chegaram, quero
que o app volte ao estado inicial, liberando-me para receber novas solicitações de corrida.

**Why this priority**: fecha o ciclo completo desta feature e da feature 010 — sem isso, o
motorista ficaria "Em corrida" indefinidamente após terminar.

**Independent Test**: com o motorista "Em corrida" e a chegada ao destino já publicada, simular o
recebimento da confirmação de destino do passageiro e verificar que o estado volta a "Aguardando
solicitação de corrida", sem nenhuma corrida ativa.

**Acceptance Scenarios**:

1. **Given** o motorista "Em corrida", **When** chega a confirmação de destino do passageiro
   daquela corrida, **Then** o estado volta a "Aguardando solicitação de corrida" e a corrida deixa
   de estar ativa (mesma regra já estabelecida pela feature 010: nenhuma corrida ativa nesse
   estado).
2. **Given** o motorista já de volta a "Aguardando solicitação de corrida" (por uma confirmação já
   processada), **When** chega outra confirmação de destino (reentrega), **Then** nada muda.
3. **Given** o motorista de volta a "Aguardando solicitação de corrida", **When** uma nova
   solicitação de corrida chega, **Then** o comportamento normal (modal de solicitação, feature
   007) volta a funcionar — o motorista está livre para uma nova corrida.

---

### Edge Cases

- O que acontece se a confirmação de encontro chegar antes do motorista sequer ter publicado a
  chegada à origem (`kind: 20007`, feature 011)? Ainda assim é aceita normalmente, desde que
  referencie o orçamento da corrida ativa e o motorista esteja em "Deslocando-se até o
  passageiro" — o pedido original não condiciona uma coisa à outra, e a checagem de FR-001 já
  cobre o essencial (corrida ativa correta).
- O que acontece se o motorista já estiver a 5 metros ou menos do destino no instante em que entra
  em "Em corrida"? A checagem de proximidade vale desde a primeira posição recebida nesse estado —
  mesmo padrão já adotado pela feature 011 para a chegada à origem.
- O que acontece se a posição do motorista não estiver disponível enquanto "Em corrida"? Nenhuma
  mensagem de chegada ao destino é publicada enquanto a posição não estiver disponível — mesma
  postura já adotada pelas features 010/011.
- O que acontece se não houver relay conectado no instante em que a confirmação de encontro, a
  chegada ao destino ou a confirmação de destino deveriam ser processadas/publicadas? Recepção
  (confirmação de encontro, confirmação de destino) não depende de relay — só de já ter chegado;
  publicação (chegada ao destino) é melhor esforço, sem repetição automática — mesma postura já
  adotada pelas features 010/011 para os eventos automáticos delas.
- O que acontece se uma confirmação de encontro ou de destino chegar duplicada (reentrega por mais
  de um relay)? Deduplicada por `id` do evento antes de agir — mesma regra de recepção 2 do
  contrato já usada em toda feature anterior.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: O app MUST reconhecer uma confirmação de encontro recebida, referenciando o
  orçamento da corrida ativa, como o sinal para transicionar do estado "Deslocando-se até o
  passageiro" para "Em corrida".
- **FR-002**: O app MUST NOT agir sobre uma confirmação de encontro que não referencie a corrida
  ativa, ou que chegue fora do estado "Deslocando-se até o passageiro" (já em "Em corrida", ou
  "Aguardando solicitação de corrida").
- **FR-003**: O app MUST verificar, a cada atualização de posição do motorista enquanto ele
  estiver no estado "Em corrida", se essa posição está a 5 metros ou menos do destino da corrida
  ativa.
- **FR-004**: O app MUST publicar uma mensagem de chegada ao destino ao passageiro da corrida
  ativa na primeira vez que a posição do motorista entrar nesse raio de 5 metros.
- **FR-005**: O app MUST NOT publicar mais de uma mensagem de chegada ao destino para a mesma
  corrida ativa, mesmo que o motorista permaneça dentro do raio, ou saia dele e volte a entrar.
- **FR-006**: O app MUST NOT verificar proximidade do destino nem publicar chegada ao destino fora
  do estado "Em corrida".
- **FR-007**: O app MUST reconhecer uma confirmação de destino recebida, referenciando o orçamento
  da corrida ativa, como o sinal para transicionar do estado "Em corrida" de volta a "Aguardando
  solicitação de corrida", encerrando a corrida ativa.
- **FR-008**: O app MUST NOT agir sobre uma confirmação de destino que não referencie a corrida
  ativa, ou que chegue fora do estado "Em corrida".
- **FR-009**: O app MUST persistir o estado "Em corrida" e a corrida ativa correspondente, de
  forma que sobrevivam ao fechamento do app — mesma garantia já dada aos demais estados da corrida
  (feature 010).
- **FR-010**: O app MUST persistir a coordenada de destino da corrida ativa, capturada no momento
  do envio do orçamento, para permitir a checagem de FR-003 mesmo através de um reinício do app.
- **FR-011**: O app MUST persistir se a mensagem de chegada ao destino já foi publicada para a
  corrida ativa corrente, de forma que sobreviva a um reinício, para cumprir FR-005 mesmo assim.

### Key Entities

- **Estado "Em corrida"**: novo valor do estado do motorista (que hoje só assume "Aguardando
  solicitação de corrida" ou "Deslocando-se até o passageiro", feature 010) — assumido só por
  confirmação de encontro recebida (FR-001), até a confirmação de destino (FR-007) devolver o
  motorista a "Aguardando solicitação de corrida".
- **Corrida ativa (ampliada)**: ganha a coordenada de destino e a marca de "chegada ao destino já
  publicada", junto do que já existia desde as features 010/011 (orçamento, chave do passageiro,
  origem, marca de chegada à origem já publicada).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% das confirmações de encontro válidas (referenciando a corrida ativa, com o
  motorista em "Deslocando-se até o passageiro") resultam em "Em corrida" em até 1 segundo.
- **SC-002**: 100% das vezes em que a posição do motorista cruza o raio de 5 metros do destino
  durante "Em corrida", uma mensagem de chegada ao destino é publicada em até 1 segundo.
- **SC-003**: Nenhuma corrida ativa gera mais de uma mensagem de chegada ao destino.
- **SC-004**: 100% das confirmações de destino válidas resultam no motorista de volta a
  "Aguardando solicitação de corrida" em até 1 segundo.
- **SC-005**: Nenhuma mensagem de chegada ao destino é publicada antes da posição do motorista
  efetivamente cruzar o raio de 5 metros, nem fora do estado "Em corrida".

## Assumptions

- O pedido original descreve um fluxo bidirecional entre as duas apps; esta especificação cobre
  só o lado do motorista (transições de estado, checagem de proximidade do destino, publicação da
  chegada ao destino). O lado do passageiro (exibir as duas modais, publicar as duas confirmações)
  é uma feature separada, do passageiro, especificada em seguida — mesma divisão por app já
  praticada em todo o histórico deste protótipo.
- Os três eventos novos do fluxo (confirmação de encontro, chegada ao destino, confirmação de
  destino) são definidos nesta feature, mesmo os dois publicados pelo passageiro — precedente já
  existente no projeto (`kind: 20005`, definido pela feature 010 do motorista, consumido só por
  uma feature posterior do passageiro).
- A coordenada de destino é capturada no momento do envio do orçamento (a partir da solicitação
  respondida), mesmo mecanismo já usado para a origem desde a feature 011 — nenhuma posição "ao
  vivo" do destino existe neste protótipo, nem esta feature introduz uma.
- A publicação da localização periódica (`kind: 20005`, a cada 50 m, feature 010) continua
  normalmente durante "Em corrida" — nada neste pedido pede para pará-la, e o passageiro
  presumivelmente ainda se beneficia de acompanhar a posição do motorista até o destino.
- O que acontece durante "Em corrida" além do já descrito (ex.: o motorista poder receber novas
  solicitações enquanto leva o passageiro atual) continua sujeito às mesmas regras já
  estabelecidas pela feature 010 para "Deslocando-se até o passageiro" — nenhuma solicitação nova é
  aceita fora de "Aguardando solicitação de corrida", e "Em corrida" não é esse estado.
