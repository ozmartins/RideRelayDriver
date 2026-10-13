# Feature Specification: Cadastro do Motorista

**Feature Branch**: `003-cadastro-motorista`

**Created**: 2026-09-16

**Status**: Draft

**Input**: User description: "Quando o app do motorista for aberto pela primeira vez, deve-se abrir uma
formulário onde o motorista informará o seu nome, a UF de atuação (permitir apenas as unidades da
federação brasileira e o distrito federal), a cidade de atuação (permitir apenas cidades que constem na
lista oficial do IBGE), a marca do veículo, o modelo do veículo, a cor do veículo e a placa do veículo.
Todas as informações solicitadas neste formulário devem ser persistidas em um banco de dados SQLite."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Preencher o cadastro na primeira abertura (Priority: P1)

Como motorista que abre o aplicativo por vez primeira, quero informar meus dados pessoais e os do meu
veículo, para que o aplicativo saiba quem eu sou e o que dirijo antes de eu poder usar o restante das
funções.

**Why this priority**: sem esse cadastro não há como demonstrar, no protótipo, que o motorista está
identificado por um perfil de caronas (nome e veículo), e não apenas por uma chave criptográfica —
condição para qualquer história seguinte que dependa desse perfil.

**Independent Test**: instalar o aplicativo, abri-lo pela primeira vez e verificar que o formulário de
cadastro aparece antes de qualquer outra tela, e que ele não pode ser contornado sem preencher os campos
obrigatórios.

**Acceptance Scenarios**:

1. **Given** o aplicativo recém-instalado, **When** o motorista o abre pela primeira vez, **Then** o
   formulário de cadastro é exibido antes de qualquer outra tela.
2. **Given** o formulário de cadastro aberto, **When** o motorista seleciona uma UF, **Then** o campo de
   cidade passa a oferecer apenas os municípios daquela UF, segundo a lista oficial do IBGE.
3. **Given** o formulário de cadastro aberto, **When** o motorista tenta enviá-lo com algum campo
   obrigatório vazio ou com a placa em formato inválido, **Then** o envio é impedido e o motivo é
   indicado junto ao campo correspondente.
4. **Given** o formulário de cadastro aberto e todos os campos válidos preenchidos (nome, UF, cidade,
   marca, modelo, cor e placa do veículo), **When** o motorista confirma o envio, **Then** os dados são
   guardados e o aplicativo segue para a tela principal.

---

### User Story 2 - Não ver o formulário de novo depois de cadastrado (Priority: P1)

Como motorista que já preencheu o cadastro, quero que o aplicativo abra direto na tela principal nas
vezes seguintes, para não ter que repetir os mesmos dados a cada uso.

**Why this priority**: um formulário que reaparece a cada abertura tornaria o aplicativo inutilizável no
dia a dia e invalidaria a User Story 1 como fluxo de primeira execução.

**Independent Test**: completar o cadastro, fechar o aplicativo por completo, reabri-lo e verificar que a
tela inicial aparece direto, sem o formulário.

**Acceptance Scenarios**:

1. **Given** o cadastro já preenchido em uma execução anterior, **When** o motorista reabre o
   aplicativo, **Then** a tela principal é exibida diretamente, sem o formulário de cadastro.
2. **Given** o cadastro já preenchido, **When** o motorista consulta seus dados, **Then** o aplicativo
   mostra os valores exatamente como foram cadastrados.

---

### User Story 3 - Corrigir um dado cadastrado (Priority: P2)

Como motorista, quero poder corrigir meus dados ou os do meu veículo depois do cadastro inicial — por
exemplo, ao trocar de carro —, para que meu perfil continue correspondendo à realidade sem precisar
reinstalar o aplicativo.

**Why this priority**: é uma consequência direta de existir um cadastro persistido; sem uma forma de
editar, qualquer erro de digitação ou troca de veículo exigiria reinstalar o aplicativo, o que não é uma
alternativa razoável de uso. Não é, porém, pré-condição para demonstrar as User Stories 1 e 2.

**Independent Test**: com o cadastro já preenchido, abrir a tela de edição, alterar um campo e verificar
que o novo valor é o que aparece depois de fechar e reabrir o aplicativo.

