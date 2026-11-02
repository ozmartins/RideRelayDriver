# Pendências da feature 026 (recibos de reputação) — para análise

**Data**: 2026-10-20 · **Estado**: as 36 tarefas de `tasks.md` estão concluídas; `flutter analyze` e `flutter test` passam nos dois apps
(motorista 768 testes, passageiro 732); as emendas 25 e 26 do contrato estão commitadas nas duas apps. O que segue **não** é trabalho
esquecido: são decisões suas e limitações conhecidas.

## A. Decisão sua

### A1. Os dois arquivos de especificação de entrada

- `RideRelayDriver/especificacao-motorista.md` e `RideRelayPassenger/especificacao-passageiro.md` estão **sem commit** (`??` no `git status`).
- Estão **desatualizados** em relação ao contrato commitado: ainda dizem que o reenvio do recibo roda "com o serviço ativo" (o contrato agora
  diz "enquanto a interface do app estiver ativa", porque o serviço em segundo plano não tem a chave) e não mencionam a emenda 26.
- O contrato (`specs/002-nostr-relay-connection/contracts/nostr-events.md`) e `specs/026-recibos-de-reputacao/contracts/` já são a fonte de verdade.
- **Opções**: (a) apagar os dois; (b) commitar como histórico do pedido original; (c) atualizar o texto da seção 1 para o contrato final e commitar.
- **Sugestão**: (a) — evita duas versões da mesma regra.

## B. Limitações conhecidas (sem ação planejada)

### B1. Recibo de uma corrida que não houve

- A emenda 26 só aceita recibo de quem **negociou** com o avaliado (motorista: orçamento que enviou àquele passageiro; passageiro: orçamento
  que recebeu daquele motorista). Quem negociou ainda pode emitir um recibo válido, com nota 1, para uma negociação que não virou corrida.
- Está registrado na seção 1.9 do contrato, nas duas apps.
- **Para fechar**: registrar a **aceitação** em cada app (motorista ao "Iniciar corrida"; passageiro ao aceitar o orçamento) e exigir que o
  recibo seja de uma corrida aceita. Custa uma migração de `receipts.db` (v1 → v2) em cada app, nova emenda do contrato e testes. Mesmo assim,
  um participante de uma corrida aceita-mas-cancelada ainda poderia emitir recibo.
- **Decisão a tomar**: aceitar o limite para o protótipo (e documentá-lo na monografia) ou abrir a emenda 27.

### B2. Passageiro em segundo plano não tratou o primeiro envio do recibo

- Observado em emulador (1ª corrida): o recibo do motorista ficou `pendente = 1` até um reenvio, com o passageiro já em primeiro plano. Na 2ª e
  na 3ª corrida a entrega ocorreu com o passageiro em segundo plano e deu certo, então não é determinístico.
- **Causa não investigada**; o reenvio do motorista (60 s, reconexão ou abertura do app) cobriu a falha. Se for um problema real, é do app do
  passageiro (feature 026 dele, serviço em segundo plano): o evento chega ao serviço, mas a interface pode não estar processando o feed.
- **Para investigar**: reproduzir com `adb logcat` do passageiro em segundo plano e conferir se o `20014` chega à interface.

### B3. Regra (h) da verificação é literal

- Com `seq_proximo = 0`, a verificação de reputação não confere nada (o contrato só exige o `head` quando existe o recibo `seq − 1`). Uma
  `reputacao` com `seq_proximo = 0` e recibos na lista passa sem ser marcada como inconsistente.
- Foi mantido literal para não divergir entre as apps (R9 do `research.md`). Endurecer exige emenda do contrato nas duas apps.

### B4. Limites do ambiente de teste (quickstart, rodadas 1 a 3)

- Os cenários rodaram em **um** emulador, com motorista e passageiro alternados em primeiro plano e a **mesma posição GPS** (os dois AVDs não
  ficaram de pé juntos; suspeita de memória, não confirmada). Não é o cenário de dois aparelhos.
- Usaram-se os **três relays públicos** da lista padrão; eventos de teste (inclusive os forjados) ficaram neles, efêmeros e endereçados às
  chaves de teste. Um dos relays (`offchain.pub`) rejeitou eventos de chaves desconhecidas.
- O **valor** da chave privada não foi procurado nos logs, porque fica no Keystore e não pude lê-la; procuraram-se termos de segredo e
  marcadores de conteúdo decifrado.
- "Pular" a avaliação do **lado do motorista** só foi exercitado em teste automatizado (o do passageiro foi exercitado em emulador).
- Recibo de negociação real, mas ligado a **outro avaliador**, só tem teste automatizado.
- O `receipts.db` do emulador do motorista ainda tem a linha do recibo forjado de antes da emenda 26 (corrida `000…`, nota 1): dado de teste.

## C. Para conferir

- Onde está cada coisa: contrato em `specs/002-nostr-relay-connection/contracts/nostr-events.md` (emendas 25 e 26, seção "Reputação por
  recibos"); resultados do quickstart em `specs/026-recibos-de-reputacao/quickstart.md` ("Resultados", rodadas 1 a 3); decisões em
  `specs/026-recibos-de-reputacao/research.md` (R1 a R9).