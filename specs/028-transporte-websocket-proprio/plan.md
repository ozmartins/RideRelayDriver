# Plano de implementação: 028-transporte-websocket-proprio

**Spec**: [spec.md](spec.md) · **App**: `driver/` · **Data**: 2026-10-22 · **Entrada**: "unificar a camada de conexão
com relays do motorista à do passageiro"

## Resumo

`NostrRelayGateway` (cliente de relays do `dart_nostr`, uma instância por relay) é substituído por um
`WsRelayGateway` que implementa a mesma interface `RelayGateway` sobre um transporte próprio de WebSocket do
`dart:io`, espelhando `ws_relay_transport.dart` e `relay_service.dart` do passageiro. Três peças, todas em
`lib/services/`:

1. **`RelayTransport` / `RelaySocket` + `WsRelayTransport`** — abre o socket com prazo de 10 s, fecha o que chega
   depois do prazo, liga o ping de 30 s. Não conhece o protocolo Nostr.
2. **`relay_protocol.dart`** — funções puras: monta `REQ`, `CLOSE`, `EVENT`, os filtros (os mesmos de hoje) e
   interpreta os frames recebidos (`EVENT`, `OK`, `NOTICE`, `EOSE`, `CLOSED`), descartando o malformado, o truncado
   e o grande demais sem lançar.
3. **`WsRelayGateway`** — o estado por relay (tentativa vigente, conexão, sonda, publicações pendentes), a
   inscrição em dois filtros com identificadores próprios, a queda de conexão e o relatório de publicação.

`RelayService`, `EventFeed`, `RelayHostCore`, `RemoteRelayConnection`, telas e o contrato de eventos não mudam. O
serviço em segundo plano (`RelayTaskHandler`) e `main.dart` só trocam o construtor. Sem dependência nova, sem
emenda de contrato, sem emenda de constituição.

## Contexto técnico

- **Linguagem/SDK**: Dart ^3.13.3, Flutter 3.47.7, Android apenas.
- **Dependências**: nenhuma nova (R1). `dart_nostr` fica no `pubspec.yaml` para chaves, assinatura e verificação
  (`identity_service.dart`, `event_verifier.dart`, `ride_rating_signature.dart` e `receipt_signature.dart`; `nip44.dart`
  só a cita em comentário); sai de `relay_gateway.dart` (só comentário) e de `nostr_relay_gateway.dart` (removido).
- **Armazenamento**: nenhum.
- **Testes**: `flutter_test` com dublês. Nenhum teste toca rede: o transporte é injetado (`FakeRelayTransport`) e o
  `WsRelayTransport` recebe uma fábrica de socket (R3). Os testes do filtro de inscrição de
  `nostr_relay_gateway_filters_test.dart` migram para o teste de `relay_protocol.dart`.
- **Alvo**: Android. Sem permissão nova (a internet já é usada).
- **Restrições**: assinatura verificada antes de tudo e deduplicação depois (inalterado, a jusante do gateway);
  filtros com `#t` e `limit: 50`, sem `since`; `20001` só online, com `#g`; o gateway nunca vê a chave privada e
  não registra payload nem conteúdo em log.
- **Escala**: até ~5 relays, 2 inscrições por relay.

## Verificação da constituição (2.18.0)

