# Feature Specification: Cancelar corrida (motorista)

**Feature Branch**: `018-cancelar-corrida-motorista`

**Created**: 2026-10-04

**Status**: Draft

**Input**: User description (pedido original, que também toca o app do passageiro — ver
Assumptions para a divisão de escopo): "Modifique o app do motorista de modo que ele possa cancelar
uma corrida enquanto está se deslocando até o ponto de origem da corrida ou quando já está no meio
de uma corrida. O cancelamento deve ser notificado ao app do passageiro, que, por sua vez, deve
notificar o passageiro via modal e cancelar a corrida no app do passageiro."

## Clarifications

### Session 2026-10-04 (decisões tomadas antes da especificação, na conversa que a originou)

- Q: O pedido toca as duas apps (o motorista cancela e publica; o passageiro recebe, avisa e
  encerra). Como dividir em specs de spec-kit, já que cada app tem seu próprio `specs/`? → A: duas
  features, uma por app, mesmo padrão das features 012/010 (confirmar encontro e destino) — esta
  (`driver`) cobre o que o motorista faz e publica: o botão de cancelar, a volta ao repouso e o
  evento novo. A contrapartida do passageiro (consumir o evento, abrir a modal, encerrar a corrida
  dele) é uma segunda feature, do passageiro, especificada em seguida.
- Q: Quem define o formato do evento de cancelamento? → A: esta feature (motorista), numa emenda
  nova do contrato, replicada no passageiro na mesma alteração (Princípio IV). O motorista é o
  publicador, como nos `kind: 20005`/`20007`/`20009`.
- Q: O passageiro também poderá cancelar depois de aceitar o orçamento? → A: fora de escopo — o
  pedido é só do lado do motorista. Hoje o passageiro só cancela enquanto aguarda orçamentos
  (feature 015 dele).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Cancelar a corrida a caminho do passageiro (Priority: P1)

Como motorista no estado "Deslocando-se até o passageiro", quero poder cancelar a corrida (por
exemplo, por um imprevisto com o veículo), para não ficar preso a um compromisso que não vou
cumprir.

**Why this priority**: hoje o motorista não tem saída desse estado a não ser o passageiro confirmar
o encontro; sem cancelamento, um imprevisto o deixa bloqueado para novas solicitações.

**Independent Test**: com o motorista em "Deslocando-se até o passageiro", tocar em "Cancelar
corrida", confirmar, e verificar que o estado volta a "Aguardando solicitação de corrida", a
corrida ativa é descartada, a publicação de localização cessa e um aviso de cancelamento é
publicado ao passageiro daquela corrida.

**Acceptance Scenarios**:

1. **Given** o motorista em "Deslocando-se até o passageiro", **When** ele toca em "Cancelar
   corrida" e confirma, **Then** o estado volta a "Aguardando solicitação de corrida", nenhuma
   corrida permanece ativa e uma mensagem de cancelamento é publicada ao passageiro da corrida.
2. **Given** a modal de confirmação do cancelamento aberta, **When** o motorista escolhe desistir
   (voltar), **Then** nada muda: o estado e a corrida ativa permanecem, nada é publicado.
3. **Given** o motorista já cancelou, **When** novas posições chegam, **Then** nenhuma localização
   é publicada ao passageiro daquela corrida.

---

### User Story 2 - Cancelar a corrida em andamento (Priority: P1)

Como motorista no estado "Em corrida", quero poder cancelar a corrida (por exemplo, por pane ou
situação de risco), com os mesmos efeitos do cancelamento anterior.

**Why this priority**: mesmo valor da US1 — hoje a corrida em andamento só termina com a
confirmação de destino do passageiro.

**Independent Test**: com o motorista "Em corrida", cancelar e confirmar, e verificar que o estado
volta a "Aguardando solicitação de corrida", a corrida ativa é descartada, a localização e a rota
deixam de ser publicadas e o aviso de cancelamento é publicado ao passageiro.

**Acceptance Scenarios**:

1. **Given** o motorista "Em corrida", **When** ele cancela e confirma, **Then** o estado volta a
   "Aguardando solicitação de corrida", a corrida é descartada e o aviso é publicado ao passageiro.
2. **Given** o cancelamento concluído, **When** o mapa é exibido, **Then** o marcador de destino e
   o trajeto da corrida cancelada não aparecem mais.
3. **Given** a corrida cancelada, **When** o motorista volta ao repouso, **Then** a modal de
   avaliação da corrida **não** é aberta (a avaliação é só de corridas concluídas).

---

### User Story 3 - Cancelamento sobrevive a reinício e não vaza para outras corridas (Priority: P2)

Como motorista, quero que o cancelamento seja definitivo e valha só para a corrida cancelada.

**Why this priority**: protege contra estados inconsistentes (corrida "ressuscitando" ao reabrir o
app) e contra o aviso atingir a corrida errada.

**Independent Test**: cancelar, reiniciar o app e verificar que o estado persistido é "Aguardando
solicitação de corrida", sem corrida ativa; em seguida aceitar e iniciar outra corrida e verificar
que ela segue normalmente.

**Acceptance Scenarios**:

1. **Given** uma corrida cancelada, **When** o app é reiniciado, **Then** o motorista reabre em
   "Aguardando solicitação de corrida", sem corrida ativa.
2. **Given** uma corrida cancelada, **When** chega uma confirmação de encontro ou de destino
   daquela corrida (atrasada), **Then** é ignorada, sem mudança de estado.
