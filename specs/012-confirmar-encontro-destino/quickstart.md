# Quickstart — Confirmar encontro e notificar chegada ao destino

Guia de validação manual desta feature, em `Prototipo/driver/`. Pressupõe dois
aparelhos/emuladores Android com um relay em comum: motorista já com uma corrida aceita, no estado
"Deslocando-se até o passageiro" (feature 010), tendo já publicado a chegada à origem (feature
011); e passageiro capaz de publicar as duas confirmações manualmente (via ferramenta de teste, já
que a feature dele ainda não existe neste ponto — ou, depois de implementada em conjunto, pelos
botões das modais dele).

## Cenários de validação (referem os FR/SC de `spec.md`)

### 1. Confirmação de encontro transiciona para "Em corrida" (US1, SC-001)

1. Publicar (manualmente, ou pelo app do passageiro) uma confirmação de encontro (`kind: 20008`)
   referenciando o orçamento da corrida ativa.
2. **Esperado**: em até poucos segundos, o estado do motorista passa a "Em corrida" — verificável
   pelo comportamento do cenário 2 abaixo (bloqueio de novas solicitações já valia desde
   "Deslocando-se", mas a checagem de destino só começa aqui).
3. Repetir a mesma publicação (reentrega). **Esperado**: nenhuma mudança adicional.

### 2. Chegada a 1 km do destino publica a mensagem (US2, SC-002, SC-003)

1. Com o motorista "Em corrida" (cenário 1), movimentar o aparelho/emulador até menos de 1 km do
   destino da corrida.
2. **Esperado**: inspecionar (via `dart run tool/verify_published.dart <pubkey>` ou equivalente) um
   evento `kind: 20009` publicado, com tags `["e", "<id-do-orçamento>"]` e
   `["p", "<pubkey-do-passageiro>"]`.
3. Permanecer dentro do raio, ou se afastar e voltar a entrar. **Esperado**: nenhum novo evento
   `kind: 20009`.
4. Repetir fora do estado "Em corrida" (motorista ainda "Deslocando-se", ou já "Aguardando").
   **Esperado**: nenhum evento `kind: 20009`, independentemente da distância.

### 3. Confirmação de destino volta o motorista a "Aguardando" (US3, SC-004)

1. Publicar uma confirmação de destino (`kind: 20010`) referenciando o mesmo orçamento.
2. **Esperado**: em até poucos segundos, o motorista volta ao estado "Aguardando solicitação de
   corrida", livre para uma nova corrida — verificável enviando uma nova solicitação de teste e
   confirmando que a modal de solicitação volta a aparecer normalmente.
