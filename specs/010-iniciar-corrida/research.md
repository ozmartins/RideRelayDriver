# Research: Iniciar corrida após aceitação e deslocamento até o passageiro

## D1 — Onde persistir o estado do motorista ("Aguardando"/"Deslocando-se")

**Decisão**: reaproveitar `KeyValueStore` (`shared_preferences`, já em uso por `RelayRepository`
desde a feature 002), guardando uma string JSON com `{"status": "...", "quoteId": "...",
"passengerPubkey": "..."}` sob uma chave própria (`driver_ride_state`). Quando o motorista está em
"Aguardando solicitação de corrida", a chave não existe (ou é removida) — ausência de valor é o
próprio default, mesmo padrão já usado por `CadastroStore.load()` devolvendo `null`.

**Alternativas avaliadas**:
- **Nova tabela SQLite** (como `driver_profile`, via `sqflite`), com migração de versão dedicada.
  Rejeitada: é um valor pequeno, sem necessidade de consulta relacional nem de campos adicionais
  que justifiquem colunas — introduzir uma segunda tecnologia de persistência local para um caso
  que o mecanismo mais simples já cobre violaria o Princípio V (simplicidade proporcional).
- **Estado só em memória** (como `AvailabilityStatus`, que reinicia em `offline` a cada abertura).
  Rejeitada explicitamente pelo pedido original: o estado "Deslocando-se até o passageiro" MUST
  sobreviver ao fechamento do app (FR-003), ao contrário do status online/offline.

**Justificativa**: `shared_preferences` já é dependência do projeto (decisão registrada em
`specs/002-nostr-relay-connection/research.md`); esta feature não adiciona pacote novo, só uma
chave nova ao mesmo armazenamento.

## D2 — Como os novos eventos referenciam a corrida e o destinatário

**Decisão**: os dois eventos novos publicados pelo motorista (localização, `kind: 20005`, e recusa
por corrida já em andamento, `kind: 20006`) seguem o mesmo par de tags já usado pelos kinds
20003/20004 do passageiro: `["e", "<id-do-orçamento>"]` (o `kind: 20002` que foi aceito) e
`["p", "<pubkey-do-passageiro>"]`. A chave pública do passageiro não vem de uma tag da aceitação
recebida (`kind: 20003` só tem `["p", "<pubkey-do-motorista>"]`, apontando ao próprio motorista,
o destinatário daquele evento) — vem do campo `pubkey` (autor) do envelope da aceitação recebida,
já disponível em todo evento processado pelo `EventFeed`.

**Alternativas avaliadas**:
- **Referenciar o `kind: 20001` original (a solicitação), não o orçamento**: rejeitada — o
  motorista pode ter enviado orçamento para várias solicitações; o orçamento (`kind: 20002`) é a
  unidade que a aceitação já referencia e é exclusiva de um motorista, evitando ambiguidade.
- **Guardar o requestId original também no estado persistido (D1)**: avaliado e descartado por
  proporcionalidade — nada nesta feature precisa do `id` da solicitação original, só do orçamento
  aceito e de para quem publicar.

## D3 — Origem e filtro da posição publicada durante "Deslocando-se"

**Decisão**: reaproveitar o mesmo `LocationService.positions` (stream de `DriverPosition`) que já
move o marcador do motorista no mapa desde a feature 004, sem nova permissão nem novo serviço.
Antes de publicar, comparar a nova posição com a última publicada; só publicar se a distância
(fórmula de Haversine, já usada indiretamente pelos cálculos de rota) ultrapassar 50 m.

**Justificativa do limiar de 50 m**: mesmo valor já medido e justificado por
`passenger/specs/007-rota-ate-destino/research.md` (decisão D2), escolhido lá para não exceder o
nível gratuito de um serviço de roteamento de terceiros e para não recalcular a cada atualização
bruta do GPS. Reaproveitar o número evita introduzir um segundo valor arbitrário sem medição
própria (Princípio V) e mantém as duas apps consistentes no mesmo tipo de decisão.

**Alternativas avaliadas**: intervalo fixo de tempo (rejeitado pela clarificação da sessão que
originou a spec — resposta explícita do usuário preferindo deslocamento mínimo de distância);
publicar a cada atualização bruta do GPS, sem filtro (rejeitado nessa mesma clarificação, e
descartado por gerar volume de publicação desproporcional ao propósito do protótipo).

