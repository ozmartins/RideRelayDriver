# Feature Specification: Publicar ao passageiro a rota da corrida

**Feature Branch**: `017-publicar-rota-ao-passageiro` (trabalho direto na `master`; ver Padrão de Commits)

**Created**: 2026-10-03

**Status**: Draft

**Input**: User description: "Metade do motorista de um pedido que também se aplica ao passageiro (contrapartida: feature própria do passageiro, no mesmo contrato). Pedido original do usuário: 'Quando o app do passageiro estiver no estado Em corrida, a rota até o destino deve ser traçada no mapa. O app do passageiro não deve calcular a rota, em vez disso, o app do motorista enviará ao passageiro a rota sempre que esta for calculada ou recalculada (isso só deve ser feito se o estado do app do motorista for igual a Em Corrida).' Escopo desta feature (motorista): definir o novo evento de contrato que carrega a geometria da rota até o destino e publicá-lo ao passageiro da corrida ativa a cada cálculo ou recálculo bem-sucedido do trecho até o destino (feature 016), somente em Em corrida; falha no cálculo não publica nada; reaproveitar o cálculo já existente, sem nova requisição ao serviço de rotas."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Passageiro recebe a rota até o destino (Priority: P1)

Com a corrida em "Em corrida", o app do motorista já calcula o trajeto da posição dele até o destino
para desenhá-lo no próprio mapa (feature 016). A cada vez que esse trajeto é calculado — a primeira
vez, ao entrar em "Em corrida", e depois a cada recálculo — o app o envia também ao passageiro da
corrida ativa, para que o app do passageiro possa traçá-lo sem precisar calcular nada.

**Why this priority**: é a única razão de ser da feature; sem o envio, a contrapartida do passageiro
não tem o que desenhar.

**Independent Test**: com uma corrida ativa em "Em corrida", posição válida e serviço de rota
disponível, observar que, junto do trajeto desenhado no mapa do motorista, um evento com esse mesmo
trajeto é publicado endereçado ao passageiro da corrida.

**Acceptance Scenarios**:

1. **Given** a transição para "Em corrida" e o primeiro trajeto até o destino calculado com
   sucesso, **When** o cálculo termina, **Then** o app publica ao passageiro da corrida ativa a
   rota recém-calculada.
2. **Given** "Em corrida" e um trajeto já enviado, **When** o motorista avança o suficiente para o
   trajeto ser recalculado com sucesso, **Then** a rota nova é publicada ao passageiro (substitui,
   do ponto de vista do passageiro, a anterior).
3. **Given** "Em corrida", **When** o trajeto é calculado, **Then** o app não faz nenhuma
   requisição ao serviço de rotas além da que já fazia para desenhar o próprio mapa.

---

### User Story 2 - Nada é enviado fora de "Em corrida" (Priority: P1)

O passageiro só deve receber rota enquanto a corrida está de fato em andamento. Em "Deslocando-se até
o passageiro" o app do motorista já calcula um trajeto (até o embarque), e em "Aguardando solicitação"
não há trajeto; nenhum dos dois é enviado.

**Why this priority**: é a regra explícita do pedido e evita que o passageiro receba o trajeto do
trecho errado (o do embarque) ou uma rota de uma corrida já encerrada.

**Independent Test**: em "Deslocando-se até o passageiro", com o trajeto até a origem calculado,
confirmar que nenhum evento de rota é publicado; confirmar o mesmo ao voltar a "Aguardando
solicitação".

**Acceptance Scenarios**:

1. **Given** "Deslocando-se até o passageiro" com o trajeto até o embarque calculado, **When** o
   cálculo termina, **Then** nada é publicado ao passageiro.
2. **Given** um cálculo do trecho até o destino ainda em andamento, **When** o estado deixa de ser
   "Em corrida" antes de a resposta chegar (destino confirmado), **Then** a resposta tardia não gera
   publicação.
3. **Given** "Aguardando solicitação de corrida", **When** qualquer evento ocorre, **Then** nenhuma
   rota é publicada.

---

### User Story 3 - Falha no cálculo não publica nada (Priority: P2)

Quando o serviço de rotas falha (rede, chave, limite), o motorista segue como já segue na feature
016: sem trajeto, com aviso discreto. O passageiro não recebe nenhum evento nesse caso; o que ele já
tinha recebido de uma rota anterior continua valendo até chegar outra.

**Why this priority**: preserva a regra de que só rotas bem-sucedidas são publicadas e evita eventos
vazios ou inválidos na rede.

**Independent Test**: simular falha do serviço de rotas em "Em corrida" e confirmar que nenhum
evento de rota é publicado e que as demais publicações (localização, chegada ao destino) seguem.

**Acceptance Scenarios**:

1. **Given** "Em corrida" e o serviço de rotas indisponível, **When** o recálculo falha, **Then**
   nenhum evento de rota é publicado e nenhuma outra ação da corrida é bloqueada.

---

### Edge Cases

- Nenhum relay confirma a publicação, ou o app está sem conexão no momento: a publicação segue a
  mesma postura de falha dos demais eventos da corrida (não bloqueia a corrida, sem fila de
  reenvio); a próxima rota calculada será publicada normalmente.
- Rota muito longa: o evento publicado MUST caber no que os relays aceitam; se a rota calculada for
  grande demais, o app a reduz mantendo o formato geral do trajeto, em vez de deixar de publicar.
- Reinício do app durante "Em corrida": o trajeto é recalculado ao reabrir o mapa (feature 016) e,
  por ser um cálculo bem-sucedido em "Em corrida", é publicado de novo ao passageiro.
