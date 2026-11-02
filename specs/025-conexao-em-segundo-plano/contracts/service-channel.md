# Contrato interno UI ↔ serviço (não é contrato Nostr)

Mensagens são `Map<String, dynamic>` com campo `t` (tipo) e `v: 1`. Só tipos primitivos. **Nenhuma mensagem carrega
chave privada, semente ou texto decifrado** (Princípio I). Mudança de formato é mudança nos dois lados do mesmo
app, na mesma alteração. Não afeta o passageiro nem o contrato `nostr-events.md`.

| `t` | Direção | Campos | Efeito |
|---|---|---|---|
| `hello` | UI→S | `foreground: bool` | handshake ao abrir/voltar |
| `ready` | S→UI | — | enviada pelo serviço assim que o isolate está de pé; até recebê-la, a UI enfileira comandos |
| `helloAck` | S→UI | `online: bool`, `relays: [{url,status,error?,isDefault}]`, `pending: [payload]` | estado atual + solicitações guardadas (≤ 5 min); cada `pending` é reentregue à UI **também como `incoming`** (mesmo caminho de verificação/dedupe) |
| `state` | UI→S | `online`, `acceptedPayments`, `rideStatus`, `foreground` | atualiza filtro; `foreground=false` habilita notificação |
| `connectAll` | UI→S | `relays: [{url,status,error?,isDefault}]` | substitui a lista e conecta |
| `addRelay` / `removeRelay` | UI→S | `url` | idem `RelayService` |
| `reconnectNow` | UI→S | — | idem `RelayService.reconnectNow` |
| `publish` | UI→S | `reqId`, `id`, `payload` (evento **já assinado/cifrado**) | publica pelo gateway |
| `publishResult` | S→UI | `reqId`, `outcomes: [{relayUrl, accepted, message?}]`, `done: bool` | uma por `PublishOutcome`; `done` fecha o stream |
| `relaysChanged` | S→UI | `relays: [...]` | reflete `statusChanges` |
| `incoming` | S→UI | `relayUrl`, `payload` | evento **já verificado** (assinatura, marcador, dedupe) |
| `stop` | UI→S | — | encerra o serviço |

**Regras**: (0) no `onStart` o serviço lê a lista de relays do `RelayRepository` e conecta sozinho; `connectAll` da
UI só chega para restaurar a lista padrão; (1) o serviço verifica assinatura (id recalculado) antes de repassar ou decidir notificar; (2)
`publish` sem relay conectado devolve `publishResult` com `done=true` e `outcomes` vazio e erro `no_relay` (a UI
converte em `NoConnectedRelay`); (3) mensagem desconhecida ou de versão `v` diferente é ignorada sem erro; (4)
`pending` nunca contém evento recusado pelo `RideRequestFilter`.
