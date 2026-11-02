---

description: "Task list for 006-preco-por-km"

---

# Tasks: Preço padrão por quilômetro

**Input**: Design documents from `specs/006-preco-por-km/`

**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md),
[data-model.md](./data-model.md), [quickstart.md](./quickstart.md)

**Tests**: incluídos, seguindo o mesmo padrão já usado pelas features 003 e 005 deste app (dublê de
armazenamento, nunca SQLite real nos testes automatizados — Princípio II por analogia).

**Organization**: tarefas agrupadas por user story do `spec.md` (US1 é P1, US2 é P2).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: pode rodar em paralelo (arquivos diferentes, sem dependência entre si)
- **[Story]**: US1 ou US2, conforme `spec.md`
- Caminhos de arquivo exatos, relativos a `Prototipo/driver/`

## Path Conventions

Projeto mobile único (`lib/`, `test/`), estrutura já em uso pelas features 001–005: `lib/domain/`,
`lib/services/`, `lib/screens/`, espelhados em `test/domain/`, `test/services/`, `test/screens/`.

---

## Phase 1: Setup

Não aplicável — esta feature não introduz nenhuma dependência nova em `pubspec.yaml` (Constitution
Check, Princípio III por vacuidade). Nenhuma tarefa nesta fase.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: extensão de `DriverProfile` e migração de esquema SQLite que as duas user stories usam

**⚠️ CRITICAL**: nenhuma user story pode começar antes desta fase

- [x] T001 Estender `DriverProfile` com `precoPorKm` (`double`, obrigatório no construtor) e o método
      estático `parsePrecoPorKm(String raw)` (aceita vírgula ou ponto, recusa vazio/`<= 0`/mais de
      duas casas decimais, D1 de `research.md`); atualizar `isValido` (exige `precoPorKm > 0`),
      `copyWith`, `toMap`/`fromMap` e `==`/`hashCode`, em `lib/domain/driver_profile.dart`, conforme
      `data-model.md`
- [x] T002 Atualizar `test/domain/driver_profile_test.dart`: acrescentar `precoPorKm` ao helper
      `perfilValido()`; cobrir `parsePrecoPorKm` (vírgula, ponto, vazio, zero, negativo, três casas
      decimais, texto não numérico) e `isValido`/`toMap`/`fromMap`/igualdade com `precoPorKm`
      (depende de T001)
- [x] T003 Subir a versão do banco de `SqfliteCadastroStore` de `2` para `3`: `onCreate` já cria a
      coluna `preco_por_km REAL NOT NULL DEFAULT 0`; `onUpgrade` de 2 para 3 executa o `ALTER TABLE`
      correspondente, empilhado ao lado do passo já existente de 1 para 2 (feature 005), em
      `lib/services/sqflite_cadastro_store.dart`, conforme `data-model.md` (D2 de `research.md`)
      (depende de T001)
- [x] T004 Atualizar `test/services/cadastro_store_test.dart`: acrescentar `precoPorKm` ao helper
      `perfilValido()`, e cobrir que um cadastro com `precoPorKm` zerado (equivalente a uma migração
      das versões 1/2) é tratado como corrompido, pela mesma regra já testada para formas de
      pagamento ausentes (depende de T003)

**Checkpoint**: `flutter analyze` e `flutter test` passam com o que existe até aqui; a tela de
cadastro ainda não expõe nenhum campo de preço — isso é US1

---

## Phase 3: User Story 1 — Informar o preço padrão por quilômetro no cadastro inicial (Priority: P1) 🎯 MVP

**Goal**: o formulário de cadastro oferece um campo de preço por quilômetro, com texto explicando que
é um valor sugerido e ajustável por corrida; enviar exige um valor válido (> 0, até duas casas
decimais), e o valor é persistido junto do restante do cadastro

**Independent Test**: cenários 2 e 3 de `quickstart.md` — informar um preço válido e enviar; tentar
enviar com preço vazio, zero, negativo ou mal formatado

### Tests for User Story 1

> Escrever estes testes primeiro; devem falhar até a implementação desta fase

- [x] T005 [P] [US1] Teste de widget: informar "2,50" no campo de preço, preencher os demais campos
      válidos, habilita o envio; ao enviar, o `DriverProfile` recebido por `onSubmit` tem
      `precoPorKm == 2.5`, em `test/screens/cadastro_screen_test.dart`
- [x] T006 [P] [US1] Teste de widget: com todos os demais campos válidos, cada um destes valores no
      campo de preço mantém o envio desabilitado: vazio, `"0"`, `"-1"`, `"2,555"`, em
      `test/screens/cadastro_screen_test.dart`
- [x] T007 [P] [US1] Teste de widget: o texto explicando que o preço pode ser alterado por corrida
      (FR-003) está visível no formulário, em `test/screens/cadastro_screen_test.dart`

### Implementation for User Story 1

- [x] T008 [US1] Acrescentar um `TextField` de preço por quilômetro (teclado
      `TextInputType.numberWithOptions(decimal: true)`, D3 de `research.md`) com um `helperText`
      fixo explicando que o valor é sugerido e ajustável por corrida (FR-003), abaixo da seção
      "Formas de pagamento aceitas", em `lib/screens/cadastro_screen.dart` (depende de T005, T006,
      T007)