**Acceptance Scenarios**:

1. **Given** o cadastro já preenchido, **When** o motorista abre a tela de edição e altera um ou mais
   campos válidos, **Then** os novos valores substituem os anteriores e passam a ser exibidos.
2. **Given** a tela de edição aberta, **When** o motorista tenta salvar um valor inválido (placa fora do
   formato, ou UF/cidade fora das listas oficiais), **Then** a alteração é recusada com o motivo
   indicado, e o valor anterior é preservado.

### Edge Cases

- O que acontece se os dados cadastrados no banco local estiverem corrompidos ou ilegíveis na
  abertura? O aplicativo trata a situação como se nenhum cadastro existisse e volta a exibir o
  formulário — diferente da identidade criptográfica (Princípio I), o cadastro não é segredo
  irrecuperável, e o motorista pode preenchê-lo de novo sem perda de acesso à rede.
- O que acontece se o motorista trocar de UF na tela de edição depois de já ter uma cidade daquela UF
  selecionada? A cidade selecionada é limpa e precisa ser escolhida de novo dentro da nova UF, para
  nunca existir uma combinação UF/cidade inconsistente.
- O que acontece se o aplicativo for desinstalado e reinstalado? Um novo cadastro é solicitado, assim
  como já acontece hoje com a identidade Nostr (FR-004 da feature 002) — consequência que já é
  documentada para o motorista.
- O que acontece com um nome contendo apenas espaços, ou com uma placa digitada em letras minúsculas
  ou com espaços/hífen em posição diferente da esperada? Espaços nas pontas são descartados antes de
  validar; a placa é normalizada para caixa alta e sem separadores antes de comparar com os formatos
  aceitos, então `abc1d23` e `ABC-1D23` são o mesmo valor válido.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: O aplicativo MUST exibir o formulário de cadastro antes de qualquer outra tela quando não
  houver, no aparelho, um cadastro do motorista previamente concluído.
- **FR-002**: O formulário MUST coletar nome do motorista, UF de atuação, cidade de atuação, marca do
  veículo, modelo do veículo, cor do veículo e placa do veículo, todos como campos obrigatórios.
- **FR-003**: O campo de UF MUST aceitar apenas as 26 unidades da federação brasileira e o Distrito
  Federal, apresentados como opções de seleção — nunca texto livre.
- **FR-004**: O campo de cidade MUST aceitar apenas municípios constantes da lista oficial do IBGE
  correspondentes à UF selecionada, apresentados como opções de seleção — nunca texto livre — e MUST
  ficar vazio e desabilitado até uma UF ser escolhida.
- **FR-005**: O aplicativo MUST validar o formato da placa do veículo, aceitando tanto o padrão antigo
  (3 letras, 4 dígitos) quanto o padrão Mercosul (3 letras, 1 dígito, 1 letra, 2 dígitos) vigentes no
  Brasil, e MUST recusar qualquer valor fora desses dois formatos.
- **FR-006**: O aplicativo MUST impedir o envio do formulário enquanto houver campo obrigatório vazio ou
  campo com valor em formato inválido, indicando o motivo junto ao campo correspondente.
- **FR-007**: Ao enviar o formulário com todos os campos válidos, o aplicativo MUST persistir os dados
  no aparelho de forma que sobrevivam ao fechamento e reabertura do aplicativo, e MUST então exibir a
  tela principal.
- **FR-008**: O aplicativo MUST permitir consultar e corrigir, depois do cadastro inicial, qualquer um
  dos dados coletados no formulário, sujeitos às mesmas validações de FR-003 a FR-006.
- **FR-009**: Ao trocar a UF na edição ou no cadastro inicial, o aplicativo MUST limpar a cidade
  selecionada anteriormente, para nunca persistir uma combinação de UF e cidade que não correspondam
  entre si.
- **FR-010**: Se os dados persistidos estiverem corrompidos ou ilegíveis na abertura do aplicativo, o
  aplicativo MUST tratar a situação como ausência de cadastro e exibir o formulário novamente, em vez
  de falhar ou de travar a inicialização.
