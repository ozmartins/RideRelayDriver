# Contrato: linha de comando do roteiro

Ponto de entrada: `dart run tool/e2e/e2e.dart <comando> [opções]`. Sem comando é erro de uso (a execução apaga dados dos apps, então exige `--executar`, `--retomar` ou `--ensaio`) (a partir da raiz do repositório
do motorista). Códigos de saída: `0` ok; `1` execução parcial ou falha de verificação; `2` uso
incorreto/pré-condição não atendida (nada foi executado nem apagado).

| Comando | Efeito |
|---------|--------|
| `--executar` | Executa a avaliação completa: pré-condições, `pm clear`, cadastros, leitura das chaves públicas, observador, ciclos até 60 válidos, teto ou orçamento; ao fim gera o relatório parcial/completo e roda a varredura. Recusa se já houver `e2e_saida/execucao/` (para continuar use `--retomar`). |
| `--retomar` | Continua a execução a partir do checkpoint, sem `pm clear` nem novo cadastro; confere as chaves públicas dos apps com as do checkpoint. |
| `--relatorio` | Lê a execução existente em `e2e_saida/execucao/` e gera `relatorio.md` e os CSV; marca como parcial o que for parcial. |
| `--verificar-saida` | Roda só a varredura de padrões proibidos em `e2e_saida/`; saída 1 se achar algum. |

Opções:

| Opção | Efeito |
|-------|--------|
| `--ensaio` | Grava em `e2e_saida/ensaio-<data>/`, com rótulo "ENSAIO — não vale para o TCC"; não conta para o teto de 80. |
| `--meta-validos N` | Só com `--ensaio`: meta menor que 60. Sem `--ensaio` é recusada. |
| `--orcamento-min N` | Só com `--ensaio`: orçamento menor que 12 h, para testar o relatório parcial. Sem `--ensaio` é recusada. |
| `--avd-motorista`, `--avd-passageiro` | Nome dos AVDs (padrão `Pixel_6_API34_1` e `Pixel_6_API34_2`); os seriais são descobertos por `adb devices` + `emu avd name`. |
| `--saida DIR` | Pasta de saída (padrão `e2e_saida`); deve estar ignorada pelo Git ou fora do repositório, senão recusa. |

Pré-condições checadas antes de qualquer `pm clear` (falha ⇒ saída 2, nada apagado):

1. Dois emuladores online, AVDs com os nomes esperados, API 34, x86_64.
2. Pacotes `br.ufsc.tcc.corridas.driver` e `br.ufsc.tcc.corridas.passenger` instalados.
3. Os dois repositórios acessíveis para registrar o commit (`../RideRelayPassenger`).
4. Saída em local ignorado pelo Git.
5. Internet: pelo menos um relay da lista alcançável pelo hospedeiro (a lista de três nunca é reduzida).
6. Chave do openrouteservice em `ORS_API_KEY` ou em `assets/ors_api_key.txt`, usada **só** para a
   varredura (D11); o valor nunca é impresso. Se ausente é **aviso**, não recusa: a varredura segue
   sem o padrão da chave e os metadados registram "padrão da chave ORS não verificado". A opção
   `--exigir-chave-ors` transforma o aviso em recusa (saída 2).
7. Retomada: `--retomar` recusa se não houver `checkpoint.json` legível; ao retomar em outro dia
   local, o roteiro registra a retomada em `desvios.md` (FR-012, FR-040).

Registro em tela/log: etapa, resultado, duração; nunca chaves, `content` nem a chave da ORS.
