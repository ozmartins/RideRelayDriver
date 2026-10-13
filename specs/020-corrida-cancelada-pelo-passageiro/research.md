# Research — Corrida cancelada pelo passageiro (motorista)

## D1 — Kind e formato

**Decision**: consumir o `kind: 20013` como a emenda 19 o define (efêmero, `["t", marcador]`, `["e", quoteId]`,
`["p", <pubkey do motorista>]`, `content` cifrado NIP-44 ao motorista, texto `{}`). Nada novo no contrato.

**Rationale**: o formato espelha o `20012` no sentido inverso e os `20008`/`20010` que o motorista já
consome; o motorista valida autor + `quoteId` como já faz com eles.

**Alternatives**: reusar o `20004` (recusa de orçamento) — rejeitado na conversa de origem: ele é anterior à
aceitação e nem é consumido; sobrecarregá-lo exigiria distinguir pelo estado.

## D2 — Conferências de recepção

**Decision**: `_processarCancelamentoDoPassageiro` confere, nesta ordem, `_decifraSemDadoProprio(evento)`
(tag `p` = este motorista, decifra para `{}`; já cobre "em claro" e "outro destinatário"), `_activeRide != null`,
`evento.referencedEventId == ativa.quoteId`, `evento.authorPublicKey == ativa.passengerPubkey` e
`DriverRideRules.canBeCancelledByPassenger(_rideStatus)`. Qualquer falha retorna em silêncio.

**Rationale**: a tag `["e", ...]` é pública no relay; sem conferir o autor, qualquer um que a conhecesse
cancelaria a corrida alheia. `ActiveRide.passengerPubkey` já existe (guardado desde a feature 010).

**Alternatives**: conferir só `quoteId` (como `20008`/`20010` fazem hoje) — rejeitado: aqui o evento *destrói*
a corrida, então o autor tem de bater. Os `20008`/`20010` não conferem autor; isso é anterior a esta feature e
**não** é tocado aqui (ver Riscos em `data-model.md`).

## D3 — Efeito local

**Decision**: o mesmo bloco de `_cancelarCorrida` (feature 018): `setState` com `_rideStatus =
aguardandoSolicitacao`, `_activeRide = null`, `_ultimaPublicacaoEm = null`; `unawaited(rideStateStore.save(status,
null))`; `_sincronizarRota()`. Sem `_publicarCancelamento` e sem `_mostrarModalAvaliacao`. Para não duplicar o
bloco, extrair um método privado `_encerrarCorridaLocalmente()` usado por `_cancelarCorrida` e pelo novo
tratador (refatoração mínima, sem mudar o comportamento da 018).

**Rationale**: persistir o estado de repouso sem corrida já é a verdade que sobrevive ao reinício (SC-004);
dispensa sinalizador. Confirmações atrasadas de encontro/destino já são ignoradas por `_activeRide == null`
(FR-008), e a publicação de `20005` só ocorre nos dois estados de corrida, então cessa sozinha.

**Alternatives**: copiar o bloco — rejeitado (duplicação de lógica de estado em três lugares); marcar
`ActiveRide.cancelled` persistido — rejeitado (Princípio V), como na 018.

## D4 — Modal informativa e modal de confirmação aberta

**Decision**: nova `RideCancelledByPassengerModal` (apresentacional: título, mensagem "O passageiro cancelou a
corrida.", botão "OK" → `onClose`), aberta por `showDialog` com `barrierDismissible: false`, mesmo padrão de
`_mostrarModalAceitacao`, **fora** da fila de modais (`_fila`/`_modalAtual`), que só trata solicitações e
aceitações em "Aguardando". Se o motorista estiver com a confirmação "Cancelar corrida?" da 018 aberta quando o
aviso chega, essa confirmação é fechada primeiro: `_mostrarModalCancelamento` guarda o `BuildContext` do
diálogo (`_contextoConfirmacaoCancelamento`) e o novo tratador faz `Navigator.of(ctx).pop()` antes de abrir a
modal informativa; o campo é zerado quando a confirmação fecha por qualquer caminho.

**Rationale**: sem isso, o diálogo "O passageiro será avisado de que você cancelou" ficaria empilhado sob a
informativa sobre uma corrida que já não existe, e "Cancelar corrida" nele cairia na guarda de `_cancelarCorrida`
sem efeito (inofensivo, porém confuso). A guarda existente já impede um aviso duplicado ao passageiro.

**Alternatives**: deixar a confirmação aberta (confiando na guarda) — rejeitado pela confusão para o usuário;
enfileirar a informativa em `_fila` — rejeitado: a fila existe para serializar modais de "Aguardando" e
descarta itens na transição de estado.

## D5 — Idempotência

**Decision**: `_idsProcessados.add(evento.id)` no ramo de `_aoAtualizarFeed`, como os demais kinds; um aviso
reentregue (mesmo `id`) não reentra. Um aviso *novo* (outro `id`) em "Aguardando" cai na guarda de estado.

**Rationale**: o `EventFeed` já deduplica por `id` dentro da janela; `_idsProcessados` cobre o que escapa dela.

## D6 — Contrato e inscrição

**Decision**: a emenda 19 já está aplicada; o motorista acrescenta `NostrEvent.kindRideCancelledByPassenger` a
`_consumedKinds` em `main.dart`, que alimenta tanto `RelayService.subscriptionKinds` quanto
`EventFeed.acceptedKinds` — o defeito da feature 010 (inscrição real fixa em `kind: 1`) já foi corrigido, então
basta o kind estar nessa lista.

**Rationale**: Princípio IV; sem o kind na lista, o evento nunca chegaria de um relay real, só nos testes (cujo
dublê ignora `kinds`) — mesmo risco que a 010 encontrou; o teste de widget MUST incluir o kind em
`acceptedKinds` do `EventFeed` do cenário, e um teste confere a lista de `main.dart` quando possível.
