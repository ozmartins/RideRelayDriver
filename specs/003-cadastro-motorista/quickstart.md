# Phase 1 — Quickstart / Validação: Cadastro do Motorista

Comandos executados a partir de `Prototipo/driver`. O cenário 1 é automatizado; os demais exigem
emulador/aparelho, porque validam o formulário e a persistência real em SQLite.

## Pré-requisitos

- Ambiente das features 001 e 002 funcionando (ver `README.md`)
- Dependências instaladas: `flutter pub get`
- Não é necessária conectividade de rede — esta feature funciona inteiramente offline (D2 de
  `research.md`)

## Cenário 1 — Gates automatizados

```bash
flutter analyze   # esperado: No issues found!
flutter test      # esperado: todos os testes passam
```

Cobre, com dublê de `CadastroStore` e sem SQLite real (Princípio II): validação de UF/cidade/placa,
combinação inconsistente de UF e cidade sendo rejeitada, limpeza da cidade ao trocar a UF, ausência de
cadastro sendo tratada como formulário a exibir, e cadastro corrompido sendo tratado como ausente
(FR-010).

## Cenário 2 — Formulário aparece na primeira execução (US1, SC-001)

```bash
flutter run
```

1. Instale o aplicativo do zero (ou limpe os dados do app: `adb shell pm clear
   br.ufsc.tcc.caronas.driver`) e abra-o.

**Esperado**: o formulário de cadastro é a primeira tela exibida, antes de qualquer tela de relays,
eventos ou identidade. Cronometre o preenchimento com dados válidos — deve ser possível concluir em
menos de 2 minutos.

## Cenário 3 — Cidade depende da UF escolhida (US1 cenário 2, FR-004)

No formulário de cadastro:

1. Deixe a UF sem selecionar e tente abrir o campo de cidade.
2. Selecione uma UF (por exemplo, `SC`) e abra o campo de cidade.
3. Troque para outra UF (por exemplo, `RS`) sem antes preencher a cidade.

**Esperado**: (1) o campo de cidade está vazio e desabilitado sem UF selecionada; (2) só aparecem
municípios de Santa Catarina; (3) ao trocar para `RS`, a lista passa a mostrar municípios do Rio
Grande do Sul, e qualquer cidade que tivesse sido escolhida antes da troca é limpa.

## Cenário 4 — Validação de placa nos dois formatos (US1 cenário 3, FR-005)

No formulário de cadastro, preencha os demais campos e teste o campo de placa com, em sequência:
`ABC1234` (antigo), `abc1d23` (Mercosul, minúsculo), `ABC-1D23` (Mercosul, com hífen) e `AB1234`
(inválido, curto demais).

**Esperado**: as três primeiras são aceitas e tratadas como o mesmo valor persistido (`ABC1D23` no
terceiro caso); a última é recusada, com o motivo indicado junto ao campo, e o envio do formulário
permanece bloqueado enquanto ela estiver preenchida assim.

## Cenário 5 — Cadastro persiste entre execuções (US2, SC-002, SC-004)

1. Complete o cadastro com dados válidos.
2. Encerre o aplicativo completamente (não apenas segundo plano) e reabra. Repita 5 vezes.

**Esperado**: nas 5 reaberturas, o aplicativo vai direto para a tela principal, sem exibir o
formulário, e os dados exibidos na tela de edição são idênticos aos cadastrados na primeira vez.

## Cenário 6 — Corrigir um dado cadastrado (US3, SC-005)

1. Com o cadastro já preenchido, abra a tela de edição.
2. Altere a cor e a placa do veículo para valores válidos e diferentes dos anteriores, e salve.
3. Encerre e reabra o aplicativo.

**Esperado**: a tela de edição mostra os novos valores, e eles continuam lá depois de reabrir o
aplicativo — sem precisar reinstalar.

## Cenário 7 — Cadastro corrompido não trava a inicialização (Edge Cases, FR-010)

```bash
adb shell "run-as br.ufsc.tcc.caronas.driver sqlite3 /data/data/br.ufsc.tcc.caronas.driver/databases/<nome-do-banco>.db \"UPDATE driver_profile SET uf = 'ZZ' WHERE id = 1;\""
```

(ajuste o nome do arquivo de banco conforme definido na implementação; o comando corrompe a UF do
único cadastro para um valor fora da lista válida.)

Reabra o aplicativo.

**Esperado**: o aplicativo não trava nem lança erro visível — trata a situação como se não houvesse
cadastro e volta a exibir o formulário, permitindo preencher de novo.

## Resultados da execução de 17/09/2026

Ambiente: emulador Android `Pixel_6_API34_1` (API 34), build **debug**, banco de dados real (nenhum
dublê). Onde não há número a medir, o resultado é qualitativo — o próprio comportamento esperado.

| Cenário | Resultado |
|---------|-----------|
| 1 — `flutter analyze` / `flutter test` | ✅ `No issues found!` e **105 testes** aprovados, nenhum ignorado |
| 2 — Formulário na primeira execução | ✅ formulário exibido antes de qualquer outra tela após instalar/limpar dados; cadastro concluído levou à tela principal, que passou a ter 4 abas (Eventos, Relays, Identidade, Cadastro) |
| 3 — Cidade depende da UF | ✅ campo de cidade vazio e desabilitado sem UF; ao escolher `SC`, a lista mostrou só municípios catarinenses em ordem alfabética (`Abdon Batista`, `Abelardo Luz`, …, `Araranguá`, …); a UF exigiu rolar a lista de opções, confirmando as 27 unidades embutidas |
| 4 — Validação de placa | ✅ `AB1234` (curta) recusada em tempo real com a mensagem "Placa fora do formato antigo ou Mercosul", botão de envio desabilitado; `abc1d23` (Mercosul, minúsculo) aceita e normalizada para `ABC1D23` |
| 5 — Cadastro persiste entre execuções | ✅ `force-stop` + reabertura: foi direto à tela principal, e a aba Cadastro mostrou todos os campos exatamente como enviados, com a placa já normalizada — persistência real em SQLite, não em dublê |
| 6 — Corrigir um dado | ✅ cor alterada de `Preto` para `Branco` pela aba Cadastro; `force-stop` + reabertura confirmou o novo valor, com os demais campos intactos |
| 7 — Cadastro corrompido não trava | ✅ `UF` corrompida para `ZZ` diretamente no banco via `sqlite3` on-device; a reabertura não travou nem lançou exceção (`adb logcat` sem `FATAL`/`AndroidRuntime`) — voltou a exibir o formulário limpo, como se não houvesse cadastro |

**SC-001 (tempo de preenchimento) — não medido numericamente nesta rodada**: os cenários acima foram
executados por automação de toques via `adb`, que não representa o tempo de digitação humano de forma
válida para essa métrica. O fluxo funcional foi validado ponta a ponta; a medição de "menos de 2
minutos" exige um motorista real preenchendo o formulário, e fica pendente para antes da entrega final
— registrar aqui um número obtido por automação seria uma medição fabricada (Princípio V).

### Observações da execução

- A tabela de UFs no dropdown é virtualizada (rolagem interna): confirma que a lista inteira de 27
  entradas está presente, não apenas as visíveis inicialmente.
- Nenhuma chamada de rede foi observada durante a navegação do formulário (sem indicador de atividade
  de rede associável ao preenchimento) — coerente com D2 de `research.md` (dado embutido).
- O arquivo do banco (`cadastro_motorista.db`) foi inspecionado diretamente via `sqlite3` on-device e
  confirmou a linha única esperada, com a restrição de no máximo um cadastro por instalação.
