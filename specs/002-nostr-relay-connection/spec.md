# Feature Specification: Conexão do Motorista com Relays Nostr

**Feature Branch**: `002-nostr-relay-connection`

**Created**: 2026-09-15

**Status**: Draft

**Input**: User description: "Conexão do aplicativo do motorista com relays Nostr: estabelecer conexão com um ou mais relays, publicar e receber eventos assinados, e registrar a escolha da biblioteca dart_nostr com sua justificativa."

## Clarifications

### Session 2026-09-16 — emenda 01 ao contrato de eventos

- Decisão: o evento de teste passa a carregar o marcador `tcc-ufsc-caronas`, e a inscrição nos relays
  passa a filtrar por esse marcador. Origem: proposta da sessão que mantém `Prototipo/passenger`,
  corroborada por medição nos dois lados — sem o filtro, o aplicativo recebe o tráfego social público
  da rede inteira (125 eventos alheios em 90 s no motorista), o que tornava a recepção do próprio
  evento inverificável na prática e transformava a "rajada" de SC-006 no caminho normal.

### Session 2026-09-15

- Q: O que entra no escopo de identidade (chaves Nostr) nesta feature? → A: Chave gerada uma vez e persistida no aparelho, mantendo a mesma identidade entre execuções
- Q: Como os relays são escolhidos nesta feature? → A: Lista inicial padrão embutida + tela para o usuário adicionar e remover relays, com a lista persistida

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Conectar-se a relays e enxergar o estado da conexão (Priority: P1)

Como motorista, quero que o aplicativo se conecte aos relays configurados ao ser aberto e me mostre
claramente quais estão conectados, para saber se estou ou não alcançável pela rede de caronas.

**Why this priority**: sem conexão estabelecida e observável, nenhuma troca de eventos é possível e
nenhuma das demais histórias tem como ser validada. É também o dado central da avaliação de viabilidade
do TCC: se conectar de forma confiável a relays públicos é ou não praticável em um app móvel.

**Independent Test**: abrir o aplicativo com a lista padrão de relays e verificar que o estado de cada
relay é exibido e evolui de "conectando" para "conectado" ou "falhou", sem travar a interface.

**Acceptance Scenarios**:

1. **Given** o aplicativo instalado e com conectividade de rede, **When** o motorista o abre,
   **Then** cada relay da lista aparece com seu estado de conexão atualizado em tempo real.
2. **Given** um relay inalcançável na lista, **When** a conexão falha, **Then** apenas aquele relay é
   marcado como indisponível, com o motivo resumido, e os demais permanecem conectados.
3. **Given** o aparelho sem conectividade de rede, **When** o aplicativo é aberto, **Then** é exibida
   uma mensagem explicando a ausência de rede, sem travamento nem erro técnico cru.
4. **Given** o aplicativo conectado, **When** o motorista o coloca em segundo plano e retorna,
   **Then** o estado exibido reflete a situação real das conexões naquele momento.

---

### User Story 2 - Ter uma identidade Nostr própria e estável (Priority: P1)

Como motorista, quero que o aplicativo tenha uma identidade criptográfica própria, criada uma única vez e
mantida entre execuções, para que meus eventos sejam sempre atribuídos a mim e verificáveis por qualquer
pessoa na rede.

**Why this priority**: sem identidade estável não é possível assinar eventos nem ser reconhecido pelo
passageiro entre sessões; publicar e receber (US3) dependem dela.

**Independent Test**: abrir o aplicativo, anotar a identidade pública exibida, fechar completamente,
reabrir e verificar que a identidade é exatamente a mesma.

**Acceptance Scenarios**:

1. **Given** o aplicativo aberto pela primeira vez, **When** a inicialização ocorre, **Then** uma
   identidade é criada e sua chave pública é exibida ao motorista em formato legível e copiável.
2. **Given** o aplicativo já usado antes, **When** ele é reaberto, **Then** a mesma identidade é
   recuperada, sem gerar uma nova.
3. **Given** a identidade existente, **When** o motorista consulta a tela de identidade, **Then** a
   chave privada **não** é exibida em tela por padrão.
4. **Given** o aplicativo desinstalado e reinstalado, **When** ele é aberto, **Then** uma nova identidade
   é criada, e essa consequência está documentada para o usuário.

---

### User Story 3 - Publicar um evento assinado e recebê-lo de volta (Priority: P1)

Como motorista, quero publicar um evento assinado nos relays conectados e ver os eventos que chegam por
eles, para comprovar que a comunicação de ida e volta funciona sem nenhum servidor próprio.

**Why this priority**: é a prova de conceito central do trabalho — se a publicação e a recepção não
funcionam, a hipótese do TCC não se sustenta. Depende de US1 e US2.

**Independent Test**: publicar um evento de teste pelo aplicativo e observar que ele retorna pela
inscrição de recepção, exibido na lista de eventos recebidos, com origem identificada.

