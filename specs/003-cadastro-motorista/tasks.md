---

description: "Task list for feature 003-cadastro-motorista"
---

# Tasks: Cadastro do Motorista

**Input**: Design documents from `specs/003-cadastro-motorista/`

**Prerequisites**: plan.md ✓, spec.md ✓, research.md ✓, data-model.md ✓, quickstart.md ✓ (sem
`contracts/` — feature sem interface externa, ver Constitution Check do `plan.md`)

**Tests**: por analogia ao Princípio II da constituição (NÃO NEGOCIÁVEL para código de assinatura e
verificação), código que decide aceitar ou rejeitar um dado — validação de UF, cidade, placa, e o
tratamento de cadastro corrompido — MUST ter teste do caso válido e do inválido, executável sem SQLite
real. Por isso as tarefas de teste abaixo são obrigatórias, não opcionais.

**Organization**: agrupadas por user story. Caminhos relativos a `Prototipo/driver/`.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: pode rodar em paralelo (arquivos diferentes, sem dependências pendentes)
- **[Story]**: US1 (preencher o cadastro na primeira abertura), US2 (não ver o formulário de novo),
  US3 (corrigir um dado cadastrado)

---

## Phase 1: Setup

**Purpose**: preparar a dependência de persistência e o dado estático de UF/município antes de
qualquer código de domínio ou de tela

- [X] T001 Adicionar a dependência `sqflite ^2.4.4` ao `pubspec.yaml` com `flutter pub add`, conforme a
  decisão D1 já registrada em `specs/003-cadastro-motorista/research.md`
- [X] T002 [P] Consultar a API de Localidades do IBGE (`/api/v1/localidades/estados/{UF}/municipios`,
  uma vez por UF) e gerar `lib/services/ibge_municipios.dart` com o mapa de município → UF, incluindo
  em comentário a data da consulta (D2 de `research.md`, FR-004)
- [X] T003 [P] Criar a estrutura `test/domain/` em `Prototipo/driver/test/`, ao lado de `test/services/`
  e `test/screens/` já existentes

**Checkpoint**: dependência justificada e instalada, dado de município disponível, estrutura de testes
pronta

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: entidades de domínio e o serviço de persistência — bloqueiam todas as user stories

**⚠️ CRITICAL**: nenhuma user story pode começar antes desta fase

- [X] T004 [P] Criar a entidade `UF` em `lib/domain/uf.dart`, com `sigla` e `nome`, e a lista fixa das
  26 unidades da federação mais o Distrito Federal (FR-003, `data-model.md`)
- [X] T005 [P] Criar a entidade `Municipio` em `lib/domain/municipio.dart`, com `nome` e `uf`, lendo do
  dado gerado em T002
- [X] T006 [P] Criar a entidade `DriverProfile` em `lib/domain/driver_profile.dart` com `nome`, `uf`,
  `cidade`, `marcaVeiculo`, `modeloVeiculo`, `corVeiculo` e `placaVeiculo`, incluindo a normalização de
  placa (caixa alta, sem separador) e a validação pelos dois formatos vigentes — expressão regular
  `^[A-Z]{3}[0-9][A-Z0-9][0-9]{2}$` (FR-005, D3 de `research.md`)
- [X] T007 Escrever os testes de `DriverProfile` em `test/domain/driver_profile_test.dart` cobrindo:
  placa no formato antigo aceita, placa Mercosul aceita (minúscula e com hífen, normalizando para o
  mesmo valor), placa fora dos dois formatos recusada, nome vazio ou só com espaços recusado
  (Princípio II por analogia, caso válido **e** inválido)
- [X] T008 Definir a interface `CadastroStore` em `lib/services/cadastro_store.dart` (`load()` devolve
  `DriverProfile?`, `save(DriverProfile)`), a exceção `CorruptedDriverProfile` (dado presente porém
  inválido — UF fora da lista, ou combinação UF/cidade inconsistente) e a exceção
  `CadastroStoreUnavailable`, seguindo o mesmo padrão de `KeyStore` e `KeyValueStore` (Princípio III)
- [X] T009 Implementar `SqfliteCadastroStore` em `lib/services/sqflite_cadastro_store.dart`, criando a
  tabela `driver_profile` (`CHECK (id = 1)`, `data-model.md`) na primeira abertura do banco e traduzindo
  falha de leitura/gravação em `CadastroStoreUnavailable` — único arquivo que importa `package:sqflite`
  (Princípio III)

**Checkpoint**: domínio e persistência prontos; `flutter analyze`/`flutter test` seguem limpos com o
código já existente das features 001 e 002

---

## Phase 3: User Story 1 - Preencher o cadastro na primeira abertura (Priority: P1)

**Goal**: na primeira abertura, sem cadastro salvo, o aplicativo exibe o formulário antes de qualquer
outra tela e só avança quando todos os campos estiverem válidos.

