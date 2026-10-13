# Quickstart — Iniciar corrida após aceitação e deslocamento até o passageiro

Guia de validação manual desta feature, em `Prototipo/driver/`. Pressupõe dois aparelhos/emuladores
Android com um relay em comum: um rodando o app do motorista (com um orçamento já enviado, feature
007) e outro rodando o app do passageiro (com a modal de orçamentos recebidos, feature 008), mesma
configuração já usada para a interoperabilidade das features 007/008.

## Cenários de validação (referem os FR/SC de `spec.md`)

### 1. Modal de aceitação e transição de estado (US1, SC-001, SC-002)

1. No app do motorista, enviar um orçamento para uma solicitação (feature 007).
2. No app do passageiro, aceitar aquele orçamento (feature 008 — botão "Aceitar").
3. **Esperado**: em até poucos segundos, o app do motorista exibe uma modal com uma mensagem
   informando que o orçamento foi aceito e um botão "Iniciar corrida".
4. Tocar em "Iniciar corrida". **Esperado**: a modal fecha.
5. Fechar completamente o app do motorista (não só minimizar) e reabri-lo.
6. **Esperado**: nenhuma nova confirmação é pedida; o app se comporta como se ainda estivesse
   "Deslocando-se até o passageiro" (ver cenário 2, que confirma isso pela ausência de modal de
   solicitação).

### 2. Bloqueio de novas solicitações fora de "Aguardando" (US2, SC-003)

1. Com o motorista já em "Deslocando-se até o passageiro" (cenário 1), no app do passageiro (ou em
   um terceiro aparelho/emulador de passageiro), disparar uma nova solicitação de corrida.
2. **Esperado**: nenhuma modal de solicitação aparece no app do motorista.
3. (Requer trabalho de uma feature futura para voltar ao estado "Aguardando" — não validável até
   lá.) Registrar como limitação conhecida do quickstart, não como falha desta feature.

### 3. Publicação de localização durante o deslocamento (US3, SC-004)

1. Com o motorista em "Deslocando-se até o passageiro" (cenário 1), movimentar o aparelho/emulador
   (ou simular deslocamento de GPS) por mais de 50 m.
2. **Esperado**: inspecionar (via `dart run tool/verify_published.dart <pubkey>` ou equivalente) um
   evento `kind: 20005` publicado, com `content` contendo `lat`/`lon` coerentes com a nova posição,
   e tags `["e", "<id-do-orçamento-aceito>"]` e `["p", "<pubkey-do-passageiro>"]`.
3. Movimentar o aparelho por menos de 50 m. **Esperado**: nenhum novo evento `kind: 20005` é
   publicado.
4. Repetir com o motorista no estado "Aguardando solicitação de corrida" (antes de aceitar
   qualquer corrida). **Esperado**: nenhum evento `kind: 20005` é publicado, independentemente do
   deslocamento.

### 4. Segunda aceitação enquanto já em deslocamento (US4, SC-005)

1. Com o motorista já em "Deslocando-se até o passageiro" (cenário 1) — comprometido com o
   passageiro A —, enviar um orçamento a uma solicitação de um segundo passageiro (B) antes desta
   feature (ou usando um orçamento já enviado antes da transição) e, no app do passageiro B,
   aceitar esse orçamento.
2. **Esperado**: nenhuma modal de "Iniciar corrida" aparece no app do motorista para essa segunda
   aceitação.
3. **Esperado**: inspecionar a publicação e confirmar um evento `kind: 20006` dirigido à chave
   pública do passageiro B (`["p", "<pubkey-B>"]`), referenciando o orçamento que ele aceitou.
4. **Esperado**: nenhuma mudança no estado do motorista — ele continua "Deslocando-se até o
   passageiro" com o passageiro A, sem interrupção.

### 5. Envio de orçamento não muda o estado (FR-006)

1. Com o motorista em "Deslocando-se até o passageiro" (cenário 1), se ainda houver uma solicitação
   pendente de antes da transição com modal já aberta, enviar o orçamento normalmente.
2. **Esperado**: o envio é publicado como sempre (feature 007), e o estado do motorista continua
   "Deslocando-se até o passageiro" — nenhuma modal de solicitação nova aparece depois (cenário 2
   continua valendo).

### 6. Interação com o status online/offline (Edge Cases)

1. Com o motorista em "Deslocando-se até o passageiro" (cenário 1), alternar o status
   online/offline (feature 004) pelo botão existente.
2. **Esperado**: nenhum efeito na publicação de localização (continua a cada 50 m, cenário 3) nem
   no próprio estado "Deslocando-se" — o toggle segue controlando só a exibição de novas
   solicitações, já bloqueadas de qualquer forma neste estado (cenário 2).
