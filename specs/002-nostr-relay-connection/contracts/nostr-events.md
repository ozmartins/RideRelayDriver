# Contrato — Eventos Nostr do protótipo de corridas

Este é o **único** ponto de interoperabilidade entre a app do motorista (`Prototipo/driver`) e a do
passageiro (`Prototipo/passenger`). Não há backend: qualquer mudança aqui precisa ser aplicada **de forma
idêntica nos dois lados, na mesma alteração**.

## Histórico de emendas

| # | Data | O que mudou | Origem |
|---|------|-------------|--------|
| 01 | 2026-09-16 | Marcador `["t", "tcc-ufsc-caronas"]` no evento de teste, seção *Forma da inscrição* e regra de recepção 6 | Proposta da sessão que mantém `Prototipo/passenger`, corroborada por medição dos dois lados: sem o filtro, ~500 eventos alheios por relay no primeiro segundo (passageiro) e 125 eventos alheios em 90 s (motorista) |
| 02 | 2026-09-16 | `"limit": 50` na seção *Forma da inscrição* | Diagnóstico das duas apps: o motorista já limitava a inscrição (`limit: 50`, mais um `since` de 24 h que este contrato não previa), o passageiro não limitava nenhuma; as duas mostravam históricos diferentes ao conectar. `since` foi descartado — no passageiro a inscrição é registrada uma vez e reenviada a cada conexão nova (regra de vivacidade do `RelayService`), e um `since` fixo no momento do registro ficaria cada vez mais velho a cada reconexão |
| 03 | 2026-09-16 | Regra de recepção 1, esclarecida | Diagnóstico das duas apps: o motorista verifica a assinatura e só depois deduplica por `id`; o passageiro checa se o `id` já foi visto antes de verificar, para não gastar a verificação criptográfica de novo no mesmo evento chegando por outro relay. A checagem de "já visto" não usa nenhum campo do evento além do `id` como chave de um conjunto e não aceita nem exibe nada — por isso não é o "processamento" que a regra 1 proíbe antes da verificação |
| 04 | 2026-09-20 | Define `kind: 20001` para "Solicitação de corrida" (seção *Conteúdo do kind 20001*), com marcador do protótipo também exigido neste kind | Feature 006 do passageiro (botão "Solicitar corrida"): primeiro evento de domínio deste protótipo, publicado pelo passageiro assim que destino, posição atual e forma de pagamento estão disponíveis |
| 05 | 2026-09-20 | Define `kind: 20002` para "Orçamento de corrida" (seção *Conteúdo do kind 20002*): primeiro evento publicado pelo motorista, em resposta a uma solicitação — introduz a tag `["e", "<id>"]` referenciando o evento respondido, além da tag de marcador já exigida | Feature 007 do motorista (modal de solicitação recebida, botão "Enviar orçamento"): o motorista precisa responder a uma solicitação específica, não apenas anunciar algo. O consumo deste kind pelo passageiro (exibir, notificar, escolher entre orçamentos) fica fora de escopo — mesmo padrão que a emenda 04 já aplicou ao consumo do kind 20001 pelo motorista |
| 06 | 2026-09-20 | Amplia o `content` do `kind: 20002` com `driverName`, `carBrand`, `carModel`, `carYear` (sempre presentes) e `etaMinutes` (opcional, omitido quando não calculável) | Feature 009 do motorista: a modal de orçamentos do passageiro (feature seguinte) precisa desses dados para o motorista decidir entre propostas, e nenhum deles existia em nenhum evento até aqui |
| 07 | 2026-09-20 | Define `kind: 20003` para "Aceitação de orçamento" e `kind: 20004` para "Recusa de orçamento" (seções *Conteúdo do kind 20003* e *20004*): o passageiro passa a se inscrever em `kind: 20002` (Forma da inscrição atualizada) e a responder a cada orçamento recebido — aceitando um e recusando os demais da mesma solicitação | Feature 008 do passageiro (persistir orçamentos recebidos, modal listando todos os de uma solicitação, botão "Aceitar"): o motorista escolhido precisa saber que venceu, e os demais precisam saber que perderam. O consumo dos kinds 20003/20004 pelo motorista fica fora de escopo — mesmo padrão já usado para o consumo do kind 20001 pelo motorista (emenda 04) e do kind 20002 pelo passageiro (emenda 05) |
| 08 | 2026-09-21 | Define `kind: 20005` para "Localização do motorista" e `kind: 20006` para "Corrida não pode mais ser atendida" (seções *Conteúdo do kind 20005* e *20006*); o motorista passa a se inscrever também em `kind: 20003` (Forma da inscrição atualizada) | Feature 010 do motorista (modal de aceitação de orçamento, estado "Deslocando-se até o passageiro"): o motorista consome pela primeira vez o `kind: 20003` (definido na emenda 07, nunca lido antes) para saber que um orçamento seu foi aceito; ao aceitar, publica a localização periodicamente enquanto se desloca e, se uma segunda aceitação chegar enquanto já está comprometido com outra corrida, avisa o passageiro dela que não pode mais ser atendido. O consumo dos kinds 20005/20006 pelo passageiro fica fora de escopo — mesmo padrão já usado para os kinds anteriores |
| 09 | 2026-09-21 | Define `kind: 20007` para "Chegada do motorista" (seção *Conteúdo do kind 20007*) | Feature 011 do motorista: ao entrar num raio de 10 m do ponto de origem da corrida ativa, durante o estado "Deslocando-se até o passageiro" (feature 010), o motorista publica um evento avisando que chegou, uma única vez por corrida. O consumo do kind 20007 pelo passageiro fica fora de escopo — mesmo padrão já usado para os kinds anteriores |
| 10 | 2026-09-21 | O passageiro passa a se inscrever em `kind: 20005` (Forma da inscrição atualizada) | Feature 009 do passageiro: reconhece a primeira localização do motorista referenciando o orçamento aceito como o sinal de que ele começou a se deslocar, e exibe uma modal avisando isso — não decodifica nem exibe a posição em si. Nenhum kind novo; `kind: 20005` já estava definido pela emenda 08 |
| 11 | 2026-09-21 | Define `kind: 20008` para "Encontro confirmado", `kind: 20009` para "Chegada ao destino" e `kind: 20010` para "Destino confirmado" (seções *Conteúdo do kind 20008*, *20009* e *20010*); o motorista passa a se inscrever também em `20008` e `20010` (Forma da inscrição atualizada) | Feature 012 do motorista (estado "Em corrida"): ao receber a confirmação de encontro do passageiro (`kind: 20008`, publicado por ele), o motorista transiciona de "Deslocando-se até o passageiro" para "Em corrida"; durante esse estado, ao entrar num raio de 5 m do destino, publica `kind: 20009`; ao receber a confirmação de destino do passageiro (`kind: 20010`), volta a "Aguardando solicitação de corrida". Os três kinds são definidos nesta feature, mesmo os dois publicados pelo passageiro — mesmo precedente já usado pelo `kind: 20005` (definido pela feature 010 do motorista, consumido só por uma feature posterior do passageiro). O consumo/publicação pelo passageiro fica fora de escopo desta feature — implementado pela feature 010 dele |
| 12 | 2026-09-30 | Nenhum formato muda. A nota *Consumo pelo passageiro* do `kind: 20005` passa a dizer que o passageiro decodifica e exibe `lat`/`lon` (marcador do motorista), só em "motorista a caminho", só em memória, e só de eventos assinados pelo motorista cujo orçamento aceitou | Feature 016 do passageiro (posição do motorista no mapa): a nota da emenda 10 ("não decodifica nem exibe `lat`/`lon`") deixa de ser verdadeira. O motorista não muda; o passageiro passa a conferir também o autor da localização (antes só a tag `["e", ...]`, pública no relay), o que aperta o gatilho "motorista a caminho" da feature 009 |
| 13 | 2026-10-03 | Define `kind: 20011` para "Rota da corrida" (seção *Conteúdo do kind 20011*); o passageiro passa a se inscrever também em `20011` (Forma da inscrição atualizada) | Feature 017 do motorista (publicar a rota ao passageiro): o passageiro deve traçar no mapa o trajeto até o destino durante "Em corrida" sem calcular rota — o motorista, que já calcula o trajeto para o próprio mapa (feature 016), o publica a cada cálculo ou recálculo bem-sucedido. O consumo pelo passageiro é da feature dele (018) |
| 14 | 2026-10-04 | Define `kind: 20012` para "Corrida cancelada" (seção *Conteúdo do kind 20012*); o passageiro passa a se inscrever também em `20012` (Forma da inscrição atualizada) | Feature 018 do motorista (cancelar corrida): depois de aceito o orçamento, o motorista passa a poder cancelar a corrida em "Deslocando-se até o passageiro" ou "Em corrida", e o passageiro precisa saber para avisar o usuário e encerrar a corrida dele. Definido pelo motorista, que o publica; o consumo é da feature dele (019) |
| 15 | 2026-10-04 | Aposenta o `kind: 20006` ("Corrida não pode mais ser atendida"): o motorista deixa de publicá-lo e ignora, sem avisar a rede, uma aceitação de orçamento (`20003`) que chegue com ele já em "Deslocando-se até o passageiro" ou "Em corrida". O número `20006` não é reutilizado | Levantamento dos fluxos entre as apps: o aviso nunca teve consumidor (o passageiro não o lê, emenda 08) e a rede não precisa saber que um motorista comprometido ignorou uma aceitação. A revisão também achou que, com o motorista "Em corrida", a aceitação abria a modal "Orçamento aceito" — e "Iniciar corrida" nela sobrescreveria a corrida ativa —, porque a guarda só cobria o deslocamento; agora só "Aguardando" abre a modal. O passageiro não muda (feature 018 do motorista, mesma alteração) |
| 16 | 2026-10-04 | Restaura o `kind: 20006` aposentado pela emenda 15 e o amplia: o motorista o publica de novo ao receber uma aceitação (`20003`) estando em "Deslocando-se até o passageiro" **ou "Em corrida"**; o passageiro passa a se inscrever em `20006` e a consumi-lo (seção *Kind 20006*, "Consumo pelo passageiro") | Revisão da emenda 15: aposentar o `20006` deixava o passageiro cuja aceitação foi ignorada preso em "orçamento aceito", sem aviso e sem saída (ele já não lia o kind, mas a rede ao menos o carregava). O passageiro agora reage ao aviso, encerrando a corrida dele e informando-o por modal (feature 020 do passageiro). Nenhum formato muda; a emenda 15 permanece no histórico como registro. A correção da guarda do motorista (modal "Orçamento aceito" não abre em "Em corrida") continua valendo |
| 17 | 2026-10-06 | Todo `content` dos kinds `20002` a `20012` passa a ser cifrado com NIP-44 v2 ao destinatário (tag `p`) e continua assinado (NIP-01); o `20002` ganha a tag `["p", <pubkey do solicitante>]`; o `20001` é a única exceção (só assinado, em claro); kinds sem dado próprio cifram o marcador `{}`; nova regra de recepção 7 e seção *Cifragem do `content`* | Pedido de que toda mensagem entre as apps seja cifrada e assinada com o par de chaves assimétricas. Definido pela feature 019 do motorista e replicado na feature 022 do passageiro, na mesma alteração (Princípio IV); constituição 2.11.0. Muda o formato de kinds já em uso, nos dois sentidos: as duas apps atualizam juntas, sem modo de compatibilidade |
| 18 | 2026-10-06 | Retira o `kind: 1` do protótipo: deixa de constar da tabela de kinds e das inscrições das duas apps, que não o publicam nem o consomem mais; a seção *Por que `kind: 1`* vira *`kind: 1` fora do protocolo*; a tag de marcador passa a ser descrita como exigência de todo evento do protótipo, não do evento de teste | Pedido de remover o `kind: 1`: nenhuma tela das apps o publicava desde as features 010 (motorista, aba "Eventos") e 013 (passageiro, botão "Publicar teste"), e todo kind de domínio já exerce o caminho ponta a ponta — relay, assinatura, filtro, cifra — com mais fidelidade que a nota de teste. Mantê-lo na inscrição só trazia, de um kind compartilhado com a rede social inteira, tráfego alheio que o filtro `#t` precisava conter. Os scripts de `tool/` que sondam relays continuam assinando um `kind: 1` por conta própria (relay o retém; os kinds `20000`–`29999` não), sem fazer parte do protocolo das apps. Aplicada nas duas apps na mesma alteração (Princípio IV) |
| 19 | 2026-10-07 | Define `kind: 20013` para "Corrida cancelada pelo passageiro" (seção *Conteúdo do kind 20013*): o passageiro o publica ao cancelar uma corrida já aceita, e o motorista passa a se inscrever em `20013` (Forma da inscrição atualizada). O `20013` entra na cifragem da emenda 17 e na regra de recepção 7 | Pedido de simetria com o `20012` (emenda 14): só o motorista tinha saída de uma corrida aceita. O passageiro só cancelava a solicitação, antes de aceitar (recusa `20004`, que o motorista não consome), então o motorista só notava o sumiço por falta de sinal. Definido pela feature 020 do motorista e replicado na feature 023 do passageiro, na mesma alteração (Princípio IV). Kind novo, sem mudar nenhum formato existente |
| 20 | 2026-10-07 | Nenhum formato muda. O `kind: 20007` deixa de ser publicado uma única vez por corrida e passa a ser publicado **a cada 5 s** enquanto o motorista está em "Deslocando-se até o passageiro" e a posição está a até 10 m da origem da corrida ativa (primeira publicação ao entrar no raio); sair do raio ou mudar de estado interrompe. O passageiro tolera repetições: cada evento tem `id` próprio (a deduplicação por `id` não as colapsa) e só a primeira chegada muda a tela | Pedido de mais chances de entrega: o `20007` é efêmero e, publicado uma só vez, se perde se o passageiro estiver sem relay ou sem o app naquele instante, sem reentrega — o mesmo raciocínio que já levou o `20005` a repetir a cada 5 s. Definido pela feature 021 do motorista; o passageiro não muda de código (já deduplica por `id` e só abre a modal em "motorista a caminho"), só ganha um teste de regressão, na mesma alteração (Princípio IV) |
| 21 | 2026-10-12 | Nenhum formato muda. O raio em que o `kind: 20007` é publicado sobe de 10 m para **30 m** da origem da corrida ativa; o resto da regra (a cada 5 s, só em "Deslocando-se até o passageiro") não muda | Teste ponta a ponta em emuladores: motorista e passageiro com marcadores sobrepostos no mapa (~22 m, os marcadores de 44 px cobrem mais que isso) e o passageiro nunca recebia a chegada, porque 10 m fica abaixo do erro típico de GPS real (5–15 m). Definido pelo motorista; o passageiro não muda de código — só a descrição do contrato, na mesma alteração (Princípio IV) |
| 22 | 2026-10-12 | Nenhum formato muda. O raio em que o `kind: 20009` é publicado sobe de 5 m para **30 m** do destino da corrida ativa; o resto da regra (uma única vez por corrida, só em "Em corrida") não muda | Mesmo achado da emenda 21, agora na chegada ao destino: em teste ponta a ponta nos dois emuladores, ambos pareciam no destino, mas o `20009` não saiu e o passageiro não viu a modal de chegada; 5 m fica abaixo do erro típico de GPS real (5–15 m) e dos marcadores de 44 px, que cobrem ~45 m no zoom 17. Definido pelo motorista; o passageiro não muda de código — só a descrição do contrato, na mesma alteração (Princípio IV) |
| 23 | 2026-10-13 | Nenhum formato muda. O raio em que o `kind: 20009` é publicado sobe de 30 m para **1 km** do destino da corrida ativa; o resto da regra (uma única vez por corrida, só em "Em corrida") não muda | A busca de endereço (Photon) nem sempre localiza o destino com precisão, e o ponto gravado pode ficar a centenas de metros do local real; com 30 m a chegada podia nunca ser avisada. Pedido do autor. Definido pelo motorista; o passageiro não muda de código — só a descrição do contrato, na mesma alteração (Princípio IV) |
| 24 | 2026-10-13 | Nenhum formato muda. A confirmação de destino (`kind: 20010`) deixa de ser pedida por uma modal aberta ao chegar o `kind: 20009` e passa a ser um **botão** no mapa do passageiro, exibido em "Em corrida" enquanto a posição dele está a até 1 km do destino pedido; o passageiro deixa de reagir ao `20009`, que o motorista continua publicando | Pedido do autor: a confirmação deve depender de o app estar no raio do destino, e não de uma modal. Definido pelo passageiro; o motorista não muda de código — só a descrição do contrato, na mesma alteração (Princípio IV) |
| 25 | 2026-10-20 | Define `kind: 20014` para "Recibo de avaliação" e `kind: 20015` para "Confirmação de recibo" (seções *Conteúdo do kind 20014* e *20015*) e o campo opcional `reputacao` em `20001` (em claro) e `20002` (cifrado); as duas apps passam a se inscrever em `20014` e `20015` (Forma da inscrição atualizada); os dois kinds entram na cifragem da emenda 17 ("`20002` a `20015`") e na regra de recepção 7; nova seção *Reputação por recibos* (recibo, cadeia por avaliado, verificação, emissão, recepção e limites conhecidos) | Pedido do autor — reputação sem backend e sem guardar avaliações em relays: cada corrida concluída gera um recibo assinado pelo avaliador, entregue ao avaliado, que apresenta os mais recentes a quem for avaliá-lo. Definido pela feature 026 do motorista e replicado na feature 027 do passageiro, na mesma alteração (Princípio IV); constituição 2.17.0 (exceção do `20001`). Kinds novos e campo opcional novo: nenhum formato existente muda |
| 26 | 2026-10-20 | Nenhum kind nem campo novo. (1) *Recepção do recibo* (1.8): o avaliado só grava o `20014` se o `guid_corrida` for de uma negociação sua com o avaliador — motorista: orçamento que ele enviou ao avaliador; passageiro: orçamento que recebeu do avaliador —, senão descarta sem erro e sem `20015`; 1.9 ganha o limite correspondente. (2) *Campo `reputacao`* (1.5): lista com mais de N recibos torna a `reputacao` malformada, tratada como ausente | Teste ponta a ponta em emuladores (rodada 2 do quickstart da feature 026 do motorista): um recibo válido, assinado por um estranho, com `guid_corrida` inventado e nota 1, foi aceito pelo motorista e entrou em `corridas`, `avaliacoes` e `media` declaradas — nenhuma regra da 1.8 exigia que a corrida existisse. O item (2) fecha a pendência registrada em R9 da 026, e o passageiro já se comportava assim. Definido pelo motorista (feature 026) e replicado no passageiro (feature 027) na mesma alteração (Princípio IV) |
| 27 | 2026-10-21 | Define a tag `["g", "<geohash>"]` do `kind: 20001` (seção *Tag `g` do `20001`*), publicada pelo passageiro em **três precisões** (5, 4 e 3 caracteres) sobre a origem da corrida, sem alterar o `content`; a inscrição do motorista no `20001` passa a ser um filtro **à parte**, com `#g` = célula da posição de referência + 8 vizinhas (seção *Forma da inscrição* atualizada); nova regra de recepção 8 (só motorista) | Pedido do autor: o motorista recebia solicitações de qualquer lugar (ruído, banda, e o `limit: 50` preenchido por pedidos distantes). Definido pela feature 027 do motorista (raio de atendimento) e replicado no passageiro, na mesma alteração (Princípio IV). Kind e campo novos só como tag: nenhum formato de `content` muda. O raio e a posição de referência do motorista nunca saem do aparelho; o `#g` revela ao relay só a região aproximada (9 células) |

