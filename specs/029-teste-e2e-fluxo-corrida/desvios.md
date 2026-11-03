# Desvios e conferências da execução (modelo)

O roteiro cria `e2e_saida/execucao/desvios.md` a partir de um modelo embutido e acrescenta linhas
automáticas (por exemplo, observador sem todos os relays). Registre aqui, com o motivo,
tudo que diferir do spec (FR-040): ajuste de limite de tempo, rótulo de tela diferente do
previsto, conferência manual (por exemplo, a distância entre o destino do `geo fix` e o
ponto devolvido pelo Photon), tela não capturada. O que não está aqui não foi alterado.

| Data (UTC) | O que mudou ou foi conferido | Motivo |
|------------|------------------------------|--------|

## Desvios já conhecidos no planejamento

| Data (UTC) | O que mudou ou foi conferido | Motivo |
|------------|------------------------------|--------|
| 2026-11-01 | Tetos de E02 e E04 maiores que o teto geral de 60 s do plano (120 s e 90 s) | Cada uma soma duas esperas (busca Photon 30 s + rota 45 s; rota 45 s + efeito remoto 45 s); com 60 s a etapa nunca poderia cumprir os limites individuais |
| 2026-11-01 | Latência de 20007 e 20009 medida a partir do `adb emu geo fix`, não de um toque | O app publica esses eventos por posição (`map_screen.dart`); ver correção na tabela de FR-028 |
| 2026-11-01 | Mapeamento de telas do cadastro, da navegação "Mais" e dos resultados da busca de endereço **não conferido contra os apps rodando** | Os emuladores não foram usados na implementação; os rótulos vêm do código dos apps. A confirmação é o cenário 2 do quickstart |
| 2026-11-01 | Destino do `geo fix` ajustado para (-28.9484, -49.4985), a 1ª resposta do Photon para o texto fixo | Conferido com a API do Photon (`photon.komoot.io`); fica a ~5 m do ponto retornado |
| 2026-11-02 | A avaliação deixa de ter dois períodos: passa a ser uma única execução de 60 ciclos válidos, teto de 80 executados, orçamento de 12 h de tempo ativo, sem exigência de dias distintos e com relatório só sobre o total | Decisão do autor (spec, Clarifications de 2026-11-02); o motivo detalhado cabe ao autor registrar aqui |
| 2026-11-01 | No passageiro, o `geo fix` também vai ao destino (etapa E09) | O botão "Confirmar chegada ao destino" depende da posição do passageiro (`map_screen.dart` do passageiro, `_noRaioDoDestino`), não do aviso 20009 |
| 2026-11-01 | Campos de texto escolhidos pela ordem e teclado fechado com ENTER | O dump não traz o rótulo dos campos e o BACK sai do app do motorista |

## Emenda de 2026-11-03

| Data (UTC) | O que mudou ou foi conferido | Motivo |
|------------|------------------------------|--------|
| 2026-11-03 | Roteiro automatizado suspenso; as 60 corridas serão feitas manualmente e a evidência virá de logs dos apps (FR-050 a FR-059, `contracts/logs.md`) | Decisão do autor: o teste automatizado não vinha funcionando; o motivo detalhado cabe ao autor registrar aqui |
