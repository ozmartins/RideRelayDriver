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
dart run tool/e2e/e2e.dart --ensaio --meta-validos 2
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

## 7. Execução real e relatório

```bash
dart run tool/e2e/e2e.dart --executar        # execução única (60 válidos, até 12 h)
# se interromper: dart run tool/e2e/e2e.dart --retomar
dart run tool/e2e/e2e.dart --relatorio
```

Esperado: a execução termina com 60 válidos em ≤ 12 h ou relatório parcial explícito;
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
| 7. Execução real | **NÃO EXECUTADO** (T045 é a avaliação em si). |

Pendências antes da execução real: executar os cenários 2 a 5 com os emuladores, corrigir
`telas.dart`/`preparo.dart` conforme o que o ensaio mostrar, e registrar cada ajuste em `desvios.md`.

### Tentativa do ensaio com os emuladores (2026-11-01, sem sucesso)

Os dois AVDs subiram (headless) e os apps (APKs de depuração do dia) foram instalados. O fluxo foi
percorrido **à mão** pelo `uiautomator` até o fim da etapa E08 e depois o roteiro foi corrigido com o
que se viu (campos de texto sem rótulo no dump, alternador `Switch` para ficar online, `ENTER` em vez de
`BACK` para fechar o teclado, aba `Mais\nTab 2 of 2`, mapa do motorista com `Ponto de embarque` →
`Destino da corrida`, forma de pagamento `PIX` obrigatória, botão de destino do passageiro dependente da
**posição do próprio passageiro**, aviso `Motorista a caminho` que reaparece, coordenada do destino conferida
no Photon). O roteiro **não chegou a completar um ciclo**: o `earlyoom` do hospedeiro envia SIGTERM a um
dos emuladores (cerca de 3 GB cada, com o Android Studio aberto) sempre que a memória disponível cai
abaixo de 10%, e isso derrubou o preparo em todas as tentativas. Etapas E09 a E12 (destino, avaliação e
recibos) **não foram observadas** nos apps reais.

Resposta a isso (2026-11-02): entre dois ciclos o roteiro desliga os dois emuladores
(`adb shell reboot -p`), espera `MemAvailable` voltar a 3 GiB e os sobe de novo a frio
(`-no-snapshot`, sem `-wipe-data`). O reinício fica fora do tempo e da janela de eventos do ciclo, conta
no orçamento de 12 h e é registrado em `desvios.md`. `--sem-reinicio-entre-ciclos` o desliga. Quanto
isso custa por ciclo e se basta para chegar aos 60 válidos **ainda não foi medido**: depende do ensaio.

## Duas máquinas (um emulador em cada)

Contrato: `contracts/coordenacao.md`. As duas máquinas precisam do repositório do motorista
(é onde está o roteiro) e do `adb`/Android Studio; a do passageiro também precisa de
`../RideRelayPassenger` ao lado, para compilar o app. No Windows, `adb` no `PATH` e
`ANDROID_HOME` (ou o SDK padrão do Android Studio) para o `emulator`.

1. Libere a porta 8765 (TCP, entrada) no firewall da máquina do **passageiro** e descubra o IP dela.
2. Passageiro (coordenador; inicie primeiro ou depois, o motorista tenta por até 10 min):
   `dart run tool/e2e/e2e.dart --executar --papel passageiro --token SEGREDO`
3. Motorista:
   `dart run tool/e2e/e2e.dart --executar --papel motorista --coordenador IP:8765 --token SEGREDO`

Cada máquina grava a sua própria saída (`e2e_saida/execucao/`); `--retomar`, `--ensaio`
e `--saida` valem em cada uma. Se o AVD tiver outro nome, use `--avd-motorista` /
`--avd-passageiro`. O reinício do emulador entre ciclos fica desligado (use
`--reinicio-entre-ciclos` para ligá-lo). Só viajam entre as máquinas as chaves públicas, a
versão do código e metadados do ciclo.

Se um lado falha no meio de um ciclo, o outro para de esperar em até 2 s (e não no prazo da
etapa) e a falha dele é tratada como reflexo; a causa vale no resultado do ciclo.

Relatório único: copie a pasta `e2e_saida/execucao` da outra máquina para esta (por exemplo
`outra/execucao`) e rode `dart run tool/e2e/e2e.dart --relatorio --juntar outra/execucao`.
A latência e as contagens por relay são calculadas por máquina, cada uma no seu relógio, e só
então somadas; os ciclos precisam ter o mesmo desfecho nas duas, senão a junção é recusada.
