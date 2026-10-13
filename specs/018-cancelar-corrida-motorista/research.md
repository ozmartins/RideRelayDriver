# Research — Cancelar corrida (motorista)

## D1 — Kind e forma do evento

**Decision**: novo `kind: 20012`, "Corrida cancelada", efêmero (faixa 20000–29999), motorista →
relays → passageiro. Tags idênticas às do `kind: 20007`/`20009`: marcador do protótipo,
`["e", quoteId]` e `["p", passengerPubkey]`; `content` vazio. Próximo número livre depois de
`20011`.

**Rationale**: reaproveita `_signCorrelatedEvent` e o mesmo trio de tags, o que deixa o passageiro
validar autor + `quoteId` como já faz com os demais eventos da corrida. Efêmero como todos os kinds
de corrida: o relay não precisa guardá-lo, e o passageiro offline na hora perde o aviso (D4).

**Alternatives**: reaproveitar `kind: 20006` ("Corrida não pode mais ser atendida") — rejeitado:
semântica diferente (recusa de uma segunda aceitação, sem corrida ativa do passageiro), e o
passageiro trata `20006` hoje de outro modo; sobrecarregá-lo exigiria distinguir pelo estado.
Evento com `content` JSON (motivo) — rejeitado: o pedido não pede motivo; formato mínimo, extensível
depois porque `content` é livre (um campo novo opcional não quebra quem lê).

## D2 — Onde fica a ação e como confirmar

**Decision**: botão "Cancelar corrida" sobreposto ao mapa, à esquerda, logo acima do cartão de
status, visível só quando `DriverRideRules.canCancelRide(_rideStatus)`. Toque abre `CancelRideModal`
(`ModalTematizado`, ações "Voltar" secundária e "Cancelar corrida" primária) via `showDialog`
`barrierDismissible: false`, mesmo padrão de `_mostrarModalAvaliacao`.

**Rationale**: o mapa é a tela inicial e única superfície de corrida do motorista; a modal evita
toque acidental (FR-002, SC-003) e reaproveita o componente temático. Estilo do botão: "faixa de
estado" em alerta da constituição (cartão `campo`, raio 16, ícone e texto `ColorScheme.error`),
porque cancelar é ação destrutiva e a constituição não define botão destrutivo próprio.

**Alternatives**: aba/menu de corrida — rejeitado: não existe tela de corrida; botão flutuante
estendido `roxo` — rejeitado: a cor primária sugere ação de avanço, não de abandono.

## D3 — Efeito local do cancelamento

**Decision**: `_cancelarCorrida()` é síncrono até a primeira `await`: confere a guarda, captura a
`ActiveRide`, e no mesmo `setState` faz `_rideStatus = aguardandoSolicitacao`, `_activeRide = null`,
`_ultimaPublicacaoEm = null`; persiste `save(status, null)`; chama `_sincronizarRota()` (que, com
`RideLeg.of` = `null`, limpa rota, marcador e enquadramento) e só então publica. Sem abrir
`_mostrarModalAvaliacao`.

**Rationale**: espelha `_processarConfirmacaoDeDestino` (feature 012), menos a modal de avaliação
(FR-006). Mudar o estado antes de qualquer `await` torna o duplo toque inofensivo (a segunda
chamada vê `aguardandoSolicitacao` e sai), cumprindo "um aviso por corrida" sem sinalizador próprio.
Confirmações de encontro/destino tardias já são ignoradas por `_activeRide == null` (FR-007), e um
cálculo de rota em voo é descartado porque `RideLeg.of` deixou de bater (feature 016).

**Alternatives**: marcar `ActiveRide.cancelled` persistido — rejeitado (Princípio V): a corrida
cancelada deixa de existir, não há o que reabrir; o estado `aguardandoSolicitacao` sem corrida já
é a verdade persistida (SC-004).

## D4 — Falha de publicação

**Decision**: igual a `_publicarChegada`: sem identidade ou sem relay conectado, não publica; erros
de `publish` são absorvidos; sem fila, sem reenvio. O cancelamento local nunca é desfeito (FR-008).

**Rationale**: mesma postura da 017 e dos demais avisos de corrida; reenvio exigiria persistir um
aviso pendente e uma regra de expiração que o pedido não pede. Consequência assumida na spec: sem
relay na hora, o passageiro pode ficar sem saber. Mitigação futura possível (não aqui): o passageiro
tratar silêncio prolongado do `kind: 20005`.

**Alternatives**: fila persistida com reenvio ao reconectar — rejeitada por Princípio V.

## D5 — Privacidade

**Decision**: sem criptografia, sem motivo, sem posição. O evento só carrega o que `20007`/`20009`
já carregam (marcador, `quoteId`, pubkey do passageiro).

**Rationale**: mesma justificativa dos kinds anteriores da corrida; não revela mais do que o
passageiro já sabe.

## D6 — Contrato

**Decision**: emenda 14 nas duas cópias, antes do código; o passageiro passa a se inscrever também
em `20012` (Forma da inscrição). O motorista não muda a inscrição.

**Rationale**: Princípio IV; mesmo precedente da emenda 13.
