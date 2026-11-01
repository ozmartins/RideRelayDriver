---

description: "Tarefas da feature 029 — teste E2E automatizado do fluxo completo da corrida"
---

# Tasks: Teste E2E automatizado do fluxo completo da corrida (caminho feliz)

**Input**: `specs/029-teste-e2e-fluxo-corrida/` (plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md)

**Prerequisites**: plan.md, spec.md

**Tests**: obrigatórios para a lógica pura (spec FR-033, constituição Princípio II: o observador descarta evento de assinatura inválida). A execução contra emuladores é validada pelo quickstart, não por `flutter test`.

**Convenções**: código em `tool/e2e/` e `tool/e2e/src/`; testes em `test/tool/e2e/` (importam por caminho relativo `../../../tool/e2e/src/...`); dublês em `test/tool/e2e/support/`. Textos, comentários e commits em português do BR (CLAUDE.md). Nenhuma dependência nova no `pubspec.yaml`.

**Ordem das histórias**: todas as histórias do spec são P1/P2, mas a ordem de implementação segue a dependência: observador (US3) → ciclo (US1) → orçamento/retomada (US2) → vazamento (US5) → relatório (US4).

## Format: `[ID] [P?] [Story] Description`

## Phase 1: Setup

- [X] T001 Acrescenta `/e2e_saida/` ao `.gitignore` do repositório, na seção de segredos/configuração local
- [X] T002 [P] Cria os diretórios `tool/e2e/src/`, `test/tool/e2e/` e `test/tool/e2e/support/` (com um arquivo `.gitkeep` só se ficarem vazios no commit)
- [X] T003 Cria `tool/e2e/e2e.dart` mínimo que importa `package:driver/services/relay_protocol.dart` e imprime a ajuda; confirma que `dart run tool/e2e/e2e.dart --ajuda` funciona (D1 do research: o importe sem Flutter) e registra o resultado em `specs/029-teste-e2e-fluxo-corrida/research.md` na decisão D1

---

## Phase 2: Foundational (bloqueia todas as histórias)

- [X] T004 Cria `tool/e2e/src/config.dart` com: lista dos 3 relays (derivada de `lib/services/default_relays.dart`, com asserção de que são exatamente `wss://nos.lol`, `wss://relay.primal.net`, `wss://offchain.pub`), pacotes dos apps, nomes dos AVDs, coordenadas fixas (partida, origem/encontro, destino — D14), texto fixo de busca do destino (ASCII), tabela de timeouts do `plan.md`, tetos (40 / 80 − executados) e orçamento de 3 h
- [X] T005 [P] Cria `tool/e2e/src/adb.dart`: interface `Adb` (`executar`, `tocar`, `texto`, `tecla`, `dump`, `captura`, `geoFix(lon, lat)`, `pmClear`, `pmGrant`, `logcat(desde)`, `avdName`, `dispositivos`, `processoVivo`) e `AdbProcesso` sobre `Process.run` com timeout por comando; `geoFix` recebe longitude antes de latitude
- [X] T006 [P] Cria `test/tool/e2e/support/fake_adb.dart` — dublê de `Adb` com telas roteirizadas (sequência de dumps XML) e registro das chamadas
- [X] T007 [P] Cria `tool/e2e/src/ui.dart`: parse do XML do `uiautomator dump` (nós com `text`, `content-desc`, `bounds`, `clickable`), seletores por texto/`content-desc`/"N-ésimo clicável dentro do contêiner que contém X" (D3), `esperar(condicao, timeout)` por condição com intervalo curto de leitura e `tocarEm(seletor)` pelo centro dos bounds
- [X] T008 [P] Teste `test/tool/e2e/ui_test.dart`: parse de dump de exemplo, seletor por texto, seletor estrutural das estrelas, `esperar` que acha antes do prazo e que estoura (retorna falha, sem lançar), usando `fake_adb.dart` e relógio injetável
- [X] T009 Cria `tool/e2e/src/telas.dart`: catálogo de rótulos dos dois apps usados em cada etapa (`Você está online`, `Para onde você quer ir?`, `Solicitar corrida`, `Aguardando orçamentos…`, `Solicitação de corrida`, `Enviar orçamento`, `Orçamentos recebidos`, `Aceitar`, `Iniciar corrida`, `Motorista a caminho`, `Motorista chegou`, `Confirmo que encontrei o motorista`, `CORRIDA EM ANDAMENTO`, `Confirmar chegada ao destino`, `Avalie a corrida`, `Confirmar`) e a lista de marcadores de **telas sensíveis** (cadastro, relays, "Minha identidade"/"Chave pública", backup, chave privada)
- [X] T010 Cria `tool/e2e/src/evidencia.dart`: `Evidencia.permitida(dumpXml)` (falso se tela sensível, D10), `capturar(adb, rotulo, ...)` que grava PNG + dump só se permitida e devolve o caminho relativo, ou registra "captura omitida: tela sensível"
- [X] T011 [P] Teste `test/tool/e2e/evidencia_test.dart`: dump de mapa comum → grava; dump de "Minha identidade", de cadastro e de relays → não grava e devolve o motivo
- [X] T012 Cria `tool/e2e/src/checkpoint.dart`: modelos `Periodo`, `Ciclo`, `Etapa` (data-model.md) com `toJson/fromJson`, `ciclos.jsonl` só-acréscimo, `checkpoint.json` com escrita atômica (arquivo temporário + rename), cálculo dos tetos (período 1 = 40; período 2 = 80 − executados do 1) e do orçamento por tempo ativo acumulado
- [X] T013 [P] Teste `test/tool/e2e/checkpoint_test.dart`: ida e volta JSON; escrita atômica não deixa arquivo parcial; contadores recalculados de `ciclos.jsonl` iguais aos do checkpoint; tetos 40 / 80 − N; ciclo `externo` e `interrompido` não contam como válidos