- [x] T009 [US1] Incluir a validação de `DriverProfile.parsePrecoPorKm` em `_formularioValido` e
      `precoPorKm` (já convertido) na construção do `DriverProfile` em `_enviar`, em
      `lib/screens/cadastro_screen.dart` (depende de T001, T008)
- [x] T010 [US1] Atualizar o helper `_preencherValido` de `test/screens/cadastro_screen_test.dart`
      para também informar um preço válido (ex.: "2,50"), preservando todos os testes já existentes
      das features 003/005 que dependem dele para chegar a um formulário válido (depende de T008,
      T009)

**Checkpoint**: US1 funcional e testável de forma independente — cenários 2 e 3 do `quickstart.md`

---

## Phase 4: User Story 2 — Corrigir o preço padrão por quilômetro depois do cadastro (Priority: P2)

**Goal**: a tela de edição pré-preenche o preço já cadastrado e permite alterá-lo, com a mesma
validação do cadastro inicial

**Independent Test**: cenário 5 de `quickstart.md` — alterar o preço na edição e confirmar que o novo
valor é o que aparece na consulta seguinte

### Tests for User Story 2

- [x] T011 [P] [US2] Teste de widget: abrir `CadastroScreen` com `initial` tendo `precoPorKm = 2.5`,
      alterar o campo para "3,00" e salvar; o `DriverProfile` recebido por `onSubmit` tem
      `precoPorKm == 3.0`, em `test/screens/cadastro_screen_test.dart`
- [x] T012 [P] [US2] Teste de widget: abrir `CadastroScreen` com `initial` tendo `precoPorKm = 2.5`,
      apagar o campo de preço, e verificar que o botão de salvar fica desabilitado (mesma regra de
      US1, T006, aplicada à edição), em `test/screens/cadastro_screen_test.dart`

### Implementation for User Story 2

- [x] T013 [US2] Confirmar, a partir de T011/T012, que a inicialização do controlador de texto do
      preço a partir de `widget.initial?.precoPorKm` (T008) já cobre a pré-marcação na edição;
      ajustar `lib/screens/cadastro_screen.dart` se os testes encontrarem lacuna (depende de T008,
      T011, T012)

**Checkpoint**: US1 + US2 funcionais juntas

---

## Phase 5: Polish & Cross-Cutting Concerns

**Purpose**: fechar os gates da constituição e a rastreabilidade acadêmica

- [x] T014 Rodar `flutter analyze` — esperado "No issues found!"
- [x] T015 Rodar `flutter test` — esperado todos os testes passando, incluindo os desta feature
- [ ] T016 Executar os cenários 2 a 5 do `quickstart.md` em aparelho/emulador, incluindo o Cenário 4
      (cadastro de uma instalação anterior a esta feature sendo tratado como corrompido após a
      migração de esquema), e registrar os resultados
- [x] T017 Registrar a feature 006 do motorista no `CLAUDE.md` da raiz do repositório, em commit
      separado desta implementação (Padrão de Commits, granularidade)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: não aplicável
- **Foundational (Phase 2)**: bloqueia as duas user stories — nenhuma pode validar nem persistir um
  cadastro sem `precoPorKm`/`parsePrecoPorKm` ou a migração de esquema
- **US1 (Phase 3)**: depende do Foundational; introduz o controlador de texto do preço e a validação
  de envio, reaproveitados por US2
- **US2 (Phase 4)**: depende de US1 (T008, o controlador e sua inicialização a partir de
  `widget.initial`)
- **Polish (Phase 5)**: depende de US1 e US2 completas

### Parallel Opportunities

- T005, T006, T007 (testes de US1) em paralelo entre si, antes de T008–T010
- T011, T012 (testes de US2) em paralelo entre si, depois de T008

---

## Parallel Example: User Story 1

```bash
# Testes de US1 em paralelo:
Task: "Teste de preço válido habilitando o envio em test/screens/cadastro_screen_test.dart"
Task: "Teste de preço inválido desabilitando o envio em test/screens/cadastro_screen_test.dart"
Task: "Teste do texto explicativo visível em test/screens/cadastro_screen_test.dart"
```

---

## Implementation Strategy

### MVP First (User Story 1)

1. Completar Phase 2 (Foundational)
2. Completar Phase 3 (US1) — informar preço no cadastro inicial
3. **PARAR e VALIDAR**: cenários 2 e 3 de `quickstart.md`
4. US1 sozinha já cumpre o pedido central da feature; US2 é a mesma capacidade de edição que as
   features 003/005 já garantem para os demais campos, aplicada a este campo novo

### Incremental Delivery

1. Foundational → base pronta (entidade estendida, esquema migrado)
2. US1 → validar cenários 2 e 3 → preço informado e validado no cadastro inicial
3. US2 → validar cenário 5 → correção pela tela de edição
4. Polish → validar cenário 4 (migração em aparelho real), gates da constituição, e registrar no
   `CLAUDE.md`

---

## Notes

- [P] = arquivos diferentes, sem dependência entre as tarefas marcadas
- Commits seguem a seção Padrão de Commits da constituição — uma mudança lógica por commit; T017 é
  necessariamente um commit à parte, depois desta implementação
- Verificar que os testes falham antes de implementar (T005–T007, T011, T012)
- Nenhuma tarefa desta feature introduz ou altera evento Nostr, lista de relays ou marcador — nada a
  replicar em `passenger/`
