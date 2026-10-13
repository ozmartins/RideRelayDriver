# Research — Chegada periódica à origem (motorista)

## D1 — Regra de publicação

**Decision**: publicar quando (a) `_rideStatus == deslocandoAtePassageiro`, (b) há corrida ativa, (c)
`metersBetween(origem, posição) <= 10` e (d) `_ultimaChegadaEm == null` ou
`posicao.capturedAt - _ultimaChegadaEm >= 5 s`. Ao publicar, `_ultimaChegadaEm = posicao.capturedAt`. Fora do
raio, retorna sem zerar o relógio.

**Rationale**: é a regra de `_talvezPublicarLocalizacao` (`20005`) com o critério espacial da 011; um relógio
independente do da localização evita que um dos dois avisos atrase o outro. Não zerar o relógio fora do raio
impede rajada ao oscilar na borda do raio (GPS).

**Alternatives**: `Timer.periodic` de 5 s — rejeitado: diverge do `20005`, publicaria sem posição nova (GPS
caído) e exigiria cancelamento em cada transição. Zerar o relógio ao sair do raio — rejeitado: permitiria um
aviso por oscilação.

## D2 — Remover `arrivalNotified`

**Decision**: remover o campo de `ActiveRide` e a chave de `RideStateStore`; a leitura ignora a chave antiga.

**Rationale**: sem a regra "uma vez por corrida" a marca não decide nada; mantê-la seria estado morto e
persistido que mente sobre o comportamento (Princípio V). Reinício dentro do raio republica na hora — desejado.

**Alternatives**: manter o campo sem uso — rejeitado; usá-lo como "pelo menos um já saiu" — sem consumidor.

## D3 — Zerar o relógio

**Decision**: `_ultimaChegadaEm = null` onde `_ultimaPublicacaoEm` é zerado (conclusão, cancelamento pelo
motorista, cancelamento pelo passageiro) e ao iniciar uma corrida (`_iniciarCorrida`).

**Rationale**: a corrida seguinte não herda o intervalo (Edge Case de `spec.md`). Em "Em corrida" o relógio fica
parado e, de qualquer forma, `_talvezNotificarChegada` não publica fora de "Deslocando-se".

## D4 — Passageiro

**Decision**: nenhuma mudança de código. `_processarChegadaMotorista` deduplica por `id` (cada evento tem um novo),
confere `["e", quoteId]` e `canConfirmMeeting`, e só liga um flag de modal; depois do toque em "Confirmo..." o estado
vira `emCorrida` e os avisos seguintes caem na guarda. Um teste de regressão no passageiro (emenda 20) fixa isso.

**Rationale**: repetir é inofensivo no consumo atual; mexer no passageiro seria escopo sem motivo.

## D5 — Contrato

**Decision**: emenda 20, já aplicada nas duas cópias antes do código; nenhum formato muda.