**Checkpoint**: base pronta — histórias podem começar.

---

## Phase 3: User Story 3 — Observador independente (Priority: P1)

**Goal**: registrar relay, kind, id, `created_at` e instante local de cada evento das identidades do período, sem `content`, conectado antes de cada ciclo.

**Independent Test**: com `fake_relay_transport`, eventos válidos são registrados (sem `content`), evento adulterado é descartado e contado, e a inscrição só tem os filtros do período.

- [X] T014 [P] [US3] Teste `test/tool/e2e/observador_test.dart` (usa `test/support/fake_relay_transport.dart` e `signed_payload.dart`): (a) evento válido de uma das identidades → uma linha por relay com kind/id/created_at/instante, **sem campo `content`**; (b) assinatura adulterada → descartado e contado em `invalidos_por_relay`; (c) evento de autor/`p` fora das identidades → não gravado; (d) o mesmo evento em 3 relays → 3 linhas; (e) o `REQ` enviado tem os dois filtros (`authors` e `#p`) com kinds 20001–20015, `#t` e `since` = agora − 10 min; (f) o observador nunca envia `EVENT`
- [X] T015 [US3] Cria `tool/e2e/src/observador.dart`: `Observador` sobre `RelayTransport` (`WsRelayTransport` em produção), `EventoObservado` (sem `content`), verificação com `NostrEventVerifier`, filtros de D4, relógio monotônico + UTC, `prontoParaCiclo()` (inscrito em cada relay, via `EOSE`/conexão aberta — FR-023), associação a ciclo por janela e papel, gravação em `eventos.jsonl`; associa evento a ciclo por `recebido_utc` (relógio do hospedeiro), nunca por `created_at` (F1)
- [X] T016 [US3] Em `tool/e2e/src/observador.dart`, expõe consultas usadas pelo ciclo: `primeiroEvento(kind, autor, apos)` (menor instante entre relays), `vistoEmAlgumRelay(...)`, `todosRelaysCaidos()`, contagem por relay e por kind; cobre-as em `test/tool/e2e/observador_test.dart`

**Checkpoint**: observador testável sem rede.

---

