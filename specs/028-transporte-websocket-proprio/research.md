# Pesquisa: 028-transporte-websocket-proprio

Referência de comportamento: `../RideRelayPassenger/lib/services/ws_relay_transport.dart`, `relay_transport.dart` e
`relay_service.dart` (lidos em 2026-10-22). Estado atual do motorista: `lib/services/nostr_relay_gateway.dart`.

## R1 — Dependência

- **Decisão**: nenhuma dependência nova; WebSocket do `dart:io`.
- **Alternativas**: `web_socket_channel` (já transitiva no projeto) — descartada: mais uma camada entre o app e o
  `dart:io`, e o passageiro não a usa; a assimetria que a feature quer remover voltaria a existir. Manter o cliente
  do `dart_nostr` — é o que se quer substituir (spec, Problema).
- **Risco**: reimplementar o protocolo no motorista. **Mitigação**: o protocolo usado é pequeno (7 frames), os
  frames saem de funções puras com teste, e o passageiro já o faz há várias features.
- **Constituição III**: sem entrada de dependência a registrar além desta.

## R2 — Camadas e nomes

- **Decisão**: três peças — transporte (`RelayTransport`/`RelaySocket`/`WsRelayTransport`), protocolo puro
  (`relay_protocol.dart`) e gateway (`WsRelayGateway`). O gateway recebe o transporte por construtor
  (`WsRelayGateway({RelayTransport transport = const WsRelayTransport(), Duration connectionTimeout, Duration publishTimeout})`).
- **Por quê**: o transporte isolado deixa o gateway testável com dublê (Princípio II) e espelha o passageiro. O
  protocolo puro permite testar frames hostis sem socket.
- **Alternativas**: um arquivo só com o `WebSocket` dentro do gateway — descartada: não dá para testar handshake,
  prazo e socket tardio sem rede. Reaproveitar `RelayConnection` do passageiro como nome — descartada: o nome está
  ocupado no motorista (interface do `RelayService`); renomear aquela tocaria `RelayService`, UI e testes, contra
  o escopo.

## R3 — Handshake, prazo, socket tardio e ping

- **Decisão**: copiar a lógica do passageiro. `WebSocket.connect(url)` observado à parte; se o prazo (10 s) expira,
  marca `expirado` e o socket que chegar depois é fechado. `socket.pingInterval = 30 s` só depois de conectar. O
  `WsRelayTransport` recebe uma fábrica `Future<WebSocket> Function(String)` (padrão `WebSocket.connect`) para o
  teste injetar um socket falso e controlar quando o handshake termina.
- **Por quê**: o `.timeout()` só desiste de esperar, não cancela a conexão; sem a observação à parte o socket tardio
  fica órfão. Com o ping, o `dart:io` fecha a conexão quando o pong não vem, e o fechamento vira `onDone` (queda).
- **Risco**: `WebSocket` é tipo do `dart:io`, mais pesado de dublar que uma interface própria. **Mitigação**: o
  dublê (`Fake implements WebSocket`) implementa só o que o transporte usa (`where`/stream, `add`, `close`,
  `pingInterval`). Se ficar frágil, o plano admite um servidor `HttpServer` em `127.0.0.1` só nesse teste (sem rede
  externa nem relay real); decisão na implementação, registrada no teste.
- **Cobertura do ping**: o teste afirma que o intervalo é configurado no socket; a detecção real de conexão morta
  (pong ausente) não é provável sem rede e fica no cenário 4 do quickstart, relatado como tal.

## R4 — Estado por relay, tentativa vigente e queda

- **Decisão**: `Map<url, Object> _attempts` (token da tentativa), `Map<url, _Link> _links` (conexão estabelecida:
  socket + assinatura das mensagens + sonda pendente + publicações pendentes). `connect` chama `disconnect(url)`,
  cria o token, espera o transporte; se o token mudou, fecha o socket e lança `StateError('conexão cancelada')`.
  Estabelecida, registra o `_Link`, escuta o stream e inicia a inscrição se o gateway já foi assinado.
