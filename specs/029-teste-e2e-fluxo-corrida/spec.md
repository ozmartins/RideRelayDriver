# Feature Specification: Teste E2E automatizado do fluxo completo da corrida (caminho feliz)

**Feature Branch**: `029-teste-e2e-fluxo-corrida` (desenvolvimento direto na `master`, sem ramo — ver CLAUDE.md)

**Created**: 2026-11-01

**Status**: Draft

**Input**: User description: "Teste E2E automatizado do fluxo completo da corrida (caminho feliz), para avaliação experimental do TCC"

> **Nota sobre versões anteriores.** Esta especificação substitui qualquer versão anterior de
> teste E2E ou de spec 029; as antigas foram removidas pelo autor e não são fonte de requisitos.
> O que for reaproveitado de `tool/e2e` só o será se existir e estiver de acordo com esta spec;
> na data da criação a pasta `tool/e2e` está vazia.

## Contexto e finalidade

Trabalho acadêmico (TCC, UFSC) que avalia possibilidades e limitações do protocolo Nostr como
infraestrutura de comunicação descentralizada para aplicativos de mobilidade urbana. Os aplicativos
do motorista e do passageiro já existem. Esta feature cria o roteiro automatizado de ponta a ponta
que gera as evidências do TCC. **O que esta spec descreve é exatamente o que o TCC afirma ter sido
feito:** nada pode ser acrescentado, omitido ou alterado na execução sem registro do motivo
(ver FR-040).

## Clarifications

### Session 2026-11-01

- Q: Como tratar as specs 029 anteriores? → A: Removidos pelo autor; esta spec assume o número 029.
- Q: Como o limite de 80 ciclos executados se divide entre os dois períodos? → A: Teto de 40 ciclos no período 1; o período 2 pode usar o saldo (80 menos os executados no período 1), nunca passando de 80 no total.
- Q: Qual a origem da falha quando o evento esperado não chega a nenhum relay observado? → A: Indeterminada no registro bruto (`origem_bruta`), contada como aplicativo no relatório (`origem`) e listada à parte.
- Q: Como tratar o recibo 20014 na latência, já que os dois lados emitem? → A: Dois tipos de evento: `20014` motorista→passageiro e `20014` passageiro→motorista, cada um medido a partir do toque do respectivo avaliador; a latência geral usa os dois.
- Q: Que evidência atribui uma falha a serviço externo? → A: Somente sinais dos apps: mensagem de erro na interface ou entrada no `logcat` indicando falha de Photon, OpenFreeMap ou OpenRouteService (incl. HTTP 429); sem sondagem independente.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Executar um período completo de ciclos da corrida (Priority: P1)

O pesquisador inicia, com um único comando, um período de avaliação (`--periodo 1` ou
`--periodo 2`). O roteiro prepara os dois emuladores, cria identidades descartáveis, e repete o
fluxo completo de uma corrida (solicitação → orçamento → seleção → deslocamento → encontro →
início/acompanhamento → encerramento → avaliações e recibos) até obter 30 ciclos válidos, sem
intervenção manual.

**Why this priority**: É a única propriedade avaliada pelo TCC. Sem isso não há evidência.

**Independent Test**: Com os dois emuladores e a Internet disponíveis, rodar um período com meta
reduzida (ex.: 2 ciclos válidos) e verificar que cada ciclo termina com resultado por etapa
registrado e que o fluxo se completa nos dois aplicativos.

**Acceptance Scenarios**:

1. **Given** dois emuladores configurados e os aplicativos instalados, **When** o pesquisador inicia
   o período 1, **Then** os dados dos dois aplicativos são apagados, os cadastros refeitos com
   identidades descartáveis e o primeiro ciclo começa.
2. **Given** um ciclo em andamento, **When** todas as etapas do caminho feliz se completam nos dois
   aplicativos, **Then** o ciclo é registrado como sucesso e os aplicativos voltam ao estado
   inicial do fluxo, sem apagar dados, antes do ciclo seguinte.
3. **Given** um período em curso, **When** são atingidos 30 ciclos válidos, **Then** o roteiro para,
   grava os dados e informa que o período terminou.
4. **Given** um ciclo cuja falha é atribuída a serviço externo, **When** ele termina, **Then** não
   conta como válido e é reposto por um novo ciclo, respeitando o limite de 80 ciclos no total.