## Phase 4: User Story 1 — Executar um período completo de ciclos (Priority: P1) 🎯 MVP

**Goal**: um comando prepara os emuladores, faz o fluxo da corrida repetidamente e registra cada ciclo, com classificação da origem das falhas.

**Independent Test**: quickstart cenário 2 (ensaio de 2 ciclos) — cada ciclo termina com resultado por etapa, 6 telas × 2 emuladores no ciclo 1, eventos esperados no `eventos.jsonl`.

- [X] T017 [P] [US1] Teste `test/tool/e2e/classificacao_test.dart`: um caso por regra e por precedência de D9 — ambiente (adb offline; observador sem nenhum relay), serviço externo (sinal de UI Photon; sinal de logcat de rota → OpenRouteService, com e sem HTTP 429; sem sinal nunca é externo), relays (evento visto em ≥1 relay e app não avançou), aplicativo (elemento ausente; processo ausente) e `origem_bruta = indeterminada` (ação feita, evento em nenhum relay, observador conectado, `origem = aplicativo`); dúvida entre regras resolve-se pela de menor número
- [X] T018 [US1] Cria `tool/e2e/src/classificacao.dart`: função pura `classificar(Evidencias) → {origem, servicoExterno?, origemBruta, sinalExterno?}` conforme D9/FR-026/FR-021a; do `logcat` só sai a classificação, nunca a linha
- [X] T019 [P] [US1] Teste `test/tool/e2e/preparo_test.dart` (com `fake_adb`): `pm clear` dos dois pacotes, `pm grant` de localização e notificações, rejeição se a lista de relays lida na tela de relays tiver ≠ 3 URLs ou URLs diferentes (FR-007), leitura das chaves públicas (hex de 64) da tela de identidade **sem** chamar `captura` nem gravar o dump, recusa se os AVDs/API/ABI não forem os esperados
- [X] T020 [US1] Cria `tool/e2e/src/preparo.dart`: pré-condições do `contracts/cli.md` (itens 1–7), descoberta de seriais por `adb devices` + `emu avd name`, `pm clear` + `pm grant`, cadastro do passageiro (nome ASCII) e do motorista (campos de `cadastro_screen.dart` com valores ASCII fixos; raio padrão 10 km), leitura das chaves **públicas** nas telas "Minha identidade" (em memória), conferência dos 3 relays na tela de relays, leitura da deriva de relógio dos emuladores (`adb shell date +%s`) gravada em `ambiente.deriva_relogio_s`, `geo fix` inicial nos dois emuladores antes de abrir os apps, aviso se a data de início for a do período 1 (`--exigir-chave-ors` e chave ORS ausente tratados como aviso/recusa conforme `contracts/cli.md`), commits dos dois repositórios (`git rev-parse HEAD`, `git status --porcelain`), sem salvar dump nem captura em nenhum desses passos
- [X] T021 [P] [US1] Teste `test/tool/e2e/ciclo_test.dart` (com `fake_adb`, observador falso e relógio injetável): ciclo feliz completo E01–E12 e R → `resultado = sucesso`, `acao_inicio_utc`/`acao_utc`/`acao_tipo` preenchidos nas etapas de ação; etapa que estoura o prazo → `timeout`, ciclo `falha` e próximo ciclo começa; 6 capturas × 2 feitas na primeira vez em que cada tela é atingida (ciclo 1 falha na E06 → as telas seguintes são capturadas no ciclo 2, sem repetir as já feitas); captura + dump dos dois na falha (respeitando telas sensíveis); falha externa → `valido = false` e reposição com número novo; falha de outra origem → `valido = true`; cancelamento de recuperação (D8) fica em janela `recuperacao`
- [X] T022 [US1] Cria `tool/e2e/src/ciclo.dart`: as etapas E01–E12 e R do `plan.md` (tabela "Fluxo do ciclo") com `esperar` por condição e o limite de cada etapa e do ciclo (5 min), `geoFix` na origem e no destino, escolha da nota na avaliação por seletor estrutural, registro dos instantes das ações, confirmação do observador antes de iniciar (FR-023), classificação via `classificar`, capturas fixas na primeira vez em que cada tela é atingida (conjunto já capturado guardado em `checkpoint.json`), recuperação por cancelamento do app (D8) e volta ao estado inicial sem `pm clear`
- [X] T023 [US1] Em `tool/e2e/e2e.dart`, implementa `--periodo N` (+ `--ensaio`, `--meta-validos`, `--avd-*`, `--saida`) conforme `contracts/cli.md`: pré-condições → preparo → observador → laço de ciclos até a meta ou até o teto → checkpoint a cada ciclo → saída 0/1/2; recusa `--periodo` se a pasta do período já existir
- [X] T024 [US1] Cria `specs/029-teste-e2e-fluxo-corrida/desvios.md` como modelo vazio (cabeçalho e tabela) e faz o roteiro copiá-lo para `e2e_saida/<periodo>/desvios.md`, registrando ali ajustes de timeout, rótulo de tela diferente e conferência do destino (D14)