**Acceptance Scenarios**:

1. **Given** ao menos um relay conectado e a identidade criada, **When** o motorista publica um evento de
   teste, **Then** o aplicativo informa por relay se a publicação foi aceita ou recusada.
2. **Given** uma inscrição ativa de eventos, **When** um evento correspondente chega de um relay,
   **Then** ele é exibido na lista com autor, horário e conteúdo.
3. **Given** um evento recebido com assinatura inválida, **When** ele chega, **Then** é descartado e não
   aparece na lista.
6. **Given** um evento sem o marcador do protótipo, **When** o relay o entrega mesmo assim, **Then** ele
   é descartado e não aparece na lista.
4. **Given** o mesmo evento entregue por dois relays diferentes, **When** ambos chegam, **Then** ele é
   exibido uma única vez.
5. **Given** nenhum relay conectado, **When** o motorista tenta publicar, **Then** a ação é impedida com
   explicação, sem perda silenciosa do conteúdo.

---

### User Story 4 - Gerenciar a lista de relays (Priority: P2)

Como motorista, quero adicionar e remover relays da minha lista, para testar diferentes provedores e não
depender de um conjunto fixo escolhido pelo desenvolvedor.

**Why this priority**: é o que permite avaliar comportamento em relays distintos — dado relevante para a
análise de viabilidade —, mas o aplicativo já é demonstrável com a lista padrão.

**Independent Test**: adicionar um relay novo, confirmar que ele passa a ser usado, removê-lo, fechar e
reabrir o aplicativo, verificando que a lista persistiu.

**Acceptance Scenarios**:

1. **Given** a tela de relays, **When** o motorista adiciona um endereço de relay válido, **Then** o
   aplicativo tenta conectar-se a ele e passa a exibi-lo na lista.
2. **Given** um endereço inválido ou duplicado, **When** o motorista tenta adicioná-lo, **Then** a adição
   é recusada com explicação, e a lista permanece inalterada.
3. **Given** um relay na lista, **When** o motorista o remove, **Then** a conexão é encerrada e ele deixa
   de receber ou publicar eventos por ele.
4. **Given** alterações feitas na lista, **When** o aplicativo é fechado e reaberto, **Then** a lista
   alterada é restaurada.
5. **Given** a lista esvaziada pelo motorista, **When** ele abre a tela principal, **Then** o aplicativo
   explica que nenhum relay está configurado e oferece restaurar a lista padrão.

### Edge Cases

- Como o sistema se comporta quando um relay aceita a conexão mas nunca responde? Deve haver limite de
  espera, após o qual o relay é marcado como indisponível.
- O que acontece quando a rede cai durante o uso? As conexões devem ser marcadas como perdidas e
  reestabelecidas quando a rede voltar, sem intervenção manual.
- O que acontece quando a rede alterna entre Wi-Fi e dados móveis? A reconexão deve ocorrer sem
  duplicar eventos já recebidos.
- Como o sistema se comporta quando um relay exige pagamento ou autenticação para publicar? A recusa
  deve ser reportada por relay, sem sugerir que a publicação foi bem-sucedida.
- O que acontece quando um relay envia um volume muito grande de eventos? A interface deve permanecer
  responsiva, limitando o que é mantido em memória.
- O que acontece se o armazenamento seguro da identidade estiver indisponível no aparelho? O aplicativo
  deve informar o problema em vez de gerar silenciosamente uma identidade nova a cada abertura.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: O aplicativo MUST conectar-se, na inicialização, a todos os relays da lista configurada.
- **FR-002**: O aplicativo MUST exibir o estado de cada relay (conectando, conectado, indisponível) e
  atualizá-lo em tempo real.
- **FR-003**: Falha em um relay MUST NOT impedir o funcionamento com os demais.
- **FR-004**: O aplicativo MUST criar uma identidade criptográfica na primeira execução e reutilizá-la
  nas execuções seguintes.
- **FR-005**: A chave privada MUST ser guardada no armazenamento protegido do aparelho e MUST NOT ser
  exibida por padrão, registrada em log ou enviada a qualquer relay.
- **FR-006**: O aplicativo MUST exibir a chave pública da identidade em formato legível e copiável.
- **FR-007**: O aplicativo MUST publicar eventos assinados com a identidade do motorista e MUST reportar,
  por relay, se a publicação foi aceita ou recusada.
- **FR-008**: O aplicativo MUST receber eventos dos relays por inscrição e exibi-los com autor, horário
  e conteúdo.
- **FR-009**: O aplicativo MUST descartar eventos cuja assinatura não seja válida.
- **FR-010**: O aplicativo MUST exibir uma única vez um evento entregue por mais de um relay.
- **FR-011**: O aplicativo MUST permitir adicionar e remover relays, validando o endereço informado e
  rejeitando duplicados.
