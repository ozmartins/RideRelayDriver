# Desvios e conferências do período (modelo)

O roteiro copia este modelo para `e2e_saida/<período>/desvios.md` e acrescenta linhas
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