**Checkpoint**: ensaio de 2 ciclos roda de ponta a ponta (quickstart 2).

---

## Phase 5: User Story 2 — Término limitado e retomada (Priority: P1)

**Goal**: nada passa de 3 h por período; interrupção não perde ciclos; cota da OpenRouteService esgotada para o período de forma controlada.

**Independent Test**: quickstart 3 (orçamento artificial → relatório parcial) e 4 (interrupção + `--retomar`).

- [X] T025 [P] [US2] Teste `test/tool/e2e/orcamento_retomada_test.dart`: orçamento acumulado ao retomar (tempo ativo somado entre execuções); estouro do orçamento no meio de um ciclo → ciclo `interrompido`, período `parcial` com motivo `orcamento`; `--retomar` não refaz ciclos registrados e não duplica linhas; chaves públicas divergentes → recusa; checkpoint ausente/corrompido → recusa sem apagar nada; teto de ciclos atingido sem a meta → `parcial` com motivo `teto_executados`; sinal de cota diária da ORS → `parcial` com motivo `limite_diario_ors`
- [X] T026 [US2] Em `tool/e2e/src/checkpoint.dart` e `tool/e2e/e2e.dart`, implementa os estados `em_andamento/concluido/parcial` e os motivos de parada (o orçamento por tempo ativo já vem de T012), `--retomar` (confere chaves públicas na tela com as do checkpoint, refaz o ciclo interrompido desde o início e o marca `interrompido`), tratamento de SIGINT que grava o checkpoint antes de sair, e geração do relatório parcial do período ao parar
- [X] T027 [US2] Em `tool/e2e/src/ciclo.dart` e `classificacao.dart`, detecta sinal de limite da ORS (HTTP 429 quando o texto do app o trouxer; senão falha da chamada de rota), classifica como `servico_externo/OpenRouteService` e sinaliza o fim controlado do período quando o limite diário esgota (FR-021); cobre em `test/tool/e2e/classificacao_test.dart`
- [X] T028 [US2] Em `tool/e2e/e2e.dart`, implementa as opções de ensaio `--orcamento-min N` e `--teto-periodo-1-executados N` (`contracts/cli.md`), com recusa fora de `--ensaio`/fora do período 2

---

## Phase 6: User Story 5 — Evidências sem vazamento (Priority: P1)

**Goal**: nenhuma chave privada, `content` ou chave de API em arquivo gerado; verificação automática que falha se achar.

**Independent Test**: quickstart 6 (plantar padrões proibidos → saída 1; saída legítima → 0).