5. **Given** um ciclo com falha de outra origem, **When** ele termina, **Then** conta como válido e
   como falha.

---

### User Story 2 - Garantir término limitado e retomada (Priority: P1)

O pesquisador precisa ter certeza de que nenhuma execução passa do orçamento (antes, uma execução
passou de 24 horas e foi interrompida) e de que uma interrupção não perde ciclos já registrados.

**Why this priority**: É requisito obrigatório; sem ele a execução é inviável na prática.

**Independent Test**: Iniciar um período com orçamento artificialmente curto e verificar o relatório
parcial; interromper outro período no meio e retomar com `--retomar`.

**Acceptance Scenarios**:

1. **Given** uma etapa que não conclui, **When** o timeout da etapa estoura, **Then** a etapa é
   registrada como falha, o ciclo é encerrado (respeitando o timeout do ciclo) e o roteiro segue
   para o próximo ciclo.
2. **Given** um período que atinge 3 horas, **When** o orçamento se esgota, **Then** o roteiro
   para, grava os dados e gera relatório parcial indicando claramente que é parcial.
3. **Given** um período interrompido (queda, Ctrl+C), **When** o roteiro é reiniciado com
   `--retomar`, **Then** os ciclos já registrados não são refeitos e a contagem continua deles.
4. **Given** a OpenRouteService respondendo limite (ex.: HTTP 429), **When** isso ocorre num ciclo,
   **Then** o ciclo é classificado como falha externa (OpenRouteService); se o limite diário
   esgotar, o período para de forma controlada e gera relatório parcial.

---

### User Story 3 - Observar a entrega de eventos nos relays (Priority: P1)

Um observador independente dos aplicativos, inscrito nos mesmos três relays antes de cada ciclo,
registra metadados de cada evento para medir latências e descrever o comportamento por relay.

**Why this priority**: Fornece os dados de latência e de comportamento por relay do relatório.

**Independent Test**: Publicar eventos conhecidos nos três relays e verificar que o observador
registra relay, kind, id, `created_at` e instante local — e nada de `content`.

**Acceptance Scenarios**:

1. **Given** o início de um ciclo, **When** o ciclo vai começar, **Then** o observador já está
   conectado e inscrito nos três relays.
2. **Given** um evento recebido, **When** o observador o registra, **Then** o registro contém
   somente relay de origem, kind, id, `created_at` e instante local de recebimento.
3. **Given** eventos recebidos, **When** são associados a ciclos, **Then** a associação usa a
   janela de tempo do ciclo e as chaves públicas das identidades do ciclo.

---

### User Story 4 - Gerar o relatório do TCC (Priority: P2)

Com um segundo comando (ex.: `--relatorio`), o pesquisador gera o relatório em Markdown, mais os
dados em CSV, combinando os dois períodos.

**Why this priority**: Consome os dados dos P1; é o artefato usado no TCC.

**Independent Test**: Gerar o relatório a partir de dados de ciclos sintéticos com resultados
conhecidos e conferir cada seção e cada número.

**Acceptance Scenarios**:

1. **Given** os dados de um ou dois períodos, **When** o relatório é gerado, **Then** contém as
   oito seções descritas em FR-030 a FR-037.
2. **Given** 0 falhas em 60 ciclos válidos (sem externas), **When** o critério é aplicado,
   **Then** o resultado é ATENDIDO e o limite superior bilateral de 95% da taxa de falha é ≈ 5,96%.
3. **Given** só um período disponível ou período parcial, **When** o relatório é gerado, **Then**
   isso é dito explicitamente e na seção de limitações.

---

### User Story 5 - Evidências sem vazamento (Priority: P1)

Cada ciclo deixa evidências estruturadas e capturas de tela, sem jamais gravar chave privada,
`content` de evento, nem chave de API.

**Why this priority**: Regra inegociável de segurança (Princípio I da constituição).

**Independent Test**: Executar a verificação automática de padrões proibidos sobre uma pasta de
saída contendo, de propósito, uma chave privada e um `content` de teste: deve falhar. Sobre uma
saída legítima, deve passar.

**Acceptance Scenarios**:

1. **Given** uma falha em um ciclo, **When** ela é registrada, **Then** são gravadas capturas de
   tela dos dois emuladores e o dump da interface no instante da falha.
