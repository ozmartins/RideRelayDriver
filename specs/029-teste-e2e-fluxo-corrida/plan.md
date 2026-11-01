# Implementation Plan: Teste E2E automatizado do fluxo completo da corrida (caminho feliz)

**Branch**: `029-teste-e2e-fluxo-corrida` (direto na `master`) | **Date**: 2026-11-01 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/029-teste-e2e-fluxo-corrida/spec.md`

## Summary

Um roteiro de linha de comando em Dart (`tool/e2e/e2e.dart`) que, por ADB, opera os dois
emuladores (motorista e passageiro) e repete o fluxo completo da corrida até obter 30 ciclos
válidos por período, enquanto um observador independente (conexão WebSocket própria aos mesmos
três relays, reaproveitando o transporte e os frames de `lib/services/`) registra só metadados dos
eventos. Cada ciclo grava um registro JSON Lines e um checkpoint; o relatório (Markdown + CSV) é
gerado a partir desses registros por um segundo comando, com Clopper-Pearson e mediana/P95
calculados por código próprio testado contra valores do scipy. Nenhuma dependência nova.

## Technical Context

**Language/Version**: Dart 3.13 (SDK do Flutter já usado no repositório); scripts em `tool/e2e/`

**Primary Dependencies**: nenhuma nova. Reaproveita `dart:io`, `dart_nostr` (só verificação de
assinatura, via `NostrEventVerifier`), e código do próprio app sem Flutter:
`lib/services/relay_protocol.dart`, `relay_transport.dart`, `ws_relay_transport.dart`,
`event_verifier.dart`, `default_relays.dart`, `prototype_marker.dart`, `domain/geohash.dart`,
`domain/nostr_event.dart`. Ferramentas externas: `adb` (e `emulator` para conferência de AVD).

**Storage**: arquivos em `e2e_saida/` (ignorada pelo Git): JSON Lines, JSON de checkpoint, PNG,
XML, CSV, Markdown. Sem banco.

**Testing**: `flutter test` (gate da constituição) para toda a lógica pura, em `test/tool/e2e/`,
com dublês de `Adb`, de `RelayTransport` (já existe `test/support/fake_relay_transport.dart`) e de
relógio; a execução contra emuladores reais é validada pelo `quickstart.md`, não por `flutter test`.

**Target Platform**: Linux (máquina do pesquisador) controlando 2 AVDs Android 14/API 34 x86_64.

**Project Type**: ferramenta de linha de comando de avaliação experimental (fora do app).

**Performance Goals**: um período de 30 ciclos válidos em ≤ 3 h (orçamento duro); média alvo ≤ 5 min por
ciclo incluindo a volta ao estado inicial.

**Constraints**: nenhuma chave privada, `content` ou credencial em arquivo/log/relatório; nenhum
relay local/simulado; esperas só por condição com timeout; retomável; orçamento de 3 h por período.

**Scale/Scope**: ≤ 80 ciclos executados no total (40 no período 1, saldo no 2); ~12 etapas por
ciclo; 3 relays; 1 observador.

## Constitution Check

*GATE: passa antes da pesquisa e é reavaliado após o desenho.*

| Item da constituição | Avaliação |
|----------------------|-----------|
| I. Segredo não vaza | **Passa.** O roteiro nunca lê chave privada: as identidades são geradas pelos apps no Keystore e o roteiro lê só a **chave pública** da tela "Minha identidade", em memória, sem salvar dump nem captura dessa tela. Verificação automática de saída (FR-029, `output_scan`) cobre `nsec`, hex de 64/128 caracteres fora de lista de permitidos, `"content"` e a chave do openrouteservice. A verificação de não vazamento é critério de aceitação (quickstart 6). |
| II. Assinatura/verificação com teste | **Passa.** O observador descarta evento com assinatura inválida; testes cobrem válido e adulterado, sem rede (`fake_relay_transport`). |
| III. Dependência decide-se por escrito | **Passa, sem dependência nova.** Clopper-Pearson em código próprio (decisão D5 de `research.md`); scipy é só referência de conferência, não dependência do projeto. |
| IV. Contrato antes do código | **Passa.** Nenhum kind novo, nenhuma mudança no contrato. A tabela ação→evento só **lê** o contrato (kinds 20001–20015). Fora do escopo: nada é replicado no app do passageiro. |
| V. Simplicidade e rastreabilidade | **Passa com ressalva registrada.** `Adb` é interface porque há dublê de teste (segunda implementação real). Timeouts são **limites escolhidos**, não medições; o relatório os rotula como tal (D7). |
| Segurança e privacidade | O observador só envia `REQ`/`CLOSE` a relays (nunca `EVENT`); nenhum dado de usuário vai a serviço de terceiros por este roteiro (não há sondagem aos serviços, FR-021a). Pubkeys de terceiros não são persistidas: filtro por `authors`/`#p` das identidades do período (D4). |
| Identidade visual | Não se aplica (nenhuma tela nova). |
| Gates de desenvolvimento | `flutter analyze` e `flutter test` limpos; cenários do `quickstart.md` executados e relatados, inclusive os que falharem. |