**Independent Test**: instalar o aplicativo, abri-lo pela primeira vez e verificar que o formulário
aparece antes de qualquer outra tela, e que não é possível avançar com campo obrigatório vazio ou placa
em formato inválido.

- [X] T010 [US1] Escrever os testes de `CadastroStore` em `test/services/cadastro_store_test.dart` com
  um dublê em memória, cobrindo: `load()` devolve `null` quando nada foi salvo, `save()` seguido de
  `load()` devolve o mesmo cadastro, e dado corrompido (UF fora da lista, ou UF/cidade inconsistentes)
  é reportado como `CorruptedDriverProfile` em vez de devolvido como válido (FR-010, Princípio II por
  analogia). Este round-trip único é o que fica automatizado para SC-004; os "5 ciclos" do critério são
  a mesma garantia repetida manualmente no cenário 5 do `quickstart.md` (T023), não uma lacuna de teste
- [X] T011 [US1] Implementar `CadastroScreen` em `lib/screens/cadastro_screen.dart`: campos de nome
  (texto), UF (seleção fixa, T004), cidade (seleção filtrada pela UF escolhida, T005, desabilitada até
  uma UF ser escolhida — FR-004), marca, modelo e cor do veículo (texto) e placa (texto, validada por
  T006); botão de envio desabilitado enquanto houver campo obrigatório vazio ou placa inválida, com o
  motivo indicado junto ao campo (FR-002, FR-006)
- [X] T012 [US1] No `main.dart`, no bootstrap, chamar `CadastroStore.load()`: se devolver `null` (ou
  lançar `CorruptedDriverProfile`, tratado como ausência — FR-010), exibir `CadastroScreen` em modo
  bloqueante, sem navegação de volta, no lugar do `Shell` existente; ao enviar o formulário com sucesso,
  chamar `save()` e então exibir o `Shell` (FR-001, FR-007)
- [X] T013 [US1] Escrever o teste de widget em `test/screens/cadastro_screen_test.dart` verificando: o
  botão de envio permanece desabilitado com campo obrigatório vazio; trocar a UF limpa a cidade
  selecionada (FR-009); o envio com todos os campos válidos chama `save()` exatamente uma vez; e uma
  tentativa de envio com campo obrigatório vazio ou placa inválida **nunca** chama `save()` no dublê de
  `CadastroStore` — SC-003 exige recusa antes de qualquer persistência, não só o botão desabilitado

**Checkpoint**: primeira abertura sem cadastro leva ao formulário, e um envio válido persiste e avança
para a tela principal

---

## Phase 4: User Story 2 - Não ver o formulário de novo depois de cadastrado (Priority: P1)

**Goal**: com o cadastro já salvo, o aplicativo abre direto na tela principal, sem exibir o formulário.

**Independent Test**: completar o cadastro, fechar o aplicativo por completo, reabri-lo e verificar que
a tela principal aparece direto.

**Depende de**: US1 (é o mesmo mecanismo de bootstrap de T012, sob a condição oposta).

- [X] T014 [US2] Acrescentar ao `test/screens/cadastro_screen_test.dart`, ou a um novo teste de
  `main.dart`/bootstrap, o caso em que `CadastroStore.load()` devolve um cadastro existente: o `Shell`
  é exibido diretamente, sem `CadastroScreen`, usando um dublê de `CadastroStore` pré-populado
- [X] T015 [US2] Confirmar em `main.dart` que o bootstrap de T012 já cobre esta condição sem
  duplicação de lógica; se não cobrir, ajustar a decisão para ler o resultado de `load()` uma única vez

**Checkpoint**: reabrir o aplicativo com cadastro existente não exibe o formulário, em nenhum dos casos
testados

---

## Phase 5: User Story 3 - Corrigir um dado cadastrado (Priority: P2)

**Goal**: o motorista consulta e corrige seus dados depois do cadastro inicial, sem reinstalar o
aplicativo.

**Independent Test**: com o cadastro já preenchido, abrir a tela de edição, alterar um campo e verificar
que o novo valor é o que aparece depois de fechar e reabrir o aplicativo.

**Depende de**: US1 (reaproveita `CadastroScreen` e `CadastroStore`).

- [X] T016 [US3] Ajustar `CadastroScreen` (T011) para aceitar um `DriverProfile` inicial opcional: nulo
  no modo de cadastro (T012), preenchido no modo de edição (T017) — mesma validação, mesmo formulário,
  sem duplicar código (Princípio V)
- [X] T017 [US3] Acrescentar a aba "Cadastro" à navegação existente do `Shell` em `main.dart`, ao lado
  de "Eventos", "Relays" e "Identidade", abrindo `CadastroScreen` (já ajustada em T016) em modo de
  edição (com navegação de volta), pré-preenchida com o cadastro atual
