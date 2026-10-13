# Research — Rota da corrida no mapa

## D1 — Reaproveitar `RouteDistanceService` em vez de novo serviço ou nova dependência

**Decisão**: acrescentar `trace({origin, destination})` a `RouteDistanceService`, devolvendo
`RouteTrace` (pontos + distância). `OrsRouteDistanceService` o implementa com a mesma chamada
`directionsRouteGeoJsonGet` já usada por `estimate()`, lendo a geometria como o
`OrsRouteService` do passageiro (`feature.geometry.coordinates.first`), e reaproveita o cliente com
header `Authorization` (D7 da feature 007). `open_route_service` já é dependência do motorista
(Princípio III: sem dependência nova).

**Alternativas**: (a) interface separada `RouteTraceService` — exigiria novo parâmetro em
`MapScreen`/`main.dart` para o mesmo cliente HTTP; rejeitada por Princípio V. (b) copiar
`OrsRouteService` do passageiro — o código das apps não é espelho; o motorista já tem seu
equivalente. (c) devolver geometria em `estimate()` — pagaria o custo de decodificar a geometria
na modal de solicitação, que não a usa.

**Consequência**: os dublês de `RouteDistanceService` nos testes (`ride_request_modal_test.dart`,
`route_distance_service_test.dart`) ganham `trace()`. `FallbackRouteDistanceService.trace` repassa
ao serviço interno **sem** nova tentativa e **sem** reta como substituto: uma linha reta não diz ao
motorista por qual via seguir (spec, Edge Cases); as tentativas extras consumiriam o limite gratuito
do ORS.

## D2 — Privacidade: sem emenda de constituição

A exceção de roteamento (2.3.0, ampliada na 2.4.0) permite enviar a terceiro duas coordenadas — a
posição atual do usuário e um destino, ou origem e destino de uma solicitação recebida —, por HTTPS,
sem identificador, sem persistir a resposta além da sessão. Trecho 1: posição do motorista →
origem da solicitação; trecho 2: posição → destino da solicitação. Ambos se enquadram. Verificação
na implementação: o corpo da requisição contém só as coordenadas (já é o caso de `estimate()`).
Nenhuma permissão de sistema nova (localização já é usada pela feature 004).

## D3 — Recálculo: mudança de trecho + 50 m; tentativa conta mesmo se falhar

**Decisão**: guardar a posição usada na última *tentativa* de rota (`RouteTrace.originUsed` em
sucesso; um registro separado em falha). Nova consulta quando: o trecho mudou (alvo diferente), ou
não há tentativa anterior, ou `metersBetween(últimaOrigem, posiçãoAtual) ≥ 50`. Contar a tentativa
falha evita uma consulta por atualização de GPS enquanto o serviço está fora (SC-004); a próxima
tentativa ocorre ao andar 50 m ou trocar de trecho. Uma única requisição em voo por vez; resposta
cujo alvo já não é o trecho vigente é descartada (mesma ideia do FR-008 da feature 007 do passageiro).
A publicação de localização da feature 010 (por tempo) é independente e não muda.

**Alternativas**: recalcular por tempo (consome cota parado); recalcular a cada GPS (viola SC-004).

## D4 — Estado derivado, não persistido

O trecho vigente é função pura de `(DriverRideStatus, ActiveRide?)`: `deslocandoAtePassageiro` →
origem; `emCorrida` → destino; qualquer outro, ou `ActiveRide` nula → nenhum. `ActiveRide` já
persiste origem e destino desde as features 011/012, então a restauração após reinício (FR-006)
vem de graça: o trajeto é pedido de novo à primeira posição disponível.

Coordenada ausente: uma corrida iniciada antes da feature 011/012 pode ter origem ou destino
zerados (`0, 0`, o valor que `ActiveRide` carrega nesse caso). `RideLeg.of` devolve `null` quando
o alvo do trecho é exatamente `(0, 0)` — nenhum ponto real de corrida cai ali — para nunca
consultar o serviço de rota com um ponto inválido (Edge Case da spec).

