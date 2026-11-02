# Feature Specification: Chegada periódica à origem (motorista)

> **Atualização (2026-10-12, emenda 21 do contrato):** o raio de chegada passou de 10 m para **30 m**
> (`_raioDeChegadaMetros` em `driver/lib/screens/map_screen.dart`): em teste ponta a ponta o motorista, a ~22 m,
> aparecia sobreposto ao passageiro no mapa (marcadores de 44 px) sem nunca avisar a chegada, e 10 m fica abaixo
> do erro típico de GPS real (5–15 m). Os "10 m" abaixo são o texto original desta feature, mantido como
> histórico.

**Feature Branch**: `021-chegada-periodica` (sem branch git: trabalho direto na `master`)

**Created**: 2026-10-07

**Status**: Draft

**Input**: User description: "O kind 20005 é enviado a cada 5 segundos. Preciso que o kind 20007 seja
enviado a cada 5 segundos desde que o app esteja no estado 'Deslocando-se até o passageiro' e enquanto
ele ainda estiver no raio de 10 m da origem da corrida ativa."

## Clarifications

### Session 2026-10-07 (decisões tomadas antes da especificação, na conversa que a originou)

- Q: Isso muda o contrato? → A: sim, só a regra de publicação, não o formato: a emenda 20 do contrato
  (já commitada e replicada nas duas cópias, antes do código — Princípio IV) troca "uma única vez por
  corrida" por "a cada 5 s dentro do raio". O passageiro não muda de código (já ignora repetições; ganha
  só um teste de regressão).
- Q: O que acontece com a marca persistida de "chegada já avisada" (`arrivalNotified`, feature 011)? →
  A: deixa de ter função e é removida; um reinício do app dentro do raio volta a publicar na hora, que é o
  comportamento desejado.
- Q: Como contar os 5 s? → A: pelo instante de captura da posição, como o `kind: 20005` já faz
  (feature 010), não por um temporizador independente.
- Q: E a chegada ao destino (`kind: 20009`)? → A: fora de escopo — continua uma única vez.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Avisar repetidamente que cheguei à origem (Priority: P1)

Como motorista em "Deslocando-se até o passageiro" que chegou ao ponto de origem, quero que o aviso de
chegada seja repetido enquanto eu estiver ali, para que o passageiro o receba mesmo que tenha perdido o
primeiro (sem sinal, app fechado).

**Why this priority**: o aviso é efêmero e não é reentregue pelo relay; publicado uma só vez, perde-se se o
passageiro não estiver conectado naquele instante.

**Independent Test**: com o motorista nesse estado e a posição a até 10 m da origem, entregar posições
com instantes de captura espaçados e verificar que um aviso sai na primeira posição e depois um a cada 5 s.

**Acceptance Scenarios**:

1. **Given** o motorista em "Deslocando-se até o passageiro" fora do raio, **When** chega a primeira
   posição a até 10 m da origem, **Then** um aviso de chegada é publicado ao passageiro da corrida na hora.
2. **Given** um aviso acabou de ser publicado, **When** chegam posições dentro do raio capturadas há menos
   de 5 s da última publicação, **Then** nada é publicado.
3. **Given** o último aviso foi publicado há 5 s ou mais (pelo instante de captura), **When** chega uma
   posição dentro do raio, **Then** um novo aviso é publicado.
4. **Given** o motorista parado dentro do raio por 30 s, **Then** são publicados avisos a cada 5 s, um
   por intervalo (cerca de sete no total).

---

### User Story 2 - Parar de avisar quando deixa de valer (Priority: P1)

Como motorista, quero que o aviso pare quando eu saio do raio ou deixo o estado, para não anunciar uma
chegada que já não é verdade.

**Why this priority**: sem isso o aviso continuaria depois do embarque ou do cancelamento.

**Independent Test**: com avisos em curso, afastar a posição para mais de 10 m, e em outro cenário mudar o
estado (confirmação de encontro, cancelamento, conclusão), e verificar que nenhum aviso novo sai.

**Acceptance Scenarios**:

1. **Given** avisos em curso, **When** chega uma posição a mais de 10 m da origem, **Then** nenhum aviso é
   publicado, e ao voltar para dentro do raio os avisos retomam respeitando os 5 s desde o último.
2. **Given** avisos em curso, **When** o passageiro confirma o encontro e o motorista passa a "Em corrida",
   **Then** nenhum aviso de chegada à origem é publicado depois.
3. **Given** avisos em curso, **When** o motorista ou o passageiro cancela a corrida, **Then** nenhum aviso
   é publicado depois.
