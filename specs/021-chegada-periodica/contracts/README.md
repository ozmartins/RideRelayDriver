# Contrato — emenda 20: `kind: 20007` periódico

Esta feature **não altera formato**: a emenda 20 já foi escrita nas duas cópias de
`specs/002-nostr-relay-connection/contracts/nostr-events.md` (commit `7c77d9a`, 2026-10-07), antes do código
(Princípio IV). Ela troca "uma única vez por corrida" por "a cada 5 s enquanto em 'Deslocando-se até o
passageiro' a até 10 m da origem" e descreve o consumo idempotente pelo passageiro.

Conferir ao fim: `diff <(tail -n +12 ../passenger/specs/002-nostr-relay-connection/contracts/nostr-events.md)
specs/002-nostr-relay-connection/contracts/nostr-events.md` não deve imprimir nada.
