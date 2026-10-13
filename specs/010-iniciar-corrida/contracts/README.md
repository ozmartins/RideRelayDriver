# Contratos desta feature

Esta feature não define um contrato próprio neste diretório: uma nova emenda (08) ao contrato
único do protótipo cobre os dois kinds novos, e a leitura do `kind: 20003` já definido pela
feature 008 do passageiro.

Ver `../../002-nostr-relay-connection/contracts/nostr-events.md`, seções (a escrever/atualizar
durante a implementação desta feature, replicadas na mesma alteração em
`Prototipo/passenger/specs/002-nostr-relay-connection/contracts/nostr-events.md`, Princípio IV):

- *Conteúdo do kind 20003 — Aceitação de orçamento* (emenda 07, já existente — esta feature passa a
  consumi-la do lado do motorista, primeira consumidora desse kind).
- *Conteúdo do kind 20005 — Localização do motorista* (nova, emenda 08 — ver D2 e D4 de
  `../research.md` para o formato de tags e conteúdo).
- *Conteúdo do kind 20006 — Corrida não pode mais ser atendida* (nova, emenda 08 — mesma seção
  acima).
- *Forma da inscrição*: a lista de `kinds` da inscrição do motorista passa a incluir `20003`
  (emenda 08) — hoje só inclui `20001`.

O consumo dos kinds 20005/20006 pelo passageiro fica fora de escopo desta feature, mesmo padrão já
usado para o consumo do `kind: 20001` pelo motorista (emenda 04) e do `kind: 20002` pelo passageiro
(emenda 05) — ver D5 de `../research.md`.