Reavaliação pós-desenho: sem mudança; nenhuma violação a justificar (Complexity Tracking vazio).

## Project Structure

### Documentation (this feature)

```text
specs/029-teste-e2e-fluxo-corrida/
├── plan.md
├── research.md          # decisões D1–D12
├── data-model.md        # registros e estados
├── quickstart.md        # validação (ensaio, retomada, vazamento, relatório)
├── contracts/
│   ├── cli.md           # linha de comando do roteiro
│   └── saidas.md        # esquema dos arquivos gerados (JSONL, CSV, pastas)
└── tasks.md             # /speckit-tasks (não criado aqui)
```

### Source Code (repository root)

```text
tool/e2e/
├── e2e.dart                     # ponto de entrada: --periodo | --retomar | --relatorio | --verificar-saida
├── gen_clopper_pearson_vectors.py   # gera test/fixtures (segunda via: scipy); não faz parte do roteiro
└── src/
    ├── config.dart              # relays, pacotes, coordenadas fixas, timeouts, tetos, rótulos de tela
    ├── adb.dart                 # interface Adb + AdbProcesso (Process.run) — screencap, dump, tap, text, geo fix, pm, logcat
    ├── ui.dart                  # parse do dump XML, seletores por texto/content-desc, esperar(condição, timeout)
    ├── telas.dart               # catálogo de seletores/rótulos dos dois apps + lista de telas sensíveis
    ├── preparo.dart             # pm clear, permissões, cadastros, leitura das chaves públicas, conferência dos relays
    ├── ciclo.dart               # etapas do ciclo + volta ao estado inicial + recuperação
    ├── periodo.dart             # laço do período: meta, teto, orçamento, checkpoint, parada
    ├── opcoes.dart              # linha de comando
    ├── registro.dart            # log sem segredos (sanitizar)
    ├── relogio.dart             # relógio injetável
    ├── observador.dart          # Observador (REQ aos 3 relays, verifica assinatura, registra metadados sem content)
    ├── latencia.dart            # tabela ação→evento e cálculo por tipo
    ├── classificacao.dart       # regras determinísticas de origem da falha
    ├── evidencia.dart           # capturas/dumps: política de telas permitidas e sensíveis
    ├── checkpoint.dart          # leitura/escrita de ciclos.jsonl e checkpoint.json; tetos; orçamento acumulado
    ├── estatistica.dart         # Clopper-Pearson, posto mais próximo, mediana
    ├── relatorio.dart           # Markdown + CSV
    └── varredura_saida.dart     # verificação automática de padrões proibidos

test/tool/e2e/                   # espelha tool/e2e/src (flutter test)
test/fixtures/e2e_clopper_pearson_vectors.json   # valores do scipy, gerado por gen_clopper_pearson_vectors.py
.gitignore                       # + /e2e_saida/
```

**Structure Decision**: tudo em `tool/e2e/` (já reservado a sondas e geradores, fora de `lib/`), para
que o app não ganhe código de avaliação; a lógica pura é testada em `test/tool/e2e/`. A saída vai
para `e2e_saida/` na raiz (não `build/`, que o `flutter clean` apaga).

## Fluxo do ciclo (etapas)

