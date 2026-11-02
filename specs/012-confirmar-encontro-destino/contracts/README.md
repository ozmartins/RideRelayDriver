# Contratos desta feature

Esta feature não define um contrato próprio neste diretório: uma nova emenda (11) ao contrato
único do protótipo cobre os três kinds novos.

Ver `../../002-nostr-relay-connection/contracts/nostr-events.md` (a escrever/atualizar durante a
implementação desta feature, replicada na mesma alteração em
`Prototipo/passenger/specs/002-nostr-relay-connection/contracts/nostr-events.md`, Princípio IV):

- *Conteúdo do kind 20008 — Encontro confirmado* (nova, emenda 11 — publicado pelo passageiro,
  consumido pelo motorista nesta feature).
- *Conteúdo do kind 20009 — Chegada ao destino* (nova, emenda 11 — publicado pelo motorista nesta
  feature).
- *Conteúdo do kind 20010 — Destino confirmado* (nova, emenda 11 — publicado pelo passageiro,
  consumido pelo motorista nesta feature).
- *Forma da inscrição*: a lista de `kinds` da inscrição do motorista passa a incluir `20008` e
  `20010`.

A publicação de `kind: 20008`/`20010` e o consumo de `kind: 20009` pelo passageiro ficam fora de
escopo desta feature — implementados por uma feature própria do passageiro, especificada em
seguida (D5 de `../research.md`).