| Princípio / restrição | Situação |
|---|---|
| I — segredo não vaza | Nenhum material novo: o gateway só recebe o evento já assinado. Verificação: busca por `print`/`debugPrint`/`log` nos arquivos novos (nenhum) e, no teste, o payload enviado ao socket é exatamente o assinado (sem campo extra). Cenário 4 do quickstart. |
| II — assinatura/descarte nasce com teste | O gateway **descarta** frames (malformado, truncado, grande demais, sub desconhecida) e **não** verifica assinatura (continua em `EventFeed`/`RelayHostCore`). Testes junto do código, caso válido e inválido, sem rede: `relay_protocol_test`, `ws_relay_gateway_test`, `ws_relay_transport_test`. Os testes do `EventFeed` que provam "assinatura primeiro" seguem intactos. |
| III — dependência registrada | Nenhuma dependência nova (R1). Tipos de `dart:io` ficam em `lib/services`; `domain/` não muda. `dart_nostr` perde um consumidor. |
| IV — contrato antes do código | Contrato de eventos **não muda**. [contracts/protocolo-relay.md](contracts/protocolo-relay.md) só descreve o que o motorista envia/aceita no fio e remete à seção "Forma da inscrição"; conferido para ser idêntico ao que o passageiro faz. Ordem de recepção preservada. |
| V — simplicidade | `RelayTransport` tem duas implementações (real e dublê), como no passageiro. Sem camada nova além das três peças. Decisões não óbvias em `research.md` (R2–R8). Nenhuma medição é citada (SC-006). |
| Permissões | Nenhuma. |
| Serviço em segundo plano | Inalterado: a conexão segue no serviço; o gateway não recebe posição nem chave. A cobertura (`applyCoverage`/`ServiceSetCoverage`) continua só em memória e chega ao gateway apenas como lista de células, como hoje. |
| Identidade visual | Nenhuma tela muda. |

Sem violações; "Complexity Tracking" não se aplica. Reavaliação após o desenho (Fase 1): mesmo resultado.

## Estrutura do código

```text
lib/services/
├── relay_transport.dart          # novo: RelayTransport (connect com prazo), RelaySocket (messages, send, close)
├── ws_relay_transport.dart       # novo: WsRelayTransport — dart:io WebSocket, ping 30 s, handshake 10 s, socket tardio
├── relay_protocol.dart           # novo: frames e filtros puros; parseRelayFrame → sealed RelayFrame
├── ws_relay_gateway.dart         # novo: WsRelayGateway implements RelayGateway
├── relay_gateway.dart            # muda só o comentário ("A implementação real usa dart_nostr")
├── nostr_relay_gateway.dart      # REMOVIDO
└── background/relay_task_handler.dart   # troca NostrRelayGateway() por WsRelayGateway()
lib/main.dart                     # idem (construtor e dispose)

test/
├── services/ws_relay_transport_test.dart       # novo: handshake ok/falha/prazo, socket tardio, ping configurado
├── services/relay_protocol_test.dart           # novo: filtros (ex-nostr_relay_gateway_filters_test) + frames
├── services/ws_relay_gateway_test.dart         # novo: conexão, queda, sonda, inscrição, células, publicação
├── services/nostr_relay_gateway_filters_test.dart   # REMOVIDO (migrado)
└── support/fake_relay_transport.dart           # novo: transporte e socket dublês
```

**Decisão de estrutura**: o nome `RelayConnection` já existe no motorista (interface do `RelayService` consumida
pela UI), por isso o par do transporte chama-se `RelayTransport`/`RelaySocket`, e não `RelayConnection` como no
passageiro. O comportamento é o mesmo; só o nome diverge (registrado em R2).

## Fases

- **Fase 0** — [research.md](research.md): R1 sem dependência; R2 camadas e nomes; R3 transporte e socket tardio
  testável; R4 estado por relay, tentativa vigente e queda; R5 inscrição em dois ids e troca de células; R6 sonda;
  R7 publicação, `OK` e prazo; R8 frames hostis e limite de tamanho.
- **Fase 1** — [data-model.md](data-model.md), [contracts/protocolo-relay.md](contracts/protocolo-relay.md),
  [quickstart.md](quickstart.md).
- **Fase 2** — `/speckit-tasks`. Ordem sugerida: protocolo puro (+ migração do teste de filtros) → transporte →
  gateway → troca em `main.dart`/`RelayTaskHandler` e remoção do antigo → cenários do quickstart → commit separado
  da documentação (`CLAUDE.md`, comentário de `relay_gateway.dart`).