- [X] T018 [US3] Ao salvar uma edição válida, chamar `CadastroStore.save()` substituindo o cadastro
  existente (a restrição `CHECK (id = 1)` do esquema garante que não há acúmulo — `data-model.md`) e
  voltar à tela anterior mostrando os novos valores (FR-008)
- [X] T019 [US3] Acrescentar a `test/screens/cadastro_screen_test.dart` os casos do modo de edição:
  campos vêm pré-preenchidos com o cadastro atual; salvar um valor inválido (placa fora do formato, ou
  UF/cidade fora das listas) é recusado com o motivo indicado, e o cadastro anterior permanece
  intacto no dublê de `CadastroStore` (US3 cenário 2)

**Checkpoint**: um dado corrigido na tela de edição é o que aparece na consulta seguinte, sem reinstalar

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: fechar os gates da constituição (seção *Fluxo de Desenvolvimento e Gates*)

- [X] T020 Executar `flutter analyze` em `Prototipo/driver/` até obter `No issues found!` (gate 1)
- [X] T021 [P] Executar `dart format lib test` em `Prototipo/driver/` e confirmar que nada ficou fora do
  padrão
- [X] T022 Executar `flutter test` em `Prototipo/driver/` e confirmar aprovação integral, **sem nenhum
  teste ignorado ou marcado como pendente** (gate 2)
- [X] T023 Executar os 7 cenários de `specs/003-cadastro-motorista/quickstart.md` em emulador/aparelho,
  registrando o resultado de cada um — cenários que falharem devem ser **relatados, não omitidos**
  (gate 3), incluindo a medição do tempo de preenchimento do cenário 2 (SC-001) — Princípio V: número
  apresentado como medição precisa ter sido medido. O cenário 5 é a repetição manual dos "5 ciclos" de
  SC-004; o round-trip em si já está automatizado por T010
- [X] T024 [P] Atualizar `Prototipo/driver/README.md` com o escopo desta feature e a nova dependência
- [X] T025 [P] Atualizar a seção "Protótipo" de `/home/oseias/Documentos/ufsc/TCC/CLAUDE.md` com o novo
  estado do `driver/` — cadastro do motorista, nova aba de navegação, dependência `sqflite`
- [X] T026 Commitar em português descrevendo a mudança de comportamento, não os arquivos tocados (gate
  5, Padrão de Commits) — sem contrapartida em `Prototipo/passenger`, pois esta feature não toca o
  contrato de eventos (Constitution Check do `plan.md`)

---

## Dependencies & Execution Order

```text
Phase 1 (Setup: T001–T003)
        ↓
Phase 2 (Foundational: T004–T009)
        ↓
Phase 3 (US1 · cadastro inicial: T010–T013)
        ↓
Phase 4 (US2 · não repetir o formulário: T014–T015)   ← mesma mecânica de T012, condição oposta
        ↓
Phase 5 (US3 · corrigir depois: T016–T019)             ← reaproveita CadastroScreen e CadastroStore
        ↓
Phase 6 (Polish: T020–T026)
```

- **T001 não depende de nenhum registro pendente**: D1 já está em `research.md` desde a fase de
  planejamento — ao contrário da feature 002, aqui a decisão de dependência foi resolvida antes da
  geração de tarefas, não durante ela.
- **US1 é pré-requisito de US2 e US3**: US2 verifica a condição oposta do mesmo bootstrap que US1
  implementa (T012); US3 reaproveita a tela e o serviço que US1 cria. Nenhuma das duas é independente
  de US1 na prática, embora sejam independentemente **testáveis** uma vez que US1 exista.
- **US2 tem poucas tarefas por construção**: se T012 (US1) for implementada corretamente — decidir a
  tela a partir de um único `load()` —, a condição de US2 já está coberta; as tarefas de US2 são
  sobretudo de verificação, não de código novo.

## Parallel Opportunities

- Phase 1: `T002` e `T003` em paralelo (fontes de dados e estrutura de teste, sem sobreposição).
- Phase 2: `T004` e `T005` em paralelo (entidades sem dependência mútua); `T006` depende de nenhuma das
  duas mas compartilha a fase.
- Phase 6: `T021`, `T024` e `T025` em paralelo.
- Dentro de cada história, teste → implementação é sequencial por construção (Princípio II por
  analogia).

## Implementation Strategy

**MVP**: Phases 1–4 (T001–T015). Ao final, o motorista é obrigado a se cadastrar na primeira abertura e
o aplicativo nunca mais pede de novo — a demonstração central desta feature.

**Incremento 2**: Phase 5 (T016–T019) — edição do cadastro, que evita depender de reinstalação para
corrigir um erro de digitação ou uma troca de veículo.

**Fechamento**: Phase 6 (T020–T026) — os gates da constituição.

**Total**: 26 tarefas (Setup 3, Foundational 6, US1 4, US2 2, US3 4, Polish 7).
