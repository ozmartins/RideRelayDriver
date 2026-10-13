# Research: Notificar chegada ao passageiro

## D1 — De onde vem a coordenada de origem no momento da chegada

**Decisão**: `SentQuotesStore` (feature 010) passa a guardar, junto de cada `id` de orçamento
enviado, a coordenada de origem (`RideRequestReceived.origin`) da solicitação respondida — captada
no mesmo ponto em que `MapScreen._enviarOrcamento` já registra o `id` (D6/FR-011 da feature 010).
`_iniciarCorrida` lê essa origem por `SentQuotesStore.originFor(quoteId)` e grava em `ActiveRide`,
junto do restante do estado já persistido por `RideStateStore`.

**Justificativa**: `QuoteAccepted` (leitura do `kind: 20003`) só carrega `quoteId` e
`passengerPubkey` — a aceitação não repete a origem, e não há, no protótipo, nenhum canal de
posição ao vivo do passageiro (Assumptions do `spec.md`). A única origem conhecida é a que veio na
solicitação (`kind: 20001`) respondida por aquele orçamento, e o único ponto em que o motorista
ainda tem essa origem em mãos é o instante do envio do orçamento — por isso precisa ser guardada
ali, não recalculada depois.

**Alternativas avaliadas**:
- **Guardar a origem só em memória, associada à modal aberta**: rejeitada — já seria perdida antes
  mesmo de uma aceitação chegar, quanto mais sobreviver a um reinício do app entre o envio do
  orçamento e a aceitação (mesma janela que já motivou `SentQuotesStore` ser persistido na feature
  010, D6 de `010-iniciar-corrida/research.md`).
- **Reconsultar a solicitação original (`kind: 20001`) pelo `EventFeed` no momento da aceitação**:
  rejeitada — eventos `kind: 20001` são efêmeros (contrato, faixa 20000-29999) e o `EventFeed`
  mantém só uma janela limitada em memória (`maxEvents`); não há garantia de que a solicitação
  original ainda esteja disponível, e a suposição de que estaria introduziria um acoplamento frágil
  a um detalhe de implementação do `EventFeed`.

## D2 — Onde persistir "a mensagem de chegada já foi enviada para esta corrida"

**Decisão**: um campo booleano `arrivalNotified` em `ActiveRide`, persistido por `RideStateStore`
junto dos demais campos da corrida ativa (mesmo mecanismo já usado por FR-003/FR-009 da feature
010). Ao publicar a mensagem de chegada, `MapScreen` regrava o estado com
`arrivalNotified: true`, mesmo status (`deslocandoAtePassageiro`).

**Justificativa**: sem persistência, um reinício do app enquanto o motorista ainda está dentro do
raio de 10 m — cenário normal, dado que o estado "Deslocando-se até o passageiro" já sobrevive a
reinícios desde a feature 010 — faria a próxima posição recebida reenviar a mensagem, violando
FR-003. `ActiveRide`/`RideStateStore` já existem exatamente para esse tipo de dado por-corrida;
criar um mecanismo de persistência paralelo só para este booleano violaria o Princípio V.

**Alternativas avaliadas**:
- **Flag só em memória no `State` de `MapScreen`**: rejeitada pelo motivo acima — mesma classe de
  defeito que o achado C1 do `/speckit-analyze` da feature 010 já corrigiu para a validação do
  orçamento aceito (`SentQuotesStore`), desta vez para o "já avisei" em vez do "já enviei".
- **Novo serviço de persistência dedicado**: rejeitado por proporcionalidade — é um único booleano
  por corrida ativa, e `ActiveRide` já é o lugar natural para dado por-corrida.

## D3 — Novo kind do contrato

**Decisão**: `kind: 20007` — "Chegada do motorista", motorista → passageiro, mesma faixa efêmera
20000-29999 dos demais eventos de domínio (perde sentido depois que o passageiro embarca, não há
razão para o relay retê-lo). Tags: marcador + `["e", "<id-do-orçamento>"]` +
`["p", "<pubkey-do-passageiro>"]` — mesmo formato já usado pelos kinds 20005/20006 (feature 010).
`content`: string vazia, mesma convenção dos kinds 20003/20004/20006 (toda informação necessária já
está nas tags e no próprio kind).

**Justificativa do número**: sequencial ao último kind definido (`20006`, feature 010).

**Alternativas avaliadas**:
- **Reaproveitar o `kind: 20005` (Localização do motorista), com algum campo indicando chegada**:
  rejeitada — misturaria duas semânticas (atualização periódica de posição vs. evento único e
  significativo de chegada) no mesmo kind, dificultando o consumo futuro pelo passageiro (que
  precisaria inspecionar `content` para distinguir os dois casos em vez de filtrar por kind, único
  propósito de ter kinds distintos neste protótipo).

## D4 — Consumo pelo passageiro

**Decisão**: fora de escopo desta feature, mesmo padrão já usado para todos os kinds anteriores —
o contrato é escrito e replicado nas duas apps (Princípio IV), mas reagir ao `kind: 20007` do lado
do passageiro é trabalho de uma feature futura (o próprio pedido do usuário já delimita isso
explicitamente).
