# Feature Specification: Corrida cancelada pelo passageiro (motorista)

**Feature Branch**: `020-corrida-cancelada-pelo-passageiro` (sem branch git: trabalho direto na `master`)

**Created**: 2026-10-07

**Status**: Draft

**Input**: User description (pedido original, que também toca o app do passageiro — ver
Assumptions para a divisão de escopo): "Existe algum kind que avisa o motorista que o passageiro
cancelou a corrida? [Não existe.] Sim, monte isso." O contrato do novo kind, `20013` ("Corrida
cancelada pelo passageiro"), já foi definido pela emenda 19 do contrato de eventos; esta feature é
o lado do motorista: passar a receber o aviso, encerrar a corrida e informar o motorista.

## Clarifications

### Session 2026-10-07 (decisões tomadas antes da especificação, na conversa que a originou)

- Q: O pedido toca as duas apps (o passageiro cancela e publica; o motorista recebe, avisa e
  encerra). Como dividir em specs de spec-kit? → A: duas features, uma por app, mesmo padrão das
  features 018/019 (cancelamento pelo motorista) — esta (`driver`) cobre o que o motorista recebe e
  faz; a contrapartida do passageiro (botão, confirmação, publicação) é `023-cancelar-corrida-passageiro`,
  especificada em seguida dentro de `passenger/`.
- Q: Quem define o formato do evento? → A: o motorista, na emenda 19 do contrato, já commitada e
  replicada nas duas cópias antes do código (Princípio IV). O motorista só consome o `20013`;
  mesmo precedente do `kind: 20005`/`20008`, em que quem define não é necessariamente quem publica.
- Q: Em quais estados do motorista o aviso vale? → A: "Deslocando-se até o passageiro" e "Em
  corrida" — os mesmos estados em que o motorista pode cancelar (feature 018). Em "Aguardando
  solicitação de corrida" não há corrida a encerrar e o aviso é ignorado.
- Q: O motorista deve ser informado ou só voltar ao repouso em silêncio? → A: informado, por modal
  simples com "OK": voltar sozinho ao repouso deixaria o motorista sem entender por que a rota e o
  marcador sumiram.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Ser avisado de que o passageiro cancelou a caminho dele (Priority: P1)

Como motorista no estado "Deslocando-se até o passageiro", quero ser avisado imediatamente quando o
passageiro cancela a corrida, para parar de me deslocar e voltar a receber solicitações.

**Why this priority**: hoje o motorista só descobre o sumiço do passageiro por falta de sinal — e o
app dele não tem relógio de silêncio —, então segue dirigindo até uma origem vazia.

**Independent Test**: com o motorista em "Deslocando-se até o passageiro", entregar um aviso de
cancelamento válido do passageiro da corrida e verificar que o estado volta a "Aguardando
solicitação de corrida", a corrida ativa é descartada, a publicação de localização cessa e uma modal
informa o cancelamento.

**Acceptance Scenarios**:

1. **Given** o motorista em "Deslocando-se até o passageiro", **When** chega um aviso de
   cancelamento válido do passageiro dessa corrida, **Then** o estado volta a "Aguardando
   solicitação de corrida", nenhuma corrida permanece ativa e uma modal "O passageiro cancelou a
   corrida" com botão "OK" é exibida.
2. **Given** a modal exibida, **When** o motorista toca em "OK", **Then** a modal fecha e nada mais
   acontece (nada é publicado).
3. **Given** o cancelamento processado, **When** novas posições chegam, **Then** nenhuma localização
   é publicada ao passageiro daquela corrida.

---

### User Story 2 - Ser avisado do cancelamento com a corrida em andamento (Priority: P1)

Como motorista no estado "Em corrida", quero o mesmo aviso e o mesmo encerramento quando o
passageiro cancela durante a viagem.

**Why this priority**: mesmo valor da US1 — sem isso, o motorista só encerraria "Em corrida" pela
confirmação de destino, que um passageiro que cancelou nunca vai enviar.

**Independent Test**: com o motorista "Em corrida", entregar o aviso válido e verificar o estado de
repouso, a corrida descartada, a rota e o marcador de destino removidos do mapa e a modal exibida.

**Acceptance Scenarios**:

1. **Given** o motorista "Em corrida", **When** chega o aviso válido, **Then** o estado volta a
   "Aguardando solicitação de corrida", a corrida é descartada e a modal é exibida.
2. **Given** o cancelamento processado, **When** o mapa é exibido, **Then** o marcador de destino e
   o trajeto da corrida cancelada não aparecem mais e nenhuma rota é publicada.
3. **Given** o cancelamento processado, **Then** a modal de avaliação **não** é aberta (a avaliação
   é só de corridas concluídas).

---

### User Story 3 - Só o aviso legítimo cancela, e só uma vez (Priority: P2)

Como motorista, quero que apenas o passageiro da minha corrida ativa consiga cancelá-la, e que um
aviso repetido não tenha efeito.

**Why this priority**: o relay é público e a tag de referência é visível a todos; sem conferir
autoria e correlação, qualquer um poderia derrubar a corrida de um motorista.

**Independent Test**: entregar avisos com autor errado, referência a outra corrida, tag de
destinatário de outro motorista, conteúdo que não decifra para `{}`, em claro, e em "Aguardando", e
verificar que nenhum altera o estado nem abre modal; entregar o mesmo aviso válido duas vezes e
verificar um único efeito.

**Acceptance Scenarios**:

1. **Given** uma corrida ativa, **When** chega um aviso assinado por outra chave que não a do
   passageiro da corrida, **Then** é ignorado, sem efeito.
2. **Given** uma corrida ativa, **When** o aviso referencia o orçamento de outra corrida, **Then** é
   ignorado, sem efeito.
3. **Given** o motorista em "Aguardando solicitação de corrida", **When** chega qualquer aviso de
   cancelamento, **Then** é ignorado, sem modal.
4. **Given** um aviso válido já processado, **When** o mesmo evento é reentregue, **Then** não
   reabre a modal nem altera nada.
5. **Given** um aviso cujo `content` não decifra para o marcador `{}` (ou veio em claro), **When**
   chega, **Then** é descartado em silêncio.

---

### User Story 4 - O cancelamento sobrevive a reinício e não vaza para outras corridas (Priority: P2)

Como motorista, quero que o encerramento seja definitivo e valha só para a corrida cancelada.

**Independent Test**: processar o aviso, reiniciar o app e verificar o repouso sem corrida ativa; em
seguida aceitar e iniciar outra corrida e verificar que segue normalmente.

**Acceptance Scenarios**:

1. **Given** uma corrida cancelada pelo passageiro, **When** o app é reiniciado, **Then** reabre em
   "Aguardando solicitação de corrida", sem corrida ativa.
2. **Given** uma corrida cancelada, **When** chega uma confirmação de encontro ou de destino atrasada
   daquela corrida, **Then** é ignorada, sem mudança de estado.
3. **Given** o cancelamento processado, **When** o motorista inicia uma nova corrida com outro
   passageiro, **Then** o aviso anterior não afeta a nova corrida.

---

### Edge Cases

- Aviso recebido em "Aguardando solicitação de corrida" (corrida já encerrada por outro caminho,
  por exemplo conclusão ou cancelamento do próprio motorista): ignorado.
- O motorista cancela no mesmo instante em que o passageiro cancela: vale o que chegar primeiro; o
  segundo encontra "Aguardando" e é ignorado, sem modal duplicada.
- O motorista está com a confirmação "Cancelar corrida?" (feature 018) aberta quando o aviso chega: o
  encerramento acontece no instante do recebimento e a confirmação é fechada, para não ficar sobre uma
  corrida que já não existe; a modal informativa é exibida no lugar. (Nesses dois estados não há outra
  modal possível: a "Orçamento aceito" já fechou ao iniciar a corrida e a fila de solicitações é descartada.)
- Aviso chega com o motorista offline: o status online/offline controla só a exibição de
  solicitações; o aviso vale mesmo assim.
- Aviso perdido (motorista sem relay no momento): o `20013` é efêmero e não é reentregue; consequência
  aceita, mesma da feature 019 do lado oposto.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: O app MUST passar a se inscrever em `kind: 20013` (emenda 19 do contrato), junto aos
  kinds que já consome, tanto na inscrição real ao relay quanto no filtro do `EventFeed`.
