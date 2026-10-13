# Contrato — emenda 13: `kind: 20011` "Rota da corrida"

Este diretório não guarda um contrato próprio: o contrato único do protótipo está em
`specs/002-nostr-relay-connection/contracts/nostr-events.md` (e na cópia do passageiro, com
cabeçalho de procedência). Esta feature **acrescenta a emenda 13 às duas cópias, na mesma alteração
e antes do código** (Princípio IV). O texto a inserir:

## 1. Linha na tabela de kinds (depois de `20010`)

```
| `20011` | Rota da corrida | feature 017 (motorista) | motorista → relays → passageiro | JSON estruturado — ver *Conteúdo do kind 20011* abaixo |
```

## 2. Linha no *Histórico de emendas*

```
| 13 | 2026-10-03 | Define `kind: 20011` para "Rota da corrida" (seção *Conteúdo do kind 20011*); o passageiro passa a se inscrever também em `20011` (Forma da inscrição atualizada) | Feature 017 do motorista (publicar a rota ao passageiro): o passageiro deve traçar no mapa o trajeto até o destino durante "Em corrida" sem calcular rota — o motorista, que já calcula o trajeto para o próprio mapa (feature 016), o publica a cada cálculo ou recálculo bem-sucedido. O consumo pelo passageiro é da feature dele (018) |
```

## 3. Seção nova (depois de *Conteúdo do kind 20010*)

```
## Conteúdo do kind 20011 — Rota da corrida (emenda 13)

Evento **efêmero** (mesma faixa 20000–29999 — uma rota perde sentido assim que uma nova chega).
Publicado pelo motorista **a cada cálculo ou recálculo bem-sucedido do trajeto até o destino**,
somente enquanto está no estado local "Em corrida" (feature 012); nunca em "Deslocando-se até o
passageiro" nem em "Aguardando solicitação de corrida", e nunca quando o cálculo falha.

**Tags**: a tag de marcador do protótipo, `["t", "tcc-ufsc-caronas"]`; uma tag de referência ao
orçamento aceito daquela corrida, `["e", "<id-do-orçamento>"]`; e uma tag de destinatário,
`["p", "<pubkey-do-passageiro>"]` — mesmo formato do `kind: 20005`.

**`content`**: string JSON com este formato:

{ "points": [[-28.93123, -49.48891], [-28.93140, -49.48870], ...] }

| Campo | Tipo | Observação |
|-------|------|------------|
| `points` | lista de `[lat, lon]` | Trajeto da posição do motorista, no instante do cálculo, até o destino da corrida, na ordem de percurso. Mínimo 2 pontos, **máximo 1000**. `lat`/`lon` em graus decimais com **no máximo 5 casas** (~1 m). Se a rota calculada tiver mais de 1000 pontos, o motorista toma pontos uniformemente espaçados, sempre preservando o primeiro e o último |

**Tamanho**: ~23 KB com 1000 pontos, ~18 % do menor `max_message_length` anunciado pelos relays
padrão (131 072 B em `nos.lol`/`offchain.pub`, medido em 2026-10-03).

**Privacidade**: publicado sem criptografia, para o passageiro daquela corrida — mesma justificativa
dos kinds anteriores. Origem e destino já constam do `kind: 20001`, e a posição do motorista, do
`kind: 20005`; este evento não acrescenta dado sobre pessoas além do trajeto entre eles.

**Consumo pelo passageiro**: implementado pela feature 018 dele. Só vale rota **assinada pelo
motorista cujo orçamento o passageiro aceitou** (autor do evento = autor do `kind: 20002` aceito) e
que referencia o `quoteId` da corrida, com o passageiro em "Em corrida"; vale a de maior
`created_at`; `content` malformado, com menos de 2 ou mais de 1000 pontos, ou com coordenadas fora
de faixa, é descartado sem alterar o traçado; só em memória, nunca persistido. Fora dessas
condições, é ignorado sem erro.
```

## 4. Forma da inscrição

Acrescentar ao parágrafo que lista os kinds consumidos: o passageiro inclui também `20011` (desde
a emenda 13). A inscrição do motorista não muda.

## 5. Cópia do passageiro

Atualizar o cabeçalho de procedência (data e "emenda 13, kind 20011") e manter o restante
**idêntico** ao do motorista (`diff` das duas cópias, ignorando o cabeçalho, deve ser vazio).