3. **Given** o aviso de cancelamento publicado, **When** o motorista inicia uma nova corrida com
   outro passageiro, **Then** o aviso anterior não afeta a nova corrida.

---

### Edge Cases

- Fora dos estados "Deslocando-se até o passageiro" e "Em corrida" (isto é, em "Aguardando
  solicitação de corrida"), o botão de cancelar não é oferecido.
- Falha ao publicar o aviso (sem relay conectado): o cancelamento local prevalece — o motorista
  fica livre — e a falha é absorvida, sem fila nem reenvio (mesma decisão da feature 017). O
  passageiro pode não ser avisado nesse caso (ver Assumptions).
- Duplo toque em "Confirmar cancelamento": no máximo um aviso é publicado por corrida.
- Cancelar logo após o motorista ter notificado a chegada à origem ou ao destino: vale como
  qualquer cancelamento naquele estado.
- Aviso de cancelamento reentregue ou duplicado pelo relay, na ponta do passageiro: tratado na
  feature do passageiro; aqui o formato não carrega nada que torne um aviso repetido perigoso.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Nos estados "Deslocando-se até o passageiro" e "Em corrida", o app MUST oferecer ao
  motorista a ação "Cancelar corrida"; nos demais estados, MUST NOT oferecê-la.
- **FR-002**: Ao acionar "Cancelar corrida", o app MUST pedir confirmação explícita antes de
  efetivar, com opção de desistir sem efeito algum.
- **FR-003**: Ao confirmar, o app MUST voltar o estado do motorista a "Aguardando solicitação de
  corrida" e descartar a corrida ativa (inclusive o que ela guardava: origem, destino e
  sinalizadores de notificação), persistindo isso de modo que sobreviva a um reinício.
- **FR-004**: Ao confirmar, o app MUST publicar ao passageiro da corrida ativa um aviso de
  cancelamento, referenciando o orçamento aceito da corrida e endereçado à chave pública do
  passageiro (mesmo esquema de correlação dos eventos de corrida anteriores). Um único aviso por
  corrida.
- **FR-005**: Após o cancelamento, o app MUST cessar a publicação de localização e de rota da
  corrida cancelada e MUST remover do mapa o marcador e o trajeto dela.
- **FR-006**: O cancelamento MUST NOT abrir a modal de avaliação da corrida.
- **FR-007**: Depois do cancelamento, o app MUST ignorar, sem erro nem mudança de estado,
  confirmações de encontro ou de destino referentes à corrida cancelada.
- **FR-008**: Falha ao publicar o aviso MUST NOT impedir nem desfazer o cancelamento local.
- **FR-009**: O formato do aviso de cancelamento MUST ser definido numa emenda nova do contrato de
  eventos (evento efêmero, sem criptografia, tag de marcador do protótipo), antes do código e
  replicado na cópia do passageiro na mesma alteração (Princípio IV).
- **FR-010**: Depois de cancelar, o motorista MUST voltar a poder receber e responder novas
  solicitações de corrida conforme o status online/offline que já tinha.

### Key Entities

- **Corrida ativa (existente)**: compromisso persistido do motorista com um passageiro (orçamento
  aceito, origem, destino, sinalizadores de notificação). Passa a poder ser encerrada por
  cancelamento, além da conclusão normal.
- **Aviso de cancelamento (novo)**: mensagem efêmera do motorista ao passageiro, identificando a
  corrida pelo orçamento aceito; não carrega motivo nem posição.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Em 100% das tentativas nos dois estados cancelável, confirmar o cancelamento devolve
  o motorista a "Aguardando solicitação de corrida" em até 1 s, sem corrida ativa.
- **SC-002**: Em 100% dos cancelamentos com ao menos um relay conectado, exatamente um aviso é
  publicado ao passageiro da corrida correta e nenhum a outra corrida.
- **SC-003**: Em 0% dos casos o cancelamento é efetivado sem passar pela confirmação explícita.
- **SC-004**: Após o cancelamento e um reinício do app, 100% das aberturas mostram o motorista sem
  corrida ativa e sem publicar localização.
- **SC-005**: Depois de cancelar, o motorista consegue aceitar e concluir uma nova corrida sem
  nenhuma interferência da cancelada.

## Assumptions

- Divisão de escopo: esta feature é só o lado do motorista; a modal do passageiro e o encerramento
  da corrida no app dele são a feature irmã em `passenger/`, especificada em seguida.
- O kind do aviso é o próximo livre do contrato (`20012`), evento efêmero publicado pelo motorista
  — detalhe fixado no plano.
- O aviso não leva motivo do cancelamento: o pedido não o menciona e o formato fica mínimo, como
  `20007`/`20010`.
- Sem fila nem reenvio em falha de publicação (mesma decisão da feature 017). Consequência aceita:
  sem relay no momento, o passageiro pode não ser avisado; tratar isso (por exemplo, expiração por
  silêncio) é trabalho futuro.
- A confirmação do cancelamento é uma modal simples (mensagem + "Cancelar corrida" /
  "Voltar"), no padrão visual das demais modais do app.
- Só o motorista cancela depois do orçamento aceito; cancelamento pelo passageiro nesses estados
  está fora de escopo.
- Dependência: reaproveita o estado persistido (`DriverRideStatus`/`ActiveRide`), a assinatura de
  eventos de corrida e a publicação por relay já existentes.
