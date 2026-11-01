# Quickstart: validação da feature 029

Pré-requisitos: os dois AVDs (`Pixel_6_API34_1` e `_2`) iniciados e com os apps instalados
(versão a avaliar, com a chave do openrouteservice embutida); Wi-Fi com Internet; `adb` no PATH;
`flutter pub get` feito. Comandos a partir da raiz do repositório do motorista. Os cenários que
falharem devem ser **relatados**, não omitidos (constituição, gate 3).

## 1. Gates de código (sem emulador)

```bash
dart format tool test
flutter analyze            # sem apontamentos
flutter test test/tool/e2e # estatística, relatório, classificação, checkpoint, varredura, observador
flutter test               # suíte inteira
```

Esperado: tudo verde; o teste do Clopper-Pearson reproduz 0/60 → limite superior ≈ 5,96% e os
valores do fixture do scipy (`test/fixtures/e2e_clopper_pearson_vectors.json`).

## 2. Ensaio com 2 ciclos (valida seletores, timeouts e coordenadas)

```bash
dart run tool/e2e/e2e.dart --periodo 1 --ensaio --meta-validos 2
```

Esperado: pasta `e2e_saida/ensaio-*/` com 2 ciclos, 6 telas × 2 emuladores (no ciclo 1, se ele chegar a todas) `eventos.jsonl`
com os kinds 20001, 20002, 20003, 20005, 20007, 20008, 20009, 20010, 20011, 20014 (e 20015).
Anotar em `desvios.md`: duração real de cada etapa, qualquer ajuste de limite, e se o ponto de
destino do `geo fix` ficou a ≤ 1 km do ponto devolvido pelo Photon. Os rótulos de tela da tabela
de etapas são confirmados aqui; rótulo diferente atualiza `telas.dart` e é registrado.

## 3. Orçamento e relatório parcial

Executar um ensaio com orçamento artificial (`--ensaio --orcamento-min 3`, opção só de ensaio) e
verificar: o roteiro para, grava, gera relatório marcado **PARCIAL** com o motivo `orcamento`.

## 4. Retomada

Iniciar um ensaio de 4 ciclos, interromper com Ctrl+C no meio do ciclo 2, rodar de novo com
`--retomar`. Esperado: o ciclo 1 não é refeito, o 2 é refeito desde o início e registrado como
`interrompido` no anterior, contadores consistentes, nenhum ciclo duplicado em `ciclos.jsonl`.

## 5. Falha externa e reposição (controlado)

Com o Wi-Fi do hospedeiro ligado, derrubar apenas o acesso do emulador do passageiro à Internet
durante a busca de endereço (`adb shell svc wifi disable` / `data disable` no emulador) num
ensaio. Esperado: ciclo classificado `servico_externo` (Photon) só se o app mostrar o sinal de
FR-021a; ciclo não contado como válido; novo ciclo de reposição; total ≤ teto. Se o app não
mostrar sinal, a classificação esperada é `aplicativo` — registrar o que ocorreu.

## 6. Vazamento (Princípio I, FR-029)

```bash
dart run tool/e2e/e2e.dart --verificar-saida          # saída 0 numa saída legítima
echo '"content":"x"' > e2e_saida/ensaio-teste.txt       # plantar proibido
dart run tool/e2e/e2e.dart --verificar-saida          # saída 1, indicando o arquivo
rm e2e_saida/ensaio-teste.txt
```

Repetir plantando `nsec1` + 58 caracteres válidos, um hex de 64 desconhecido e a chave da ORS.
Conferir também, manualmente, que nenhuma captura de `capturas/` mostra cadastro, relays,
identidade ou chave.

## 7. Período real e relatório

```bash
dart run tool/e2e/e2e.dart --periodo 1       # dia 1
dart run tool/e2e/e2e.dart --periodo 2       # outro dia
dart run tool/e2e/e2e.dart --relatorio
```

Esperado: cada período termina com 30 válidos em ≤ 3 h ou relatório parcial explícito;
`relatorio.md` com as 8 seções, critério conforme FR-031 e valores iguais aos CSV.

## Resultados da validação (registrados em 2026-11-01)

| Cenário | Resultado |
|---------|-----------|
| 1. Gates de código | `dart format tool test`, `flutter analyze` (sem apontamentos) e `flutter test` (1141 testes, todos passaram) executados. `test/tool/e2e` tem 132 testes. |
| 2. Ensaio com 2 ciclos | **NÃO EXECUTADO.** Nenhum emulador estava em execução e os apps não foram instalados nesta sessão. Os rótulos de tela, o cadastro automatizado, a navegação "Mais", a escolha do resultado do Photon e as coordenadas do destino foram escritos a partir do código dos apps e **não** foram conferidos rodando. O fluxo do ciclo foi exercitado contra um simulador dos dois apps (`test/tool/e2e/support/simulador_corrida.dart`), que valida a lógica do roteiro, não os apps reais. |
| 3. Orçamento e relatório parcial | **Só com dublês:** `orcamento_retomada_test.dart` cobre o estouro do orçamento entre ciclos e no meio de um ciclo, e `relatorio_test.dart` cobre o relatório marcado como parcial. O comando real com `--ensaio --orcamento-min` não foi executado. |
| 4. Retomada | **Só com dublês:** `orcamento_retomada_test.dart` ("retomada: soma o tempo ativo e não refaz nem duplica ciclos"). A retomada real com Ctrl+C não foi executada. |
| 5. Falha externa e reposição | **Só com dublês:** `ciclo_test.dart` (Photon pela interface, OpenRouteService com 429 pelo logcat) e `orcamento_retomada_test.dart` (reposição). Não foi provocada queda de rede num emulador. |
| 6. Vazamento | Executado pela linha de comando sobre uma saída sintética em pasta temporária: `--relatorio` gerou o relatório e a varredura saiu com código 0; com `"content":"x"` plantado, `--verificar-saida` saiu com código 1 apontando o arquivo (sem imprimir o valor); com o arquivo limpo, voltou a 0. Os demais padrões (`nsec1…`, hex de 64 desconhecido, hex de 128, chave da ORS) estão em `varredura_saida_test.dart` e `log_sem_segredo_test.dart`. Inspeção manual das capturas: **pendente** (não houve capturas reais). |
| 7. Período real | **NÃO EXECUTADO** (T045 e T046 são a avaliação em si). |

Pendências antes de qualquer período real: executar os cenários 2 a 5 com os emuladores, corrigir
`telas.dart`/`preparo.dart` conforme o que o ensaio mostrar, e registrar cada ajuste em `desvios.md`.