2. **Given** o primeiro ciclo de um período, **When** ele atravessa as telas fixas, **Then** são
   capturadas as seis telas listadas em FR-027, nos dois emuladores.
3. **Given** qualquer tela de configuração, cadastro com chaves, backup ou exibição de chave
   privada, **When** o roteiro passa por ela, **Then** nenhuma captura é feita.

### Edge Cases

- Emulador offline, travado ou sem Wi-Fi no início/meio do ciclo: falha de **ambiente de teste**.
- Um ou dois relays da lista não entregam o evento, mas o fluxo conclui: não é falha; aparece só no
  comportamento por relay. Se o fluxo não conclui por ausência de entrega: falha de **relays**.
- Serviço externo (Photon, OpenFreeMap, OpenRouteService) lento, indisponível ou limitado: falha
  externa, ciclo reposto; a falha precisa ser **atribuível** por sinal do app (FR-021a); sem
  esse sinal, a origem não pode ser externa.
- Falha na reconfiguração entre ciclos (voltar ao estado inicial): falha de ambiente de teste ou
  de aplicativo conforme a causa, registrada com captura.
- Limite de 80 ciclos (ou teto do período) atingido sem os válidos previstos: relatório declara isso e apresenta o obtido.
- Retomada com dados de checkpoint ausentes ou corrompidos: o roteiro recusa continuar e diz por
  quê, sem apagar nada; não inventa ciclos.
- Saída contendo padrão proibido: a verificação falha e o relatório não é dado como íntegro.
- Chave da OpenRouteService ausente: o roteiro avisa antes de iniciar e não grava a chave em
  lugar algum.
- Data/hora do host: latências usam um único relógio (o da máquina que roda o roteiro e o
  observador).

## Requirements *(mandatory)*

### Funcional — o que é avaliado

- **FR-001**: O roteiro MUST avaliar **somente** a conclusão do fluxo completo da corrida no
  caminho feliz: solicitação pelo passageiro; envio e seleção do orçamento; deslocamento do
  motorista até o passageiro; confirmação do encontro; início e acompanhamento da corrida;
  encerramento; troca de avaliações com emissão dos recibos de reputação.
- **FR-002**: Um ciclo MUST ser sucesso se, e somente se, todas as etapas se completam nos dois
  aplicativos, sem intervenção manual. Qualquer etapa não concluída no prazo torna o ciclo falha.
- **FR-003**: A emissão dos recibos MUST ser apenas **constatada** (foram emitidos nos dois
  sentidos), sem verificação detalhada de conteúdo.
- **FR-004**: O roteiro MUST registrar a latência de entrega dos eventos apenas de forma
  descritiva, sem critério de sucesso (ver FR-028).

### Funcional — fora do escopo (NÃO implementar)

- **FR-005**: O roteiro MUST NOT implementar: recusa ou cancelamento de corrida; relay
  inalcançável ou simulação de falha de relay; testes de segurança, desempenho em larga escala,
  escalabilidade ou tolerância a falhas; vários motoristas ou propostas concorrentes; verificação
  detalhada de recibos; relay local, instrumentado ou simulado.

### Funcional — ambiente

- **FR-006**: A execução MUST usar dois emuladores Android de mesma configuração (Google Pixel 6,
  Android 14/API 34, x86_64, mesma memória e processamento): um para o app do motorista, outro para
  o do passageiro. AVDs existentes: `Pixel_6_API34_1` e `Pixel_6_API34_2`. A configuração efetiva
  MUST ser registrada nos metadados do relatório.
- **FR-007**: Ambos os aplicativos MUST usar sempre a lista padrão completa dos três relays
  públicos, simultaneamente: `wss://nos.lol`, `wss://relay.primal.net`, `wss://offchain.pub`. O
  roteiro MUST verificar essa configuração antes de cada período e recusar-se a rodar se a lista
  estiver reduzida.
- **FR-008**: A comunicação MUST ocorrer por Wi-Fi comum com a Internet real. Os serviços externos
  reais (Photon, OpenFreeMap, OpenRouteService em plano gratuito) MUST ser usados.
- **FR-009**: A chave da OpenRouteService MUST vir de variável de ambiente ou de arquivo ignorado
  pelo Git, e MUST NOT ser gravada no repositório, em logs, em relatório nem em captura de tela.