- [X] T029 [P] [US5] Teste `test/tool/e2e/varredura_saida_test.dart`: reprova `nsec1`+58 caracteres válidos, hex de 64 que não é id observado nem chave pública do período, hex de 128, `"content"` como chave JSON e a chave da ORS como substring; aprova id observado, chave pública do período e a palavra `content-desc` em dump XML; relatório do achado traz arquivo e padrão, **nunca** o valor encontrado
- [X] T030 [US5] Cria `tool/e2e/src/varredura_saida.dart` (D11): varre todos os arquivos de texto de `e2e_saida/`, lista de permitidos montada de `eventos.jsonl` e `checkpoint.json`, chave da ORS lida de `ORS_API_KEY` ou `assets/ors_api_key.txt` sem imprimir (ausente = aviso e "padrão da chave ORS não verificado" nos metadados, salvo `--exigir-chave-ors`); devolve achados mascarados
- [X] T031 [US5] Em `tool/e2e/e2e.dart`, liga a varredura: comando `--verificar-saida` (saída 1 se achar), execução automática ao fim de cada período e ao gerar o relatório (relatório não é dado como íntegro se falhar)
- [X] T032 [P] [US5] Teste `test/tool/e2e/log_sem_segredo_test.dart`: o log do roteiro (`execucao.log`) e as mensagens de erro não incluem o texto de `content`, chaves nem linhas brutas de `logcat`, usando entradas que contêm esses valores

---

## Phase 7: User Story 4 — Relatório do TCC (Priority: P2)

**Goal**: `--relatorio` gera `relatorio.md` e CSV combinando os períodos, com exatamente os critérios do spec.

**Independent Test**: relatório sobre ciclos sintéticos de resultado conhecido confere cada número e cada seção.

- [X] T033 [P] [US4] Cria `tool/e2e/gen_clopper_pearson_vectors.py`: gera `test/fixtures/e2e_clopper_pearson_vectors.json` com `scipy.stats.beta.ppf` (n de 1 a 80, x de 0 a n, confiança 95% bilateral), registrando versão do scipy e comando; falha com mensagem clara se scipy não existir; roda o gerador e confere o fixture (D5)
- [X] T034 [P] [US4] Teste `test/tool/e2e/estatistica_test.dart`: 0 falhas em 60 → limite superior = 1 − 0,025^(1/60) ≈ 5,96% (tolerância 1e-9) e inferior 0; x = n; todos os valores do fixture do scipy (tolerância 1e-9); posto mais próximo: ⌈p·N⌉ com N par/ímpar, lista de 1 elemento, lista vazia → sem valor (não zero); mediana = P50 por posto mais próximo
- [X] T035 [US4] Cria `tool/e2e/src/estatistica.dart`: beta incompleta regularizada (Lentz) + bisecção, `clopperPearson(x, n, confianca)`, intervalo de sucesso como complemento do de falha, `postoMaisProximo(valores, p)`
- [X] T036 [P] [US4] Teste `test/tool/e2e/latencia_test.dart`: tabela ação→evento de FR-028 (9 linhas, 20014 em dois sentidos), menor instante entre relays, sem evento → sem amostra, latência negativa descartada com desvio, categoria `toque` vs `posicionamento`
- [X] T037 [US4] Cria `tool/e2e/src/latencia.dart`: tabela ação→evento do `spec.md` (FR-028) e cálculo por tipo, por período e total, mediana e P95, com as linhas "geral (todas)", "geral (toque)" e "geral (posicionamento)"
- [X] T038 [P] [US4] Teste `test/tool/e2e/relatorio_test.dart` (golden com ciclos sintéticos): veredito **único, sobre o total**: 0 falhas → ATENDIDO, 1 e 3 → PARCIALMENTE ATENDIDO, 4 → NÃO ATENDIDO, aplicado às falhas **sem** as externas e n = válidos; por período só contagens e taxa, sem rótulo; período único → "não aplicável (período único)"; telas fixas não atingidas listadas na seção 8; taxa de falha total separada e rotulada "informativo"; IC por período e total; contagem por origem com sublista `indeterminada` dentro de aplicativo; seção 7 por relay; seção 8 com ciclos repostos/interrompidos/parcial; as 8 seções na ordem; ausência de `content` e de critério de aceitação de latência; período ausente declarado
- [X] T039 [US4] Cria `tool/e2e/src/relatorio.dart`: gera `relatorio.md` (seções 1–8 de `contracts/saidas.md`) e `dados/ciclos.csv`, `latencias.csv`, `falhas.csv`, `relays.csv`; metadados com commits, AVDs, relays, timeouts rotulados "limites escolhidos, não medidos", tempo ativo e indicação de parcial
- [X] T040 [US4] Em `tool/e2e/e2e.dart`, implementa `--relatorio` (lê todos os períodos presentes, roda a varredura, grava o relatório) e a chamada do relatório parcial ao fim de `--periodo`