- **Queda**: `onDone`/`onError` do stream de uma conexão já registrada chama `_dropped(url, link)`, que só age se
  `link` ainda for o vigente; descarta a conexão (como `disconnect`) e emite em `connectionLost` uma vez.
  `disconnect` remove o `_Link` **antes** de fechar o socket, então o fechamento pedido encontra outro valor e não
  emite. Falha de handshake lança de `connect`, nunca emite `connectionLost`.
- **Por quê**: é exatamente o contrato de hoje (`NostrRelayGateway._dropped`), com o token fazendo o papel de
  `identical(_instances[url], instance)`.
- **Alternativa**: marcar a flag `established` como hoje — descartada: sem a biblioteca chamando dois callbacks por
  queda, a identidade do `_Link` basta.

## R5 — Inscrição em dois filtros e troca de células

- **Decisão**: dois identificadores de inscrição por relay, fixos: `tcc-geral` (kinds exceto `20001`, sempre) e
  `tcc-solicitacoes` (`20001` com `#g`, só online). `REQ` é um por inscrição, com os mesmos filtros de
  `buildFilters` (marcador `#t`, `limit: 50`, sem `since`). `setRideRequestCells(cells)`: se as células mudaram
  (`_sameCells`), em cada relay conectado faz `CLOSE tcc-solicitacoes` e, havendo células, `REQ tcc-solicitacoes`
  novo; **não** toca em `tcc-geral`. Relay que conectar depois recebe os dois com as células vigentes.
- **Por quê**: a spec (FR-006) pede refazer só o `20001`. Hoje a troca refaz tudo, o que reentrega o histórico dos
  outros kinds; o contrato não o exige. Ids estáveis tornam o `CLOSE` e o reconhecimento de `CLOSED` triviais.
- **Atenção a mudança observável**: o relay deixa de reentregar o histórico (até 50) dos outros kinds a cada troca
  de células. É a única diferença de comportamento do motorista e vai no quickstart (cenário 3) como ponto a
  conferir; `EventFeed` já deduplica por `id`, então nada que dependia do reenvio é esperado.
- **Alternativas**: refazer tudo como hoje — descartada, contraria FR-006. Um `REQ` com os dois filtros e reenviar
  com o mesmo id — descartada: NIP-01 substitui a inscrição inteira, reentregando os dois grupos.

## R6 — Sonda de vivacidade

- **Decisão**: como hoje: `REQ vivacidade {"ids":[0×64],"limit":1}` seguido de `CLOSE vivacidade`; o `Completer` da
  sonda completa com **qualquer** mensagem de texto recebida do relay (inclusive `NOTICE` e `EOSE`), mesmo
  malformada. Sem conexão registrada: `Future.error(StateError)` na hora. `disconnect` completa a sonda
  pendente com erro. O prazo é do chamador (`RelayService`, `livenessTimeout`).
- **Por quê**: preserva o contrato de `RelayGateway.probe`; "qualquer mensagem prova vida" vale também para frame
  que o parser descartaria, porque o que se mede é o socket respondendo.

## R7 — Publicação

- **Decisão**: `publish` envia `["EVENT", payload]` a cada relay conectado e espera `["OK", id, aceito, mensagem]`
  com o `id` do evento, dentro de `publishTimeout` (padrão 10 s, igual a `connectionTimeout`). Resultados:
  `OK true` ⇒ aceito; `OK false` ⇒ recusado com a mensagem do relay (vazia ⇒ `null`); sem resposta ⇒ recusado
  com `'sem resposta do relay'`; envio que lança (socket morto) ⇒ recusado com a descrição curta do erro.
  O stream fecha quando todos os relays respondem. Sem relay conectado, o stream fecha vazio (`RelayService`
  já lança `NoConnectedRelay` antes).
