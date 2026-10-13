# Phase 0 — Research: Detalhes do motorista e tempo estimado no orçamento

## D1 — ETA a partir da mesma chamada de rota (atende FR-002, FR-003)

**Decision**: `RouteDistanceService` deixa de expor só `distanceMeters(...)` e passa a expor
`estimate(...)`, devolvendo um `RouteEstimate` com `distanceMeters` **e** `durationSeconds` — a
resposta do endpoint de directions do OpenRouteService já traz os dois no mesmo `summary`
(`{"distance": ..., "duration": ...}`), então nenhuma chamada de rede nova é necessária.

**Contexto da decisão**: a feature 007 já calcula a distância motorista→origem chamando
`OrsRouteDistanceService`, descartando a duração que a API já devolvia. Ler o campo que já estava
na resposta é estritamente mais barato do que uma segunda chamada.

### Alternativas avaliadas

| Opção | Observação |
|-------|------------|
| `estimate()` devolvendo distância + duração (escolhida) | Uma chamada, dois dados — a resposta do OpenRouteService já traz ambos no mesmo `summary`. |
| Segunda chamada só para duração | Dobraria as requisições ao serviço de rota sem necessidade — o dado já vem na primeira resposta. |
| Estimar `etaMinutes` a partir da distância e uma velocidade média fixa | Rejeitada: é uma estimativa inventada, não uma medição — contradiz o motivo original de usar rota real em vez de linha reta (feature 007). |

### Riscos assumidos e mitigação

- Nenhum risco novo além dos já aceitos em D1 de `specs/007-receber-solicitacao-corrida/research.md`
  — mesma chamada, um campo a mais lido da mesma resposta.

## D2 — Omissão do campo em vez de valor sentinela (atende FR-003)

**Decision**: quando a duração motorista→origem não estiver disponível no momento do envio,
`etaMinutes` é omitido do `content` JSON (chave ausente), nunca `null` nem `0`.

**Contexto da decisão**: `0` seria lido como "chegada imediata", uma afirmação falsa; `null`
exigiria que todo consumidor futuro do contrato tratasse esse caso especificamente. Uma chave
ausente é o formato mais simples de expressar "este dado não existe para este evento" — o mesmo
raciocínio já usado pela emenda 04 ("nenhum outro campo é definido").

### Riscos assumidos e mitigação

- Nenhum — decisão de formato, sem custo de implementação adicional em nenhum dos lados.
