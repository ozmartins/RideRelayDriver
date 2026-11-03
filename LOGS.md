# Onde ficam os logs das execuções

O app grava o log do fluxo em JSON Lines, no armazenamento privado do app, na pasta de bancos
do sqflite:

```
/data/data/br.ufsc.tcc.corridas.driver/databases/logs/
├── fluxo-ui.jsonl          # isolate da interface
├── fluxo-servico.jsonl     # isolate do serviço em primeiro plano (conexão com os relays)
├── fluxo-ui.jsonl.1        # arquivo anterior, só depois de uma rotação (teto de 32 MiB)
└── fluxo-servico.jsonl.1
```

O relatório precisa dos dois arquivos de cada app (e dos `.1`, se existirem).

## Extrair do aparelho (build debug)

```bash
mkdir -p logs-driver
for f in fluxo-ui.jsonl fluxo-servico.jsonl fluxo-ui.jsonl.1 fluxo-servico.jsonl.1; do
  adb exec-out run-as br.ufsc.tcc.corridas.driver cat databases/logs/$f > logs-driver/$f
done
```

Com mais de um aparelho conectado, acrescente `-s <serial>` ao `adb`. Arquivo que não existe sai
vazio; apague-o. `run-as` só funciona em build debug.

## Identificar a execução

`flutter run --dart-define=EXEC_ID=<nome>`. Sem o define, o campo `exec` vale `manual`.

## Como executar os testes (60 corridas manuais)

1. **Mesmo `EXEC_ID` nos dois apps.** Rode motorista e passageiro com o mesmo valor, por exemplo
   `--dart-define=EXEC_ID=tcc-01`. O relatório filtra por ele (`--exec`); misturar valores separa os
   logs e quebra a contagem.
2. **Relógios coerentes.** A latência é a diferença entre o `evento.publicou` de um app e o primeiro
   `evento.recebeu` do outro, ligados pelo `id` do evento. Com dois aparelhos, sincronize a hora
   (automática/NTP) antes de começar; o desvio entra na seção de limitações do relatório.
3. **Não apague dados nem desinstale os apps** durante a execução: isso zera os logs e, no motorista,
   a chave de identidade. Os logs acumulam entre aberturas do app; não é preciso limpá-los.
4. **Cada corrida completa** vai do orçamento aceito até o recibo emitido pelos dois lados. O relatório
   conta como ciclo o `guid_corrida` que chegou à aceitação e como sucesso o ciclo com `recibo.emitiu`
   nos dois apps. Corrida abandonada no meio conta como falha: não a "refaça por fora", registre-a e
   siga; a meta (60) é de ciclos válidos, e o relatório informa quantos foram executados.
5. **Anote desvios** (aparelho reiniciado, sem internet, troca de relay) em
   `RideRelayDriver/specs/029-teste-e2e-fluxo-corrida/desvios.md`; o log não os explica sozinho.
6. **Ao terminar**, extraia os logs dos dois aparelhos (seção acima) para `logs-driver/` e
   `logs-passenger/` e gere o relatório no repositório do motorista:

   ```bash
   cd RideRelayDriver
   dart run tool/relatorio_logs.dart --motorista ../logs-driver --passageiro ../logs-passenger \
     --exec tcc-01 --meta 60
   ```

   A saída vai para `e2e_saida/logs/` (Markdown, CSVs e `externas.csv`; a pasta é ignorada pelo Git).
   Sem `--passageiro` o relatório sai só com o lado do motorista, sem latência entre apps.

## Limites conhecidos

- Nada disso foi rodado num aparelho ainda: confirme na **primeira corrida** que os dois arquivos
  (`fluxo-ui` e `fluxo-servico`) existem e têm linhas antes de seguir para as outras 59.
- Tiles do OpenFreeMap não são registrados; só estilo e atlas de ícones.
- O `.1` mais antigo é descartado numa segunda rotação: extraia os logs ao longo da execução se um
  arquivo se aproximar de 32 MiB.

## Cuidados

- O log contém endereços e coordenadas de passageiros e o texto de erros: anonimize antes de
  levá-lo para fora da máquina.
- Desinstalar o app apaga os logs.
- Contrato dos campos: `RideRelayDriver/specs/029-teste-e2e-fluxo-corrida/contracts/logs.md`.
