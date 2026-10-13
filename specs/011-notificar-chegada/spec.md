# Feature Specification: Notificar chegada ao passageiro

> **Atualização (2026-10-12, emenda 21 do contrato):** o raio de chegada passou de 10 m para **30 m**
> (`_raioDeChegadaMetros` em `driver/lib/screens/map_screen.dart`): em teste ponta a ponta o motorista, a ~22 m,
> aparecia sobreposto ao passageiro no mapa (marcadores de 44 px) sem nunca avisar a chegada, e 10 m fica abaixo
> do erro típico de GPS real (5–15 m). Os "10 m" abaixo são o texto original desta feature, mantido como
> histórico.

**Feature Branch**: `011-notificar-chegada`

**Created**: 2026-09-21

**Status**: Draft

**Input**: User description: "Modifique o app do motorista de modo ele envie uma mensagem ao app do
passageiro quando estiver em uma raio de 10 metros do passageiro. Esta mensagem deve informar o
passageiro que o motorista chegou. Esta spec não contempla o que o app do passageiro fará com a
mensagem recebida."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Avisar automaticamente que chegou ao ponto de encontro (Priority: P1)

Como motorista a caminho do passageiro (estado "Deslocando-se até o passageiro", feature 010),
quando minha posição atual entra num raio de 10 metros do ponto onde o passageiro solicitou a
carona, quero que o app avise automaticamente o passageiro de que cheguei, sem que eu precise tocar
em nada.

**Why this priority**: é o pedido central da feature — sem essa notificação automática, não há
nada mais nesta spec.

**Independent Test**: com o motorista no estado "Deslocando-se até o passageiro" de uma corrida
específica, simular uma posição do motorista a menos de 10 metros do ponto de origem daquela
corrida e verificar que uma mensagem de chegada é enviada ao passageiro correspondente.

**Acceptance Scenarios**:

1. **Given** o motorista no estado "Deslocando-se até o passageiro", a mais de 10 metros do ponto
   de origem da corrida, **When** a posição do motorista se atualiza para um ponto a 10 metros ou
   menos daquele ponto de origem, **Then** uma mensagem de chegada é enviada ao passageiro daquela
   corrida.
2. **Given** a mensagem de chegada já foi enviada para a corrida ativa, **When** o motorista
   permanece dentro do raio de 10 metros por mais tempo, ou sai e volta a entrar nele, **Then**
   nenhuma mensagem de chegada adicional é enviada para a mesma corrida.
3. **Given** o motorista no estado "Aguardando solicitação de corrida" (nenhuma corrida ativa),
   **When** a posição do motorista se atualiza, **Then** nenhuma mensagem de chegada é enviada,
   independentemente da distância até qualquer ponto.

---

### Edge Cases

- O que acontece se o motorista já estiver a 10 metros ou menos do ponto de origem no instante em
  que a corrida começa (transição para "Deslocando-se até o passageiro")? A checagem de
  proximidade vale desde a primeira posição recebida nesse estado — não exige que o motorista
  primeiro se afaste e depois se aproxime.
- O que acontece se a posição do motorista não estiver disponível (permissão negada ou GPS
  indisponível) enquanto ele está "Deslocando-se até o passageiro"? Nenhuma mensagem de chegada é
  enviada enquanto a posição não estiver disponível — mesma postura já adotada pela publicação de
  localização da feature 010.
- O que acontece se não houver conexão com nenhum relay no instante em que o motorista entra no
  raio de 10 metros? A mensagem de chegada não é reenviada automaticamente depois — mesma postura
  de melhor esforço já adotada pelos demais eventos automáticos da feature 010 (localização e aviso
  de corrida indisponível), já que não há ação do motorista para repetir nem mensagem de erro a
  exibir para uma notificação automática.
- O que acontece se o motorista sair do estado "Deslocando-se até o passageiro" e entrar em uma
  nova corrida (trabalho de uma feature futura, fora de escopo aqui)? A nova corrida passa a ter
  sua própria checagem de proximidade, independente de uma mensagem de chegada já enviada para uma
  corrida anterior.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: O app MUST verificar, a cada atualização de posição do motorista enquanto ele
  estiver no estado "Deslocando-se até o passageiro" (feature 010), se essa posição está a 10
  metros ou menos do ponto de origem informado na solicitação de carona que originou a corrida
  ativa.
- **FR-002**: O app MUST enviar uma mensagem de chegada ao passageiro da corrida ativa na primeira
  vez que a posição do motorista entrar nesse raio de 10 metros.
- **FR-003**: O app MUST NOT enviar mais de uma mensagem de chegada para a mesma corrida ativa,
  mesmo que o motorista permaneça dentro do raio, ou saia dele e volte a entrar.
- **FR-004**: O app MUST NOT enviar mensagem de chegada enquanto o motorista estiver no estado
  "Aguardando solicitação de corrida" (sem corrida ativa, sem ponto de referência do passageiro).
- **FR-005**: A mensagem de chegada MUST informar apenas que o motorista chegou — nenhum outro
  dado além do necessário para o passageiro identificar a qual corrida ela se refere.
- **FR-006**: O app MUST permitir que uma corrida ativa futura, distinta da corrida em que a
  mensagem de chegada já foi enviada, tenha sua própria mensagem de chegada — a restrição de
  FR-003 vale por corrida, não pela vida inteira do aplicativo.

### Key Entities

- **Notificação de chegada**: representa o aviso automático de que o motorista chegou ao ponto de
  origem da corrida ativa; não carrega estado próprio além de "já foi enviada para esta corrida" —
  controlado pela mesma corrida ativa já rastreada pela feature 010, não uma entidade nova
  persistida à parte.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% das vezes em que a posição do motorista cruza o raio de 10 metros do ponto de
  origem de uma corrida ativa, uma mensagem de chegada é enviada em até 1 segundo dessa
  atualização de posição.
- **SC-002**: Nenhuma corrida ativa gera mais de uma mensagem de chegada, independentemente de
  quanto tempo o motorista permanece nas proximidades do ponto de origem.
- **SC-003**: Nenhuma mensagem de chegada é enviada antes de a posição do motorista efetivamente
  cruzar o raio de 10 metros.

## Assumptions

- O "ponto onde o passageiro solicitou a carona" é a coordenada de origem (`origin`) já recebida
  no evento de solicitação de carona (`kind: 20001`, contrato do protótipo) que deu origem ao
  orçamento aceito — este protótipo não tem, e esta feature não introduz, nenhum mecanismo de
  posição ao vivo do passageiro; a única posição do passageiro conhecida pelo motorista é a que
  ele informou no instante da solicitação.
- A checagem de proximidade dos 10 metros roda a cada posição recebida do motorista, independente
  de qualquer limiar de distância usado para outros fins (como a publicação periódica de
  localização da feature 010, que usa um limiar de 50 metros com outro propósito) — os 10 metros
  desta feature são um raio de chegada, não uma frequência de publicação.
- O envio da mensagem de chegada é melhor esforço (mesma postura da feature 010 para localização e
  aviso de corrida indisponível): não há re-tentativa automática nem mensagem de erro exibida ao
  motorista se a publicação falhar, já que é um evento automático, sem ação do motorista para
  repetir.
- O que o app do passageiro faz ao receber a mensagem de chegada (exibir, notificar, etc.) é
  trabalho de uma feature futura, conforme já delimitado pelo pedido original.
- O que acontece depois da chegada — motorista recolhe o passageiro, corrida termina, retorno ao
  estado "Aguardando solicitação de corrida" — continua fora de escopo, mesma delimitação já
  registrada pela feature 010.
