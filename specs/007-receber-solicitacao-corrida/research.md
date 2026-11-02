# Phase 0 — Research: Receber solicitação de corrida e enviar orçamento

## D1 — Cliente de roteamento: `open_route_service`, reinstalado no motorista (atende FR-004,
FR-005; exceção da constituição 2.4.0)

**Decision**: reinstalar `open_route_service ^1.2.9` como dependência direta em `pubspec.yaml`,
confinada a `lib/services/route_distance_service.dart`, no mesmo perfil `driving-car` já escolhido
pela feature 007 do passageiro.

**Contexto da decisão**: esta biblioteca já foi avaliada e testada contra a API openrouteservice na
feature 007 do passageiro (`Prototipo/passenger/specs/007-rota-ate-destino/research.md`, D1). Foi
instalada no motorista antes da especificação desta feature (decisão da conversa que a originou),
depois revertida por não haver, na época, nenhuma feature do motorista que a usasse (Princípio III
exige decisão registrada *na feature que efetivamente usa* a dependência) — esta é essa feature.

### Alternativas avaliadas

| Opção | Observação |
|-------|------------|
| `open_route_service` (escolhida) | Mesma biblioteca, mesma avaliação da feature 007 do passageiro: cliente tipado para directions, sem exigir montar a URL/JSON à mão. Reutilizar a mesma biblioteca nas duas apps (ainda que sem compartilhar código) evita duas soluções diferentes para o mesmo problema dentro do mesmo protótipo. |
| Chamar a API diretamente via `http` | Mesma desproporção já descartada na feature 007 do passageiro — exigiria reimplementar o parser da resposta GeoJSON de directions só para este app. |
| Linha reta (Haversine) | Rejeitada explicitamente na conversa que originou esta feature — o pedido é por distância real de rota, não linha reta. |

### Riscos assumidos e mitigação

- **Risco de indisponibilidade do serviço ou limite de requisições excedido**: mitigado tratando
  toda exceção como falha de cálculo de distância, absorvida sem bloquear a modal (US1/FR-016) —
  mesmo padrão da feature 007 do passageiro.
- **Risco de duas chamadas por solicitação esgotarem o limite de requisições sob rajada**: mitigado
  pela fila estritamente sequencial de D3 — nunca há duas modais, e portanto nunca mais de duas
  chamadas de rota, simultâneas.
- **Risco de chave de API ausente/inválida**: mesma mitigação de D3 da feature 007 do passageiro —
  chave lida de `String.fromEnvironment('ORS_API_KEY')`, nunca hardcoded; ausência é uma falha de
  cálculo como qualquer outra (FR-016).

## D2 — Abstração mais leve que a do passageiro: `RouteDistanceService` (atende FR-004, FR-005)

**Decision**: criar uma abstração própria do motorista, `RouteDistanceService`, com um único método
`Future<double> distanceMeters({required LatLng origin, required LatLng destination})` — sem
`points` nem qualquer estrutura para desenhar `Polyline`.

**Contexto da decisão**: a modal desta feature não tem mapa (Assumptions do `spec.md`) — só exibe
números. O `RouteResult` da feature 007 do passageiro carrega `points` porque a tela do passageiro
desenha o trajeto; replicar essa estrutura aqui criaria um campo sem nenhum consumidor.

### Alternativas avaliadas

| Opção | Observação |
|-------|------------|
| `RouteDistanceService.distanceMeters` (escolhida) | Cobre exatamente o que as duas chamadas desta feature precisam: um número, duas vezes. |
| Copiar `RouteResult`/`RouteService` do passageiro tal como estão | Rejeitada por Princípio V: `points` ficaria sem uso nesta feature (a modal não tem mapa), e as duas apps não compartilham código de qualquer forma — copiar a estrutura maior não traz nenhum benefício de manutenção compartilhada. |

### Riscos assumidos e mitigação

- Nenhum risco novo além dos já listados em D1 — esta decisão é sobre forma da interface interna,
  não sobre a chamada de rede em si.

## D3 — Fila estritamente sequencial de solicitações (atende FR-015)

**Decision**: manter, no estado da tela que orquestra a recepção (`MapScreen`), uma fila (`List`
usado como FIFO) de solicitações recebidas ainda não apresentadas. Uma nova solicitação só abre
modal se nenhuma modal estiver aberta; ao encerrar uma modal (orçamento enviado ou corrida
recusada), a próxima da fila — se houver — abre imediatamente.

**Contexto da decisão**: FR-015 exige nunca mais de uma modal simultânea; a fila é a forma mais
direta de garantir isso sem introduzir um serviço ou controlador novo — o próprio estado da tela já
processa eventos um a um pela ordem de chegada do `EventFeed`.

### Alternativas avaliadas

| Opção | Observação |
|-------|------------|
| Fila FIFO no estado da tela (escolhida) | Sem estrutura nova: um `List<RideRequestReceived>` e a mesma disciplina de `setState` já usada pelo restante da tela. |
| Descartar solicitações que chegam com modal já aberta | Rejeitada: o Edge Case do `spec.md` exige que cada solicitação válida recebida enquanto online seja exibida, não perdida silenciosamente — perder uma solicitação sem indicação seria pior para o motorista do que esperar a fila. |
| Um `StreamController`/serviço dedicado de fila | Desproporcional (Princípio V): a fila só precisa existir enquanto a tela existe, e o `EventFeed` já entrega os eventos em ordem — não há necessidade de mais uma camada assíncrona. |

### Riscos assumidos e mitigação

- **Risco de fila crescer sem limite sob rajada de solicitações**: aceito como risco de protótipo —
  fora do escopo medir ou limitar isso nesta feature (não há Success Criteria sobre volume de
  solicitações simultâneas).

