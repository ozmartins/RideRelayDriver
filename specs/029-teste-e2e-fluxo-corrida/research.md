# Research: Teste E2E automatizado do fluxo completo da corrida

Cada decisão: escolha, motivo, alternativas descartadas. Nenhuma medição foi feita nesta etapa; o
que vem de leitura de código está marcado com o arquivo.

## D1 — Nenhuma dependência nova (Princípio III)

**Decisão**: usar só `dart:io`, `dart_nostr` (verificação de assinatura via `NostrEventVerifier`) e
código existente em `lib/services/` que não importa Flutter. **Por quê**: o observador precisa de
WebSocket, frames NIP-01 e verificação de assinatura, e o app já tem os três
(`WsRelayTransport`, `relay_protocol.dart`, `event_verifier.dart`). **Descartado**: pacotes de
automação Android (appium, patrol, `integration_test`): exigem toolchain extra, não operam dois
emuladores ao mesmo tempo com relógio comum e a spec fixa ADB + `uiautomator dump`.

**Validado em 2026-11-01** (T003): `dart run tool/e2e/e2e.dart --ajuda` importa `package:driver/...`
(transporte, frames e verificador) e roda; os arquivos escolhidos não importam `flutter`.

## D2 — Reaproveitar `tool/e2e`?

`tool/e2e/` está vazia (verificado em 2026-11-01); não há infraestrutura a reaproveitar além das
sondas de `tool/` (`publish_ride_request.dart` serve de modelo de uso do transporte).

## D3 — Entrada de texto e seletores

`adb shell input text` com valores só ASCII (cadastros e busca de endereço escolhidos sem acento).
Seletores por `text` ou `content-desc` do dump (Flutter publica o texto visível como
`content-desc`). Ícones sem rótulo (as 5 estrelas do `RideRatingModal`, `IconButton` sem
tooltip) são selecionados **estruturalmente**: o N-ésimo nó clicável dentro do contêiner que contém
"Avalie a corrida". Coordenada fixa só como último recurso e registrada em `desvios.md`.

## D4 — Observador: escopo da assinatura e do que se grava

**Decisão**: o observador abre as mesmas 3 URLs, inscrição `REQ` com dois filtros (`authors`
= {motorista, passageiro}, `kinds` 20001–20015, `#t` marcador, `since` = agora − 10 min) e (`#p` =
{motorista, passageiro}, mesmos kinds e marcador). Verifica a assinatura de cada evento (descarta
e conta os inválidos) e grava só: relay, kind, id, `created_at`, instante local (relógio
monotônico + UTC), autor e destinatário (`p`) **da identidade do período** quando aplicável. O
`content` não é copiado do payload para nenhuma estrutura do observador (o tipo `EventoObservado`
nem tem o campo).

**Por quê**: a spec exige registrar relay/kind/id/created_at/instante e associar por chaves
públicas das identidades; filtrar no relay evita guardar pubkeys de terceiros que usam o
marcador nos mesmos relays públicos (privacidade) e reduz volume. **Descartado**: assinar por
`#t` apenas e filtrar localmente (grava/trafega eventos de terceiros sem necessidade).
**Dependência de ordem**: o observador só pode ser aberto depois de conhecer as chaves públicas
(fim do preparo) — e fica conectado até o fim do período, inscrito antes de cada ciclo (FR-023,
conferido por `EOSE`/conexão aberta em cada relay).

**Relógio do emulador (F1 da análise)**: `since` compara com o `created_at`, que vem do relógio do
emulador. Por isso a margem de 10 min, e o roteiro lê `adb shell date +%s` de cada emulador antes
do primeiro ciclo e grava a deriva em relação ao hospedeiro (`ambiente.deriva_relogio_s`). A
associação de evento a ciclo e a latência usam `recebido_utc` (relógio do hospedeiro), nunca o
`created_at`.

**Limite honesto** (FR-024): o observador aproxima, não mede, a chegada ao app destinatário; os
relays podem entregar ao observador antes ou depois do que entregam ao app.

## D5 — Clopper-Pearson em código próprio, conferido por scipy

**Decisão**: implementar a beta incompleta regularizada (fração contínua de Lentz) e inverter por
bissecção (tolerância 1e-12); casos x=0 e x=n tratados com fórmula fechada. Testes de unidade com
valores conhecidos (0/60 → superior bilateral 95% = 1 − 0,025^(1/60) ≈ 5,96%) **e** um fixture
JSON gerado por `tool/e2e/gen_clopper_pearson_vectors.py` com `scipy.stats.beta.ppf`
(scipy 1.14.1 está instalado na máquina do pesquisador, verificado em 2026-11-01). O fixture
registra versão do scipy e comando; se scipy não existir ao regenerar, o gerador falha em vez de
inventar valores. **Descartado**: pacote Dart de estatística (nova dependência sem necessidade; o
cálculo cabe em ~60 linhas e é auditável).

## D6 — Mediana e P95

Ambos pelo posto mais próximo (nearest-rank): valor ordenado na posição ⌈p·N⌉ (1-indexada),
p = 0,5 e 0,95. A spec pede mediana "e" P95 pelo método do posto mais próximo; usar o mesmo
método nos dois evita a mediana por interpolação, que não é amostra real. Essa leitura é
declarada no relatório. Sem amostras, o campo sai "—" (nunca zero).

## D7 — Valores dos timeouts

São os da tabela do `plan.md`; derivados do que cada etapa faz (rede pública, 5 s de intervalo do
app, Photon/ORS), **não** medidos. Escolha de 5 min por ciclo porque 30 ciclos × (5 + 1) min = 3 h,
exatamente o orçamento: nenhum ciclo pode estourar a média sem o orçamento cortar o período.
Orçamento = tempo ativo acumulado (soma das durações de execução), para que a retomada após dormir
não consuma o saldo; o relatório informa o tempo ativo e as datas de cada execução.

