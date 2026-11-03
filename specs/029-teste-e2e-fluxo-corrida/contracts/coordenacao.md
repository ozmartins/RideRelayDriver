# Contrato: coordenação entre as duas máquinas do E2E

Proposta (rascunho) para executar o roteiro E2E com um conjunto de scripts por máquina:
o do **motorista** (este repositório) e o do **passageiro** (`../RideRelayPassenger`).
Este arquivo deve ser idêntico nos dois repositórios.

## Papéis
- `--papel motorista|passageiro`: cada processo opera apenas o seu emulador.
- O **passageiro é o coordenador**: dono do orçamento (60 ciclos válidos, teto 80, 12 h),
  do `--retomar` e do servidor de coordenação. O motorista é cliente e segue as barreiras.

## Transporte
HTTP/1.1 em JSON na LAN, porta padrão `8765` (`--porta`), endereço do coordenador em
`--coordenador <ip:porta>`. Sem TLS (rede local de teste). Toda requisição leva o
cabeçalho `X-E2E-Token` com um segredo curto combinado por `--token`; sem ele, `401`.

## Mensagens
Somente metadados: índice do ciclo, papel, status e instante local. **Nunca** chave
privada, `content`, chave da ORS nem qualquer dado de evento.

| Rota | Corpo | Efeito |
|---|---|---|
| `POST /barreira` | `{"nome","ciclo","papel","dados"?}` | Bloqueia (long-poll, até `--espera-barreira`) até os dois papéis chegarem; responde `{"liberada":true,"outro":{…}?}` (`outro` = `dados` do outro papel) ou `408`. |
| `POST /abortar` | `{"ciclo","papel","motivo"}` | Marca o ciclo como abortado; a próxima barreira de ambos responde `{"abortado":true}`. |
| `GET /estado` | — | `{"ciclo","validos","executados","ativoMs","encerrado","motivo"?}`: decisão do coordenador sobre o ciclo `ciclo` (-1 = nada decidido). `motivo`: `meta_atingida` ou o motivo da parada parcial. |
| `POST /falha` | `{"ciclo","papel","etapa"}` | Registra que o papel falhou na etapa (`E01`–`E12` ou `R`); vale a primeira. |
| `GET /falha?ciclo=N&papel=P` | — | `{"etapa"?}`: etapa em que o **outro** papel (o que não é `P`) falhou no ciclo `N`. |
| `POST /relogio` | `{"t0"}` | Responde `{"t0","t1","t2"}` (NTP simplificado) para registrar o deslocamento entre os relógios **só como metadado do relatório**. |

Barreiras por ciclo, nesta ordem: `inicio-ciclo`, `fim-ciclo`, `pronto-para-reiniciar`.

## Laço da execução
No topo de cada iteração (depois de n ciclos): o coordenador avalia meta, teto,
orçamento e Ctrl+C e publica a decisão (`ciclo = n`, `encerrado`, `motivo`); o motorista
espera `GET /estado` trazer `ciclo ≥ n` (até 90 s) e confere `validos` e `executados` com
os seus (divergência ⇒ parada por `ambiente`). Se não encerrou: reinício dos emuladores
(só entre ciclos, nunca depois do último), barreira `pronto-para-reiniciar` (ciclo `n`),
verificação do observador, barreira `inicio-ciclo` (ciclo `n+1`), o ciclo, e barreira
`fim-ciclo` com `dados` = `{resultado, valido, etapaFalha?, origem?, servicoExterno?,
origemBruta?, limiteDiarioOrs, recuperacaoFalhou}`. Cada lado funde os dois resumos: ciclo
válido só se os dois forem; vale a falha de serviço externo e, depois, a etapa mais cedo;
`interrompido` de qualquer lado interrompe o ciclo. Quem para por conta própria (ambiente,
Ctrl+C) chama `POST /abortar` nos ciclos `n` e `n+1` para soltar o outro; o lado solto lê
`/estado` e adota o motivo do coordenador se ele já encerrou.

## Falha no meio do ciclo
Quem falha numa etapa avisa por `POST /falha`. Quem espera consulta `GET /falha` a cada 2 s
nas esperas por tela; se o outro já falhou, para na hora (falha marcada `consequencia`) em
vez de esgotar o prazo da etapa. No `fim-ciclo`, a causa (falha sem `consequencia`) vale
antes do reflexo, independentemente da etapa.

## Medição
Cada máquina mede latência apenas de eventos de que é **autora** (`autor` em
`TipoLatencia`), ação → evento no seu próprio `Observador`, no mesmo relógio. Nenhuma
latência cruza relógios. A junção dos relatórios só concatena as amostras.

## Falhas
- Barreira expirada ⇒ o ciclo é invalidado e registrado como desvio; o orçamento do
  coordenador decide se repete.
- Coordenador inalcançável ⇒ o motorista encerra o ciclo corrente, grava o checkpoint
  local e sai com código de erro de ambiente.
