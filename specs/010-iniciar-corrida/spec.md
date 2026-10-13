# Feature Specification: Iniciar corrida após aceitação e deslocamento até o passageiro

**Feature Branch**: `010-iniciar-corrida`

**Created**: 2026-09-21

**Status**: Draft

**Input**: User description: "Modifique o app do motorista. Quando o app receber a notificação de
aceitação do seu orçamento, deve exibir uma modal informando o motorista sobre isso. A modal
posuirá uma mensagem informativa e um botão iniciar corrida. Um clique no botão iniciar corrida
colocará o motorista no estado 'Deslocando-se até o passageiro' (informação que deve ser
persistida localmente). A criação deste estado exige que o fluxo de orçamentos seja modificado de
modo que o motorista só possa ver solicitações de orçamento se estiver no estado 'Aguardando
solicitação de corrida'. O envio de um orçamento não precisa mudar o estado do motorista. Durante
o estado 'Deslocando-se até o passageiro', o app deve mandar ao passageiro a localização atual do
motorista (não se preocupe com o processamento desta mensagem pelo do app do passageiro, por
enquanto). Na presente spec não trataremos sobre o que acontece quando o motorista recolhe o
passageiro ou sobre quando a corrida termina, estes são tópicos pra outra spec."

## Clarifications

### Session 2026-09-21 (decisões tomadas antes da especificação, na conversa que a originou)

- Q: Se o motorista já estiver no estado "Deslocando-se até o passageiro" e chegar uma aceitação
  (kind 20003) de outro orçamento seu, o que o app deve fazer? → A: publicar uma notificação ao
  passageiro informando que o motorista não pode mais aceitar aquela corrida — não apenas ignorar
  em silêncio, o passageiro que aceitou aquele orçamento precisa saber que ele não será atendido.
- Q: O que acontece com solicitações de corrida (kind 20001) já enfileiradas ou que cheguem depois
  da transição para "Deslocando-se", antes do fim desta corrida? → A: descartar a fila e parar de
  aceitar novas — nenhuma modal de solicitação é exibida enquanto o motorista não estiver de volta
  ao estado "Aguardando solicitação de corrida" (o retorno a esse estado é trabalho de uma feature
  futura, fora de escopo aqui).
- Q: Com que frequência/critério a localização deve ser publicada durante "Deslocando-se até o
  passageiro"? → A: a cada deslocamento mínimo de distância percorrida, mesmo padrão já usado pela
  feature 007 do passageiro para recalcular a rota (limite de 50 m, ver
  `passenger/specs/007-rota-ate-destino/research.md`, decisão D2) — reaproveitar o mesmo limiar
  evita depender do nível gratuito de um serviço de terceiro e mantém as duas apps consistentes
  sem introduzir um novo valor arbitrário.
- Q: Como a publicação de localização (User Story 3) interage com o status online/offline já
  existente (feature 004)? → A: a publicação de localização depende só do estado "Deslocando-se
  até o passageiro" — o toggle online/offline continua controlando apenas a exibição de novas
  solicitações de corrida (seu propósito já registrado), sem nenhum efeito sobre a publicação de
  localização nem sobre o próprio estado "Deslocando-se".

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Ser avisado que um orçamento foi aceito e iniciar a corrida (Priority: P1)

Como motorista que enviou um orçamento, quando o passageiro aceita minha proposta, quero ver
imediatamente uma modal me avisando disso, para então confirmar que vou até o passageiro tocando
em "Iniciar corrida".

**Why this priority**: é o gatilho de toda a feature — sem essa modal e sem a confirmação do
motorista, não existe transição de estado nem envio de localização.

**Independent Test**: com o motorista no estado "Aguardando solicitação de corrida" e um orçamento
já enviado, simular o recebimento de uma aceitação de orçamento (kind 20003) referenciando aquele
orçamento e verificar que a modal aparece com a mensagem informativa e o botão "Iniciar corrida".

**Acceptance Scenarios**:

1. **Given** o motorista no estado "Aguardando solicitação de corrida" com um orçamento enviado
   anteriormente, **When** chega a aceitação daquele orçamento, **Then** uma modal é exibida com
   uma mensagem informando que o orçamento foi aceito e um botão "Iniciar corrida".
2. **Given** a modal de aceitação exibida, **When** o motorista toca em "Iniciar corrida", **Then**
   o motorista passa para o estado "Deslocando-se até o passageiro", essa informação é persistida
   localmente (sobrevive ao fechar e reabrir o app) e a modal é fechada.