## Escopo desta feature

A feature 002 **não** definiu eventos de domínio de corridas (oferta, solicitação, mensagem): definiu
apenas o evento de teste que comprovava conectividade ponta a ponta, o `kind: 1`, retirado pela
emenda 18. Os formatos de domínio foram acrescentados a este arquivo pelas features seguintes,
mantendo a tabela de kinds abaixo como registro único.

## Envelope comum

Todo evento segue o envelope padrão do protocolo Nostr:

| Campo | Origem | Observação |
|-------|--------|------------|
| `id` | derivado | Hash canônico do evento; usado para deduplicação entre relays |
| `pubkey` | identidade local | Chave pública do autor (motorista ou passageiro) |
| `created_at` | relógio local do autor | Declarado pelo autor; **não confiável** como ordenação absoluta |
| `kind` | tabela abaixo | Define a semântica do evento |
| `tags` | por kind | Em todo evento do protótipo, a tag de marcador `["t", "tcc-ufsc-caronas"]` (mais as tags próprias de cada kind) |
| `content` | por kind | Kind `20001`: texto simples. Kinds `20002`–`20015` (emendas 17, 19 e 25): payload NIP-44 v2 cifrado ao destinatário — ver *Cifragem do `content`* |
| `sig` | derivado | Assinatura sobre `id`; verificada obrigatoriamente na recepção |