- **`OK` com `id` desconhecido ou campos fora de tipo**: ignorado (conta como vida para a sonda).
- **Por quê**: substitui `sendEventToRelaysAsync`, que fazia o mesmo com a biblioteca. O payload vai como está,
  sem reconstruir o evento: hoje o código recria um `NostrEvent` a partir do mapa, o que era uma ida e volta sem
  ganho.
- **Mensagem de prazo**: hoje o prazo estourado chega ao usuário como o texto cru da exceção, truncado em 80
  caracteres. A mudança para `sem resposta do relay` é intencional (o texto cru não ajudava) e é a única diferença
  visível; o corte de 80 caracteres e `…` da descrição de outros erros (`_describe` atual) é mantido.
- **Autenticação/pagamento**: `auth-required:`/`payment-required:` chegam no `OK false` e são repassados como
  mensagem, sem tratamento (fora de escopo).

## R8 — Frames hostis e limite de tamanho

- **Decisão**: `parseRelayFrame(String)` devolve um `RelayFrame` selado (`EventFrame`, `OkFrame`, `NoticeFrame`,
  `EoseFrame`, `ClosedFrame`) ou `null`. Retorna `null` — nunca lança — para: texto acima de
  `kMaxRelayMessageChars` (262 144 caracteres, 4× o `content` máximo de 65 535 bytes do contrato, que cobre as
  tags e o escape JSON), JSON inválido ou truncado, raiz que não é lista, tipo desconhecido, número de elementos ou
  tipos errados (`EVENT` sem objeto, `OK` sem booleano). O gateway entrega `EventFrame` cujo identificador de
  inscrição é um dos seus; `EVENT` de inscrição desconhecida é descartado.
- **`CLOSED`**: o relay encerrou uma inscrição (ex.: `invalid: bad tag`, `auth-required`). Não derruba o socket nem
  as outras inscrições; a inscrição fica fechada até a próxima conexão ou troca de células. Sem laço de
  reenvio, porque reenviar o mesmo filtro recusado repetiria a recusa.
- **`NOTICE`**: texto livre do relay; ignorado (só vale como vida para a sonda). Não conclui publicação, porque não
  traz o `id`.
- **Por quê**: o conteúdo do relay é entrada de terceiros (Princípio IV); o transporte só entrega o payload bruto,
  a assinatura é verificada a jusante. `dart:io` não permite limitar o tamanho antes de receber o frame; o limite
  evita decodificar JSON gigante, não evita o recebimento.
- **Alternativas**: derrubar a conexão em frame hostil — descartada: um relay que mande um `NOTICE` estranho deixaria
  de ser usado. Limite de 1 MiB — descartado: sem caso que o exija e mais caro de decodificar.
- **Validade do limite**: derivado do contrato (65 535 bytes de `content`), não medido; não é um número de
  desempenho e não será citado como medição.

## R9 — Divergências encontradas ao reler o passageiro (T002)

Conferido em 2026-10-22 contra `ws_relay_transport.dart`, `relay_transport.dart`, `relay_service.dart` e
`subscription_request.dart` do passageiro. Prazos e ping coincidem (handshake 10 s, ping 30 s, socket tardio fechado).
Diferenças de frame, **não corrigidas** aqui (o passageiro está fora de escopo) e sem efeito no contrato de eventos:

| Item | Passageiro | Motorista (esta feature) |
|---|---|---|
| Id da inscrição | um só, `corridas` | dois: `tcc-geral` e `tcc-solicitacoes` (emenda 27 exige filtro à parte para o `20001`) |
| Id da sonda | `liveness` | `vivacidade` (mantido, é o de hoje) |
| Filtro da sonda | `{"ids":[0×64]}` | `{"ids":[0×64],"limit":1}` (mantido) |
| `CLOSE` da sonda | não envia | envia (libera a inscrição no relay) |
| Quem dá a sonda por feita | `RelayService`, na conexão (primeira mensagem) | `RelayService`, periódica (a cada 30 s), via `RelayGateway.probe` |

Nenhuma delas muda o que o relay entrega nem o que o usuário vê.