## D8 — Recuperação após falha no meio da corrida

`pm clear` apagaria identidade e reputação (FR-014 manda mantê-las no período). Logo, para
destravar uma corrida pendente usa-se o cancelamento pelo botão do próprio app (kinds 20012/20013).
Esses eventos aparecem depois do fim do ciclo, em janela marcada `recuperacao`, não entram nas
anomalias do ciclo nem na latência. Se a recuperação falhar, o período para com falha de **ambiente
de teste** (o roteiro não segue com aplicativos em estado desconhecido).

## D9 — Origem da falha (FR-026, FR-021a): regras em ordem de precedência

1. **ambiente de teste**: `adb` sem resposta/dispositivo offline; emulador travado; observador
   sem conexão com **nenhum** dos 3 relays (rede do hospedeiro); falha na volta ao estado inicial
   por causa de `adb`.
2. **serviço externo**: sinal do app na janela da etapa (FR-021a): mensagem de falha de rota/
   distância (→ OpenRouteService), de busca de endereço (→ Photon: "Não foi possível buscar
   endereços no momento"), ou linha de `logcat` dos `debugPrint` que citam falha do serviço
   ("Distância … falhou", "Endereço … falhou" em `ride_request_modal.dart`) / erro de tiles
   (→ OpenFreeMap), com HTTP 429 anotado quando o texto o trouxer. Sem sinal, nunca é externo.
3. **relays**: o evento esperado **foi observado em ≥ 1 relay** e, ainda assim, o app destinatário
   não avançou no prazo.
4. **aplicativo**: o restante — elemento de UI ausente com ações já feitas, app encerrado (processo
   ausente / "FATAL EXCEPTION"), e o caso `origem_bruta = indeterminada` (ação executada, evento
   esperado não observado em nenhum relay, observador conectado).

Determinístico: a função `classificar(evidências)` é pura e testada caso a caso. Dúvida entre
duas regras resolve-se pela de menor número.

**Risco registrado**: se o app não distinguir 429 de outro erro no texto, o sinal é "a chamada ao
serviço falhou", atribuída ao serviço chamado; o relatório diz isso. Falha de OpenFreeMap só é
atribuível se existir sinal; se o app não mostrar erro de tiles, ela não bloqueia o fluxo e não
há como atribuí-la (limitação declarada).

## D10 — Evidências e telas sensíveis (FR-027)

Capturas e dumps só passam por `Evidencia.permitida(dump)`: bloqueia se o dump contiver marcadores
de tela de cadastro, relays, "Minha identidade"/chave pública, backup ou chave privada
(lista em `telas.dart`). Os cadastros, a leitura de chaves públicas e a conferência de relays
**nunca** salvam dump ou captura; o dump lido fica em memória. Na falha, se a tela atual é
sensível, grava-se apenas um registro "captura omitida: tela sensível" no lugar da imagem.

## D11 — Verificação de vazamento (FR-029)

Hex de 64 caracteres identifica tanto uma chave privada quanto um id/chave pública, então o
padrão sozinho não separa. **Decisão**: lista de permitidos — todo token de 64 hex na saída deve
ser um id de evento observado ou uma das chaves públicas do período; qualquer outro reprova.
Tokens de 128 hex (assinatura) e `nsec1…` reprovam sempre; `"content"` como chave JSON reprova; e a
chave do openrouteservice (lida do ambiente/arquivo local, nunca impressa) reprova se aparecer
como substring. A varredura roda sobre todos os arquivos de texto da saída ao fim do período, ao
gerar o relatório e por comando próprio; PNGs são cobertos pela política D10, não por varredura.

## D12 — Saída e retomada

`e2e_saida/` (nova linha em `.gitignore`), uma pasta por período e uma `ensaio-*` para ensaios
(`--ensaio`, `--meta-validos N`), que **não** contam para o teto de 80 e saem rotuladas "ENSAIO — não
vale para o TCC". Checkpoint a cada ciclo: `ciclos.jsonl` é só-acréscimo; `checkpoint.json` é
reescrito de forma atômica (arquivo temporário + rename). Ao retomar, o roteiro confere se as
chaves públicas na tela ainda são as do checkpoint; divergência recusa seguir. Ciclo que estava em
andamento no momento da interrupção é refeito do início do ciclo e registrado como
`interrompido` (não conta como executado válido); isso é dito nas limitações.

## D13 — Ambiente e preparo

`pm clear` seguido de `pm grant` de localização e notificações (evita diálogos de permissão),
`adb emu geo fix <lon> <lat>` (atenção: longitude primeiro), AVD conferido por
`adb -s <serial> emu avd name`. Pré-condição verificada e não automatizada: apps instalados com a
chave do openrouteservice embutida (build via `--dart-define` ou `assets/ors_api_key.txt`). O
roteiro não compila nem instala; registra `git rev-parse HEAD` dos dois repositórios
(`RideRelayDriver` e `../RideRelayPassenger`) e se há alterações não commitadas.

## D14 — Coordenadas fixas

Partida do motorista, origem do passageiro (= ponto de encontro) e destino são constantes em
`config.dart`, escolhidas dentro do raio de atendimento padrão (10 km) e com o destino a > 1 km do
ponto de encontro. A coordenada de destino usada no `geo fix` deve ficar a ≤ 1 km do ponto que o
Photon devolve para o texto de busca fixo; essa conferência é feita **uma vez** no ensaio e o
resultado vai para `desvios.md`, não por sondagem em cada ciclo.