- **FR-010**: O roteiro MUST ser um script Dart em `tool/e2e`, operando os emuladores por ADB
  (comandos `adb`, `uiautomator dump` com seletores de texto e `adb emu geo fix`), reaproveitando
  infraestrutura de `tool/e2e` somente se existir e fizer sentido.
- **FR-011**: O deslocamento do motorista MUST ser simulado por **posicionamento pontual** do
  emulador nos pontos relevantes (partida do motorista, ponto de encontro, destino), de modo a
  exercitar as regras que dependem de proximidade. O roteiro MUST NOT reproduzir o percurso.

### Funcional — estrutura da avaliação

- **FR-012**: A avaliação MUST totalizar 60 ciclos **válidos**, em dois períodos de 30 ciclos
  válidos cada, executados em dias distintos. Cada período é uma invocação separada
  (`--periodo 1`, `--periodo 2`).
- **FR-013**: O total de ciclos executados (soma dos dois períodos) MUST ser limitado a 80. O
  período 1 MUST ter teto de 40 ciclos executados; o período 2 MUST ter teto igual a 80 menos os
  ciclos executados no período 1 (o saldo não usado é repassado). O roteiro MUST ler os ciclos já
  registrados do período 1 ao iniciar o período 2 para calcular esse teto. Ao atingir o teto do
  período sem 30 válidos, o período para e gera relatório parcial. Se o limite for atingido sem 60
  válidos no total, o relatório MUST dizer isso e apresentar o obtido.
- **FR-014**: Antes de cada período o roteiro MUST apagar os dados dos dois aplicativos
  (`adb shell pm clear`), refazer os cadastros e usar identidades descartáveis. Dentro do período,
  identidades e histórico de reputação MUST ser mantidos entre os ciclos.
- **FR-015**: Entre os ciclos de um período o roteiro MUST devolver os aplicativos ao estado inicial
  do fluxo, sem apagar dados.
- **FR-016**: Ciclo com falha atribuída a serviço externo MUST NOT contar como válido e MUST ser
  reposto por novo ciclo (respeitado o limite de 80). Ciclo com falha de outra origem MUST contar
  como válido **e** como falha.

### Funcional — orçamento de tempo e robustez

- **FR-017**: Cada etapa e cada ciclo MUST ter timeout. Ao estourar, a etapa é registrada como
  falha e o roteiro segue para o próximo ciclo. Os valores dos timeouts MUST ser fixados no plano
  e registrados nos metadados do relatório.
- **FR-018**: Cada período MUST ter orçamento máximo de 3 horas. Ao atingi-lo, o roteiro MUST
  parar, gravar os dados e gerar relatório parcial, indicando claramente que é parcial.
- **FR-019**: O roteiro MUST gravar checkpoint a cada ciclo concluído e MUST poder ser retomado
  (`--retomar`) sem refazer ciclos já registrados.
- **FR-020**: O roteiro MUST NOT usar esperas fixas longas; toda espera é por condição (seletor
  presente) com timeout.
- **FR-021**: O roteiro MUST detectar respostas de limite da OpenRouteService (ex.: HTTP 429),
  classificar o ciclo como falha externa e, se o limite diário (cerca de 2000 requisições de rota
  por dia) esgotar, parar o período de forma controlada e gerar relatório parcial.
- **FR-021a**: Uma falha só MUST ser classificada como serviço externo se houver sinal dos
  próprios aplicativos que a atribua a um serviço identificado: mensagem de erro na interface ou
  entrada no `logcat` indicando falha de Photon, OpenFreeMap ou OpenRouteService (incluindo
  resposta de limite, como HTTP 429). O roteiro MUST NOT fazer sondagem independente aos serviços
  (não consome cota nem usa a chave da OpenRouteService). Do `logcat` o roteiro grava apenas a
  classificação e o serviço identificado, nunca as linhas brutas (FR-029). Etapa que falha sem esse
  sinal é classificada segundo as demais regras de FR-026.

### Funcional — observador

- **FR-022**: Um cliente observador independente dos aplicativos MUST assinar os mesmos três
  relays e registrar, para cada evento recebido: relay de origem, kind, id, `created_at` e o
  instante local de recebimento. MUST NOT registrar `content` nem chave privada.