## D4 — Novos kinds do contrato

**Decisão**: dois novos kinds na faixa efêmera 20000-29999 (mesma faixa de todos os eventos de
domínio deste protótipo, pela mesma razão já registrada nas emendas 04/05 do contrato: a
informação perde sentido depois de um momento, não há razão para o relay retê-la):

- `kind: 20005` — "Localização do motorista", motorista → passageiro.
- `kind: 20006` — "Corrida não pode mais ser atendida", motorista → passageiro.

**Justificativa dos números**: sequenciais aos já definidos (20001-20004), seguindo a numeração já
estabelecida pelo contrato único do protótipo (`specs/002-nostr-relay-connection/contracts/nostr-events.md`).

**Alternativas avaliadas**: reaproveitar `kind: 20004` (Recusa de orçamento, já definido) para o
aviso de "corrida não pode mais ser atendida". Rejeitada: `20004` já tem semântica fixa (recusa
*antes* de aceitar, publicada pelo passageiro) e direção oposta (passageiro → motorista); reutilizar
o mesmo kind para um evento motorista → passageiro com semântica diferente violaria a definição já
publicada do contrato e quebraria qualquer consumidor futuro que filtre por direção implícita do
kind.

## D6 — Como o motorista sabe se um orçamento foi realmente enviado por ele (FR-011)

**Decisão**: persistir o conjunto de `id`s de orçamento publicados com sucesso num novo serviço,
`SentQuotesStore` (`data-model.md`), sobre o mesmo `KeyValueStore` já usado por `RideStateStore`
(D1). `MapScreen._enviarOrcamento` grava o `id` do evento assinado assim que ao menos um relay
aceita a publicação (mesmo ponto em que a modal de solicitação já fecha, feature 007); ao processar
uma aceitação recebida, `MapScreen` consulta esse conjunto antes de decidir modal ou descarte.

**Origem da decisão**: achado CRITICAL do `/speckit-analyze` desta feature — a primeira versão do
plano cobria FR-011 (ignorar aceitação sem orçamento correspondente) só implicitamente, sem
nenhuma estrutura de dados que soubesse "quais orçamentos este motorista enviou". Um conjunto só em
memória, mantido dentro do `State` de `MapScreen`, pareceria suficiente à primeira vista (o
orçamento acabou de ser enviado pela própria tela), mas falha exatamente no mesmo tipo de janela
que já justifica a persistência de `RideStateStore`: se o app reiniciar entre o motorista enviar um
orçamento e a aceitação chegar — cenário normal, não um caso extremo, dado que FR-003/FR-009 já
tratam reinício como parte do fluxo principal desta feature —, uma aceitação **legítima** seria
descartada como se fosse de origem desconhecida, quebrando silenciosamente a User Story 1 (MVP).

**Alternativas avaliadas**:
- **Conjunto em memória, não persistido**: rejeitada pelo motivo acima — reintroduziria exatamente
  o defeito que a persistência do estado do motorista (D1) foi desenhada para evitar, só que para
  outro dado.
- **Guardar os orçamentos enviados dentro do próprio `RideStateStore`** (um campo a mais no mesmo
  registro): rejeitada — `RideStateStore` guarda no máximo uma corrida ativa por vez; o conjunto de
  orçamentos enviados é maior (um motorista pode enviar vários antes de qualquer aceitação) e tem
  ciclo de vida diferente (um orçamento pode nunca ser aceito, e mesmo assim continua "enviado"
  para fins de FR-011). Misturar os dois violaria a coesão de cada abstração sem ganho.
- **Não validar a origem do orçamento, confiar em qualquer `id` referenciado**: é a lacuna que
  motivou esta decisão — rejeitada porque descumpre FR-011 diretamente.

## D5 — Consumo pelo passageiro

**Decisão**: fora de escopo desta feature — mesmo padrão já usado para o consumo do `kind: 20001`
pelo motorista (feature 006 do passageiro, emenda 04) e do `kind: 20002` pelo passageiro (feature
007 do motorista, emenda 05). O contrato dos kinds 20005/20006 é escrito e replicado nas duas apps
(Princípio IV) nesta mesma alteração; a app do passageiro reagir a eles (exibir a localização,
mostrar o aviso de indisponibilidade) é trabalho de uma feature futura do passageiro.
