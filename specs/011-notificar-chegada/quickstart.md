# Quickstart — Notificar chegada ao passageiro

Guia de validação manual desta feature, em `Prototipo/driver/`. Pressupõe dois
aparelhos/emuladores Android com um relay em comum: motorista já com uma corrida aceita, no estado
"Deslocando-se até o passageiro" (feature 010), e passageiro com a solicitação original ainda
identificável (para conferir a origem usada).

## Cenários de validação (referem os FR/SC de `spec.md`)

### 1. Entrar no raio de 30 m publica a chegada (US1, SC-001, SC-003)

1. Com o motorista em "Deslocando-se até o passageiro", movimentar o aparelho/emulador (ou simular
   posição) até menos de 30 m do ponto de origem da solicitação original.
2. **Esperado**: em até poucos segundos, inspecionar (via
   `dart run tool/verify_published.dart <pubkey>` ou equivalente) um evento `kind: 20007`
   publicado, com tags `["e", "<id-do-orçamento>"]` e `["p", "<pubkey-do-passageiro>"]` e `content`
   vazio.
3. Repetir com o motorista a mais de 30 m do ponto de origem. **Esperado**: nenhum evento
   `kind: 20007` é publicado.

### 2. Nunca mais de uma mensagem por corrida (US1, SC-002)

1. Após o cenário 1, permanecer dentro do raio de 30 m por mais tempo (várias atualizações de
   posição), ou se afastar e voltar a entrar no raio.
2. **Esperado**: nenhum novo evento `kind: 20007` é publicado além do primeiro.
3. Fechar completamente o app do motorista e reabri-lo, ainda dentro do raio de 30 m.
4. **Esperado**: nenhum novo evento `kind: 20007` é publicado — o estado "já avisei" sobreviveu ao
   reinício.

### 3. Fora do estado "Deslocando-se", nenhuma mensagem é publicada (Edge Cases)

1. Com o motorista no estado "Aguardando solicitação de corrida" (sem corrida ativa), simular
   qualquer posição.
2. **Esperado**: nenhum evento `kind: 20007` é publicado, independentemente da posição.