- **FR-023**: O observador MUST estar conectado e inscrito **antes** de cada ciclo começar; o
  roteiro MUST confirmar isso e, se não estiver, não iniciar o ciclo.
- **FR-024**: Os eventos MUST ser associados ao ciclo pela janela de tempo e pelas chaves públicas
  das identidades do ciclo. A documentação MUST registrar que o observador aproxima, mas não mede,
  a chegada do evento ao aplicativo destinatário.

### Funcional — evidências

- **FR-025**: Por ciclo, o roteiro MUST gravar um registro em JSON Lines com: número do ciclo,
  período, instantes de início e fim, resultado de cada etapa, instantes das ações, resultado
  final (sucesso/falha), etapa da falha e classificação da origem da falha.
- **FR-026**: A origem da falha (campo `origem`) MUST ser exatamente uma de: **aplicativo**,
  **relays**, **serviço externo** (informando qual: Photon, OpenFreeMap ou OpenRouteService),
  **ambiente de teste**. As regras de decisão MUST ser definidas no plano e aplicadas de forma
  determinística. Caso em que, após a ação do roteiro, o evento esperado não é observado em
  nenhum dos três relays dentro do timeout: o registro bruto MUST trazer `origem_bruta:
  indeterminada` (não se sabe se o app não publicou ou se os relays não entregaram), `origem`
  MUST ser **aplicativo**, e o relatório MUST listar esses casos à parte (FR-035). A origem
  **relays** só se atribui quando o evento foi observado em pelo menos um relay e, ainda assim, o
  app destinatário não avançou dentro do timeout.
- **FR-027**: O roteiro MUST capturar a tela (`adb exec-out screencap -p`) dos **dois**
  emuladores: (a) no instante de cada falha, junto com o dump da interface; (b) apenas no
  **primeiros ciclos de cada período, até as seis telas existirem** (cada tela é capturada na
  primeira vez em que é atingida), nas telas: solicitação enviada, orçamento recebido,
  motorista a caminho, corrida em andamento, corrida encerrada, avaliação concluída. MUST NOT
  capturar telas de configuração, de cadastro com chaves, de backup ou de exibição de chave
  privada. O dump da interface também MUST ser descartado/filtrado nessas telas. Telas fixas não atingidas até o fim do período MUST ser declaradas na seção 8 do relatório.

### Funcional — latência (descritiva)

- **FR-028**: Latência = intervalo entre a ação do roteiro na interface do emulador (o toque que
  dispara a publicação) e o recebimento do evento correspondente pelo observador, pelo relógio
  da mesma máquina. A tabela abaixo define "ação → evento esperado" a partir do contrato
  (`specs/002-nostr-relay-connection/contracts/nostr-events.md`, kinds 20001 a 20015). Reportar
  **somente** mediana e percentil 95 (nearest-rank), por período e no total, sem intervalo de
  confiança e sem limite de aceitação.

| Ação do roteiro no emulador | App | Evento esperado | Kind |
|-----------------------------|-----|-----------------|------|
| Toque em "Solicitar corrida" | passageiro | Solicitação de corrida | 20001 |
| Toque em "Enviar orçamento" | motorista | Orçamento de corrida | 20002 |
| Toque em "Aceitar" (lista de orçamentos) | passageiro | Aceitação de orçamento | 20003 |
| Posicionamento (`adb emu geo fix`) do motorista no ponto de encontro | motorista | Chegada do motorista | 20007 |
| Toque em "Confirmo que encontrei o motorista" | passageiro | Encontro confirmado | 20008 |
| Posicionamento (`adb emu geo fix`) do motorista no destino | motorista | Chegada ao destino | 20009 |
| Toque em "Confirmar chegada ao destino" | passageiro | Destino confirmado | 20010 |
| Toque em "Confirmar" na avaliação (motorista avalia o passageiro) | motorista | Recibo de avaliação (motorista→passageiro) | 20014 |
| Toque em "Confirmar" na avaliação (passageiro avalia o motorista) | passageiro | Recibo de avaliação (passageiro→motorista) | 20014 |

  **Correção feita no planejamento (registrada por FR-040):** a versão inicial desta tabela
  atribuía 20007 e 20009 a um toque do motorista. Lendo o código do app do motorista
  (`map_screen.dart`: `_talvezNotificarChegada`, `_talvezNotificarChegadaAoDestino`), esses dois
  eventos são publicados **automaticamente** quando a posição recebida fica a ≤ 30 m da origem
  (20007) ou a ≤ 1 km do destino (20009); não existe toque. A "ação" da linha, nesses dois casos, é o
  posicionamento do emulador (FR-011), e a latência medida inclui a entrega da posição ao app e o
  intervalo mínimo de 5 s entre publicações do app. Por isso esses dois tipos são relatados com o
  rótulo "ação = posicionamento", sem somá-los aos de toque no tipo "geral" sem essa distinção. O
  "toque" de FR-028 passa a ser lido como "ação do roteiro no emulador (toque ou posicionamento)".

  Eventos sem toque único que os dispare (localização `20005`, rota `20011`, confirmação de
  recibo `20015`) são observados e contados mas **não** têm latência calculada a partir de ação.
  Kinds `20004`, `20006`, `20012`, `20013` pertencem a recusa/cancelamento/falha de atendimento e
  estão fora do escopo (FR-005); se aparecerem num ciclo, isso é registrado como anomalia. A
  correspondência exata ação↔tela (rótulos de botões) é detalhe do plano.