## D4 — Assinatura do novo kind: método dedicado em `IdentityService` (atende FR-011, FR-017)

**Decision**: acrescentar `IdentityService.signRideQuote({identity, requestId, pricePerKm, total})`,
que monta o `content` JSON, as tags (`["t", ...]` e `["e", requestId]`) e assina com
`kind: NostrEvent.kindRideQuote` — mesmo formato de retorno (`SignedEvent`) de `signTextNote`.

**Contexto da decisão**: `IdentityService` já é o único lugar do app, além do teste correspondente,
que conhece `package:dart_nostr` para assinatura (Princípio III); um segundo método dedicado segue o
padrão já estabelecido por `signTextNote`, em vez de generalizar prematuramente uma API para dois
casos de uso.

### Alternativas avaliadas

| Opção | Observação |
|-------|------------|
| Método dedicado `signRideQuote` (escolhida) | Mesmo formato de `signTextNote`; a tag extra (`["e", ...]`) e o `content` estruturado são a única diferença real. |
| Generalizar para um único `signEvent({kind, content, tags})` | Rejeitada por ora (Princípio V): com dois usos concretos, a generalização não elimina duplicação relevante — a diferença entre os dois métodos já está inteiramente no `content`/tags que cada chamador monta. Fica como possível refatoração quando um terceiro kind assinado existir. |

### Riscos assumidos e mitigação

- Nenhum risco novo — reaproveita a mesma verificação de assinatura e o mesmo caminho de teste já
  exigido pelo Princípio II para `signTextNote`.

## D5 — Nova tag de referência (`["e", ...]`) no contrato (atende FR-017)

**Decision**: usar a convenção padrão do NIP-01 para "responder a" outro evento — uma tag
`["e", "<id>"]` apontando para o `id` do evento respondido — em vez de inventar um campo próprio
dentro do `content` para essa referência.

**Contexto da decisão**: já registrada na emenda 05 do contrato de eventos
(`specs/002-nostr-relay-connection/contracts/nostr-events.md`); repetida aqui porque é uma decisão
de projeto não óbvia (Princípio V exige registro em `research.md`, além do contrato em si).

### Alternativas avaliadas

| Opção | Observação |
|-------|------------|
| Tag `["e", "<id>"]` (escolhida) | Convenção já definida pelo protocolo Nostr (NIP-01) para referenciar outro evento; qualquer relay ou cliente que já entenda tags `e` trata isso de forma previsível, mesmo sem conhecer este protótipo. |
| Campo `requestId` dentro do `content` JSON | Funcionaria, mas duplicaria uma convenção que o protocolo já define na camada de envelope (`tags`), e ficaria fora do alcance de uma inscrição futura que quisesse filtrar por `#e` no relay. |

## D6 — `http` como `dev_dependency` (suporta o teste de D1)

**Decision**: adicionar `http` a `dev_dependencies` em `pubspec.yaml`, usada só em
`test/services/route_distance_service_test.dart` para injetar um `http.Client` dublê em
`OpenRouteService` (o mesmo padrão de teste já usado na feature 007 do passageiro).

**Contexto da decisão**: `http` já é dependência transitiva do projeto (via `open_route_service`),
mas não estava declarada. Diferente da feature 007 do passageiro, que promove `http` a dependência
de produção (usada em `PhotonGeocodingService`), aqui ela só aparece em teste — motorista não faz
nenhuma chamada HTTP direta fora de `OpenRouteService`. `dev_dependency`, não dependência direta,
reflete esse uso exclusivo de teste.

**Superada por D7**: `http` passou a dependência de produção quando D7 precisou construir um
`http.Client` próprio — o motivo original (uso exclusivo de teste) deixou de valer.

## D7 — Header `Authorization` manual sobre `OpenRouteService` (corrige bug do pacote, atende FR-016)

**Decision**: `OrsRouteDistanceService` passa a construir o `OpenRouteService` com um `client:`
próprio — `_AuthorizingHttpClient`, um `http.BaseClient` que acrescenta o header
`Authorization: <chave>` a toda requisição antes de delegar a um `http.Client` interno. `http`
promovida de `dev_dependency` (D6) para dependência de produção em `pubspec.yaml`.

**Contexto da decisão**: validação manual em aparelho (dois emuladores, motorista e passageiro)
encontrou toda chamada de rota falhando com `401 Authorization field missing`. Diagnóstico por
`curl` direto contra `api.openrouteservice.org`: `open_route_service` 1.2.9 monta a URL da chamada
GET de directions com a chave como query param `api_key=...`
(`ORSDirections.directionsRouteGeoJsonGet`, em `open_route_service_base.dart`), formato que a API
atual do openrouteservice.org rejeita — só aceita a chave no header HTTP `Authorization`. Bug do
pacote vendorizado, não do código deste projeto; sem correção anunciada no `CHANGELOG.md` da versão
instalada.

Sem tocar no pacote (fora do controle do projeto, mudança se perderia em qualquer
`flutter pub get`/`pub cache repair`/outra máquina): `OpenRouteService` já aceita um `client:`
(`http.Client?`) opcional no construtor, usado internamente para toda chamada — ponto de extensão
correto para acrescentar o header sem depender do formato de autenticação que o pacote decidiu usar
por conta própria.

**Risco assumido**: se uma versão futura do pacote corrigir o bug e passar a mandar o header por
conta própria, o header fica duplicado (mesmo valor duas vezes) — inofensivo, mas a decisão deve
ser revisitada ao atualizar a versão de `open_route_service`.