4. **Given** o motorista em "Aguardando solicitação de corrida" ou "Em corrida", **When** a posição está a
   até 10 m da origem de uma corrida anterior ou da atual, **Then** nenhum aviso de chegada à origem sai.

---

### User Story 3 - Sobrevive a reinício e a falhas (Priority: P2)

Como motorista, quero que o aviso retome sozinho depois de reabrir o app e que falhas de publicação não
travem nada.

**Independent Test**: reiniciar o app dentro do raio e verificar que o aviso volta na primeira posição; sem
relay conectado, verificar que nada é publicado e nada quebra.

**Acceptance Scenarios**:

1. **Given** o app reaberto em "Deslocando-se até o passageiro" dentro do raio, **When** chega a primeira
   posição, **Then** um aviso é publicado na hora.
2. **Given** nenhum relay conectado (ou identidade indisponível), **When** chega uma posição dentro do raio,
   **Then** nada é publicado, sem erro e sem reenvio posterior do que ficou para trás.

---

### Edge Cases

- Posições com instante de captura fora de ordem ou repetido: a diferença negativa ou zero em relação à
  última publicação não conta como 5 s (nada é publicado).
- Entrar e sair do raio em menos de 5 s: o relógio é o da última publicação, sem rajada ao voltar.
- Corrida nova depois de uma cancelada ou concluída: não herda o intervalo da anterior (primeira posição
  no raio publica na hora).
- A posição que mede 10,0 m exatos conta como dentro (≤ 10 m), como na feature 011.
- O passageiro recebe vários avisos iguais: o comportamento do lado dele é o da emenda 20 (a primeira
  chegada abre a tela; as demais não mudam nada).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Enquanto o estado for "Deslocando-se até o passageiro" e a posição recebida estiver a até 10 m
  da origem da corrida ativa, o app MUST publicar ao passageiro da corrida o aviso de chegada
  (`kind: 20007`) a cada 5 s.
- **FR-002**: A primeira publicação MUST ocorrer na primeira posição recebida dentro do raio, sem esperar
  intervalo; as seguintes, só quando o instante de captura da posição avançar 5 s ou mais em relação à
  última publicação.
- **FR-003**: O app MUST NOT publicar o aviso com a posição a mais de 10 m da origem, nem em qualquer estado
  que não seja "Deslocando-se até o passageiro".
- **FR-004**: O app MUST NOT guardar nem persistir marca de "chegada já avisada" para o aviso de chegada à
  origem; o intervalo é estado só em memória, que recomeça a cada corrida e a cada reinício.
- **FR-005**: Falha ao publicar (sem relay, sem identidade, falha de cifra, publicação recusada) MUST ser
  absorvida: sem erro visível, sem fila e sem reenvio.
- **FR-006**: Cada aviso MUST seguir o formato da emenda 19/17 do contrato sem alteração: tags de marcador,
  `["e", quoteId]` e `["p", passageiro]`, `content` cifrado ao passageiro com `{}`.
- **FR-007**: A chegada ao destino (`kind: 20009`) e a localização (`kind: 20005`) MUST NOT mudar.

### Key Entities

- **Corrida ativa (existente)**: deixa de carregar a marca de chegada à origem já avisada; continua com
  origem, destino e a marca da chegada ao destino.
- **Relógio do aviso de chegada (novo, só em memória)**: instante de captura da última posição que gerou
  um aviso, para espaçar as publicações em 5 s; zerado quando a corrida acaba.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Com o motorista parado dentro do raio por 30 s, são publicados avisos a cada 5 s: o primeiro
  na primeira posição e nenhum intervalo menor que 5 s entre dois avisos.
- **SC-002**: Em 100% das posições a mais de 10 m, ou fora de "Deslocando-se até o passageiro", nenhum aviso
  de chegada à origem é publicado.
- **SC-003**: Após o encontro confirmado ou o cancelamento, 0 avisos de chegada à origem são publicados.
- **SC-004**: Após reiniciar o app dentro do raio, o primeiro aviso sai na primeira posição recebida.
- **SC-005**: Uma falha de publicação não impede o próximo aviso, 5 s depois, de ser tentado.

## Assumptions

- A contagem dos 5 s usa o instante de captura da posição (como o `kind: 20005`); o fluxo de posições do app
  emite de modo contínuo, mesmo com o motorista parado (distância mínima zero).
- O passageiro já tolera repetições (emenda 20); esta feature não toca o app dele.
- Motorista e passageiro mantêm o raio de 10 m da feature 011; mudar o raio ou o intervalo fica fora de
  escopo.
- Esta feature **substitui** a regra "uma única vez por corrida" da feature 011; os artefatos da 011 ficam
  como histórico.