Seletores por texto visível ou `content-desc` de `uiautomator dump`; rótulos hoje conhecidos do
código dos apps (a confirmação em execução é o cenário 2 do quickstart). "t" = instante registrado.

| # | Etapa | Ação do roteiro | Condição de sucesso (espera com timeout) | Evento (observador) |
|---|-------|-----------------|-------------------------------------------|---------------------|
| E01 | Estado inicial | verificar mapa ocioso nos dois apps; motorista online ("Você está online") e posicionado na partida; passageiro posicionado na origem | seletores de mapa ocioso | — |
| E02 | Solicitar | passageiro: campo "Para onde você quer ir?" → texto fixo → escolhe 1º resultado; toque "Solicitar corrida" (t) | passageiro mostra "Aguardando orçamentos…" | 20001 |
| E03 | Motorista recebe | — | motorista mostra modal "Solicitação de corrida" | (20001 já visto) |
| E04 | Orçamento | motorista: toque "Enviar orçamento" (t) | passageiro mostra "Orçamentos recebidos" com "Aceitar" | 20002 |
| E05 | Seleção | passageiro: toque "Aceitar" (t) | motorista mostra modal com "Iniciar corrida" | 20003 |
| E06 | Início | motorista: toque "Iniciar corrida" | passageiro mostra "Motorista a caminho" | 20005 (e 20011) observados |
| E07 | Chegada | `geo fix` do motorista na origem (t) | passageiro mostra "Motorista chegou" | 20007 |
| E08 | Encontro | passageiro: toque "Confirmo que encontrei o motorista" (t) | motorista mostra "CORRIDA EM ANDAMENTO" | 20008 |
| E09 | Destino | `geo fix` do motorista no destino (t) | passageiro mostra "Confirmar chegada ao destino" | 20009 |
| E10 | Confirmar destino | passageiro: toque "Confirmar chegada ao destino" (t) | motorista mostra "Avalie a corrida" | 20010 |
| E11 | Avaliações | motorista: escolhe nota, toque "Confirmar" (t); passageiro: idem (t) | ambos de volta ao mapa ocioso | 20014 ×2 |
| E12 | Recibos | — | 20014 observado nos dois sentidos (emissão constatada) | 20014, 20015 (contado) |
| R | Volta ao estado inicial | `geo fix` do motorista na partida; garantir online; passageiro em mapa ocioso | seletores de E01 | — |

Capturas fixas (nos primeiros ciclos do período, cada tela na primeira vez em que é atingida, FR-027): após E02 "solicitação enviada"; após E04
"orçamento recebido"; após E06 "motorista a caminho"; após E08 "corrida em andamento"; após E10
"corrida encerrada"; após E11 "avaliação concluída" — sempre dos dois emuladores.

Recuperação após falha no meio da corrida: botão de cancelar do app (`botao-cancelar-corrida` no
motorista; "Cancelar corrida" no passageiro) para destravar o estado, sem `pm clear` (que
perderia o histórico de reputação). É apoio de limpeza, não variante testada (D8).

## Timeouts e orçamentos (valores iniciais, D7)

| Limite | Valor | Observação |
|--------|-------|------------|
| Elemento de UI local aparece | 15 s | transição de tela |
| Resultado da busca Photon | 30 s | |
| Efeito remoto visível no outro app (entrega via relay) | 45 s | E03–E06, E08, E10 |
| Cálculo de rota/distância | 45 s | |
| Efeito de posicionamento (geo fix → evento/tela) | 30 s | inclui 5 s de intervalo do app |
| Etapa (teto geral) | 60 s | prevalece sobre os anteriores se menor |
| Volta ao estado inicial (R) | 60 s | |
| Ciclo | 5 min | soma das etapas E01–E12; a volta ao estado inicial (R) tem limite próprio |
| Período | 3 h de **tempo ativo acumulado** | retomada continua o saldo |
| Tetos de ciclos | 40 no período 1; 80 − executados do 1 no período 2 | FR-013 |

São limites escolhidos, não resultados de medição. O ensaio (quickstart 2) mede as durações reais
de cada etapa e, se um limite precisar mudar, a mudança e o motivo vão para `desvios.md` e para a
seção de limitações (FR-040).

## Complexity Tracking

Sem violações da constituição a justificar.
