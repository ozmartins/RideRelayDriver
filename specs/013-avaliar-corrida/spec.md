# Feature Specification: Avaliar corrida (motorista)

**Feature Branch**: `013-avaliar-corrida`

**Created**: 2026-09-23

**Status**: Draft

**Input**: User description: "Quando a corrida terminar, o motorista deve ver uma tela que lhe
permita avaliar a corrida com 1 a 5 estrelas. A avaliação fica salva no banco de dados local do
app do motorista. O uso posterior das avaliações persistidas está fora do escopo desta spec."

> Esta é a metade do motorista de um pedido que também se aplica ao passageiro — a contrapartida
> dele já foi especificada e implementada em `passenger/specs/011-avaliar-corrida/`, sem nenhum
> evento Nostr novo conectando as duas (ver Assumptions).

## Clarifications

### Session 2026-09-23

- Q: Se o motorista fechar o app antes de avaliar uma corrida, a tela de avaliação deve
  reaparecer na próxima abertura? → A: Não — a oportunidade de avaliar aquela corrida se perde;
  a tela não é reexibida depois que o app fecha sem a avaliação ter sido feita. (Mesma decisão já
  tomada para a contrapartida do passageiro, `passenger/specs/011-avaliar-corrida/spec.md`.)
- Q: A avaliação é obrigatória ou o motorista pode dispensá-la sem avaliar? → A: Opcional — a
  tela tem uma ação de fechar/pular sem selecionar nota nenhuma. (Mesma decisão do passageiro.)

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Avaliar a corrida ao final (Priority: P1)

Ao receber a confirmação de que o passageiro chegou ao destino, encerrando a corrida, o motorista
vê uma tela de avaliação da corrida que acabou de terminar, com cinco estrelas selecionáveis. Ele
toca na quarta estrela contando da esquerda, o que seleciona uma nota de 4, e confirma. A nota
fica registrada localmente no dispositivo do motorista, associada àquela corrida específica.

**Why this priority**: É o próprio pedido do usuário — sem isso, a corrida termina sem nenhum
registro de satisfação do motorista, e a feature não existe.

**Independent Test**: Pode ser testado de ponta a ponta simulando o fim de uma corrida (destino
confirmado pelo passageiro) e verificando que a tela de avaliação aparece, que tocar numa estrela
seleciona a nota correspondente e que, ao confirmar, a nota é persistida no banco local associada
ao identificador da corrida.

**Acceptance Scenarios**:

1. **Given** o motorista está com uma corrida ativa no estado "Em corrida", **When** a
   confirmação de destino do passageiro (que encerra a corrida) é recebida, **Then** a tela de
   avaliação da corrida é exibida, com cinco estrelas e nenhuma nota pré-selecionada.
2. **Given** a tela de avaliação está visível, **When** o motorista toca na estrela de posição N
   (1 a 5), **Then** as estrelas de 1 até N aparecem preenchidas/selecionadas e as demais não.
3. **Given** o motorista selecionou uma nota de 1 a 5, **When** ele confirma a avaliação,
   **Then** a nota é salva no banco de dados local do app associada à corrida encerrada, e a tela
   de avaliação é fechada.
4. **Given** a tela de avaliação está visível, **When** o motorista toca em fechar/pular sem
   selecionar nenhuma nota, **Then** a tela é fechada sem nenhuma nota persistida para aquela
   corrida, e a tela não volta a ser exibida para ela.

---

### Edge Cases

- Se o motorista fechar o aplicativo (ou o sistema encerrar o processo) antes de avaliar a
  corrida, a oportunidade de avaliar aquela corrida específica se perde — a tela de avaliação não
  reaparece numa próxima abertura do app.
- O motorista pode fechar a tela de avaliação sem escolher nenhuma nota (avaliação opcional) —
  ver User Story 1, cenário 4.
- O que acontece se o motorista tiver mais de uma corrida encerrada em sequência antes de avaliar
  a anterior? Assume-se que isso não ocorre no protótipo, já que o app só acompanha uma corrida
  ativa por vez (`ActiveRide`/`DriverRideStatus` existentes) — a tela de avaliação corresponde
  sempre à única corrida recém-encerrada.