- **FR-011**: Os dados cadastrados MUST ser persistidos em um banco de dados local estruturado
  (SQLite, por exigência explícita desta feature), e não apenas em preferências de chave-valor —
  decisão de dependência de terceiros a ser registrada conforme o Princípio III da constituição.

### Key Entities

- **Cadastro do motorista**: nome do motorista, UF e cidade de atuação, e os dados do veículo (marca,
  modelo, cor, placa). Existe no máximo um cadastro por instalação do aplicativo; sua ausência é o que
  determina a exibição do formulário. Não é segredo criptográfico — corrupção ou perda leva a solicitar
  o preenchimento de novo, não à perda de acesso à rede.
- **Unidade da federação (UF)**: uma das 26 unidades da federação brasileira mais o Distrito Federal;
  lista fixa e conhecida de antemão, não sujeita a atualização externa.
- **Município**: cidade pertencente a uma UF, conforme a lista oficial do IBGE; o conjunto de municípios
  válidos para seleção depende da UF escolhida no cadastro.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Um motorista que abre o aplicativo pela primeira vez consegue concluir o cadastro em até
  2 minutos, em condições normais de digitação.
- **SC-002**: Em 100% dos casos em que o cadastro já foi concluído, reabrir o aplicativo leva direto à
  tela principal, sem exibir o formulário.
- **SC-003**: 100% das tentativas de envio do formulário com placa fora dos dois formatos aceitos, ou
  com UF/cidade fora das listas oficiais, são recusadas antes de qualquer persistência.
- **SC-004**: Os dados cadastrados permanecem idênticos após 5 ciclos consecutivos de fechar e reabrir
  o aplicativo.
- **SC-005**: Uma correção feita na tela de edição é a que aparece na consulta seguinte, em 100% das
  tentativas, sem exigir reinstalar o aplicativo.

## Assumptions

- O formulário de cadastro é **obrigatório e bloqueante**: o motorista não acessa nenhuma outra tela do
  aplicativo (relays, identidade, eventos) enquanto não concluir o cadastro com todos os campos válidos.
  A descrição da feature não previa um cadastro opcional ou postergável, e um perfil de motorista
  incompleto não tem valor demonstrável para o protótipo.
- O cadastro pode ser **consultado e corrigido** depois de concluído (User Story 3), por meio de uma
  nova tela acessível a partir da navegação já existente do aplicativo (ao lado de "Eventos", "Relays" e
  "Identidade"). Um cadastro permanentemente imutável obrigaria reinstalar o aplicativo para corrigir
  qualquer erro de digitação ou troca de veículo, o que não é uma alternativa razoável.
- A lista de UFs é fixa (as 26 unidades da federação e o Distrito Federal) e embutida no aplicativo, sem
  necessidade de fonte externa.
- A lista de municípios do IBGE é **embutida no aplicativo**, não consultada por uma chamada de rede em
  tempo real. O protótipo já documenta (feature 002) que ausência de rede é condição esperada, e um
  formulário de cadastro que dependesse de rede para validar cidade contradiria FR-016 daquela feature
  (rede é necessária só para as funções de relay). A fonte, o formato e o processo de geração dessa
  lista embutida — e a decisão de dependência de terceiros associada, caso um pacote de terceiros seja
  usado para fornecê-la — são registrados na fase de planejamento (research.md), conforme o Princípio
  III da constituição.
- Marca, modelo e cor do veículo são campos de **texto livre**: diferente de UF e município, não existe
  lista oficial equivalente para marcas/modelos de veículo ou cores, e exigir uma lista fechada aqui
  extrapolaria o que a feature descreve.
- Esta feature não cria nem altera nenhum evento Nostr: o cadastro é dado local do motorista, sem
  contrapartida no contrato de eventos (`specs/002-nostr-relay-connection/contracts/nostr-events.md`),
  e por isso o Princípio IV da constituição (contrato antes do código, replicado no passageiro) não se
  aplica a esta feature. Nada aqui precisa ser replicado em `Prototipo/passenger`.
- SQLite é a tecnologia de persistência **exigida explicitamente** pela descrição da feature, não uma
  escolha desta especificação; a biblioteca de acesso a SQLite a ser usada em Flutter, com sua
  justificativa e alternativas avaliadas, é registrada na fase de planejamento (Princípio III).