### Funcional — segurança do roteiro (inegociável)

- **FR-029**: O roteiro MUST NEVER gravar chave privada em arquivo, log ou relatório; MUST NEVER
  gravar o campo `content` dos eventos; MUST NOT pôr chave de API ou credencial no repositório.
  Uma verificação automática MUST procurar esses padrões (chave privada em hex e em `nsec`,
  campo `content`, chave da OpenRouteService) em todos os arquivos de saída e MUST falhar se
  encontrar algum. Qualquer nova dependência MUST ter decisão registrada em `research.md`
  (Princípio III).

### Funcional — relatório

- **FR-030**: Um comando MUST gerar relatório em Markdown e dados em CSV, combinando os períodos.
  Seção 1 — metadados: data, período, versão do código (tag ou hash de commit **dos dois
  aplicativos**), configuração dos emuladores, lista de relays, ciclos executados e válidos,
  indicação de relatório parcial.
- **FR-031**: Seção 2 — resultado do critério de sucesso, aplicado à taxa de falha **calculada sem
  as falhas atribuídas a serviços externos**, com n = ciclos válidos: **ATENDIDO** com 0 falhas;
  **PARCIALMENTE ATENDIDO** com 1 a 3 falhas; **NÃO ATENDIDO** com mais de 3 falhas.
  O veredito é dado **uma única vez, sobre o total** (n = ciclos válidos dos dois períodos, alvo 60).
  Por período o relatório mostra apenas número de falhas, n e taxa, sem o rótulo do critério. Com um
  único período disponível, o veredito sai como "não aplicável (período único)", com as contagens.
- **FR-032**: Seção 3 — taxa de falha **total** (incluindo externas), separada, apenas
  informativa, sem critério.
- **FR-033**: Seção 4 — taxas de sucesso e de falha com intervalo de confiança de Clopper-Pearson
  bilateral de 95%, por período e no total. O cálculo MUST ser validado por testes de unidade com
  valores conhecidos (ex.: 0 falhas em 60 → limite superior ≈ 5,96% = 1 − 0,025^(1/60)) e os
  demais valores MUST ser conferidos por segunda via independente (ex.: scipy, se disponível; se
  não, registrar que não foi possível e como se conferiu).
- **FR-034**: Seção 5 — latência: mediana e P95 (nearest-rank), por período e no total, por tipo
  de evento e geral. Para o kind `20014` há dois tipos de evento, um por sentido (FR-028).
- **FR-035**: Seção 6 — contagem de falhas por origem (aplicativo, relays, serviço externo
  detalhado, ambiente de teste), com lista de cada falha: ciclo, etapa, origem e referência à
  captura de tela. As falhas com `origem_bruta: indeterminada` (FR-026) MUST ser contadas em
  aplicativo e identificadas numa sublista própria.
- **FR-036**: Seção 7 — comportamento por relay: quais relays entregaram os eventos ao observador,
  em cada período; somente descritivo.
- **FR-037**: Seção 8 — limitações da própria execução: ciclos repostos, limites atingidos, partes
  não executadas.
- **FR-038**: O relatório MUST reproduzir exatamente os critérios deste documento, sem acrescentar
  critérios de aceitação de latência, nem outros testes estatísticos.

