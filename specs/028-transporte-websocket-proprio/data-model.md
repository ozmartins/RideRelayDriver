# Modelo de dados: 028-transporte-websocket-proprio

Nenhum dado persistido nem tipo de domínio novo. Tudo abaixo vive em memória, em `lib/services/`.

## RelayTransport / RelaySocket (`relay_transport.dart`)

| Tipo | Membro | Descrição |
|---|---|---|
| `RelayTransport` | `Future<RelaySocket> connect(String url, {Duration timeout})` | Abre o socket; lança em falha ou `TimeoutException` no prazo (padrão 10 s). |
| `RelaySocket` | `Stream<String> messages` | Só frames de texto, em *broadcast*; termina (`onDone`) ou falha (`onError`) quando o socket cai. |
| | `void send(String message)` | Envia um frame de texto; lança `StateError` se o socket já fechou. |
| | `Future<void> close()` | Fecha; idempotente. |

`WsRelayTransport({pingInterval = 30 s, connector = WebSocket.connect})` é a implementação real.

## RelayFrame (`relay_protocol.dart`)

```text
sealed RelayFrame
├── EventFrame  { subscriptionId: String, payload: Map<String, dynamic> }
├── OkFrame     { eventId: String, accepted: bool, message: String? }
├── NoticeFrame { message: String }
├── EoseFrame   { subscriptionId: String }
└── ClosedFrame { subscriptionId: String, message: String? }
```

`RelayFrame? parseRelayFrame(String raw)` — `null` para tudo que não for um frame bem formado (R8).
Montagem: `reqFrame(subId, filters)`, `closeFrame(subId)`, `eventFrame(payload)`; `buildFilters(kinds, cells)` devolve
`List<Map<String, dynamic>>` (substitui o método estático homônimo de `NostrRelayGateway`).

## Estado do WsRelayGateway

| Campo | Tipo | Vida |
|---|---|---|
| `_attempts` | `Map<url, Object>` | token da tentativa de conexão vigente; removido por `disconnect` |
| `_links` | `Map<url, _Link>` | conexão estabelecida; removida em `disconnect` ou queda |
| `_Link` | `socket`, `sub` (assinatura de `messages`), `probe: Completer?`, `pendingOk: Map<eventId, Completer<OkFrame>>`, `subs: Set<subId>` | uma por conexão |
| `_kinds`, `_cells`, `_subscribing` | `List<int>`, `List<String>?`, `bool` | configuração da inscrição, igual à de hoje |

Identificadores de inscrição: `tcc-geral`, `tcc-solicitacoes`, `vivacidade` (sonda).

### Transições de uma conexão

```text
(sem conexão) --connect--> [handshake] --ok e tentativa vigente--> [estabelecida]
[handshake] --falha/prazo--> (sem conexão) + connect lança
[handshake] --disconnect ou nova connect--> socket fechado + connect lança "conexão cancelada"
[estabelecida] --disconnect--> (sem conexão), sem connectionLost
[estabelecida] --onDone/onError (link vigente)--> (sem conexão) + connectionLost(url) uma vez
```

## Validações

- Inscrição: nunca `since`; `limit: 50`; `#t` em todos os filtros; `20001` só com `#g` não vazio e `kinds` contendo-o.
- Entrada: `EVENT` só entra se a inscrição for uma das do relay; payload deve ser objeto; o resto é a jusante.