## Tabela de kinds do protótipo

| Kind | Nome | Definido em | Direção | Conteúdo | Proteção do `content` |
|------|------|-------------|---------|----------|-----------------------|
| — | Oferta de corrida | *futura* | motorista → passageiro | A definir | cifrado (previsto) |
| `20001` | Solicitação de corrida | feature 006 (passageiro) | passageiro → relays → motorista | JSON estruturado — ver *Conteúdo do kind 20001* abaixo; tags `t` e `g` (emenda 27) | **claro — exceção** (anúncio sem destinatário; emenda 17; `reputacao` opcional, emenda 25) |
| `20002` | Orçamento de corrida | feature 007 (motorista) | motorista → relays → passageiro | JSON estruturado — ver *Conteúdo do kind 20002* abaixo | cifrado ao destinatário (emenda 17) |
| `20003` | Aceitação de orçamento | feature 008 (passageiro) | passageiro → relays → motorista escolhido | Ver *Conteúdo do kind 20003* abaixo | cifrado ao destinatário (emenda 17) |
| `20004` | Recusa de orçamento | feature 008 (passageiro) | passageiro → relays → motorista não escolhido | Ver *Conteúdo do kind 20004* abaixo | cifrado ao destinatário (emenda 17) |
| `20005` | Localização do motorista | feature 010 (motorista) | motorista → relays → passageiro | Ver *Conteúdo do kind 20005* abaixo | cifrado ao destinatário (emenda 17) |
| `20006` | Corrida não pode mais ser atendida | feature 010 (motorista) | motorista → relays → passageiro | Ver *Kind 20006* abaixo | cifrado ao destinatário (emenda 17) |
| `20007` | Chegada do motorista | feature 011 (motorista) | motorista → relays → passageiro | Ver *Conteúdo do kind 20007* abaixo | cifrado ao destinatário (emenda 17) |
| `20008` | Encontro confirmado | feature 012 (motorista) | passageiro → relays → motorista | Ver *Conteúdo do kind 20008* abaixo | cifrado ao destinatário (emenda 17) |
| `20009` | Chegada ao destino | feature 012 (motorista) | motorista → relays → passageiro | Ver *Conteúdo do kind 20009* abaixo | cifrado ao destinatário (emenda 17) |
| `20010` | Destino confirmado | feature 012 (motorista) | passageiro → relays → motorista | Ver *Conteúdo do kind 20010* abaixo | cifrado ao destinatário (emenda 17) |
| `20011` | Rota da corrida | feature 017 (motorista) | motorista → relays → passageiro | JSON estruturado — ver *Conteúdo do kind 20011* abaixo | cifrado ao destinatário (emenda 17) |
| `20012` | Corrida cancelada | feature 018 (motorista) | motorista → relays → passageiro | Ver *Conteúdo do kind 20012* abaixo | cifrado ao destinatário (emenda 17) |
| `20013` | Corrida cancelada pelo passageiro | feature 020 (motorista) | passageiro → relays → motorista | Ver *Conteúdo do kind 20013* abaixo | cifrado ao destinatário (emendas 17 e 19) |
| `20014` | Recibo de avaliação | feature 026 (motorista) | avaliador → relays → avaliado (motorista ↔ passageiro) | Ver *Conteúdo do kind 20014* abaixo | cifrado ao destinatário (emenda 25) |
| `20015` | Confirmação de recibo | feature 026 (motorista) | avaliado → relays → avaliador | Ver *Conteúdo do kind 20015* abaixo | cifrado ao destinatário (emenda 25) |
| — | Mensagem entre pares | *futura* | bidirecional | A definir (exigirá criptografia de conteúdo) | cifrado (previsto) |

## Forma da inscrição (vale para as duas apps)

O formato do evento não basta para interoperar: as duas apps precisam **procurar pela mesma coisa**.
Toda inscrição (*subscription*) em eventos do protótipo MUST filtrar pelo marcador, e não apenas pelo
kind:

```text
["REQ", "<id-da-inscrição>", {"kinds": [20001], "#t": ["tcc-ufsc-caronas"], "limit": 50}]
```

Inscrever-se só por `kinds`, sem o filtro `#t`, entrega a qualquer evento de terceiros que use os
mesmos kinds — e MUST NOT ser usado. (Medido, com o `kind: 1` que as apps usavam antes da emenda 18:
cerca de 500 eventos alheios por relay já no primeiro segundo.)

A lista de `kinds` na inscrição real de cada app inclui só os kinds que ela efetivamente consome —
sempre com o filtro `#t` e o `limit`, iguais nas duas. O motorista inclui `20001` (recebe
solicitações, emenda 04), desde a emenda 08, `20003` (recebe aceitações de orçamento, feature 010
do motorista), e, desde a emenda 11, `20008` e `20010` (recebe as confirmações de encontro e de
destino do passageiro, feature 012 do motorista) e, desde a emenda 19, `20013` (recebe o cancelamento da
corrida pelo passageiro, feature 020 do motorista); o passageiro inclui `20002` (recebe orçamentos,
emenda 05, consumido pela feature 008 dele — emenda 07) e, desde a emenda 10, `20005` (recebe a
localização do motorista, feature 009 do passageiro) e, desde a emenda 13, `20011` (recebe a rota da
corrida, feature 018 do passageiro) e, desde a emenda 14, `20012` (recebe o cancelamento da corrida
pelo motorista, feature 019 do passageiro) e, desde a emenda 16, `20006` (recebe o aviso de que o
motorista não pode atender a corrida, feature 020 do passageiro). **Desde a emenda 25, as duas apps incluem também `20014` e `20015`** (recebem recibos de avaliação e as confirmações de recibo; ambos os papéis consomem os dois kinds). Nenhuma das duas apps consome `20004`
ainda (emenda 07, "Consumo pelo motorista" fora de escopo) — quando isso mudar, a app
correspondente acrescenta esses kinds à própria inscrição.

O `limit: 50` (emenda 02) bota um teto no histórico que o relay devolve ao estabelecer a inscrição.
Sem ele, as duas apps recebiam volumes diferentes de histórico — o motorista já limitava, o
passageiro não — e o passageiro acumulava mais eventos antigos a cada nova conexão. MUST NOT usar
`since`: no passageiro a mesma inscrição é reenviada a cada relay que conecta ou reconecta (regra de
vivacidade do `RelayService`, para que a inscrição sobreviva à queda de conexão), e um `since` calculado
uma vez no registro ficaria cada vez mais velho a cada reconexão, ao contrário do `limit`, que vale
igual em qualquer conexão.

**Inscrição do motorista no `20001` (emenda 27).** O exemplo acima vale para o **passageiro**, com os kinds que ele
consome (sem `20001`). O **motorista** usa dois filtros no mesmo `REQ`:

```text
["REQ", "<id-da-inscrição>",
  {"kinds": [<kinds do motorista exceto 20001>], "#t": ["tcc-ufsc-caronas"], "limit": 50},
  {"kinds": [20001], "#t": ["tcc-ufsc-caronas"], "#g": ["<célula>", ... até 9 ...], "limit": 50}]
```

- O **segundo filtro só existe com o motorista online**. Offline, o motorista inscreve só o primeiro: não pede
  solicitações. Ao ficar online (ou ao reconectar a um relay estando online), inscreve os dois; ao ficar
  offline, volta a um filtro só. Muda-se o `REQ` fechando a inscrição anterior (`CLOSE`) e abrindo outra.
- **Células**: a célula da posição de referência do motorista (a posição em que ficou online) e as 8 vizinhas
  (sem repetição; sem vizinha além do polo; a longitude dá a volta no antimeridiano), **todas de uma mesma
  precisão**, escolhida entre 5, 4 e 3 como a **maior** em que as 9 células cobrem o círculo de raio R em
  torno da referência. A cobertura garantida de uma precisão é `min(altura, largura × cos(φ'))`, com
  `φ' = min(|lat| + R/111,195 °, 89°)` — a distância da referência até a borda do bloco 3×3 é, no pior caso,
  uma célula. Se nem a precisão 3 cobre (latitudes acima de ~49°), usa-se a 3 mesmo assim: limite do protótipo,
  fora da região de uso.
- O raio é entre **1 e 100 km** e fica só no aparelho do motorista; **a posição de referência e o raio nunca
  são publicados em evento**. O filtro `#g` revela ao relay, porém, a região aproximada do motorista (as 9
  células); isso é custo aceito desta emenda.
- O `limit: 50` vale por filtro e só limita o histórico entregue ao abrir a inscrição.
- O relay pode ignorar `#g` (como pode ignorar `#t`): por isso a regra de recepção 8 vale sempre, e o filtro por
  célula não é mecanismo de segurança nem substitui a conferência de distância.

O marcador `tcc-ufsc-caronas` identifica o tráfego deste protótipo. Ele **não** é mecanismo de
segurança: qualquer pessoa pode publicar com a mesma tag, e por isso a verificação de assinatura
(regra 1 de recepção) e a checagem de autoria continuam obrigatórias.

**`kind: 1` fora do protocolo (emenda 18)**: a nota de texto padrão do NIP-01 serviu, até a emenda 17,
de teste de conectividade — aceita por qualquer relay público sem configuração especial. As apps não
a publicam nem a consomem mais, e MUST NOT incluí-la na inscrição. Eventos de domínio **não** reutilizam
`kind: 1`: têm kinds próprios, para não poluir nem serem poluídos pelo tráfego social geral da rede.

A emenda 04 estende a exigência do marcador a eventos de domínio: toda publicação e toda inscrição de
eventos deste protótipo, qualquer que seja o `kind`, MUST incluir a tag `["t", "tcc-ufsc-caronas"]` e
filtrar por ela. Sem isso, distinguir tráfego do protótipo do restante da rede exigiria depender
apenas do `kind`, que qualquer outro cliente Nostr pode escolher livremente e colidir por acaso.

## Conteúdo do kind 20001 — Solicitação de corrida (emenda 04)

Evento **efêmero** (faixa 20000–29999 do NIP-01: relays não retêm nem reenviam a inscrições futuras —
uma solicitação de corrida é, por natureza, um pedido momentâneo). Publicado pelo passageiro assim que
ele tem posição atual, destino e forma de pagamento disponíveis.

**Tags**: a tag de marcador do protótipo, `["t", "tcc-ufsc-caronas"]` — obrigatória em qualquer
kind deste protótipo (ver acima) — e, desde a emenda 27, três tags `g` (ver *Tag `g` do `20001`*, abaixo).

**`content`**: string JSON com este formato:

```json
{
  "origin": { "lat": -28.9298, "lon": -49.4753 },
  "destination": { "lat": -28.6721, "lon": -49.3671 },
  "payment": "pix"
}
```

| Campo | Tipo | Observação |
|-------|------|------------|
| `origin.lat`, `origin.lon` | `number` (graus decimais) | Posição atual do passageiro no instante da publicação; sem truncamento de precisão |
| `destination.lat`, `destination.lon` | `number` (graus decimais) | Destino escolhido pelo passageiro; sem truncamento de precisão |
| `payment` | `string`, um de `"dinheiro"`, `"pix"`, `"cartao"` | Forma de pagamento escolhida pelo passageiro; nenhum outro valor é válido |

Campo opcional (emenda 25): `reputacao`, ver *Reputação por recibos*, seção 1.5 — ausente = passageiro sem histórico; em
claro, como o resto do `content`. Nenhum outro campo é definido. `content` continua sendo dado, nunca instrução — regra 3
de recepção, abaixo, vale igualmente para este `kind`; um `reputacao` malformado não invalida a solicitação, é tratado como ausente.

**Privacidade (exceção da emenda 17)**: publicado sem criptografia, deliberadamente — é o **único** kind de domínio que continua em claro (só assinado), pois é um anúncio a qualquer motorista
interessado, não uma mensagem a um destinatário já escolhido. A justificativa completa, exigida pela
seção "Restrições de Segurança e Privacidade" da constituição, está no `spec.md` da feature 006 do
passageiro. A emenda 25 acrescenta o campo opcional `reputacao`, que expõe em claro as chaves públicas das
contrapartes anteriores e as notas dadas (limites na seção 1.9 de *Reputação por recibos*; constituição 2.17.0).

**Consumo pelo motorista**: fora de escopo da feature 006 — este contrato define apenas o formato
publicado. A app do motorista se inscrever neste `kind` e reagir a ele é trabalho de uma feature
futura.

### Tag `g` do `20001` (emenda 27)


## Conteúdo do kind 20002 — Orçamento de corrida (emenda 05, ampliada pela emenda 06)

Evento **efêmero** (mesma faixa 20000–29999 do `kind: 20001` — um orçamento perde sentido depois
que a corrida for decidida, não há razão para o relay retê-lo). Publicado pelo motorista em
resposta a uma solicitação de corrida (`kind: 20001`) específica, quando ele decide enviar um
orçamento em vez de recusar.

**Tags**: a tag de marcador do protótipo, `["t", "tcc-ufsc-caronas"]`, **e** uma tag de referência
ao evento respondido, `["e", "<id-da-solicitação>"]`, onde `<id-da-solicitação>` é o `id` do evento
`kind: 20001` original. Diferente do `kind: 20001` (só a tag de marcador), este kind precisa de uma
segunda tag porque é uma resposta a um evento específico, não um anúncio — sem a referência, nada
liga o orçamento à corrida a que ele se refere. Desde a emenda 17 leva também uma tag de
destinatário, `["p", "<pubkey-do-solicitante>"]` — a chave pública do autor (`pubkey`) do `kind: 20001`
respondido —, de onde se tira a chave com que o `content` é cifrado.

**`content`**: string JSON com este formato:

```json
{
  "pricePerKm": 2.5,
  "total": 18.75,
  "driverName": "Fulano da Silva",
  "carBrand": "Fiat",
  "carModel": "Palio",
  "carYear": 2018,
  "etaMinutes": 6
}
```

| Campo | Tipo | Observação |
|-------|------|------------|
| `pricePerKm` | `number` | Preço por quilômetro usado neste orçamento — pode diferir do preço padrão do cadastro do motorista (editável só para esta corrida, `spec.md` da feature 007 do motorista) |
| `total` | `number` | `pricePerKm` multiplicado pela distância real entre origem e destino da solicitação; calculado pelo motorista, não recalculado pelo relay nem por este contrato |
| `driverName` | `string` | Nome do motorista, copiado do cadastro (feature 003) no momento do envio (emenda 06) |
| `carBrand`, `carModel` | `string` | Marca e modelo do veículo, copiados do cadastro (feature 003) no momento do envio (emenda 06) |
| `carYear` | `number` (inteiro) | Ano-modelo do veículo, copiado do cadastro (feature 008) no momento do envio (emenda 06) |
| `etaMinutes` | `number` (inteiro), **opcional** | Tempo estimado do trajeto motorista→origem, em minutos, derivado da mesma chamada de rota que calcula essa distância (feature 007/009 do motorista). **Omitido** (chave ausente do JSON, não `null` nem `0`) quando essa duração não pôde ser calculada — emenda 06 |
| `reputacao` | objeto, **opcional** (emenda 25) | Reputação do motorista (seção 1.5 de *Reputação por recibos*): contagens declaradas e os 5 recibos mais recentes. **Omitido** (chave ausente, não `null`) quando o motorista não tem recibos. Cifrado junto com o resto do `content` |

Nenhum outro campo é definido nestas emendas. `content` continua sendo dado, nunca instrução —
regra 3 de recepção, abaixo, vale igualmente para este `kind`. Valores numéricos em ponto
flutuante (`pricePerKm`, `total`) ou inteiro (`carYear`, `etaMinutes`) — quem exibe decide o
arredondamento, este contrato não impõe nenhum.

