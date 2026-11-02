# Tarefas: 028-transporte-websocket-proprio

**Entrada**: `specs/028-transporte-websocket-proprio/` (plan.md, spec.md, data-model.md, research.md, contracts/protocolo-relay.md, quickstart.md)
**Testes**: obrigatórios aqui — Princípio II e CLAUDE.md ("código que descarta mensagem exige teste junto, caso válido e inválido,
sem rede nem relay real") e spec §FR-016. Em cada par, o teste vem **antes** da implementação e deve falhar primeiro.
**Formato**: `- [ ] ID [P?] [US?] Descrição com caminho`. `[P]` = arquivos distintos, sem dependência de tarefa aberta.
**Commits**: um por mudança lógica, em português do BR, direto na `master`, com o trailer `Co-Authored-By`; sem Conventional
Commits nem emojis. Pontos de commit marcados com **Commit**. O `CLAUDE.md` e o comentário de `relay_gateway.dart` vão em
commit separado, no fim (T021).
**Sem contrato novo, sem emenda de constituição, sem dependência nova, sem mudança no passageiro**: nada a replicar na outra app.

**Histórias** (spec.md): US1 = a corrida completa funciona como antes (P1, MVP); US2 = recuperar sozinho de queda de
conexão (P1); US3 = comportamento provável sem rede, inclusive contra frames hostis (P2).

**Nota de ordem**: `WsRelayGateway` só pode entrar em produção quando US1 **e** US2 estiverem prontas (sem detecção de queda
seria regressão). Por isso a troca em `main.dart`/`RelayTaskHandler` e a remoção do gateway antigo ficam na Fase 6, e os
cenários manuais 3 e 4 do quickstart só rodam depois dela.

## Fase 1: Preparação

- [x] T001 Rodar `flutter analyze` e `flutter test` na `master` limpa e confirmar que ambos passam antes de qualquer mudança; se algo falhar, parar e relatar (a linha de base precisa estar verde para que falhas posteriores sejam desta feature).
- [x] T002 Reler `../RideRelayPassenger/lib/services/ws_relay_transport.dart`, `relay_transport.dart`, `relay_service.dart` (`_connect`, sonda, reinscrição) e `subscription_request.dart` e conferir cada frame e tempo de `specs/028-transporte-websocket-proprio/contracts/protocolo-relay.md` contra eles (id e filtro da sonda, prazos, ordem `REQ`/`CLOSE`). Divergência encontrada: registrar em `research.md` (nova seção R9) sem alterar o passageiro; se for divergência que muda um frame do motorista, ajustar o `contracts/protocolo-relay.md`.

## Fase 2: Fundação (bloqueia todas as histórias)

- [x] T003 [P] Teste primeiro: `test/services/relay_protocol_test.dart`. (a) Filtros, migrando os seis casos de `test/services/nostr_relay_gateway_filters_test.dart` para `buildFilters(kinds, cells)` que devolve `List<Map<String, dynamic>>`: sem células ⇒ um filtro sem `20001`; com células ⇒ dois filtros, `#g` com ≤ 9 valores; `#t` e `limit: 50` em todos; nenhum filtro tem `since`; só `20001` sem células ⇒ vazio; células sem `20001` nos kinds ⇒ sem `#g`. (b) Montagem: `reqFrame('tcc-geral', filtros)` decodifica para `["REQ","tcc-geral",{…}]`, `closeFrame`, `eventFrame(payload)` decodifica para `["EVENT",payload]` sem campo extra. (c) `parseRelayFrame` aceita `EVENT` (subId + objeto), `OK` com e sem mensagem, `NOTICE`, `EOSE`, `CLOSED` com e sem mensagem. (d) devolve `null`, sem lançar, para: texto vazio, JSON inválido, JSON truncado no meio, raiz que não é lista, lista vazia, tipo desconhecido, `EVENT` sem objeto / com objeto no lugar do subId / com 2 elementos, `OK` com campo aceito que não é booleano, `NOTICE` sem texto, e texto com `kMaxRelayMessageChars` + 1 caracteres (com exatamente `kMaxRelayMessageChars` ainda é aceito se válido).
- [x] T004 Implementar `lib/services/relay_protocol.dart` (data-model.md): constantes `kMaxRelayMessageChars = 262144` e os ids `tcc-geral`, `tcc-solicitacoes`, `vivacidade`; `buildFilters`; `reqFrame`, `closeFrame`, `eventFrame`; `sealed class RelayFrame` com `EventFrame`, `OkFrame`, `NoticeFrame`, `EoseFrame`, `ClosedFrame`; `RelayFrame? parseRelayFrame(String)` que nunca lança. Usa `prototypeMarker` de `prototype_marker.dart` e `NostrEvent.kindRideRequest` do domínio; não importa `dart_nostr`. (depende de T003)
- [x] T005 [P] Definir `lib/services/relay_transport.dart` (`abstract interface class RelayTransport { Future<RelaySocket> connect(String url, {Duration timeout}); }` e `RelaySocket` com `messages`, `send`, `close`) e o dublê `test/support/fake_relay_transport.dart`: `FakeRelayTransport` com controle por url do resultado do handshake (completar, falhar, ficar pendente e completar depois) e lista de sockets criados; `FakeRelaySocket` com `push(texto)`, `closeFromRelay()`, `failFromRelay(erro)`, `sent` (lista do que o app enviou), `closed`, e `send` que lança `StateError` depois de fechado.
- [x] T006 [P] Teste primeiro: `test/services/ws_relay_transport_test.dart`, com fábrica de socket injetada (nenhuma conexão real): handshake com sucesso devolve socket e liga `pingInterval` de 30 s (e o valor customizado quando passado); falha do `connect` propaga o erro; handshake que passa do prazo lança `TimeoutException`; **socket que chega depois do prazo é fechado**; socket que chega dentro do prazo **não** é fechado; `messages` entrega só frames de texto (binário é ignorado); `send` e `close` chegam ao socket. Se o dublê de `WebSocket` ficar frágil (research R3), usar `HttpServer` em `127.0.0.1` só neste arquivo e anotar o motivo num comentário.
- [x] T007 Implementar `lib/services/ws_relay_transport.dart`: `WsRelayTransport({pingInterval = 30 s, connector = WebSocket.connect})` e `_WsRelaySocket`, com a mesma lógica do passageiro (future observado à parte, `expirado`, `pingInterval` só depois de conectar, `messages` filtrando `String` e *broadcast*). Único arquivo novo que importa `dart:io`. (depende de T005, T006)

**Commit** (Fase 2): "Adiciona o protocolo de relay e o transporte WebSocket próprio, ainda sem uso" — T003 a T007 juntos ou em dois commits (protocolo; transporte).

**Ponto de controle**: `flutter analyze` e `flutter test` limpos.

## Fase 3: História 1 — A corrida completa funciona como antes (P1) 🎯 MVP

**Meta**: o `WsRelayGateway` conecta, inscreve nos mesmos filtros, entrega eventos, troca células só do `20001` e publica reportando o resultado por relay.
**Teste independente**: `test/services/ws_relay_gateway_test.dart` com `FakeRelayTransport`, sem rede.

- [x] T008 [US1] Teste primeiro: `test/services/ws_relay_gateway_test.dart` (parte 1). Conexão: `connect` registra o relay; falha do handshake lança e nada fica registrado. Inscrição: `subscribe` antes de `connect` ⇒ ao conectar sai `REQ tcc-geral` e, com células, `REQ tcc-solicitacoes` com `#g`; `subscribe` depois de conectar ⇒ sai para os relays conectados; sem células (offline) só o `tcc-geral`; só `20001` e sem células ⇒ nada é enviado; `subscribe` repetido não duplica `REQ` num relay já inscrito; cada reconexão reinscreve. Recepção: `EVENT` de `tcc-geral` e de `tcc-solicitacoes` vira `IncomingEvent(url, payload)`. Células: `setRideRequestCells` com células novas envia `CLOSE tcc-solicitacoes` + `REQ tcc-solicitacoes` **e nada para `tcc-geral`**; mesmas células ⇒ nada enviado; `null` ⇒ só `CLOSE`; de `null` para células ⇒ só `REQ`; relay que conecta depois recebe as células vigentes. Publicação: o texto enviado é `jsonEncode(["EVENT", payload])` com o payload assinado intacto; `OK true` ⇒ aceito; `OK false` com mensagem ⇒ recusado com a mensagem; `OK false` sem mensagem ⇒ mensagem nula; vários relays ⇒ um resultado por relay e o stream fecha ao fim; relay que não responde (`publishTimeout` curto) ⇒ recusado com `sem resposta do relay`; `send` que lança ⇒ recusado com a descrição curta do erro (corte de 80 caracteres com `…`, como o `_describe` atual); nenhum relay conectado ⇒ stream fecha vazio. `disconnect` fecha o socket; `dispose` desconecta todos e fecha os streams.
- [x] T009 [US1] Implementar `lib/services/ws_relay_gateway.dart` (parte 1): `WsRelayGateway({transport = const WsRelayTransport(), connectionTimeout = 10 s, publishTimeout = 10 s})` implementando `RelayGateway`; `_attempts` e `_links` (data-model.md); `connect` (chama `disconnect`, cria o token, espera o transporte, checa o token e fecha o socket se a tentativa foi cancelada, registra o `_Link`, escuta `messages`, inicia a inscrição se já assinado); `disconnect` (remove o `_Link` **antes** de fechar o socket); `subscribe`, `setRideRequestCells` com `_sameCells`; `publish` com `OK` pendente por `eventId` e prazo; `dispose`. Roteia só `EventFrame` de inscrições próprias e `OkFrame`. Sem `print`/`debugPrint`/log. `probe` e `connectionLost` ficam para a US2 (declarar `connectionLost` com um `StreamController` vazio e `probe` lançando `UnimplementedError` só até T011). (depende de T004, T007, T008)

**Sem commit aqui**: o gateway ainda não satisfaz `probe`/`connectionLost`. O commit sai ao fim da US2 (T012), com a mensagem abaixo.

## Fase 4: História 2 — Recuperar sozinho de uma queda de conexão (P1)

**Meta**: queda de conexão estabelecida é percebida e notificada uma vez; desconexão pedida e falha de handshake não notificam; a sonda responde a qualquer mensagem; o `RelayService` reconecta e reinscreve.
**Teste independente**: `ws_relay_gateway_test.dart` (parte 2) e um teste do `RelayService` com o gateway novo, ambos sem rede.

- [x] T010 [US2] Teste primeiro: `test/services/ws_relay_gateway_test.dart` (parte 2). Queda: fim do stream (`closeFromRelay`) de conexão estabelecida emite `connectionLost(url)` **uma única vez**; erro do stream idem; depois da queda o relay não aceita mais `probe`/`publish`; `disconnect` pedido **não** emite; falha de handshake e handshake com prazo estourado **não** emitem; fechamento tardio de um socket já substituído **não** derruba a conexão vigente nem emite; reconectar depois da queda reinscreve (`REQ` de novo). Guarda de tentativa: `disconnect` durante o handshake ⇒ o socket que chegar é fechado, `connect` lança `StateError('conexão cancelada')` e nada fica registrado; segunda `connect` ao mesmo relay durante o handshake da primeira ⇒ a primeira fecha o próprio socket e a segunda vale. Sonda: `probe` envia `REQ vivacidade` com `ids` de 64 zeros e `limit: 1`, seguido de `CLOSE vivacidade`; completa com **qualquer** mensagem do relay (`EOSE`, `NOTICE`, texto que nem é JSON); sem conexão falha na hora com `StateError`; `disconnect` com sonda pendente a completa com erro; duas sondas simultâneas no mesmo relay completam juntas.
- [x] T011 [US2] Implementar em `lib/services/ws_relay_gateway.dart` (parte 2): `connectionLost` (broadcast), `_dropped(url, link)` que só age se `link` ainda é o vigente, descarta a conexão e emite uma vez; `probe` com `Completer` por `_Link` completado por qualquer texto recebido; remover o `UnimplementedError` provisório. (depende de T009, T010)
- [x] T012 [P] [US2] Teste de integração: `test/services/relay_service_ws_gateway_test.dart` — `RelayService` real sobre `WsRelayGateway` + `FakeRelayTransport`: relay conecta e fica `connected`; `closeFromRelay` ⇒ passa a `unavailable`; `reconnectUnavailable` reconecta e a inscrição (inclusive `tcc-solicitacoes` com as células vigentes pela `applyCoverage`) é refeita; sonda sem resposta (`livenessTimeout` curto) ⇒ `unavailable` e socket fechado; falha de handshake do transporte (`SocketException`, `WebSocketException`) aparece em `Relay.lastError` já resumida por `RelayService.describeFailure`, nunca como texto cru; `removeRelay` durante o handshake não deixa conexão órfã nem evento do relay removido. Usa relógio curto real, sem `Timer` de produção longo. (depende de T011)

**Commit** (US1 + US2): "Adiciona o WsRelayGateway com inscrição em dois filtros, publicação por relay, detecção de queda e sonda de vivacidade".

## Fase 5: História 3 — Comportamento provável sem rede, inclusive contra frames hostis (P2)

**Meta**: cada item de SC-002 tem um teste nomeado, e frame hostil nunca derruba a conexão nem enfraquece a verificação a jusante.
**Teste independente**: `flutter test test/services` verde sem rede.

- [x] T013 [US3] Teste primeiro: `test/services/ws_relay_gateway_test.dart` (parte 3). Com a conexão estabelecida, empurrar `EVENT` malformado, `EVENT` truncado, texto acima de `kMaxRelayMessageChars`, `EVENT` de inscrição desconhecida, tipo desconhecido e lixo não JSON: nenhum gera `IncomingEvent` nem `connectionLost`, nenhum lança para fora do gateway, e um `EVENT` válido depois ainda é entregue. `OK false` com `invalid: bad tag` ⇒ publicação recusada com essa mensagem, socket e inscrições intactos. `CLOSED` de `tcc-solicitacoes` ⇒ conexão e `tcc-geral` seguem, **nenhum `REQ` é reenviado sozinho**, e a próxima troca de células reabre a inscrição. `NOTICE` ignorado. `OK` de `id` desconhecido ou repetido ignorado. Um `EVENT` com assinatura adulterada **é entregue bruto** pelo gateway e **descartado pelo `EventFeed`** (teste de ponta a ponta gateway → `EventFeed` com o helper de `test/support/signed_payload.dart`): prova que a verificação continua a jusante e não foi enfraquecida (FR-013).
- [x] T014 [US3] Ajustar `lib/services/ws_relay_gateway.dart` até T013 passar: descarte de inscrição desconhecida, bookkeeping de `CLOSED` (marca a inscrição como fechada sem reenviar), tolerância a `OK` repetido, nada lançando do `listen`. (depende de T011, T013)
- [x] T015 [US3] Acrescentar ao `specs/028-transporte-websocket-proprio/quickstart.md`, no cenário 1, a **matriz SC-002**: uma linha por item (handshake ok/falha/prazo; socket tardio; `EVENT` malformado/truncado; `OK` aceito/recusado; publicação sem resposta; queda uma única vez; desconexão pedida; sonda; células só do `20001` e relay tardio; limite de tamanho; tag recusada) com o nome do teste correspondente, e conferir por `flutter test --plain-name` que cada nome existe e passa. Item sem teste ⇒ criar o teste antes de fechar a tarefa. (depende de T012, T014)

**Commit** (US3): "Cobre frames hostis e a matriz de casos do transporte próprio com testes sem rede".

## Fase 6: Troca em produção e remoção do gateway antigo

- [x] T016 Em `lib/main.dart` trocar `NostrRelayGateway()` por `WsRelayGateway()` (linha ~119) e o teste de tipo do `dispose` (linha ~249) para `WsRelayGateway`; em `lib/services/background/relay_task_handler.dart` trocar o campo `NostrRelayGateway? _gateway` e a criação `NostrRelayGateway()` por `WsRelayGateway`. Nenhuma outra mudança em `RelayService`, `EventFeed`, `RelayHostCore`, `RemoteRelayConnection` nem telas. (depende de T011, T014)
- [x] T017 Remover `lib/services/nostr_relay_gateway.dart` e `test/services/nostr_relay_gateway_filters_test.dart` (já migrado em T003); `grep -rn "NostrRelayGateway" lib test` deve ficar vazio. Rodar `flutter analyze` e `flutter test` integrais: nenhum teste ignorado, incluindo `test/services/background/no_secret_leak_test.dart`. (depende de T016)

**Commit** (troca): "Troca NostrRelayGateway por WsRelayGateway na interface e no serviço em segundo plano e remove o antigo".

- [x] T018 Conferir o cenário 2 do quickstart (confinamento de `dart_nostr`, `dart:io` fora de `lib/domain`, ausência de log nos arquivos novos, nenhum `NostrRelayGateway`) e registrar a saída real no quickstart. `dart_nostr` permanece no `pubspec.yaml`. (depende de T017)
- [ ] T019 [US1] Executar o cenário 3 do quickstart (corrida completa `20001` a `20015` entre dois emuladores, relays públicos, incluindo ficar offline/online; a recusa de relay é opcional, a prova é o teste de T008) e preencher o "Registro de execução" com data, método e resultado reais, falhas inclusive. Sem número de latência ou tempo de conexão no registro, a menos que medido com método descrito. (depende de T018)
- [ ] T020 [US2] Executar o cenário 4 do quickstart (rede do emulador desligada por ~25 s, depois religada; repetir com o app em segundo plano) e registrar o caminho observado (queda detectada ou conexão que sobreviveu), o que o usuário viu e o tempo até voltar a receber eventos, com o método. Falha ⇒ relatada e aberta como pendência, não omitida. (depende de T018)

## Fase 7: Acabamento e documentação

- [x] T021 Atualizar em **commit separado, por último**: `CLAUDE.md` (linha da arquitetura: trocar `nostr_relay_gateway.dart` por `ws_relay_gateway.dart`/`ws_relay_transport.dart`/`relay_protocol.dart`; na feature 027, `NostrRelayGateway.buildFilters` ⇒ `buildFilters` em `relay_protocol.dart`; acrescentar um item curto da feature 028: transporte próprio, ids de inscrição, ping/handshake, e o que os testes cobrem) e o comentário de `lib/services/relay_gateway.dart` ("A implementação real usa `dart_nostr`" ⇒ "usa WebSocket do `dart:io`"). Conferir também `lib/services/relay_service.dart` (comentário da linha 13) e a constituição: `grep -n "dart_nostr\|NostrRelayGateway" .specify/memory/constitution.md CLAUDE.md` não pode mais descrever `dart_nostr` como transporte. Commit: "Atualiza o CLAUDE.md e o comentário do RelayGateway para o transporte WebSocket próprio" (separado da mudança que descreve).
- [ ] T022 Gates finais (Fluxo e Gates da constituição): `dart format lib test` (formatação de arquivo alheio vai em commit à parte, sem reverter), `flutter analyze` limpo, `flutter test` integral sem ignorados, quickstart com os quatro cenários registrados e falhas relatadas. Conferir ainda que nenhum número de latência ou de tempo de conexão entrou em `spec.md`, `research.md`, `quickstart.md` ou `CLAUDE.md` sem método descrito (SC-006); o teto de ~65 s do SC-004 é derivado e deve estar rotulado assim. Relatar qualquer gate pendente com a lista do que ficou de fora e por quê. (depende de T019, T020, T021)

## Dependências e ordem de execução

```text
T001 → T002
T003 → T004 ──────────┐
T005 ─┬→ T007 ────────┤
T006 ─┘               ├→ T008 → T009 → T010 → T011 → T012
                      │                         └→ T013 → T014 → T015
T011 + T014 → T016 → T017 → T018 → T019 / T020 (paralelas, emuladores distintos) → T021 → T022
```

- **Fundação (T003–T007)** bloqueia tudo; `T003`, `T005`, `T006` são paralelas (arquivos distintos).
- **US1 → US2 → US3** (US1 e US2 num commit só) compartilham `ws_relay_gateway.dart` e seu teste: sem `[P]` entre elas. `T012` é a única paralelizável (arquivo próprio) depois de `T011`.
- **Fase 6** só começa com US1 e US2 prontas (T011) e a tolerância a frames hostis (T014) feita, para não colocar em produção um gateway que um relay estranho derruba.

### Exemplo de paralelismo

```text
Fundação:  T003 (relay_protocol_test)  ‖  T005 (relay_transport + fake)  ‖  T006 (ws_relay_transport_test)
Depois:    T004 (protocolo)  ‖  T007 (transporte)
Validação: T019 (corrida completa)  ‖  T020 (queda de rede)   — se houver dois pares de emuladores; senão em sequência
```

## Estratégia de implementação

- **MVP = US1 + US2** (as duas P1 formam o mínimo para trocar o gateway em produção); US3 fecha a prova para a banca e endurece o gateway contra relay hostil antes da troca.
- Entregar em incrementos verdes: protocolo → transporte → gateway (US1) → queda e sonda (US2) → hostis e matriz (US3) → troca → cenários manuais → documentação.
- Se T020 mostrar que a recuperação depende de algo que o `RelayService` faz de forma diferente do passageiro, registrar como divergência e decidir com o usuário; mudar `RelayService` está fora do escopo desta feature.