### Funcional — saída e rastreabilidade

- **FR-039**: Todos os arquivos gerados pela execução MUST ficar em pasta de saída ignorada pelo
  Git (ou claramente separada do código), sem poluir o repositório.
- **FR-040**: Qualquer desvio da especificação durante a execução (ciclo anulado, parâmetro
  alterado, etapa pulada) MUST ser registrado com o motivo, no registro do ciclo e na seção de
  limitações.

### Key Entities

- **Período**: invocação do roteiro (1 ou 2) com meta de 30 ciclos válidos, orçamento de 3 h,
  identidades próprias e checkpoint.
- **Ciclo**: uma passagem pelo fluxo completo; tem número, período, início/fim, etapas, resultado,
  validade (conta ou não como válido) e, se falhou, etapa e origem.
- **Etapa**: passo do fluxo com timeout e resultado (sucesso, falha, tempo esgotado).
- **Identidade descartável**: par de chaves do motorista e do passageiro criado para o período;
  só a chave pública é conhecida do roteiro nos registros.
- **Evento observado**: relay, kind, id, `created_at`, instante local; sem `content`.
- **Falha**: ciclo, etapa, origem (uma das categorias), serviço externo quando aplicável,
  referência às capturas.
- **Evidência**: registro JSON Lines, capturas de tela, dumps, CSV e relatório.
- **Checkpoint**: estado persistido a cada ciclo concluído que permite retomada.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Um único comando inicia um período completo e outro gera o relatório.
- **SC-002**: Um período de 30 ciclos válidos termina em até 3 horas, ou termina com relatório
  parcial explícito; nenhuma execução excede 3 horas por período.
- **SC-003**: Após interrupção em qualquer ponto, `--retomar` conclui o período sem repetir ciclos
  já registrados (0 ciclos duplicados nos dados).
- **SC-004**: Em 100% dos arquivos de saída, a verificação automática não encontra chave privada,
  campo `content` nem chave de API; e falha quando um padrão proibido é plantado de propósito.
- **SC-005**: Toda falha registrada tem exatamente uma origem entre as quatro categorias (com o
  serviço externo informado quando aplicável) e referência a captura dos dois emuladores.
- **SC-006**: Em 100% dos casos o relatório traz as oito seções e os valores conferem com os
  dados brutos; Clopper-Pearson: 0 falhas em 60 resulta em limite superior de 95% bilateral
  de ≈ 5,96% (tolerância de 0,01 ponto percentual), e os valores do relatório coincidem com a
  segunda via independente.
- **SC-007**: O critério de sucesso é computado conforme FR-031 em todos os casos de teste do
  limite (0, 1, 3, 4 falhas).
- **SC-008**: Todos os ciclos contam como válido ou reposto conforme FR-016, com no máximo 80 ciclos
  executados (40 no período 1, saldo no período 2), e o relatório declara explicitamente se foram obtidos os 60 válidos.

## Assumptions

- O observador assina os mesmos três relays, mas com filtros restritos às duas identidades do
  período (`authors` e `#p`), para não registrar eventos nem chaves públicas de terceiros que usam
  o marcador nos relays públicos. É um desvio consciente de "cada evento recebido" (FR-022),
  justificado em `research.md` D4.
- Os dois aplicativos estão instalados nos emuladores com a versão a ser avaliada; o roteiro
  registra o hash de commit de ambos e não os compila nem instala.
- Existe um único passageiro e um único motorista por ciclo, e uma única proposta.
- Os textos de interface usados como seletores são os dos aplicativos na data da execução; mudança
  de textos exige atualizar os seletores (registrado como desvio).
- A máquina hospedeira executa, ao mesmo tempo, o roteiro e o observador (relógio único).
- Os períodos são executados em dias distintos e o limite diário da OpenRouteService é consumido
  por período; o roteiro não tem como medir a cota restante além de detectar respostas de limite.
- Os valores concretos de timeout por etapa/ciclo e as regras de classificação de origem são
  decididos no plano e registrados; esta spec exige que existam, sejam determinísticos e constem
  do relatório.
- O diretório de saída padrão será algo como `build/e2e/` ou pasta equivalente já ignorada pelo
  Git; a escolha final fica no plano (FR-039).
- O app do passageiro (`../passenger`) é projeto independente: esta feature não o modifica.