3. **Given** o motorista já reiniciou o app depois de tocar em "Iniciar corrida", **When** o app
   abre novamente, **Then** o motorista continua no estado "Deslocando-se até o passageiro", sem
   precisar confirmar de novo.

---

### User Story 2 - Deixar de ver novas solicitações de corrida fora do estado "Aguardando" (Priority: P1)

Como motorista que já iniciou uma corrida, não quero mais ser interrompido por modais de novas
solicitações de corrida enquanto estou a caminho do passageiro que já aceitei atender.

**Why this priority**: sem essa restrição, o motorista poderia enviar orçamentos e comprometer-se
com corridas simultâneas incompatíveis — é a mudança que justifica a criação do próprio estado.

**Independent Test**: com o motorista no estado "Deslocando-se até o passageiro", simular o
recebimento de uma nova solicitação de corrida (kind 20001) e verificar que nenhuma modal aparece;
repetir com o motorista de volta ao estado "Aguardando solicitação de corrida" e verificar que a
modal volta a aparecer normalmente.

**Acceptance Scenarios**:

1. **Given** o motorista no estado "Deslocando-se até o passageiro", **When** chega uma nova
   solicitação de corrida, **Then** nenhuma modal de solicitação é exibida e a solicitação não é
   enfileirada.
2. **Given** o motorista no estado "Deslocando-se até o passageiro" com solicitações já
   enfileiradas antes da transição, **When** a transição para esse estado ocorre, **Then** a fila
   de solicitações pendentes é descartada.
3. **Given** o motorista no estado "Aguardando solicitação de corrida", **When** chega uma nova
   solicitação de corrida, **Then** o comportamento existente (modal de solicitação) continua
   funcionando normalmente.
4. **Given** o motorista no estado "Deslocando-se até o passageiro", **When** ele envia um
   orçamento para uma solicitação (caso ainda hipoteticamente chegasse uma, ou remanescente de
   antes da transição), **Then** o envio de um orçamento nunca muda, por si só, o estado do
   motorista — a regra vale simetricamente em qualquer estado.

---

### User Story 3 - Compartilhar a localização atual com o passageiro durante o deslocamento (Priority: P2)

Como passageiro que aceitou um orçamento, quero que o app do motorista publique a localização
atual dele enquanto está a caminho, para que eu possa (em uma feature futura) acompanhar sua
aproximação.

**Why this priority**: depende da existência do estado "Deslocando-se até o passageiro" (User
Story 1), por isso vem depois; é priorizada acima da User Story 4 porque é a única parte desta
feature com efeito observável fora do app do motorista.

**Independent Test**: com o motorista no estado "Deslocando-se até o passageiro", simular
deslocamentos de posição do dispositivo e verificar que uma localização é publicada a cada
deslocamento mínimo percorrido, e que nenhuma localização é publicada fora desse estado.

**Acceptance Scenarios**:

1. **Given** o motorista no estado "Deslocando-se até o passageiro", **When** a posição do
   dispositivo muda o suficiente para ultrapassar o deslocamento mínimo configurado, **Then** a
   localização atual do motorista é publicada.
2. **Given** o motorista no estado "Deslocando-se até o passageiro", **When** a posição do
   dispositivo muda por um valor menor que o deslocamento mínimo configurado, **Then** nenhuma
   nova localização é publicada.
3. **Given** o motorista no estado "Aguardando solicitação de corrida" (fora do deslocamento),
   **When** a posição do dispositivo muda, **Then** nenhuma localização é publicada ao passageiro.
4. **Given** o app reiniciado enquanto o motorista está no estado "Deslocando-se até o
   passageiro" (User Story 1, cenário 3), **When** o app volta a rodar, **Then** a publicação de
   localização a cada deslocamento mínimo é retomada sem exigir nova confirmação do motorista.

---

### User Story 4 - Avisar o passageiro quando uma segunda aceitação não pode mais ser atendida (Priority: P3)

Como passageiro que aceitou um orçamento de um motorista que, nesse meio-tempo, já iniciou outra
corrida, quero ser avisado de que ele não pode mais me atender, para não ficar esperando por
alguém que não vai aparecer.

**Why this priority**: cobre uma condição de corrida entre duas aceitações quase simultâneas;
menos central que o fluxo principal, mas necessária para não deixar um passageiro sem resposta.

**Independent Test**: com o motorista já no estado "Deslocando-se até o passageiro", simular o
recebimento de uma segunda aceitação de orçamento (kind 20003) diferente da que originou o estado
atual e verificar que nenhuma modal de "Iniciar corrida" aparece e que uma notificação é publicada
ao passageiro daquela segunda aceitação, informando que a corrida não pode ser atendida.

**Acceptance Scenarios**:

1. **Given** o motorista no estado "Deslocando-se até o passageiro" (já comprometido com uma
   corrida), **When** chega uma aceitação de outro orçamento seu, **Then** nenhuma modal de
   "Iniciar corrida" é exibida para essa segunda aceitação.
2. **Given** a mesma situação do cenário 1, **Then** uma notificação é publicada ao passageiro
   daquela aceitação, informando que o motorista não pode mais atender à corrida.
3. **Given** o motorista no estado "Aguardando solicitação de corrida" (nenhuma corrida em
   andamento), **When** chega uma aceitação de orçamento, **Then** o comportamento descrito na
   User Story 1 ocorre normalmente (nenhuma notificação de recusa é publicada).

---

### Edge Cases

- O que acontece se chegar uma aceitação de orçamento que não corresponde a nenhum orçamento
  enviado pelo motorista (referência desconhecida)? O evento é ignorado, sem modal nem
  notificação — mesma postura de robustez já usada para eventos malformados ou não reconhecidos
  nas features anteriores (contrato de eventos, regra de recepção 4).
- O que acontece se a mesma aceitação de orçamento chegar duplicada (reentrega por mais de um
  relay)? Deduplicar por `id` do evento antes de agir, mesma regra de recepção 2 já usada nas
  demais features.
- O que acontece se o motorista estiver offline (status da feature 004) quando uma aceitação
  chega? Sem conexão ativa aos relays não há recepção possível; ao voltar a ficar online, o
  comportamento normal de recepção se aplica a partir daquele momento — não há reentrega
  retroativa a cobrir aqui, mesma limitação já aceita para o kind 20001 (efêmero, não retido pelo
  relay).
- O que acontece se o motorista fechar o app com a modal de aceitação aberta, sem tocar em
  "Iniciar corrida"? Ao reabrir, o motorista permanece no estado "Aguardando solicitação de
  corrida" (a transição só ocorre com o toque no botão) e a modal não reaparece sozinha — mesmo
  padrão da modal de solicitação de corrida (feature 007), que também não é retomada sozinha após
  fechar o app.
- O que acontece se a localização do dispositivo não estiver disponível (permissão negada ou GPS
  indisponível) durante o estado "Deslocando-se até o passageiro"? Nenhuma localização é publicada
  enquanto a posição não estiver disponível; a transição de estado em si (User Story 1) não depende
  de posição disponível, só a publicação da User Story 3.
- O que acontece se o motorista alternar o status online/offline (feature 004) enquanto estiver no
  estado "Deslocando-se até o passageiro"? Nada muda na publicação de localização nem no estado
  "Deslocando-se" — o toggle continua afetando só a exibição de novas solicitações de corrida, que
  já estão bloqueadas nesse estado independentemente dele (FR-004).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: O app MUST exibir, ao receber uma aceitação de orçamento (evento referenciando um
  orçamento que o próprio motorista enviou) enquanto ele está no estado "Aguardando solicitação de
  corrida", uma modal com uma mensagem informativa avisando que o orçamento foi aceito e um botão
  "Iniciar corrida".
- **FR-002**: O app MUST transicionar o motorista para o estado "Deslocando-se até o passageiro"
  somente quando o motorista tocar no botão "Iniciar corrida" da modal — a chegada da aceitação,
  por si só, não muda o estado.
- **FR-003**: O app MUST persistir localmente o estado "Deslocando-se até o passageiro" de modo
  que ele sobreviva ao fechamento e reabertura do app, sem exigir nova confirmação do motorista.
- **FR-004**: O app MUST impedir a exibição de qualquer modal de nova solicitação de corrida
  (kind 20001) enquanto o motorista não estiver no estado "Aguardando solicitação de corrida".
- **FR-005**: O app MUST descartar, no momento da transição para "Deslocando-se até o passageiro",
  qualquer solicitação de corrida já enfileirada aguardando exibição de modal.
- **FR-006**: O envio de um orçamento (fluxo já existente da feature 007) MUST NOT, por si só,
  alterar o estado do motorista em nenhuma circunstância — o motorista pode enviar orçamentos tanto
  no estado "Aguardando solicitação de corrida" (caso normal) quanto, se algum ainda estiver em
  trânsito, durante "Deslocando-se até o passageiro", sem que isso afete o estado corrente.
- **FR-007**: O app MUST publicar a localização atual do motorista enquanto — e somente enquanto —
  ele estiver no estado "Deslocando-se até o passageiro", independentemente do status
  online/offline (feature 004): esse status continua controlando apenas a exibição de novas
  solicitações de corrida, sem efeito sobre a publicação de localização.
