# Protocolo no fio — o que o motorista envia e aceita (feature 028)

**Não é emenda do contrato de eventos.** Kinds, tags, cifragem, marcador e regras de recepção ficam em
[`specs/002-nostr-relay-connection/contracts/nostr-events.md`](../../002-nostr-relay-connection/contracts/nostr-events.md);
a "Forma da inscrição" (e a emenda 27) continua valendo sem alteração. Este arquivo descreve só o transporte do
motorista, para conferência com o passageiro (`ws_relay_transport.dart`, `relay_service.dart`).

## Enviados (frames de texto JSON, NIP-01)

| Frame | Quando | Forma |
|---|---|---|
| `REQ` geral | conexão estabelecida (e já assinado) | `["REQ","tcc-geral",{"kinds":[…sem 20001…],"#t":["tcc-ufsc-caronas"],"limit":50}]` — omitido se não há kinds além do `20001` |
| `REQ` solicitações | online (células não vazias) e `20001` consumido; ao conectar e a cada troca de células | `["REQ","tcc-solicitacoes",{"kinds":[20001],"#t":["tcc-ufsc-caronas"],"#g":[…≤9 células…],"limit":50}]` |
| `CLOSE` | antes de refazer `tcc-solicitacoes`; ao ficar offline | `["CLOSE","tcc-solicitacoes"]` |
| sonda | `probe(url)` | `["REQ","vivacidade",{"ids":["0"×64],"limit":1}]` e `["CLOSE","vivacidade"]` |
| `EVENT` | `publish` | `["EVENT",{id,pubkey,created_at,kind,tags,content,sig}]` — o payload assinado, sem alteração |

Nenhum `since`. Nenhum filtro sem `#t`. Nenhum campo extra no evento.

## Aceitos

| Frame | Tratamento |
|---|---|
| `["EVENT",<sub>,{…}]` com `<sub>` ∈ {`tcc-geral`,`tcc-solicitacoes`} | entregue como `IncomingEvent(url, payload)`; assinatura, marcador, geografia e duplicidade são verificados adiante (`EventFeed`/`RelayHostCore`) |
| `["OK",<id>,<bool>,<msg>]` | conclui a publicação de `<id>` naquele relay: aceito / recusado com `<msg>` |
| `["NOTICE",<msg>]` | ignorado (conta como vida) |
| `["EOSE",<sub>]` | ignorado (conta como vida) |
| `["CLOSED",<sub>,<msg>]` | inscrição encerrada pelo relay; socket e outras inscrições seguem |
| qualquer outra coisa: não é JSON, truncado, raiz não lista, tipo desconhecido, campos fora de tipo, texto > 262 144 caracteres | descartado sem erro, conexão mantida (conta como vida para a sonda) |

## Tempos (iguais ao passageiro)

| Item | Valor |
|---|---|
| Prazo do handshake | 10 s; socket que chega depois é fechado |
| Ping do WebSocket | 30 s |
| Prazo de `OK` na publicação | 10 s |
| Sonda de vivacidade e retentativas | a cargo do `RelayService` (inalterado: sonda a cada 30 s, prazo 10 s, retentativa a cada 15 s) |