- Corrida sem destino persistido (iniciada antes das features 011/012): nenhum trajeto é calculado,
  portanto nada é publicado.
- Resposta de cálculo de um trecho anterior chegando tarde (já descartada pela feature 016): não
  gera publicação.
- Dois cálculos seguidos com o mesmo resultado: cada cálculo bem-sucedido publica; não há
  deduplicação por conteúdo, pois cada evento é distinto na rede.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: O contrato de eventos MUST ganhar um novo kind, "Rota da corrida", definido por uma
  nova emenda em `specs/002-nostr-relay-connection/contracts/nostr-events.md` e replicada de forma
  idêntica na cópia do passageiro **na mesma alteração** (Princípio IV da constituição). O contrato
  é do motorista; o consumo e o desenho no mapa do passageiro ficam na feature dele.
- **FR-002**: O evento MUST ser endereçado ao passageiro da corrida ativa e MUST referenciar o
  orçamento aceito daquela corrida, com o mesmo par de referências (`e` para o orçamento, `p` para o
  passageiro) e o marcador do protótipo usados pelos demais kinds da corrida.
- **FR-003**: O conteúdo do evento MUST carregar a sequência ordenada de pontos (latitude/longitude)
  do trajeto da posição do motorista até o destino da corrida, no mesmo formato de graus decimais já
  usado pelos outros eventos, de modo que o passageiro consiga traçar a linha sem nenhum dado
  adicional.
- **FR-004**: O app MUST publicar o evento sempre que o trajeto até o destino for calculado com
  sucesso e o estado do motorista for "Em corrida" — tanto o primeiro cálculo, ao entrar nesse
  estado, quanto cada recálculo posterior.
- **FR-005**: O app MUST NOT publicar o evento em "Deslocando-se até o passageiro" nem em
  "Aguardando solicitação de corrida", e MUST NOT publicar se o estado mudou entre o início e o fim
  do cálculo.
- **FR-006**: O app MUST NOT publicar nada quando o cálculo do trajeto falha; as demais ações da
  corrida (publicação de localização, chegada ao destino, confirmações) MUST seguir inalteradas.
- **FR-007**: A publicação MUST reaproveitar o resultado do cálculo já feito pela feature 016 para
  desenhar o mapa do motorista; MUST NOT haver requisição adicional ao serviço de rotas por causa
  desta feature.
- **FR-008**: O evento MUST ser efêmero, sem criptografia, mesma postura dos demais kinds da corrida
  entre as duas partes (justificativa de privacidade registrada na emenda); o conteúdo não pode
  incluir nada além do trajeto e dos identificadores de correlação já usados pelos outros kinds.
- **FR-009**: O evento MUST ter tamanho limitado a um máximo definido na emenda, compatível com o
  que os relays padrão aceitam; um trajeto que exceda esse máximo MUST ser reduzido (menos pontos)
  antes de publicar, preservando o ponto inicial e o final.
- **FR-010**: O evento MUST ser assinado pela identidade do motorista, como os demais, e o app MUST
  usar o mesmo mecanismo de publicação, sem criar novo canal de comunicação.

### Key Entities

- **Rota da corrida** (evento): trajeto da posição do motorista, no instante do cálculo, até o
  destino da corrida; referencia o orçamento aceito e o passageiro. Efêmero, sem persistência no
  motorista.
- **Corrida ativa (`ActiveRide`, já existente)**: fornece o orçamento aceito e a identidade do
  passageiro para endereçar o evento; nenhum atributo novo.
- **Trajeto (`RouteTrace`, já existente, feature 016)**: fonte da sequência de pontos publicada.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Em 100 % dos cálculos bem-sucedidos do trajeto até o destino em "Em corrida", exatamente
  um evento de rota é publicado ao passageiro da corrida ativa.
- **SC-002**: Em 100 % dos cálculos em "Deslocando-se até o passageiro", em "Aguardando solicitação"
  ou com falha do serviço de rotas, zero eventos de rota são publicados.
- **SC-003**: O número de consultas ao serviço de rotas numa corrida é idêntico ao da feature 016 sem
  esta feature (zero consultas extras).
- **SC-004**: Em 100 % dos eventos de rota publicados, o tamanho fica dentro do máximo definido no
  contrato, mesmo para uma rota de 30 km.
- **SC-005**: Com o serviço de rotas ou os relays indisponíveis, 100 % das demais ações da corrida
  (localização, chegada, confirmações) seguem funcionando.

## Assumptions

- O trecho até o destino é o já calculado pela feature 016 em "Em corrida"; esta feature só passa a
  também publicar o resultado, sem mudar quando ele é calculado (troca de trecho e a cada 50 m).
- O desenho da rota no mapa do passageiro, a validação do conteúdo recebido e a decisão de qual rota
  vale (a mais nova por `created_at`) são da feature correspondente do passageiro; este contrato
  apenas lhe dá o que consumir.
- Não há reenvio nem fila: se uma publicação se perde, o passageiro continua com a última rota
  recebida até a próxima ser publicada (a próxima vem no recálculo seguinte, em até ~50 m).
- Sem publicação de "rota limpa" ao sair de "Em corrida": o fim da corrida já é conhecido pelo
  passageiro (ele mesmo publica a confirmação de destino), então ele descarta a rota por conta própria.
- A constituição (2.9.0) já cobre a chamada ao serviço de rotas da 016; esta feature não faz chamada
  nova, só publica o resultado em relay, sem exigir emenda de constituição (o `/speckit-plan` confirma).
- Publicar a geometria da rota ao passageiro não expõe nada que ele já não receba: a posição do
  motorista já é publicada a cada 5 s no `kind: 20005`.
