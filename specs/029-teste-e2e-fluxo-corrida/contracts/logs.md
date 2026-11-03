# Contrato: log dos aplicativos (emenda de 2026-11-03)

Idêntico nos dois repositórios (motorista e passageiro). Mudou aqui ⇒ muda lá no mesmo commit.

## Arquivo

- JSON Lines, UTF-8, uma linha = um objeto. No diretório privado do app: `logs/fluxo-<isolate>.jsonl`
  (`ui` e `servico`; um arquivo por isolate para não haver escrita concorrente). O relatório junta os dois.
- Rotação por tamanho: ao passar do teto, o arquivo antigo vira `.1` (um só) e a primeira linha do novo
  é `{"op":"log.rotacao","perdidas":N,...}`.
- Extração: `adb exec-out run-as <pacote> cat files/logs/...` (build debug) ou botão de exportar.

## Campos

| Campo | Tipo | Obrigatório | Observação |
|-------|------|-------------|------------|
| `t` | inteiro | sim | UTC, ms desde a época |
| `papel` | `motorista` \| `passageiro` | sim | |
| `exec` | texto | sim | identificador da execução manual |
| `iso` | `ui` \| `servico` | sim | isolate que gravou |
| `comp` | texto | sim | componente (`tela`, `relay`, `feed`, `corrida`, `recibo`, `rota`…) |
| `op` | texto | sim | operação, ver tabela abaixo |
| `res` | `ok` \| `falha` \| `descartado` \| `info` | sim | |
| `kind` | inteiro | não | kind Nostr |
| `id` | texto | não | id do evento (hex) |
| `relay` | texto | não | URL do relay |
| `guid` | texto | não | `guid_corrida` |
| `motivo` | texto | não | código curto (`assinatura`, `marcador`, `raio`, `duplicado`, `timeout`, `http429`…) |
| `ext` | `photon` \| `openfreemap` \| `ors` | não | serviço externo, em falha atribuível |
| `n` | inteiro | não | tamanho/contagem (bytes do frame, nº de eventos) |
| `erro` | texto | não | texto do erro (até 300 caracteres, uma linha), em `externo.falha` |
| `endereco` | texto | não | endereço consultado ou escolhido (até 300 caracteres) |
| `lat`, `lon` | número | não | coordenada consultada/escolhida (graus decimais); origem, quando há duas |
| `lat2`, `lon2` | número | não | segunda coordenada (destino), em rotas e na solicitação |
| `ms` | inteiro | não | duração da chamada a serviço externo, em milissegundos |

## Operações (nomes fixos)

`app.inicio`, `tela.acao` (campo `motivo` = nome da ação), `relay.conectou`, `relay.caiu`,
`relay.ok` / `relay.closed` / `relay.notice`, `evento.publicou`, `evento.recebeu`,
`evento.descartou`, `corrida.estado` (`motivo` = novo estado), `recibo.emitiu`, `recibo.confirmou`,
`externo.chamada`, `externo.falha`, `log.rotacao`.

`externo.chamada` registra **toda** chamada a Photon, OpenFreeMap (estilo, tiles, sprites) ou
openrouteservice, com `res` `ok` ou `falha`, `ms` e o que foi consultado (`comp` = `rota`,
`geocodificacao`, `estilo`, `tile`, `sprite`). Em falha vem também um `externo.falha`, que é o sinal
usado pelo relatório para atribuir a origem. Resposta válida sem resultado ("nenhum endereço") é
`ok` com `motivo` `sem_resultado`.

## Texto livre e coordenadas (emenda de 2026-11-03)

`erro` e `endereco` são normalizados: uma linha, no máximo 300 caracteres; credenciais
(`api_key=…`, `Authorization: …`, `token`, `nsec…`), qualquer sequência de 64 hex (chave privada) e a
chave da ORS viram `[oculto]`. Coordenadas fora de ±90/±180 são omitidas.

## Proibido (FR-052)

Chave privada; `content` (cifrado ou claro); chave da ORS; raio de atendimento; qualquer campo fora
da tabela. Um teste planta esses valores e exige que não apareçam.