- **FR-012**: A lista de relays MUST ser persistida no aparelho e restaurada ao reabrir o aplicativo.
- **FR-013**: O aplicativo MUST oferecer restaurar a lista padrão de relays quando a lista estiver vazia.
- **FR-014**: O aplicativo MUST reconectar-se automaticamente aos relays após perda e retorno de rede.
- **FR-015**: O aplicativo MUST tratar ausência de rede e falhas de relay com mensagens compreensíveis,
  sem exibir erro técnico cru nem travar.
- **FR-016**: O aplicativo MUST declarar a permissão de acesso à rede necessária para uso em produção.
- **FR-017**: O trabalho MUST registrar, em documento versionado junto à feature, a biblioteca Nostr
  adotada, as alternativas avaliadas e os critérios que levaram à escolha — insumo direto da análise de
  viabilidade do TCC.
- **FR-018**: Os eventos publicados MUST carregar o marcador do protótipo definido no contrato, e a
  inscrição nos relays MUST filtrar por esse marcador, em vez de pedir todos os eventos do kind.
- **FR-019**: O aplicativo MUST descartar evento recebido que não traga o marcador, mesmo que o relay o
  entregue — o filtro pedido na inscrição não pode ser tratado como garantia.

### Key Entities

- **Identidade do motorista**: par de chaves criptográficas; a chave pública identifica o motorista na
  rede, a privada assina os eventos. Criada uma vez, persistida, nunca compartilhada.
- **Relay**: endereço de um servidor da rede Nostr, com estado de conexão e origem (padrão ou adicionado
  pelo motorista). Vários relays coexistem de forma independente.
- **Evento**: mensagem assinada trafegada pelos relays, com identificador próprio, autor, horário,
  tipo e conteúdo. O identificador é o que permite reconhecer duplicatas entre relays.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Com a lista padrão e rede disponível, ao menos um relay atinge o estado "conectado" em até
  5 segundos após a abertura do aplicativo, em 9 de 10 tentativas.
- **SC-002**: Um evento publicado pelo motorista é recebido de volta pela inscrição do próprio
  aplicativo em até 5 segundos, em 9 de 10 tentativas.
- **SC-003**: Com um relay inalcançável na lista, o aplicativo continua publicando e recebendo pelos
  demais em 100% das tentativas.
- **SC-004**: A identidade permanece idêntica após 5 ciclos consecutivos de fechar e reabrir o
  aplicativo.
- **SC-005**: Alterações na lista de relays sobrevivem a 100% dos reinícios do aplicativo.
- **SC-006**: A interface permanece responsiva (sem congelamento perceptível) ao receber uma rajada de
  ao menos 100 eventos.
- **SC-009**: Com a inscrição filtrada pelo marcador, ao menos 95% dos eventos exibidos na lista são do
  protótipo — e não tráfego social alheio —, medido em uma sessão de 2 minutos com os relays padrão.
- **SC-007**: Nenhuma chave privada aparece em tela, em log do aplicativo ou em tráfego enviado aos
  relays, verificado por inspeção.
- **SC-008**: O documento de decisão da biblioteca lista ao menos duas alternativas avaliadas e os
  critérios aplicados.

## Assumptions

- A biblioteca **`dart_nostr` (versão ^10.0.1)** já foi adicionada ao projeto por decisão explícita do
  autor e é a base desta feature; a justificativa formal e as alternativas avaliadas serão registradas no
  documento de pesquisa da fase de planejamento, atendendo FR-017.
- Esta feature reabre decisões da feature `001-flutter-app-base`, que declarava ausência de dependências
  de terceiros e proibia acesso a rede: ambas as restrições valiam apenas para a base vazia e são
  superadas aqui de forma deliberada.
- O evento publicado nesta etapa é um **evento de teste genérico**, não um formato de domínio de caronas.
  Os formatos de oferta, solicitação e mensagem entre pares são objeto de features posteriores e precisam
  ser idênticos nas apps do motorista e do passageiro.
- A lista padrão de relays será composta por relays públicos gratuitos e sem exigência de autenticação,
  escolhidos na fase de planejamento.
- Criptografia de conteúdo entre pares (mensagens privadas) está fora do escopo: os eventos desta etapa
  são públicos e servem apenas para comprovar conectividade.
- A app do passageiro não é necessária para validar esta feature; o teste de ida e volta é feito com o
  próprio motorista publicando e recebendo.
- O alvo continua sendo exclusivamente Android, conforme decidido na feature 001.
- Assume-se conectividade de internet intermitente como cenário realista de uso em mobilidade urbana.
- **Terminologia**: "assinatura" é usada exclusivamente no sentido criptográfico (assinar e verificar um
  evento). O ato de pedir a um relay que envie eventos correspondentes a um filtro é chamado de
  **"inscrição"** (*subscription*), nunca de assinatura. A distinção é deliberada: em português os dois
  sentidos colidem, e confundi-los levaria a tratar recepção como se fosse verificação criptográfica.