**Privacidade**: cifrado ao solicitante (emenda 17). Antes dela era publicado sem criptografia, pela
mesma razão do `kind: 20001`; agora só o autor do `20001` respondido lê o orçamento. Não inclui nenhum dado de localização: origem e destino já estão no evento
`kind: 20001` referenciado pela tag `["e", ...]`. A emenda 06 acrescenta o primeiro dado de
identificação pessoal do protótipo (`driverName`) a um evento público — aceito porque é o mesmo
nome que o motorista já digitou como identificação de si mesmo no cadastro (feature 003), voltado
publicamente a qualquer passageiro que vier a negociar com ele; não é um dado novo exposto, é o
mesmo dado já existente agora publicado no lugar certo para cumprir o propósito do orçamento.

**Consumo pelo passageiro**: implementado pela feature 008 do passageiro (emenda 07) — persiste
cada orçamento recebido, associando-o à solicitação correspondente pela tag `["e", ...]`, e exibe
todos os de uma mesma solicitação numa modal, com a opção de aceitar um deles.

## Conteúdo do kind 20003 — Aceitação de orçamento (emenda 07)

Evento **efêmero** (mesma faixa 20000–29999). Publicado pelo passageiro quando ele aceita um
orçamento (`kind: 20002`) específico, entre os recebidos para uma solicitação.

**Tags**: a tag de marcador do protótipo, `["t", "tcc-ufsc-caronas"]`; uma tag de referência ao
orçamento aceito, `["e", "<id-do-orçamento>"]`, onde `<id-do-orçamento>` é o `id` do evento
`kind: 20002` correspondente; e uma tag de destinatário, `["p", "<pubkey-do-motorista>"]`, a chave
pública de quem publicou aquele orçamento — a mesma convenção do NIP-01 para marcar a quem um
evento se dirige, ainda que o relay o entregue a qualquer inscrito.

**`content`**: string vazia (`""`) — toda a informação necessária já está nas tags; não há campo
adicional definido nesta emenda.

**Privacidade**: cifrado ao motorista do orçamento (emenda 17). Não inclui nenhum dado de localização
nem pessoal.

**Consumo pelo motorista**: fora de escopo desta emenda — este contrato define apenas o formato
publicado. A app do motorista se inscrever neste `kind`, reconhecer que um dos seus orçamentos foi
aceito e reagir a isso é trabalho de uma feature futura (mesmo padrão que a emenda 04 já aplicou ao
`kind: 20001`).

## Conteúdo do kind 20004 — Recusa de orçamento (emenda 07)

Evento **efêmero** (mesma faixa 20000–29999). Publicado pelo passageiro, um evento por motorista,
para cada orçamento que **não** foi o escolhido entre os recebidos para uma solicitação — no
mesmo momento em que o `kind: 20003` é publicado para o orçamento aceito.

**Tags**: a tag de marcador do protótipo, `["t", "tcc-ufsc-caronas"]`; uma tag de referência ao
orçamento recusado, `["e", "<id-do-orçamento>"]`; e uma tag de destinatário,
`["p", "<pubkey-do-motorista>"]` — mesmo formato do `kind: 20003`, trocando "aceitação" por
"recusa" no significado.

**`content`**: string vazia (`""`) — mesma razão do `kind: 20003`.

**Privacidade**: mesma do `kind: 20003`.

**Consumo pelo motorista**: fora de escopo desta emenda — mesmo padrão do `kind: 20003`.

**Consumo pelo motorista (emenda 08)**: implementado pela feature 010 do motorista — ao receber um
`kind: 20003` referenciando um orçamento que ele efetivamente enviou, com o motorista no estado
"Aguardando solicitação de corrida", exibe uma modal informando que o orçamento foi aceito. Ao
confirmar, o motorista passa ao estado "Deslocando-se até o passageiro" (estado local, não
publicado em nenhum evento) e passa a publicar `kind: 20005` (ver abaixo). Uma segunda aceitação
chegando enquanto o motorista já está nesse estado — ou, desde a emenda 16, em "Em corrida" — não
abre modal; publica `kind: 20006` (ver abaixo) ao passageiro daquela aceitação. O `kind: 20004` continua sem consumo pelo motorista.

## Conteúdo do kind 20005 — Localização do motorista (emenda 08)

Evento **efêmero** (mesma faixa 20000–29999 — uma posição perde sentido assim que uma nova chega,
não há razão para o relay retê-la). Publicado pelo motorista, repetidamente, enquanto ele estiver no
estado local "Deslocando-se até o passageiro" (feature 010), a cada 5 s desde a última
publicação.

**Tags**: a tag de marcador do protótipo, `["t", "tcc-ufsc-caronas"]`; uma tag de referência ao
orçamento aceito que originou o deslocamento, `["e", "<id-do-orçamento>"]` — o mesmo `id` de
`kind: 20002` já referenciado pela aceitação (`kind: 20003`) que o motorista recebeu; e uma tag de
destinatário, `["p", "<pubkey-do-passageiro>"]`, a chave pública de quem aceitou aquele orçamento
(lida do campo `pubkey`, autor, do evento de aceitação — a própria aceitação não traz essa chave numa
tag, só a do motorista).

**`content`**: string JSON com este formato:

```json
{ "lat": -28.9312, "lon": -49.4889 }
```

| Campo | Tipo | Observação |
|-------|------|------------|
| `lat`, `lon` | `number` (graus decimais) | Posição atual do motorista no instante da publicação; sem truncamento de precisão — mesmo formato de `origin`/`destination` do `kind: 20001` |

**Privacidade**: cifrado ao passageiro (emenda 17), que já aceitou uma corrida com este
motorista — mesma justificativa dos kinds anteriores (resposta pública dentro de um fluxo já
público entre as duas partes). Não inclui nenhum dado além da posição e dos identificadores de
correlação já necessários (`quoteId`, `pubkey` do destinatário).

**Consumo pelo passageiro (emendas 10 e 12)**: implementado pelas features 009 e 016 do passageiro.
Só vale a localização **assinada pelo motorista cujo orçamento o passageiro aceitou** (o autor do
evento, `pubkey`, MUST bater com o autor do `kind: 20002` aceito — a tag `["e", ...]` é pública no
relay e não basta) e que referencia o `quoteId` aceito. A primeira ocorrência é o sinal de que o
motorista começou a se deslocar (feature 009: exibe uma modal avisando isso; o sinal não depende de o
`content` ser válido). Desde a emenda 12, o passageiro também decodifica `lat`/`lon` e mostra o motorista
no mapa enquanto está em "motorista a caminho": só a posição mais nova (por `created_at`, declarado
pelo autor — vale apenas para um ponto antigo não sobrescrever um novo, não é decisão de segurança),
`content` malformado ou fora de faixa (`lat` −90..90, `lon` −180..180) é descartado sem alterar o
marcador, e a posição existe só em memória, nunca persistida nem reenviada.

## Conteúdo do kind 20006 — Corrida não pode mais ser atendida (emenda 08, ampliada pela 16)

Evento **efêmero** (mesma faixa 20000–29999). Publicado pelo motorista quando uma aceitação de
orçamento (`kind: 20003`) chega enquanto ele já está no estado "Deslocando-se até o passageiro" ou,
desde a emenda 16, "Em corrida" (comprometido com outra corrida) — um evento por aceitação nessa
condição, dirigido ao passageiro que a enviou. (A emenda 15 chegou a aposentá-lo; a 16 o restaurou.)

**Tags**: a tag de marcador do protótipo, `["t", "tcc-ufsc-caronas"]`; uma tag de referência ao
orçamento aceito que não pode mais ser atendido, `["e", "<id-do-orçamento>"]`; e uma tag de
destinatário, `["p", "<pubkey-do-passageiro>"]` — mesmo formato do `kind: 20005`, mesma forma de
obter a chave do passageiro (campo `pubkey` da aceitação recebida).

**`content`**: string vazia (`""`) — toda a informação necessária já está nas tags, mesma convenção
dos kinds 20003/20004.

**Privacidade**: mesma dos demais kinds efêmeros deste contrato — cifrado ao destinatário (emenda 17), sem dado além
dos identificadores de correlação.

**Consumo pelo passageiro (emenda 16)**: implementado pela feature 020 dele. Só vale evento **assinado
pelo motorista cujo orçamento o passageiro aceitou** (autor = autor do `kind: 20002` aceito) e que
referencia o `quoteId` da corrida aceita, com o passageiro em "orçamento aceito" (fase em que ainda
não recebeu localização desse motorista): exibe uma modal informando que o motorista não pode atender
e encerra a corrida no app dele, voltando ao estado inicial. Fora dessas condições (outra corrida,
outro autor, passageiro em outra fase), é ignorado sem erro. Um evento duplicado ou reentregue não
tem efeito além do primeiro.

## Conteúdo do kind 20007 — Chegada do motorista (emenda 09)

Evento **efêmero** (mesma faixa 20000–29999 — perde sentido depois que o passageiro embarca, não
há razão para o relay retê-lo). Publicado pelo motorista **a cada 5 s** (emenda 20; antes, uma única
vez por corrida) enquanto sua posição está a até 30 m (emenda 21; antes, 10 m) do ponto de origem da solicitação que gerou a
corrida ativa e ele está no estado "Deslocando-se até o passageiro" (feature 010): a primeira
publicação sai ao entrar no raio, as seguintes quando a posição capturada avança 5 s da última
publicação; fora do raio, ou fora desse estado (confirmação de encontro, cancelamento), nada é
publicado.

