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

## Operações (nomes fixos)

`app.inicio`, `tela.acao` (campo `motivo` = nome da ação), `relay.conectou`, `relay.caiu`,
`relay.ok` / `relay.closed` / `relay.notice`, `evento.publicou`, `evento.recebeu`,
`evento.descartou`, `corrida.estado` (`motivo` = novo estado), `recibo.emitiu`, `recibo.confirmou`,
`externo.falha`, `log.rotacao`.

## Proibido (FR-052)

Chave privada; `content` (cifrado ou claro); chave da ORS; latitude/longitude; raio; texto de
endereço; qualquer campo fora da tabela. Um teste planta esses valores e exige que não apareçam.