## D5 — Apresentação (constituição, Identidade Visual e Design)

- Trajeto: `PolylineLayer`, `roxo`, 5 px — valor já fixado na seção "Marcador do passageiro"
  ("Rota traçada em `roxo`, 5 px").
- Marcador do alvo: mesmo círculo de 44 px do marcador do motorista (`fundo`, borda branca 2 px),
  ícone em `destaque`: pessoa para o embarque (coerente com "Marcador do passageiro"), bandeira
  para o destino. Escolha de ícone não é cor/tamanho/raio, logo não exige emenda.
- Aviso de falha: "Faixa de estado" (cartão `campo`, raio 16, ícone e texto 13 px em
  `ColorScheme.error`), no topo do mapa, texto "Não foi possível traçar a rota agora." Some
  sozinho quando uma tentativa seguinte funciona ou o trecho acaba.
- Enquadramento (FR-010, opção A da análise F1): `_aoReceberPosicao` hoje recentraliza o mapa a
  cada posição, o que desfaria qualquer `fitCamera`. Novo `bool _seguindoMotorista` (padrão
  `true`): `_aoReceberPosicao` só move a câmera se for `true`. Ao receber o **primeiro** trajeto de
  um trecho, `fitCamera` com `CameraFit.coordinates` (posição + alvo, ou pontos da rota) e padding
  inferior ≥ 170 px para não ficar sob o cartão de status, e `_seguindoMotorista = false`. O botão
  "Centralizar" (`_BotaoCentralizar`) volta a ligá-lo. Sem trajeto (trecho `null` ou rota
  indisponível), `_seguindoMotorista` volta a `true`. Recálculos de 50 m **não** reenquadram: só
  trocam a polilinha. Alternativas descartadas: seguir sempre (enquadramento dura ~1 s) e reenquadrar
  a cada 50 m (pulos de zoom).

## D6 — Testes

Lógica pura (`RideLeg.of`, `shouldRefresh`) em `test/domain/ride_leg_test.dart`. `trace()` do ORS
testado com cliente HTTP falso, como `estimate()` já é. `MapScreen` testada com
`LocationService` e `RouteDistanceService` falsos: polilinha presente em cada estado, ausente nos
demais, troca de trecho, falha → faixa de aviso sem bloquear, limiar de 50 m via duas posições.
Cuidado conhecido da suíte: `FlutterMap` busca tiles por HTTP real e prende o relógio falso em
alguns fluxos (T019 da feature 008 do passageiro); reutilizar o padrão que `map_screen_test.dart`
já adota.

## Verificação registrada na implementação

- **D2 / FR-008**: `test/services/route_distance_service_test.dart` ("a requisição leva só as duas
  coordenadas, por HTTPS") confirma que `trace()` envia a `https://api.openrouteservice.org`, com
  como únicos parâmetros `api_key` (credencial do app, não identificador do usuário — mesmo
  comportamento do `estimate()` desde a feature 007, D7), `start` e `end` (longitude,latitude), sem
  corpo. Nenhuma chave pública, nome ou identificador da corrida.
- **Divergência de D1 / T013**: `RideLeg.of` trata o alvo `(0, 0)` como "sem trecho" (D4), então as
  corridas dos testes antigos com `ActiveRide` zerado seguem sem consulta de rota.
- **Achado (corrigido)**: sem `defaultProfile` o pacote `open_route_service` usa `foot-walking`.
  Em produção `_buildClient` já definia `driving-car`, mas um cliente injetado (testes) caía em
  `foot-walking`. `OrsRouteDistanceService._directions` agora passa
  `profileOverride: ORSProfile.drivingCar` em toda chamada (`estimate()` e `trace()`), e o teste de
  FR-008 confere `/driving-car` na URL.