**Tags**: a tag de marcador do protótipo, `["t", "tcc-ufsc-caronas"]`; uma tag de referência ao
orçamento aceito daquela corrida, `["e", "<id-do-orçamento>"]`; e uma tag de destinatário,
`["p", "<pubkey-do-passageiro>"]` — mesmo formato dos kinds 20005/20006.

**`content`**: string vazia (`""`) — toda a informação necessária já está nas tags e no próprio
kind, mesma convenção dos kinds 20003/20004/20006.

**Privacidade**: mesma dos demais kinds efêmeros deste contrato — cifrado ao destinatário (emenda 17), sem dado além
dos identificadores de correlação já usados pelos kinds 20005/20006.

**Consumo pelo passageiro**: fora de escopo desta emenda — mesmo padrão dos kinds anteriores. Desde a
emenda 20 repetições são esperadas e idempotentes: cada evento tem `id` próprio e a regra de recepção 2
(deduplicação por `id`) não as colapsa, então o passageiro as trata no estado: só a primeira chegada em
"motorista a caminho" abre a tela de chegada; as seguintes, com a tela já aberta, não mudam nada, e depois
da confirmação de encontro são ignoradas.

## Conteúdo do kind 20008 — Encontro confirmado (emenda 11)

Evento **efêmero** (mesma faixa 20000–29999). Publicado pelo passageiro quando confirma, numa
modal do próprio app dele, que encontrou o motorista — resposta ao aviso de chegada à origem
(`kind: 20007`).

**Tags**: a tag de marcador do protótipo, `["t", "tcc-ufsc-caronas"]`; uma tag de referência ao
orçamento aceito daquela corrida, `["e", "<id-do-orçamento>"]`; e uma tag de destinatário,
`["p", "<pubkey-do-motorista>"]` — mesmo formato dos kinds 20003/20004/20005/20006/20007, agora na
direção passageiro → motorista.

**`content`**: string vazia (`""`) — toda a informação necessária já está nas tags e no próprio
kind, mesma convenção dos kinds 20003/20004/20006/20007.

**Privacidade**: mesma dos demais kinds efêmeros deste contrato — cifrado ao destinatário (emenda 17), sem dado além
dos identificadores de correlação já usados pelos kinds anteriores.

**Consumo pelo motorista**: implementado pela feature 012 do motorista — ao receber, referenciando
o orçamento da corrida ativa, com o motorista no estado "Deslocando-se até o passageiro",
transiciona para "Em corrida". Fora dessas condições (corrida diferente, ou motorista fora desse
estado), é ignorado sem erro.

## Conteúdo do kind 20009 — Chegada ao destino (emenda 11)

Evento **efêmero** (mesma faixa 20000–29999 — perde sentido depois que a corrida termina, não há
razão para o relay retê-lo). Publicado pelo motorista uma única vez por corrida, quando sua posição
entra num raio de 1 km (emenda 23; antes, 30 m na 22 e 5 m na 11) do destino da solicitação que gerou a corrida ativa, durante o estado "Em
corrida" (feature 012).

**Tags**: a tag de marcador do protótipo, `["t", "tcc-ufsc-caronas"]`; uma tag de referência ao
orçamento aceito daquela corrida, `["e", "<id-do-orçamento>"]`; e uma tag de destinatário,
`["p", "<pubkey-do-passageiro>"]` — mesmo formato do `kind: 20007`.

**`content`**: string vazia (`""`) — mesma convenção dos demais kinds efêmeros deste contrato.

**Privacidade**: mesma dos demais kinds efêmeros deste contrato — cifrado ao destinatário (emenda 17), sem dado além
dos identificadores de correlação já usados pelos kinds anteriores.

**Consumo pelo passageiro**: desde a emenda 24 o passageiro não usa este aviso para abrir nada — o botão de
confirmação aparece pela posição dele (ver `kind: 20010`). O motorista segue publicando.

## Conteúdo do kind 20010 — Destino confirmado (emenda 11)

Evento **efêmero** (mesma faixa 20000–29999). Publicado pelo passageiro quando confirma, num
botão do próprio app dele, que chegaram ao destino. O botão aparece em "Em corrida" enquanto a posição do
próprio passageiro está a até 1 km do destino pedido (emenda 24; antes, era uma modal aberta pelo aviso
`kind: 20009`).

**Tags**: a tag de marcador do protótipo, `["t", "tcc-ufsc-caronas"]`; uma tag de referência ao
orçamento aceito daquela corrida, `["e", "<id-do-orçamento>"]`; e uma tag de destinatário,
`["p", "<pubkey-do-motorista>"]` — mesmo formato do `kind: 20008`.

**`content`**: string vazia (`""`) — mesma convenção dos demais kinds efêmeros deste contrato.

**Privacidade**: mesma dos demais kinds efêmeros deste contrato — cifrado ao destinatário (emenda 17), sem dado além
dos identificadores de correlação já usados pelos kinds anteriores.

**Consumo pelo motorista**: implementado pela feature 012 do motorista — ao receber, referenciando
o orçamento da corrida ativa, com o motorista no estado "Em corrida", transiciona de volta para
"Aguardando solicitação de corrida" e encerra a corrida ativa. Fora dessas condições, é ignorado
sem erro.

## Conteúdo do kind 20011 — Rota da corrida (emenda 13)

Evento **efêmero** (mesma faixa 20000–29999 — uma rota perde sentido assim que uma nova chega).
Publicado pelo motorista **a cada cálculo ou recálculo bem-sucedido do trajeto até o destino**,
somente enquanto está no estado local "Em corrida" (feature 012); nunca em "Deslocando-se até o
passageiro" nem em "Aguardando solicitação de corrida", e nunca quando o cálculo falha.

**Tags**: a tag de marcador do protótipo, `["t", "tcc-ufsc-caronas"]`; uma tag de referência ao
orçamento aceito daquela corrida, `["e", "<id-do-orçamento>"]`; e uma tag de destinatário,
`["p", "<pubkey-do-passageiro>"]` — mesmo formato do `kind: 20005`.

**`content`**: string JSON com este formato:

```json
{ "points": [[-28.93123, -49.48891], [-28.93140, -49.48870]] }
```

| Campo | Tipo | Observação |
|-------|------|------------|
| `points` | lista de `[lat, lon]` | Trajeto da posição do motorista, no instante do cálculo, até o destino da corrida, na ordem de percurso. Mínimo 2 pontos, **máximo 1000**. `lat`/`lon` em graus decimais com **no máximo 5 casas** (~1 m). Se a rota calculada tiver mais de 1000 pontos, o motorista toma pontos uniformemente espaçados, sempre preservando o primeiro e o último |

**Tamanho**: ~21 KB com 1000 pontos (mensagem inteira medida em 21 237 B), ~16 % do menor `max_message_length` anunciado pelos relays
padrão (131 072 B em `nos.lol`/`offchain.pub`, medido em 2026-10-03).

**Privacidade**: cifrado ao passageiro daquela corrida (emenda 17) — mesma justificativa
dos kinds anteriores. Origem e destino já constam do `kind: 20001`, e a posição do motorista, do
`kind: 20005`; este evento não acrescenta dado sobre pessoas além do trajeto entre eles.

**Consumo pelo passageiro**: implementado pela feature 018 dele. Só vale rota **assinada pelo
motorista cujo orçamento o passageiro aceitou** (autor do evento = autor do `kind: 20002` aceito) e
que referencia o `quoteId` da corrida, com o passageiro em "Em corrida"; vale a de maior
`created_at`; `content` malformado, com menos de 2 ou mais de 1000 pontos, ou com coordenadas fora
de faixa, é descartado sem alterar o traçado; só em memória, nunca persistido. Fora dessas
condições, é ignorado sem erro.

## Conteúdo do kind 20012 — Corrida cancelada (emenda 14)

Evento **efêmero** (mesma faixa 20000–29999). Publicado pelo motorista **uma única vez por corrida**,
quando ele cancela a corrida ativa enquanto está no estado local "Deslocando-se até o passageiro" ou
"Em corrida" (features 010 e 012). Nunca é publicado em "Aguardando solicitação de corrida".

**Tags**: a tag de marcador do protótipo, `["t", "tcc-ufsc-caronas"]`; uma tag de referência ao
orçamento aceito daquela corrida, `["e", "<id-do-orçamento>"]`; e uma tag de destinatário,
`["p", "<pubkey-do-passageiro>"]` — mesmo formato dos `kind: 20007` e `20009`.

**`content`**: string vazia (`""`) — não há motivo nem posição; mesma convenção dos demais kinds
efêmeros sem dado próprio.

**Privacidade**: mesma dos demais kinds efêmeros deste contrato — cifrado ao destinatário (emenda 17), sem dado além
dos identificadores de correlação já usados pelos kinds anteriores.

**Consumo pelo passageiro**: implementado pela feature 019 dele. Só vale evento **assinado pelo
motorista cujo orçamento o passageiro aceitou** (autor = autor do `kind: 20002` aceito) e que
referencia o `quoteId` da corrida aceita, com o passageiro em "orçamento aceito", "motorista a
caminho" ou "em corrida": exibe uma modal informando o cancelamento e encerra a corrida no app dele.
Fora dessas condições (outra corrida, outro autor, corrida já encerrada ou concluída), é ignorado
sem erro. Um evento duplicado ou reentregue não tem efeito além do primeiro.

## Conteúdo do kind 20013 — Corrida cancelada pelo passageiro (emenda 19)

