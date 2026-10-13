# Feature Specification: Receber solicitação de corrida e enviar orçamento

**Feature Branch**: `007-receber-solicitacao-corrida`

**Created**: 2026-09-20

**Status**: Draft

**Input**: User description: "Modifique o app do motorista. Quando ele receber uma mensagem que
representa uma solicitação de corrida, uma modal deve ser exibida. Nesta modal devem constar o
ponto de inicio da corrida, o ponto de destino da corrida, a distância até o ponto de início, a
distância entre origem e destino, o preço por quilometro (que pode ser editado) e o total da
corrida (distância x preço por quilometro). A tela modal também deve exibir os botões 'Enviar
orçamento' e 'Recusar corrida'."

## Clarifications

### Session 2026-09-20 (decisões tomadas antes da especificação, na conversa que a originou)

- Q: A modal deve aparecer para qualquer solicitação recebida, ou só quando o motorista estiver
  online? → A: só quando o motorista estiver online (status da feature 004-mapa-status-motorista) —
  coerente com o propósito já registrado desse status ("decidir se solicitações de corrida são
  notificadas").
- Q: Como calcular as duas distâncias da modal? → A: rota real via OpenRouteService (mesmo padrão
  da feature 007 do passageiro), não linha reta.
- Q: O preço por quilômetro editável na modal persiste no cadastro do motorista? → A: não — vale
  só para esta corrida (o cadastro, feature 006-preco-por-km, continua guardando o valor padrão
  inalterado).
- Q: "Enviar orçamento" precisa publicar um evento Nostr novo? → A: sim — define-se um novo kind
  de orçamento no contrato de eventos, replicado no passageiro na mesma alteração (Princípio IV);
  a UI de recebimento no passageiro fica fora de escopo desta feature, mesmo padrão já usado para
  o kind 20001 no motorista (contrato escrito e replicado, consumo é trabalho futuro).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Ver a modal de uma solicitação recebida, com as distâncias reais e o total
calculados (Priority: P1)

Como motorista online, quando uma solicitação de carona chega, quero ver imediatamente uma modal
com a origem, o destino, a distância até a origem, a distância da corrida e o valor total, para
decidir se topo a corrida sem precisar fazer nenhuma conta de cabeça.

**Why this priority**: é o pedido central da feature — sem a modal com esses dados, não há nada
para o motorista decidir.

**Independent Test**: com o motorista online e posição disponível, simular o recebimento de um
evento de solicitação de carona (kind 20001) e verificar que a modal aparece com origem, destino,
as duas distâncias e o total calculado a partir do preço por quilômetro padrão do cadastro.

**Acceptance Scenarios**:

1. **Given** o motorista online com posição atual disponível, **When** chega uma solicitação de
   carona válida, **Then** uma modal é exibida com o ponto de origem, o ponto de destino, a
   distância do motorista até a origem, a distância entre origem e destino, o preço por quilômetro
   (pré-preenchido com o valor do cadastro) e o total (distância origem-destino × preço).
2. **Given** a modal aberta, **When** o cálculo das distâncias termina, **Then** os valores
   exibidos são atualizados a partir de zero/indicação de carregamento para os valores calculados.
3. **Given** a modal aberta com o preço padrão pré-preenchido, **When** o motorista edita o campo
   de preço por quilômetro, **Then** o total exibido é recalculado imediatamente com o novo valor,
   sem nenhuma chamada de rede adicional.

---

### User Story 2 - Enviar orçamento para a solicitação (Priority: P1)

Como motorista que decidiu topar a corrida, quero confirmar o preço por quilômetro e enviar meu
orçamento, para que o passageiro saiba que alguém está disponível e por quanto.

**Why this priority**: é a ação que dá valor de negócio à modal — sem ela, ver os dados não leva a
nada.

**Independent Test**: com a modal aberta e um preço por quilômetro válido, tocar em "Enviar
orçamento" e verificar que um evento de orçamento é publicado, referenciando a solicitação
original, com o preço por quilômetro usado e o total.

**Acceptance Scenarios**:

1. **Given** a modal aberta com um preço por quilômetro válido (> 0), **When** o motorista toca em
   "Enviar orçamento", **Then** um evento de orçamento é publicado nos relays conectados,
   referenciando a solicitação original, contendo o preço por quilômetro usado e o total.
2. **Given** nenhum relay conectado, **When** o motorista toca em "Enviar orçamento", **Then** a
   modal informa que o orçamento não foi enviado, sem fechar sozinha e sem perder os dados
   preenchidos.
3. **Given** o preço por quilômetro do campo está vazio, zero, negativo ou mal formatado, **When**
   o motorista tenta tocar em "Enviar orçamento", **Then** o envio é impedido e o motivo é
   indicado junto ao campo.
4. **Given** um orçamento enviado com sucesso, **When** a publicação é confirmada, **Then** a modal
   é fechada.

---

### User Story 3 - Recusar a corrida (Priority: P2)

Como motorista que não quer ou não pode atender a esta solicitação, quero recusá-la e fechar a
modal, para seguir disponível para a próxima sem publicar nada.

**Why this priority**: é o caminho alternativo à User Story 2 — necessário para a modal não travar
o app, mas não é o caminho que gera valor de negócio.

**Independent Test**: com a modal aberta, tocar em "Recusar corrida" e verificar que a modal fecha
e nenhum evento é publicado.

**Acceptance Scenarios**:

1. **Given** a modal aberta, **When** o motorista toca em "Recusar corrida", **Then** a modal fecha
   imediatamente e nenhum evento é publicado.
2. **Given** a modal recusada, **When** outra solicitação de carona chega depois, **Then** uma nova
   modal é exibida normalmente para ela (recusar uma não impede ver as seguintes).

---

### Edge Cases

- O que acontece se o motorista estiver offline quando a solicitação chegar? Nenhuma modal é
  exibida — a solicitação é ignorada pela mesma regra que rege notificação de corrida hoje
  (propósito já registrado do status online/offline).
- O que acontece se duas solicitações chegarem antes de a primeira modal ser respondida? Cada
  solicitação válida recebida enquanto o motorista está online e sem modal aberta abre sua própria
  modal; enquanto uma modal está aberta, uma nova solicitação recebida aguarda e é exibida assim
  que a modal atual for encerrada (enviada ou recusada) — nunca duas modais sobrepostas.
- O que acontece se o cálculo de uma das distâncias falhar (rede indisponível, serviço fora do
  ar)? A modal continua aberta e utilizável: o campo de preço e o total continuam editáveis e
  calculáveis a partir do preço (mesmo sem a distância), e "Enviar orçamento" continua disponível;
  a distância que falhou é indicada como não calculada, nunca como zero.
- O que acontece se o motorista ficar offline enquanto uma modal já está aberta? A modal já aberta
  permanece como está (o motorista já a viu); apenas novas solicitações deixam de abrir modal
  enquanto ele estiver offline.
- O que acontece se a solicitação recebida não tiver o marcador do protótipo ou tiver assinatura
  inválida? Nunca chega a esta feature — descartada pelas regras de recepção já existentes do
  contrato (regras 1 e 6), antes de qualquer processamento de domínio.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: O sistema MUST exibir uma modal quando uma solicitação de carona válida (kind 20001,
  já verificada e deduplicada pelas regras de recepção existentes) for recebida e o motorista
  estiver com o status online (feature 004-mapa-status-motorista).
- **FR-002**: O sistema MUST NOT exibir modal para uma solicitação de carona recebida enquanto o
  motorista estiver offline.
- **FR-003**: A modal MUST exibir o ponto de origem e o ponto de destino da solicitação.
- **FR-004**: O sistema MUST calcular e exibir na modal a distância do trajeto rodoviário real
  (não linha reta) entre a posição atual do motorista e o ponto de origem.
- **FR-005**: O sistema MUST calcular e exibir na modal a distância do trajeto rodoviário real
  (não linha reta) entre o ponto de origem e o ponto de destino.
- **FR-006**: A modal MUST exibir um campo de preço por quilômetro, pré-preenchido com o valor
  padrão do cadastro do motorista (feature 006-preco-por-km) e editável nesta modal.
- **FR-007**: Uma edição do preço por quilômetro nesta modal MUST valer somente para esta corrida —
  MUST NOT alterar o preço padrão persistido no cadastro do motorista.
- **FR-008**: A modal MUST exibir o total da corrida, calculado como a distância entre origem e
  destino (FR-005) multiplicada pelo preço por quilômetro atualmente no campo (FR-006), atualizado
  imediatamente a cada edição do preço, sem nova chamada ao serviço de rota.
- **FR-009**: A modal MUST exibir os botões "Enviar orçamento" e "Recusar corrida".
- **FR-010**: O sistema MUST impedir o envio do orçamento enquanto o preço por quilômetro não for
  um valor válido (> 0, seguindo a mesma validação do cadastro, `DriverProfile.parsePrecoPorKm`),
  indicando o motivo junto ao campo.
- **FR-011**: Ao tocar em "Enviar orçamento" com um preço válido e ao menos um relay conectado, o
  sistema MUST publicar um evento de orçamento (novo kind, definido no contrato desta feature)
  referenciando a solicitação original, contendo o preço por quilômetro usado e o total calculado.
- **FR-012**: Se nenhum relay estiver conectado no momento de "Enviar orçamento", o sistema MUST
  informar que o orçamento não foi enviado, sem fechar a modal e sem descartar os dados
  preenchidos.
- **FR-013**: Uma publicação de orçamento aceita por ao menos um relay MUST fechar a modal.
- **FR-014**: Ao tocar em "Recusar corrida", o sistema MUST fechar a modal imediatamente MUST NOT
  publicar nenhum evento.
- **FR-015**: O sistema MUST NOT exibir mais de uma modal de solicitação simultaneamente; uma nova
  solicitação recebida enquanto uma modal já está aberta MUST ser exibida somente depois que a
  modal atual for encerrada (enviada ou recusada).
- **FR-016**: Uma falha no cálculo de qualquer uma das distâncias (FR-004, FR-005) MUST NOT impedir
  a modal de continuar aberta e utilizável — o preço, o total e "Enviar orçamento" continuam
  disponíveis; a distância que falhou MUST ser indicada como não calculada, nunca exibida como
  zero.
- **FR-017**: O evento de orçamento (FR-011) MUST incluir a tag de marcador do protótipo
  (`["t", "tcc-ufsc-caronas"]`) e uma tag referenciando o id da solicitação original, conforme a
  emenda do contrato desta feature.

### Key Entities

- **Solicitação recebida (dado já existente, kind 20001)**: origem, destino e forma de pagamento,
  conforme já definido na emenda 04 do contrato de eventos. Esta feature apenas passa a consumi-la
  do lado do motorista.
- **Orçamento (nova entidade de domínio e de evento)**: referência à solicitação original (id do
  evento), preço por quilômetro usado e total calculado. Publicado pelo motorista, nunca persistido
  localmente além da sessão em que a modal está aberta.
- **Rota calculada (reuso do padrão já registrado na feature 007 do passageiro)**: resultado do
  cálculo de uma distância real entre dois pontos — usada duas vezes por modal (motorista→origem e
  origem→destino), sem traçado visual nesta feature (a modal não tem mapa).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Uma solicitação recebida com o motorista online abre a modal correspondente em até 1
  segundo (tempo de reação da interface — as distâncias podem continuar calculando depois disso,
  FR-004/FR-005).
- **SC-002**: Editar o preço por quilômetro sempre atualiza o total exibido antes de qualquer
  outra interação do motorista ser possível — nunca fica um total desatualizado na tela.
- **SC-003**: Em 100% dos casos de falha simulada no cálculo de distância, a modal permanece
  utilizável e "Enviar orçamento" continua disponível quando o preço é válido.
- **SC-004**: Em nenhum cenário testado duas modais aparecem simultaneamente na tela.

## Assumptions

- A posição atual do motorista já está disponível pela feature 004 (mapa como tela inicial); esta
  feature apenas consome essa posição, sem alterar como ela é obtida.
- "Trajeto rodoviário real" usa o perfil de rota de carro de passeio, mesma decisão já tomada pela
  feature 007 do passageiro — não há necessidade de outro perfil neste protótipo.
- O cálculo de distância depende de conectividade com um serviço externo (mesmo tipo de dependência
  já aceito para a feature 007 do passageiro); não há expectativa de funcionamento totalmente
  offline.
- A modal não exibe mapa nem traçado visual da rota — só as duas distâncias numéricas e o total.
  Adicionar visualização de mapa à modal é escopo futuro, se necessário.
- O consumo do evento de orçamento pelo aplicativo do passageiro (exibição, notificação, escolha
  entre orçamentos de vários motoristas) é explicitamente fora do escopo desta feature — mesmo
  padrão usado quando o contrato do kind 20001 foi escrito e replicado sem o motorista ainda o
  consumir.
- Não há requisito de manter um histórico de solicitações recusadas ou de orçamentos já enviados
  nesta feature — cada modal existe só enquanto está na tela.