---

## Phase 8: Polish & Cross-Cutting

- [X] T041 Roda `dart format tool test` e `flutter analyze` e corrige os apontamentos; confirma que `flutter test` passa inteiro, sem teste ignorado
- [ ] T042 Executa no quickstart os cenários 2 a 6 com os emuladores reais, anotando em `e2e_saida/<ensaio>/desvios.md` as durações reais das etapas, ajustes de timeout e o resultado de cada cenário (inclusive os que falharem — gate 3 da constituição); se um limite mudar, atualiza a tabela de `plan.md` e `config.dart` e registra o motivo
- [X] T043 Executa a verificação de não vazamento (Princípio I) sobre a saída do ensaio e registra o resultado em `specs/029-teste-e2e-fluxo-corrida/quickstart.md` (seção de resultados)
- [X] T044 Em commit separado do código, atualiza o `CLAUDE.md` descrevendo `tool/e2e/` (comandos `--periodo`, `--retomar`, `--relatorio`, `--verificar-saida`), a pasta `e2e_saida/` e a correção do caminho do repositório do passageiro (`../RideRelayPassenger`)

- [ ] T045 [manual] Executa `--periodo 1` com os emuladores reais, após T041–T043 verdes; confere que termina em ≤ 3 h ou com relatório parcial explícito (SC-002)
- [ ] T046 [manual] Em outro dia, executa `--periodo 2` e depois `--relatorio`; confere SC-001, SC-006 e SC-008 e roda `--verificar-saida`

---

## Dependencies & Execution Order

- Phase 1 → Phase 2 → histórias → Polish. Phase 2 bloqueia todas.
- US3 (observador) antes de US1: o ciclo exige o observador pronto (FR-023) e consulta `primeiroEvento`/`vistoEmAlgumRelay`.
- US1 antes de US2 (retomada/orçamento operam sobre o laço de ciclos) e antes de US4 (relatório lê os registros dos ciclos; os testes de US4 usam dados sintéticos e podem andar em paralelo com US1/US2).
- US5: a varredura (T029–T030) é independente e pode andar em paralelo com US1; a ligação ao comando (T031) vem depois de T023.
- Dentro de cada história: teste primeiro (falhando), depois implementação.

## Parallel Opportunities

- Phase 2: T005, T006, T007, T008, T011, T013 (arquivos distintos) após T004.
- US3: T014 em paralelo com a leitura de `fake_relay_transport.dart`; US5 (T029, T032) e US4 (T033, T034, T036, T038) têm testes e geradores sem dependência do ciclo.
- Exemplo, depois de T013: T014 (observador) ‖ T029 (varredura) ‖ T033 (gerador scipy) ‖ T034 (estatística).

## Implementation Strategy

- **MVP**: Phase 1 + 2 + US3 + US1 — um período rodando ciclos reais com observador e classificação (ensaio de 2 ciclos). Parar e validar no quickstart 2 antes de seguir.
- **Incremental**: US2 (segurança de tempo e retomada, obrigatório antes de qualquer período real), US5 (varredura), US4 (relatório). Nenhum período real (`--periodo 1` sem `--ensaio`) deve ser executado antes de US2 e US5 estarem prontas.
- Cada alteração de seletor, limite ou desvio durante a execução é registrada em `desvios.md` (FR-040).

## Notes

- Total: 46 tarefas (T045–T046 são a execução real da avaliação, manuais). Commits: um por mudança lógica, em português, com o trailer `Co-Authored-By` (CLAUDE.md); a atualização do `CLAUDE.md` (T044) em commit à parte.