Evento **efêmero** (mesma faixa 20000–29999). Publicado pelo passageiro **uma única vez por corrida**,
quando ele cancela uma corrida já aceita enquanto está no estado local "orçamento aceito", "motorista a
caminho" ou "em corrida" (features 014 e 023 dele). Nunca é publicado antes de aceitar um orçamento — ali
o cancelamento da solicitação usa o `kind: 20004` — nem depois de a corrida concluída.

**Tags**: a tag de marcador do protótipo, `["t", "tcc-ufsc-caronas"]`; uma tag de referência ao
orçamento aceito daquela corrida, `["e", "<id-do-orçamento>"]`; e uma tag de destinatário,
`["p", "<pubkey-do-motorista>"]` — mesmo formato dos `kind: 20003` e `20008`.

**`content`**: string vazia (`""`) — não há motivo nem posição; mesma convenção dos demais kinds
efêmeros sem dado próprio.

**Privacidade**: cifrado ao motorista (emendas 17 e 19), sem dado além dos identificadores de
correlação já usados pelos kinds anteriores.

**Consumo pelo motorista**: implementado pela feature 020 dele. Só vale evento **assinado pelo
passageiro cuja aceitação o motorista recebeu** (autor = passageiro da corrida ativa) e que referencia o
`quoteId` da corrida ativa, com o motorista em "Deslocando-se até o passageiro" ou "Em corrida": ele volta a
"Aguardando solicitação de corrida", encerra a corrida (sem avaliação) e exibe uma modal informando o
cancelamento. Fora dessas condições (outra corrida, outro autor, nenhuma corrida ativa), é ignorado sem
erro. Um evento duplicado ou reentregue não tem efeito além do primeiro.

## Conteúdo do kind 20014 — Recibo de avaliação (emenda 25)

Evento **efêmero** (faixa 20000–29999). Publicado pelo **avaliador** ao encerrar uma corrida concluída — com ou
sem nota —, endereçado ao **avaliado** (motorista avalia passageiro e passageiro avalia motorista), e reenviado
enquanto não chega o `20015` correspondente (seção 1.7 de *Reputação por recibos*). Nunca é publicado para corrida
cancelada ou não concluída.

**Tags**: marcador `["t", "tcc-ufsc-caronas"]`; `["e", "<guid_corrida>"]` (o `id` do `kind: 20002` aceito); e
`["p", "<pubkey_avaliado>"]`.

**`content`**: o recibo completo (JSON, com `assinatura`), formato da seção 1.2, cifrado NIP-44 ao avaliado. **Não**
usa o marcador `{}`: o recibo é o dado próprio do kind.

**Privacidade**: cifrado ao avaliado (emenda 25). O recibo carrega as duas chaves públicas e a nota, visíveis só às
partes; o avaliado é quem decide apresentá-lo depois (seção 1.5, `20001`/`20002`).

**Recepção**: regra 7 e seção 1.8. Recibo cuja tag `p` não é a chave do receptor, em claro, com assinatura ou
`id_recibo` inválidos, de `guid_corrida` diferente da tag `e`, ou de avaliador diferente do autor do evento, é
descartado sem erro e sem efeito.

## Conteúdo do kind 20015 — Confirmação de recibo (emenda 25)

Evento **efêmero** (faixa 20000–29999). Publicado pelo **avaliado** ao gravar um `20014` válido (ou ao recebê-lo de
novo, já gravado e idêntico), endereçado ao **avaliador**, para que este pare de reenviar.

**Tags**: marcador `["t", "tcc-ufsc-caronas"]`; `["e", "<guid_corrida>"]`; `["p", "<pubkey_avaliador>"]`.

**`content`**: `{"id_recibo":"<hex>"}`, cifrado NIP-44 ao avaliador. **Não** usa o marcador `{}`.

**Recepção**: regra 7. Só vale confirmação **assinada pelo avaliado do recibo pendente** e com `id_recibo` igual ao
do recibo emitido para aquela corrida; qualquer outra é ignorada sem erro.

## Reputação por recibos

> Esta seção MUST ser copiada **literalmente** para `specs/002-nostr-relay-connection/contracts/nostr-events.md` das duas apps, na mesma alteração em que o código muda (Princípio IV). É o único acoplamento entre as apps.

### 1.1 Objetivo

Reputação **sem backend e sem guardar avaliações em relays**: cada corrida concluída gera um **recibo assinado** pelo avaliador, entregue ao avaliado, que o guarda localmente e o apresenta (últimos N) quando for avaliado por outro usuário. Os recibos de cada avaliado formam uma **cadeia numerada e encadeada por hash**.

### 1.2 Recibo

Objeto JSON, **sem** o campo `assinatura` para fins de hash:

| Campo | Tipo | Regra |
|---|---|---|
| `v` | int | `1` |
| `guid_corrida` | string hex(64) | `id` do evento `kind: 20002` aceito (`quoteId`). Já é comum às duas apps |
| `pubkey_avaliador` | string hex(64) | autor do recibo |
| `pubkey_avaliado` | string hex(64) | quem recebe o recibo |
| `nota` | int 1–5, **opcional** | chave omitida se o avaliador não avaliou (conta como corrida, não como avaliação) |
| `criado_em` | int | epoch em segundos (só informativo; NUNCA usado para ordenar com segurança, regra 5) |
| `seq` | int ≥ 0 | posição na cadeia **do avaliado** |
| `hash_anterior` | string hex(64), **opcional** | `id_recibo` do recibo `seq−1`; omitido quando `seq = 0` |
| `id_recibo` | string hex(64) | SHA-256 de `canonico(recibo)` (abaixo) |
| `assinatura` | string hex(128) | Schnorr (BIP-340) do avaliador sobre `id_recibo` |

**Forma canônica** (UTF-8, campos separados por `|`, ausente = `-`):

```text
tcc-recibo-v1|<guid_corrida>|<pubkey_avaliador>|<pubkey_avaliado>|<nota|->|<criado_em>|<seq>|<hash_anterior|->
```

`id_recibo = SHA-256(canonico)` em hex minúsculo. A assinatura usa a mesma API que `RideRatingSignature` já usa (`nostr.Nostr.instance.services.keys.sign/verify`). A chave privada **nunca** entra em hash, log ou evento (constituição).

### 1.3 Cadeia

- Há uma cadeia **por avaliado**. `seq` começa em `0` e cresce de 1 em 1.
- O avaliador copia `seq` e `hash_anterior` do **estado declarado pelo avaliado** (1.5), depois de verificá-lo (1.6).
- Recibos chegando fora de ordem são aceitos; a ordem é por `seq`. Ramos (dois recibos com o mesmo `seq`, de corridas diferentes) são tolerados e exibidos como tal; o `seq` repetido em recibo recebido **para a mesma corrida** é rejeitado.

### 1.4 Novos kinds (efêmeros, cifrados NIP-44 ao destinatário, tags `t`, `e`, `p` como nos demais)

| Kind | Nome | Autor → destinatário | `e` | `content` (antes de cifrar) |
|---|---|---|---|---|
| `20014` | Recibo de avaliação | avaliador → avaliado | `guid_corrida` | o recibo completo (JSON, com `assinatura`) |
| `20015` | Confirmação de recibo | avaliado → avaliador | `guid_corrida` | `{"id_recibo":"<hex>"}` |

Entram na lista de cifragem da emenda 17 ("kinds 20002 a 20015") e na regra de recepção 7. Ambos os papéis (motorista e passageiro) consomem os dois kinds: **acrescentar `20014` e `20015` ao conjunto de kinds consumidos** de cada app (e à documentação "Forma da inscrição").

### 1.5 Campo `reputacao` (em `20001` e `20002`)

Acrescentado ao JSON de `content` do `20001` (passageiro, **em claro**) e do `20002` (motorista, cifrado). **Opcional**: ausente = usuário sem histórico.

```json
"reputacao": {
  "corridas": 12,
  "avaliacoes": 9,
  "media": 4.78,
  "seq_proximo": 12,
  "head": "<id_recibo do seq 11>",
  "recibos": [ { …recibo completo… }, … ]
}
```

- `corridas` = nº de recibos guardados; `avaliacoes` = nº com `nota`; `media` = média das notas (omitir se `avaliacoes = 0`). **Declarados**; só os `recibos` são verificáveis.
- `seq_proximo` = próximo `seq` a ser usado; `head` = `id_recibo` do recibo `seq_proximo−1` (omitido se `seq_proximo = 0`).
- `recibos` = os **N mais recentes** por `seq` (N = 5, constante `kReputacaoJanela`), do mais novo para o mais antigo. Uma lista com **mais de N** recibos torna a `reputacao` **malformada** (emenda 26): é tratada como ausente, sem verificar nenhum recibo dela.
- Limite de tamanho do `content`: continua 65 535 bytes (NIP-44).

### 1.6 Verificação ao receber uma `reputacao` (função pura, testável)

Para cada recibo: (a) `id_recibo` recalculado confere; (b) assinatura válida para `pubkey_avaliador`; (c) `pubkey_avaliado` == autor do evento (`pubkey` do `20001`/`20002`); (d) `v == 1`, `nota` ∈ 1..5 se presente; (e) `seq` estritamente decrescente na lista; (f) `guid_corrida` sem repetição; (g) `pubkey_avaliador != pubkey_avaliado`. Recibo inválido é **descartado e contado**. Depois: (h) `head` MUST ser o `id_recibo` do recibo de `seq = seq_proximo−1` presente na lista, senão a reputação é marcada **inconsistente**; (i) para recibos consecutivos na lista, `hash_anterior` do mais novo MUST ser o `id_recibo` do `seq−1` se este estiver presente; lacunas de `seq` são exibidas ("N recibos não apresentados").