- **FR-008**: O app MUST publicar uma nova localização a cada deslocamento mínimo de 50 metros
  percorridos desde a última localização publicada, e MUST NOT publicar fora desse critério (nem a
  cada atualização bruta do GPS, nem em intervalo fixo de tempo).
- **FR-009**: O app MUST retomar a publicação de localização a cada deslocamento mínimo,
  automaticamente, ao reabrir o app enquanto o estado persistido ainda for "Deslocando-se até o
  passageiro" — sem exigir nova confirmação do motorista.
- **FR-010**: Ao receber uma aceitação de orçamento enquanto o motorista já estiver no estado
  "Deslocando-se até o passageiro" (comprometido com outra corrida), o app MUST NOT exibir a modal
  de "Iniciar corrida" para essa nova aceitação, e MUST publicar uma notificação ao passageiro que
  a enviou, informando que a corrida não pode mais ser atendida.
- **FR-011**: O app MUST ignorar, sem modal nem notificação, qualquer aceitação de orçamento que
  não corresponda a nenhum orçamento efetivamente enviado pelo motorista.
- **FR-012**: O app MUST deduplicar aceitações de orçamento pelo identificador do evento antes de
  agir sobre elas, evitando reação repetida à mesma aceitação entregue por mais de um relay.

### Key Entities

- **Estado do motorista**: valor local, persistido, que passa a assumir (nesta feature) um de dois
  valores possíveis — "Aguardando solicitação de corrida" (padrão, permite receber e responder
  solicitações) e "Deslocando-se até o passageiro" (assumido após confirmar o início de uma
  corrida aceita; bloqueia novas solicitações e ativa a publicação de localização). Vinculado ao
  motorista local, não a uma corrida específica em memória — não guarda, nesta feature, qual foi o
  orçamento/corrida aceito além do necessário para saber que uma corrida está em andamento.
- **Notificação de aceitação recebida**: representa o aviso de que um orçamento específico do
  motorista foi aceito pelo passageiro; a informação de origem já está no evento de aceitação
  recebido (não é uma nova entidade persistida além do próprio estado do motorista).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A partir da chegada de uma aceitação de orçamento válida, o motorista vê a modal de
  aviso em até 1 segundo (mesma ordem de grandeza de entrega já medida para outros eventos do
  protótipo).
- **SC-002**: 100% das transições para "Deslocando-se até o passageiro" sobrevivem a um reinício do
  app, sem exigir nova ação do motorista.
- **SC-003**: 100% das solicitações de corrida que chegam enquanto o motorista está em
  "Deslocando-se até o passageiro" não geram nenhuma modal visível.
- **SC-004**: Durante o estado "Deslocando-se até o passageiro", a localização publicada nunca
  fica desatualizada por mais de um deslocamento de 50 metros do motorista.
- **SC-005**: Um passageiro cujo orçamento aceito não pode mais ser atendido recebe a notificação
  de recusa em até 1 segundo após o motorista já estar comprometido com outra corrida.

## Assumptions

- O motorista só recebe aceitações de orçamento estando online e inscrito nos relays (mesma
  precondição já válida para receber solicitações de corrida, feature 007); não há mecanismo de
  reentrega retroativa para eventos efêmeros perdidos enquanto offline.
- O deslocamento mínimo de 50 metros para publicar localização reaproveita o mesmo limiar já usado
  pela feature 007 do passageiro para recalcular rota, por consistência entre as duas apps e para
  não introduzir um novo valor arbitrário sem justificativa própria.
- O formato do evento de localização e o formato da notificação de "corrida não pode mais ser
  atendida" (FR-007 a FR-010) são novos pontos de contrato entre as duas apps; nesta feature,
  apenas o lado do motorista (publicação) é implementado — a recepção e o tratamento desses eventos
  pelo app do passageiro ficam fora de escopo, mesmo padrão já usado para o consumo do kind 20001
  pelo motorista (feature 006 do passageiro) e do kind 20002 pelo passageiro (feature 007 do
  motorista): o contrato é escrito e replicado nos dois lados (Princípio IV das constituições), mas
  o consumo pelo outro lado é trabalho futuro.
- O retorno do motorista ao estado "Aguardando solicitação de corrida" (fim da corrida, ou algum
  outro gatilho) não é definido nesta feature — fica, junto com "recolher o passageiro" e
  "finalizar a corrida", para uma spec futura, conforme já delimitado pelo pedido original.
- A modal de aceitação de orçamento segue a mesma fila estritamente sequencial já usada para a
  modal de solicitação de corrida (feature 007), nunca duas modais simultâneas.
