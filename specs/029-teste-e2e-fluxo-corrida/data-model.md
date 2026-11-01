# Data Model: Teste E2E do fluxo da corrida

Estruturas do roteiro (não são tipos do app). Nenhum campo guarda chave privada nem `content`.

## Periodo (`checkpoint.json`, um por período)

| Campo | Tipo | Regra |
|-------|------|-------|
| `periodo` | 1 \| 2 \| "ensaio" | |
| `meta_validos` | int | 30 (ensaio: `--meta-validos`) |
| `teto_executados` | int | 40 (período 1); 80 − executados do 1 (período 2) |
| `orcamento_ms` / `tempo_ativo_ms` | int | 3 h; soma das execuções |
| `execucoes` | lista de {inicio, fim, motivo_parada} | uma por invocação |
| `identidades` | {motorista_pub, passageiro_pub} | só chaves **públicas** (hex) |
| `executados`, `validos`, `falhas`, `externos_repostos`, `interrompidos` | int | contadores recalculáveis de `ciclos.jsonl` |
| `estado` | em_andamento \| concluido \| parcial | parcial por orçamento, teto, cota da ORS |
| `motivo_parcial` | texto? | orçamento \| teto_executados \| limite_diario_ors \| ambiente \| interrompido |
| `versoes` | {motorista_commit, passageiro_commit, *_sujo} | FR-030 |
| `ambiente` | {avd_motorista, avd_passageiro, serial_*, api, abi, relays[], deriva_relogio_s: {motorista, passageiro}} | FR-006/007; deriva lida de `adb shell date +%s` |

Transições: `em_andamento → concluido` (meta atingida) \| `→ parcial` (orçamento, teto, cota, ambiente).
`parcial → em_andamento` só por `--retomar` e só se o motivo não for teto/cota.

## Ciclo (`ciclos.jsonl`, uma linha por ciclo concluído)

| Campo | Tipo | Regra |
|-------|------|-------|
| `ciclo` | int | sequencial no período, a partir de 1; reposição recebe número novo |
| `periodo` | 1 \| 2 \| "ensaio" | |
| `inicio_utc`, `fim_utc` | ISO-8601 UTC | |
| `etapas` | lista de Etapa | na ordem E01…E12, R |
| `resultado` | sucesso \| falha \| interrompido | |
| `valido` | bool | falso para `externo` e `interrompido` |
| `reposto_por` | int? | não é gravado (o arquivo é só-acréscimo); o relatório deriva a reposição: cada ciclo externo é reposto pelo ciclo válido seguinte |
| `etapa_falha` | texto? | id da etapa |
| `origem` | aplicativo \| relays \| servico_externo \| ambiente_teste | exatamente uma, se falha |
| `servico_externo` | Photon \| OpenFreeMap \| OpenRouteService \| null | obrigatório se `origem = servico_externo` |
| `origem_bruta` | texto? | `indeterminada` no caso de FR-026; senão igual a `origem` |
| `sinal_externo` | {fonte: ui\|logcat, servico, http?} \| null | só classificação, nunca linha bruta |
| `capturas` | lista de caminhos relativos | |
| `anomalias` | lista de kinds | 20004/20006/20012/20013 observados dentro do ciclo |
| `desvios` | lista de texto | FR-040 |
| `eventos` | lista de ids de evento (hex 64) | os do ciclo, para auditoria; sem `content` |

## Etapa

| Campo | Tipo |
|-------|------|
| `id` | E01…E12, R |
| `resultado` | ok \| falha \| timeout \| interrompido |
| `inicio_utc`, `fim_utc` | ISO-8601 (relógio do hospedeiro) |
| `acao_utc` | ISO-8601? — instante em que o comando de ação **retornou** |
| `acao_inicio_utc` | ISO-8601? — instante em que foi **disparado** |
| `acao_tipo` | toque \| posicionamento \| null |
| `limite_ms` | int |

## EventoObservado (`eventos.jsonl`, do observador)

| Campo | Tipo | Regra |
|-------|------|-------|
| `relay` | url | uma linha por (evento, relay) |
| `kind` | int | |
| `id` | hex 64 | |
| `created_at` | int (s) | |
| `recebido_utc` | ISO-8601 | relógio do hospedeiro |
| `autor` | "motorista" \| "passageiro" | papel da identidade do período, não a chave |
| `destinatario` | "motorista" \| "passageiro" \| null | idem, a partir da tag `p` |
| `ciclo` | int? | número do ciclo em andamento no instante do registro (informativo); a associação oficial é por janela de tempo + papéis |

**Não existe campo `content`**, nem `sig`, nem `tags`. Eventos de assinatura inválida: só contador
`invalidos_por_relay` no checkpoint.

## Latencia (derivada, não persistida além do CSV)

`tipo` (linha da tabela FR-028 + categoria `toque`/`posicionamento`), `ciclo`, `acao_utc`,
`recebido_utc` (menor entre relays), `latencia_ms`, `relay_primeiro`. Evento não encontrado → sem
amostra (nunca zero). Latência negativa → descartada com `desvio` (relógio).

## Falha (derivada para o relatório)

`ciclo`, `etapa`, `origem`, `servico_externo?`, `origem_bruta`, `captura_motorista`,
`captura_passageiro`, `dump_*`. A lista da seção 6 vem daqui.

## Relações

Periodo 1—N Ciclo; Ciclo 1—N Etapa; Ciclo 1—N EventoObservado (por janela + papéis); Periodo 1—N
EventoObservado; Ciclo 0..1 Falha.