- O que acontece se o motorista tentar avaliar a mesma corrida duas vezes (por exemplo, reabrindo
  a tela de alguma forma depois de já ter avaliado)? A avaliação já registrada não é sobrescrita;
  a tela de avaliação não é exibida de novo para uma corrida já avaliada.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: O sistema MUST exibir uma tela de avaliação da corrida imediatamente após o
  encerramento de uma corrida (confirmação de destino do passageiro recebida, transição de "Em
  corrida" de volta a "Aguardando solicitação de corrida").
- **FR-002**: A tela de avaliação MUST oferecer exatamente cinco estrelas selecionáveis,
  representando notas inteiras de 1 a 5.
- **FR-003**: Ao tocar na estrela de posição N, o sistema MUST marcar como selecionadas todas as
  estrelas de 1 até N e nenhuma das demais.
- **FR-004**: Ao confirmar uma nota escolhida, o sistema MUST persistir a nota (um número inteiro
  de 1 a 5) no banco de dados local do app, associada à corrida encerrada que a originou.
- **FR-005**: A avaliação MUST ficar salva exclusivamente no banco de dados local do app do
  motorista — não é publicada como evento Nostr nem enviada ao app do passageiro.
- **FR-006**: O sistema MUST impedir que a mesma corrida seja avaliada mais de uma vez (uma
  corrida já avaliada não volta a exibir a tela de avaliação).
- **FR-007**: O uso posterior das avaliações persistidas (exibição, agregação, envio, etc.) está
  fora do escopo desta feature — esta spec cobre somente a captura e o armazenamento local da
  nota.
- **FR-008**: A tela de avaliação MUST oferecer uma ação de fechar/pular sem selecionar nenhuma
  nota; nesse caso, nenhuma nota é persistida para aquela corrida.
- **FR-009**: O sistema MUST NOT reexibir a tela de avaliação de uma corrida depois que o app é
  fechado sem ela ter sido avaliada (nem por nota escolhida, nem por pular) — a oportunidade de
  avaliar aquela corrida específica se perde.

### Key Entities *(include if feature involves data)*

- **RideRating**: representa a avaliação de uma corrida feita pelo motorista — identificador da
  corrida avaliada (mesma referência já usada para correlacionar a corrida ativa, o `quoteId` do
  orçamento aceito, `ActiveRide.quoteId`), nota de 1 a 5 e momento do registro. Existe no máximo
  uma por corrida. Estrutura conceitualmente idêntica à `RideRating` do passageiro
  (`passenger/specs/011-avaliar-corrida/data-model.md`), mas persistida separadamente, sem
  nenhuma relação de armazenamento entre as duas.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Depois de uma corrida encerrar, o motorista vê a tela de avaliação da corrida em
  até 2 segundos, sem precisar navegar manualmente até ela.
- **SC-002**: Em 100% das corridas em que o motorista seleciona uma nota e confirma, a nota
  correspondente é encontrada no banco de dados local do app imediatamente depois, associada à
  corrida correta.
- **SC-003**: Uma corrida já avaliada nunca volta a exibir a tela de avaliação para o motorista.

## Assumptions

- Não há campo de comentário/texto livre acompanhando a nota — só a nota numérica de 1 a 5, como
  descrito no pedido do usuário.
- O momento de "corrida encerrada" é o mesmo já estabelecido pelo fluxo existente: a confirmação
  de destino do passageiro recebida (`kind: 20010`), que hoje transiciona o motorista de volta a
  "Aguardando solicitação de corrida" e zera a corrida ativa (feature `012-confirmar-encontro-
  destino`).
- O motorista só tem uma corrida ativa por vez (já garantido pelo modelo existente,
  `ActiveRide`/`DriverRideStatus`), então não há ambiguidade sobre qual corrida está sendo
  avaliada quando a tela aparece.
- A tela de avaliação é local ao app do motorista — nenhum evento Nostr novo é definido por esta
  feature, e o contrato de eventos entre as duas apps não é tocado. A avaliação equivalente do
  passageiro é uma feature de spec-kit separada, já implementada em `passenger/specs/011-avaliar-
  corrida/`, sem depender desta.