Resultado exibido: **"verificado nos últimos N"** (média e contagem calculadas só sobre recibos válidos) separado do **"declarado"** (`corridas`, `avaliacoes`, `media`). Nunca misturar os dois numa só nota.

### 1.7 Emissão do recibo (avaliador)

1. Ao encerrar a corrida (modal de avaliação fechada, com ou sem nota), obter a `reputacao` que o **avaliado declarou nesta corrida** (guardada no momento do orçamento/solicitação, 2.x).
2. Verificar (1.6). Se **inconsistente**, NÃO emitir recibo, avisar o usuário em uma linha; a nota local (`ride_ratings`) continua gravada.
3. `seq = seq_proximo`, `hash_anterior = head`; montar, calcular `id_recibo`, assinar.
4. Gravar em `recibos_emitidos` com `pendente = 1` **antes** de publicar (sobrevive a reinício).
5. Publicar `kind: 20014`. Reenviar enquanto `pendente = 1`: a cada reconexão de relay, ao abrir o app e a cada 60 s enquanto a interface do app estiver ativa (temporizador próprio do serviço de recibos; o serviço em segundo plano não tem a chave privada e não reenvia). Para quando chegar `20015` com o `id_recibo` correspondente.
6. Corrida cancelada ou não concluída: **nenhum recibo**.

### 1.8 Recepção do recibo (avaliado)

Depois das regras 1, 2, 6 e 7 de recepção: validar (1.6 a–d, g) com `pubkey_avaliado == minha chave` e `pubkey_avaliador == autor do evento`; `guid_corrida` == tag `e`; **o `guid_corrida` ser de uma corrida conhecida do avaliado com o avaliador** (abaixo, emenda 26); não existir recibo salvo para o mesmo `guid_corrida` (se existir e for idêntico, apenas reenviar `20015`; se diferente, ignorar). Gravar em `recibos_recebidos` (imutável) e publicar `20015`. Recalcular `corridas`, `avaliacoes`, `media`, `seq_proximo = max(seq)+1`, `head` = `id_recibo` do maior `seq`.

**Corrida conhecida (emenda 26).** O `guid_corrida` é o `id` de um `20002`, publicado por um motorista e endereçado a um passageiro. Quem recebe o recibo só o grava se **já conhecia, por conta própria, essa negociação com o avaliador**: o motorista, por ter enviado esse orçamento àquele passageiro (o avaliador); o passageiro, por tê-lo recebido daquele motorista (o avaliador). Recibo cujo `guid_corrida` o receptor não conhece, ou que o liga a outra contraparte, é descartado sem erro e sem `20015`. Sem backend, o receptor não tem como saber se a corrida foi aceita ou concluída, então a regra só barra quem **nunca negociou** com ele. O receptor MUST guardar, junto da negociação, a chave da contraparte, e a consulta MUST usar só esse registro local, nunca dados do próprio recibo.

### 1.9 Limites conhecidos (documentar no contrato, não esconder)

- O avaliado controla o que apresenta: pode omitir recibos ruins **recentes** se criar uma cadeia sem eles; a cadeia + `head` conferido pelo avaliador só **reduz** isso, não elimina.
- Quem recria a identidade (nova chave) zera o histórico (Sybil). Perder o app/chave perde a reputação.
- `corridas/avaliacoes/media` declarados não são verificáveis além da janela de N.
- Quem **negociou** com o avaliado (recebeu ou enviou o orçamento) pode lhe emitir um recibo válido para uma corrida que não aconteceu: o avaliado não tem como saber se houve aceitação, e a emenda 26 só barra quem nunca negociou com ele. Antes da emenda 26, qualquer pessoa que conhecesse a chave pública do avaliado podia lhe enviar recibos com corridas inventadas (medido em emulador: um recibo de nota 1 de um estranho foi aceito e baixou a média declarada).
- O `20001` é público: os recibos nele expõem as chaves públicas das contrapartes. Aceito no protótipo; alternativa futura: enviar só o resumo no `20001` e os recibos após o orçamento.

## Cifragem do `content` (emenda 17)

Vale para os kinds `20002` a `20015` (emendas 17, 19 e 25). O `20001` **não** é cifrado.

- **Padrão**: NIP-44 v2. Chave de conversa = HKDF-extract (SHA-256, `salt = "nip44-v2"`) sobre o
  segredo ECDH (coordenada x, secp256k1) entre a chave privada do remetente e a pública do
  destinatário — a mesma chave de conversa serve nos dois sentidos. `content` = base64 de
  `0x02 ‖ nonce(32) ‖ texto cifrado (ChaCha20 sobre o texto com padding) ‖ HMAC-SHA256(nonce ‖ texto
  cifrado)`. Texto de entrada em UTF-8, de 1 a 65 535 bytes.
- **Destinatário** = valor da tag `["p", ...]` do evento. No `20002`, é a chave do autor do `20001`
  respondido (tag `p` **nova** neste kind); nos demais, a do outro participante da corrida, como já
  consta de suas tags.
- **Assinatura**: continua obrigatória; o `id` e a `sig` (NIP-01) cobrem o `content` já cifrado.
- **Tags**: `t`, `e` e `p` continuam em claro — o relay filtra e roteia por elas.
- **Texto de entrada**: o JSON descrito na seção de cada kind. Onde a seção diz `content` vazio
  (`""`) — `20003`, `20004`, `20006`, `20007`, `20008`, `20009`, `20010`, `20012`, `20013` —, o texto de
  entrada é o marcador fixo `{}`, porque o NIP-44 rejeita texto vazio. `content` em claro, ou que
  decifre para outro texto nesses kinds, é inválido. O `20014` (dado próprio: o recibo) e o `20015` (dado
  próprio: `{"id_recibo": …}`) **não** usam o marcador `{}` (emenda 25).
- **Exceção — `20001`**: continua em claro e só assinado. É um anúncio a qualquer motorista, sem
  destinatário, logo sem chave com que cifrar; posição e destino ficam públicos (constituição 2.11.0).
- **Fora de escopo**: metadados — autor, tag `p`, tag `e`, kind, momento e tamanho da mensagem —
  continuam visíveis a quem observa o relay.
- **Sem compatibilidade**: evento em claro nos kinds `20002`–`20015` é inválido; as duas apps
  atualizam juntas.

## Regras de recepção (valem para as duas apps)

1. Verificar a assinatura **antes** de qualquer outro processamento; evento com assinatura inválida é
   descartado silenciosamente (FR-009). "Processamento" é aceitar ou exibir algo do evento — consultar
   se o `id` já foi visto, para pular uma verificação repetida sem aceitar nada, não conta (emenda 03);
   já usar esse `id` para decidir o que fazer com o evento conta, e por isso só pode acontecer depois.
2. Deduplicar por `id` antes de exibir (FR-010).
3. Tratar `content` como **dado**, nunca como marcação ou instrução; renderizar como texto simples.
4. Ignorar kinds desconhecidos sem erro — a rede carrega tráfego de outros clientes.
5. Não confiar em `created_at` para ordenação de segurança; é informado pelo autor.
6. Descartar evento que não traga o marcador `["t", "tcc-ufsc-caronas"]`, mesmo que o relay o entregue
   — um relay pode ignorar o filtro `#t` da inscrição, e a app não deve depender do bom comportamento
   dele.
7. Para os kinds `20002`–`20015` (emendas 17, 19 e 25), **depois** da verificação de assinatura (regra 1), da
   deduplicação (regra 2) e do marcador (regra 6): se a tag `p` não for a chave do receptor, ignorar;
   decifrar o `content`; se a decifração falhar (versão, MAC, padding, base64, tamanho) ou, nos kinds
   sem dado próprio, o texto decifrado não for exatamente `{}`, descartar sem erro e sem efeito. Um
   evento em claro nesses kinds é descartado do mesmo modo. O texto decifrado é **dado**, nunca
   instrução (regra 3), e nenhuma chave nem texto decifrado é registrado em log.
8. **Recorte geográfico do `20001` (emenda 27).** Depois de verificar a assinatura e o marcador, e **antes** de
   deduplicar, o motorista online com posição de referência MUST descartar, sem erro e sem avisar a rede, o
   `20001` que (a) não tenha nenhuma tag `g` bem formada (valor de comprimento 3–5 no alfabeto de geohash)
   igual a uma das células da inscrição vigente; ou (b) tenha a `origin` do `content` a mais de R km da
   posição de referência (distância de Haversine). O motorista offline, ou online sem posição de referência,
   MUST NOT **aceitar** `20001` — isto é, não o exibir, notificar nem responder; essa recusa é feita pelo filtro
   de solicitações (que conhece o estado online), e o conferidor de recepção, sem referência, nada descarta por
   geografia. A conferência vem **antes** da deduplicação para que um evento descartado numa
   sessão online (outra referência) não seja tratado como repetido na seguinte. Tags `g` fora de padrão são
   ignoradas na busca da célula; sem nenhuma tag válida e coincidente, o evento é descartado.
