# Research: Confirmar encontro e notificar chegada ao destino

## D1 — Estado novo "Em corrida" e suas transições

**Decisão**: acrescentar `emCorrida` a `DriverRideStatus` (`driver_ride_status.dart`), entre
`deslocandoAtePassageiro` e o retorno a `aguardandoSolicitacao`. Duas novas regras de transição,
por analogia a `canStartRide`:

- `canConfirmMeeting(current)`: verdadeiro só a partir de `deslocandoAtePassageiro` (FR-001,
  FR-002).
- `canConfirmDestinationArrival(current)`: verdadeiro só a partir de `emCorrida` (FR-007, FR-008).

**Justificativa**: mesmo padrão já usado para `aguardandoSolicitacao → deslocandoAtePassageiro`
(feature 010) — cada transição só é válida a partir de um estado específico, nunca automática por
qualquer outro evento.

## D2 — Onde persistir a coordenada de destino e as duas novas marcas de "já publicado"/"já avisado"

**Decisão**: `ActiveRide` ganha `destinationLat`, `destinationLon` (mesmo estilo de `originLat`/
`originLon`, dois `double`) e `destinationArrivalNotified` (mesmo estilo de `arrivalNotified`,
renomeado implicitamente para "chegada à origem" agora que existem duas chegadas). `SentQuotesStore`
passa a capturar também `RideRequestReceived.destination` no momento do envio do orçamento (mesmo
ponto em que já captura a origem, feature 011), e `_iniciarCorrida` lê os dois pares de
`SentQuotesStore` ao montar a `ActiveRide`.

**Justificativa**: mesmo raciocínio exato da feature 011 (D1/D2 do `research.md` dela) — a única
posição do destino conhecida pelo motorista é a que veio na solicitação original, e sem persistir
"já publicada" a chegada ao destino seria reenviada a cada posição dentro do raio, ou depois de um
reinício.

**Alternativas avaliadas**:
- **Guardar origem e destino em métodos/campos separados dentro de `SentQuotesStore`** (em vez de
  ampliar o mesmo mapa já usado para a origem): avaliado e descartado — os dois são capturados no
  mesmo instante (envio do orçamento) e têm o mesmo ciclo de vida; separar introduziria dois
  caminhos de leitura para o mesmo `quoteId` sem benefício.

## D3 — Sem nova entidade de domínio para as confirmações recebidas

**Decisão**: ao contrário de `QuoteAccepted` (feature 010), as confirmações de encontro e de
destino não ganham uma classe de domínio própria — `MapScreen` compara diretamente
`evento.referencedEventId` com `_activeRide?.quoteId`.

**Justificativa**: `QuoteAccepted` existe porque sua leitura **cria** a `ActiveRide` pela primeira
vez (antes dela não há nenhum estado para comparar). Aqui, a `ActiveRide` já existe no momento em
que as duas confirmações chegam — a checagem é só igualdade de string, sem necessidade de uma
abstração dedicada (Princípio V: estrutura só quando há consumidor para ela).

## D4 — Kinds novos do contrato

**Decisão**: três kinds novos, sequenciais aos já definidos (20001-20007):

- `kind: 20008` — "Encontro confirmado", passageiro → motorista.
- `kind: 20009` — "Chegada ao destino", motorista → passageiro.
- `kind: 20010` — "Destino confirmado", passageiro → motorista.

Todos na faixa efêmera 20000-29999, mesmo formato de tags dos kinds 20005-20007 (marcador +
`["e", quoteId]` + `["p", destinatário]`), `content` vazio (toda informação necessária já está nas
tags e no próprio kind, mesma convenção dos kinds 20003/20004/20006/20007).

**Justificativa de quem define**: esta feature (motorista) define os três, mesmo os dois
publicados pelo passageiro — o motorista precisa da máquina de estados completa para implementar
suas duas transições, e a feature do passageiro (especificada em seguida) implementa contra este
mesmo contrato já escrito. Precedente já aceito no projeto: `kind: 20005`/`20006`, definidos pela
feature 010 do motorista, com o consumo pelo passageiro (do 20005) só numa feature posterior dele.

## D5 — Consumo/publicação pelo passageiro

**Decisão**: fora de escopo desta feature — mesmo padrão já usado para todos os kinds anteriores.
A feature do passageiro (especificada em seguida) implementa: consumir `kind: 20007` (já existente,
nunca consumido antes) com um botão que publica `kind: 20008`; consumir `kind: 20009` com um botão
que publica `kind: 20010`.
