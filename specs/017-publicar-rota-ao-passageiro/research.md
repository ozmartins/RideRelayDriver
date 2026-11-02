# Research — Publicar ao passageiro a rota da corrida

## D1 — Kind e forma do evento

**Decision**: novo `kind: 20011`, "Rota da corrida", efêmero (faixa 20000–29999), motorista →
relays → passageiro. Tags idênticas às do `kind: 20005`: marcador do protótipo, `["e", quoteId]`
e `["p", passengerPubkey]`. Próximo número livre depois de `20010`.

**Rationale**: reaproveita `_signCorrelatedEvent` e o mesmo trio de tags, o que deixa o passageiro
validar autor + `quoteId` como já faz com o `kind: 20005`. Efêmero porque a rota perde sentido
quando uma nova chega (mesma razão do `kind: 20005`).

**Alternatives**: estender o `kind: 20005` com os pontos — rejeitado: publicado a cada 5 s, levaria
dezenas de KB por segundo à rede para uma informação que só muda a cada ~50 m. Evento
substituível (`30000+`) — rejeitado: perde a regra de não reter e muda o contrato de
efemeridade dos demais kinds da corrida.

## D2 — `content`

**Decision**: `{"points": [[lat, lon], ...]}`, lat/lon em graus decimais **arredondados a 5 casas**
(~1,1 m), ordem do motorista ao destino, no mínimo 2 pontos. Objeto, não array solto, para poder
ganhar campos depois sem quebrar quem lê.

**Rationale**: 5 casas bastam para traçar uma linha num mapa (a precisão da própria rota do ORS é
dessa ordem) e economizam ~20 % de bytes em relação a 6–7 casas. Diferente dos outros kinds, que
publicam sem truncar, aqui o ponto é parte de uma geometria, não uma posição a rastrear.

**Alternatives**: polilinha codificada (Google/ORS `encoded_polyline`) em string — menor, mas exige
codec nas duas apps (código novo e dependência ou implementação própria, Princípio III/V) sem
necessidade medida; JSON legível é depurável com `tool/verify_published.dart`.

## D3 — Tamanho máximo e redução

**Medido** (2026-10-03, NIP-11 dos três relays padrão): `max_message_length` = 131 072 B em
`nos.lol` e `offchain.pub`, 1 000 000 B em `relay.primal.net`. O mais restritivo manda: 128 KiB.
(NIP-11 informa o limite anunciado, não prova aceitação; a aceitação é confirmada em campo no
quickstart.)

**Decision**: no máximo **1000 pontos** por evento. Um ponto serializado (`[-28.93123,-49.48891],`)
ocupa ~21–23 B, logo ~21 KB de `content`; **medido** em 2026-10-03 com `tool/probe_ride_route.dart` (rota sintética de 2500 pontos, reduzida a 1000): `content` de 20 709 B, mensagem `EVENT` inteira de 21 237 B ≈ 16 % do limite de 128 KiB. Os três relays padrão (`nos.lol`, `relay.primal.net`, `offchain.pub`) **aceitaram** (OK `true`) e **entregaram** o evento a uma segunda conexão inscrita (o kind é efêmero: os relays não o guardam, por isso a verificação é aceitação + entrega ao vivo, não recuperação posterior). Se o
`RouteTrace` tiver mais pontos, aplica-se **decimação uniforme**: tomam-se exatamente 1000 pontos nos índices
`round(i · (n − 1) / 999)`, `i = 0..999`, o que preserva o primeiro e o último ponto e nunca
excede o teto (um "cada k-ésimo" com o último anexado poderia chegar a 1001).

**Rationale**: simples, determinística, testável. Uma rota de 30 km com 1000 pontos tem um ponto a
cada ~30 m, suficiente para o traçado. 4–5× de folga contra o limite.

**Alternatives**: Ramer–Douglas–Peucker — melhor fidelidade em curvas, mas código maior sem
necessidade medida nesta escala (Princípio V); revisitar se o traçado do passageiro mostrar cantos
cortados em rota longa. Dividir em vários eventos — complexidade de remontagem sem ganho.

## D4 — Ponto de disparo e condição

**Decision**: em `_calcularRota`, no ramo de sucesso, depois do `setState` que guarda o `RouteTrace`
e depois de confirmado que o trecho continua o mesmo (`RideLeg.of(...) == leg`, já existente),
verificar `_rideStatus == DriverRideStatus.emCorrida` e `_activeRide != null`, e então
`unawaited(_publicarRota(activeRide, trajeto))`. O corpo de `_publicarRota` segue o de
`_publicarChegadaAoDestino`: sem identidade ou sem relay conectado, não publica; senão assina e
publica por `relayService.publish`.

**Rationale**: o descarte de resposta tardia da 016 já cobre "o estado mudou durante o cálculo"
(US2 cenário 2); a checagem de `emCorrida` é redundante com `leg.kind == dropoff`, mas explícita
para o requisito FR-005. Falha (`on Object`) nunca chega ao ponto de publicação (FR-006).

**Alternatives**: publicar dentro de `RouteDistanceService.trace` — rejeitado: mistura transporte
Nostr com o serviço de rotas e o faria publicar em "Deslocando-se".

## D5 — Sem fila, sem reenvio, sem persistência

**Decision**: se a publicação falhar ou não houver relay conectado, descarta. O passageiro fica com
a última rota recebida até a próxima (≤ ~50 m depois).

**Rationale**: mesma postura dos demais eventos efêmeros da corrida; evita estado novo e
reaproveita o recálculo natural. Ao reabrir o app em "Em corrida", a 016 recalcula e portanto
republica (Edge Case da spec).

## D6 — Privacidade

**Decision**: sem criptografia, como `20005`–`20010`. O evento revela a rota até o destino da
corrida ao relay e a quem o ler; mas o destino e a origem já estão no `kind: 20001` público e a
posição do motorista a cada 5 s no `kind: 20005`, também público.

**Rationale**: nenhuma informação nova sobre pessoas; justificativa idêntica à registrada nos
kinds anteriores. Mensagens privadas entre pares continuam a exigir criptografia (futuro).

## D7 — Inscrição e consumo

**Decision**: a inscrição do motorista não muda. A emenda 13 anota que o passageiro passa a se
inscrever em `20011`; essa mudança é da feature dele.

## D8 — Ordenação

**Decision**: o passageiro usa a rota de maior `created_at` (mesmo critério da posição do
motorista, emenda 12), sem decisão de segurança; recálculos distam ≥ 50 m, logo ≥ vários segundos.
