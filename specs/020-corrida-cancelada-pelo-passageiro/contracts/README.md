# Contrato — emenda 19: `kind: 20013` "Corrida cancelada pelo passageiro"

Esta feature **não altera o contrato**: a emenda 19 já foi escrita nas duas cópias de
`specs/002-nostr-relay-connection/contracts/nostr-events.md` (commit `747f944`, 2026-10-07), antes do código,
na mesma alteração (Princípio IV). O motorista só **consome** o kind.

O que o motorista implementa, em ordem, segundo a seção *Conteúdo do kind 20013* do contrato:

1. Inscrição em `kinds` inclui `20013` (Forma da inscrição, emenda 19).
2. Regra de recepção 7: tag `p` = chave do receptor; `content` decifra para exatamente `{}`; senão, descartar.
3. Consumo pelo motorista: autor = passageiro da corrida ativa; `["e", ...]` = `quoteId` da corrida ativa;
   estado "Deslocando-se até o passageiro" ou "Em corrida"; senão, ignorar sem erro.

Conferir ao fim: `diff <(tail -n +12 ../passenger/specs/002-nostr-relay-connection/contracts/nostr-events.md)
specs/002-nostr-relay-connection/contracts/nostr-events.md` não deve imprimir nada.