- **FR-002**: Um aviso de cancelamento só MUST ter efeito se, depois da verificação de assinatura,
  (a) a tag de destinatário for a chave deste motorista, (b) o `content` decifrar exatamente para o
  marcador `{}`, (c) o autor for o passageiro da corrida ativa, (d) a tag de referência for o
  orçamento aceito da corrida ativa e (e) o estado for "Deslocando-se até o passageiro" ou "Em
  corrida". Qualquer outro caso MUST ser descartado em silêncio, sem erro, sem modal e sem mudança
  de estado.
- **FR-003**: Aceito o aviso, o app MUST encerrar a corrida no instante do recebimento: voltar a
  "Aguardando solicitação de corrida" e descartar a corrida ativa (origem, destino e sinalizadores
  de notificação), persistindo isso de modo que sobreviva a um reinício.
- **FR-004**: Aceito o aviso, o app MUST cessar a publicação de localização e de rota da corrida
  encerrada e MUST remover do mapa o marcador e o trajeto dela.
- **FR-005**: Aceito o aviso, o app MUST exibir uma modal informativa ("O passageiro cancelou a
  corrida") com um botão "OK" que apenas a fecha.
- **FR-006**: O encerramento MUST NOT abrir a modal de avaliação e MUST NOT publicar nenhum evento.
- **FR-007**: Um mesmo aviso reentregue MUST NOT reabrir a modal nem repetir o efeito.
- **FR-008**: Depois do encerramento, o app MUST ignorar, sem erro nem mudança de estado,
  confirmações de encontro ou de destino da corrida encerrada.
- **FR-009**: Depois do encerramento, o motorista MUST voltar a poder receber e responder novas
  solicitações conforme o status online/offline que já tinha.
- **FR-010**: O formato do aviso é o da emenda 19 do contrato de eventos, já definido; esta feature
  MUST NOT alterá-lo nem acrescentar kind novo.

### Key Entities

- **Corrida ativa (existente)**: compromisso persistido do motorista com um passageiro (orçamento
  aceito, chave do passageiro, origem, destino, sinalizadores). Passa a poder ser encerrada também
  por aviso do passageiro, além da conclusão e do cancelamento do próprio motorista.
- **Aviso de cancelamento pelo passageiro (novo para o motorista, definido pelo contrato)**:
  mensagem efêmera, cifrada ao motorista, que identifica a corrida pelo orçamento aceito; não
  carrega motivo nem posição.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Em 100% dos avisos válidos recebidos nos dois estados cancelável, o motorista volta a
  "Aguardando solicitação de corrida" sem corrida ativa e vê a modal informativa em até 1 s do
  recebimento.
- **SC-002**: Em 0% dos avisos inválidos (autor, referência, destinatário, conteúdo ou estado
  errados) ocorre mudança de estado ou modal.
- **SC-003**: Em 100% dos reenvios do mesmo aviso, o efeito ocorre uma única vez.
- **SC-004**: Após o encerramento e um reinício do app, 100% das aberturas mostram o motorista sem
  corrida ativa e sem publicar localização.
- **SC-005**: Depois do encerramento, o motorista consegue aceitar e concluir uma nova corrida sem
  nenhuma interferência da cancelada.

## Assumptions

- Divisão de escopo: esta feature é só o lado do motorista; o botão "Cancelar corrida", a
  confirmação e a publicação do `20013` são a feature `023-cancelar-corrida-passageiro`, em
  `passenger/`. Para um teste ponta a ponta completo, as duas são necessárias.
- O kind, as tags e a cifra são os da emenda 19 (e da emenda 17): efêmero, `["t", marcador]`,
  `["e", <orçamento>]`, `["p", <motorista>]`, `content` cifrado com NIP-44 ao motorista, texto `{}`.
- A modal informativa segue o padrão visual das demais modais do app, apresentacional (mensagem +
  "OK"), como a que o passageiro mostra ao ser cancelado pelo motorista.
- Aviso perdido não é reenviado nem compensado (evento efêmero; sem relógio de silêncio no
  motorista, que fica como trabalho futuro).
- Dependência: reaproveita o estado persistido (`DriverRideStatus`/`ActiveRide`), a decifração de
  mensagens sem dado próprio (`{}`) e a inscrição por kinds já existentes.
