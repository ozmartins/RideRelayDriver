---

description: "Task list for 005-formas-pagamento"

---

# Tasks: Formas de pagamento aceitas

**Input**: Design documents from `specs/005-formas-pagamento/`

**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md),
[data-model.md](./data-model.md), [quickstart.md](./quickstart.md)

**Tests**: incluídos, seguindo o mesmo padrão já usado pela feature 003 deste app (dublê de
armazenamento, nunca SQLite real nos testes automatizados — Princípio II por analogia, já aplicado à
validação do cadastro).

**Organization**: tarefas agrupadas por user story do `spec.md` (US1 é P1, US2 é P2).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: pode rodar em paralelo (arquivos diferentes, sem dependência entre si)
- **[Story]**: US1 ou US2, conforme `spec.md`
- Caminhos de arquivo exatos, relativos a `Prototipo/driver/`

## Path Conventions

Projeto mobile único (`lib/`, `test/`), estrutura já em uso pelas features 001–004: `lib/domain/`,
`lib/services/`, `lib/screens/`, espelhados em `test/domain/`, `test/services/`, `test/screens/`.

---

## Phase 1: Setup

Não aplicável — esta feature não introduz nenhuma dependência nova em `pubspec.yaml` (Constitution
Check, Princípio III por vacuidade). Nenhuma tarefa nesta fase.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: entidade nova, extensão de `DriverProfile` e migração de esquema SQLite que as duas user
stories usam

**⚠️ CRITICAL**: nenhuma user story pode começar antes desta fase

- [X] T001 [P] Criar o enum `PaymentMethod` (`cash`/`pix`/`card`), com rótulo de exibição em
      português e o valor persistido de cada opção, em `lib/domain/payment_method.dart`, conforme
      `data-model.md` (D1 de `research.md`)
- [X] T002 [P] Criar o teste de `PaymentMethod` (rótulo de exibição e valor persistido de cada opção)
      em `test/domain/payment_method_test.dart`
- [X] T003 Estender `DriverProfile` com `paymentMethods` (`Set<PaymentMethod>`, obrigatório no
      construtor), atualizando `isValido` (exige `paymentMethods.isNotEmpty`), `copyWith`,
      `toMap`/`fromMap` (serialização por vírgula, D2 de `research.md`, ignorando valor desconhecido
      na decodificação) e `==`/`hashCode`, em `lib/domain/driver_profile.dart`, conforme
      `data-model.md` (depende de T001)
- [X] T004 Atualizar `test/domain/driver_profile_test.dart`: acrescentar `paymentMethods` ao helper
      `perfilValido()` e cobrir `isValido` com conjunto vazio (inválido) e não vazio (válido),
      `toMap`/`fromMap` preservando o conjunto, e igualdade considerando `paymentMethods` (depende de
      T003)
- [X] T005 Subir a versão do banco de `SqfliteCadastroStore` de `1` para `2`: `onCreate` já cria a
      coluna `payment_methods TEXT NOT NULL DEFAULT ''`; `onUpgrade` de 1 para 2 executa o `ALTER
      TABLE` correspondente; `load`/`save` serializam/deserializam `paymentMethods`, em
      `lib/services/sqflite_cadastro_store.dart`, conforme `data-model.md` (D2 de `research.md`)
      (depende de T003)
- [X] T006 Atualizar `test/services/cadastro_store_test.dart`: acrescentar `paymentMethods` ao helper
      `perfilValido()`, e cobrir que uma linha com `payment_methods` vazio (equivalente a uma
      migração da versão 1) é tratada como cadastro corrompido, pela mesma regra já testada para
      outros campos ausentes (depende de T005)

**Checkpoint**: `flutter analyze` e `flutter test` passam com o que existe até aqui; a tela de
cadastro ainda não expõe nenhuma seleção de forma de pagamento — isso é US1

---

## Phase 3: User Story 1 — Escolher as formas de pagamento aceitas no cadastro inicial (Priority: P1) 🎯 MVP

**Goal**: o formulário de cadastro oferece três marcações independentes (Dinheiro, PIX, Cartão);
enviar exige ao menos uma marcada, e o conjunto marcado é persistido junto do restante do cadastro

**Independent Test**: cenários 2 e 3 de `quickstart.md` — marcar Dinheiro e PIX e enviar; tentar
enviar sem marcar nenhuma

### Tests for User Story 1

> Escrever estes testes primeiro; devem falhar até a implementação desta fase

- [X] T007 [P] [US1] Teste de widget: marcar "Dinheiro" e "PIX" (sem "Cartão") e preencher os demais
      campos válidos habilita o envio; ao enviar, o `DriverProfile` recebido por `onSubmit` tem
      `paymentMethods` igual a `{PaymentMethod.cash, PaymentMethod.pix}`, em
      `test/screens/cadastro_screen_test.dart`
- [X] T008 [P] [US1] Teste de widget: com todos os demais campos válidos mas nenhuma forma de
      pagamento marcada, o botão de envio permanece desabilitado, em
      `test/screens/cadastro_screen_test.dart`

### Implementation for User Story 1

- [X] T009 [US1] Acrescentar três `CheckboxListTile` (D3 de `research.md`) à seção "Veículo" do
      formulário — um por `PaymentMethod`, sob um cabeçalho "Formas de pagamento aceitas" — com
      estado próprio (`Set<PaymentMethod> _formasPagamento`, inicializado a partir de
      `widget.initial?.paymentMethods ?? {}`), em `lib/screens/cadastro_screen.dart` (depende de
      T001, T007, T008)
- [X] T010 [US1] Incluir `_formasPagamento.isNotEmpty` em `_formularioValido` e `paymentMethods:
      _formasPagamento` na construção do `DriverProfile` em `_enviar`, em
      `lib/screens/cadastro_screen.dart` (depende de T003, T009)
- [X] T011 [US1] Atualizar o helper `_preencherValido` de `test/screens/cadastro_screen_test.dart`
      para também marcar uma forma de pagamento (ex.: "Dinheiro"), preservando todos os testes já
      existentes da feature 003 que dependem dele para chegar a um formulário válido (depende de
      T009, T010)

**Checkpoint**: US1 funcional e testável de forma independente — cenários 2 e 3 do `quickstart.md`

---

## Phase 4: User Story 2 — Corrigir as formas de pagamento aceitas depois do cadastro (Priority: P2)

**Goal**: a tela de edição pré-preenche as formas já marcadas e permite alterá-las, com a mesma
validação de "ao menos uma" do cadastro inicial

**Independent Test**: cenário 5 de `quickstart.md` — alterar a seleção na edição e confirmar que a
nova seleção é a que aparece na consulta seguinte

### Tests for User Story 2

- [X] T012 [P] [US2] Teste de widget: abrir `CadastroScreen` com `initial` tendo `paymentMethods =
      {PaymentMethod.cash}`, marcar também "Cartão" e salvar; o `DriverProfile` recebido por
      `onSubmit` tem `paymentMethods` igual a `{PaymentMethod.cash, PaymentMethod.card}`, em
      `test/screens/cadastro_screen_test.dart`
- [X] T013 [P] [US2] Teste de widget: abrir `CadastroScreen` com `initial` tendo `paymentMethods =
      {PaymentMethod.pix}`, desmarcar "PIX" sem marcar nenhuma outra, e verificar que o botão de
      salvar fica desabilitado (mesma regra de US1, T008, aplicada à edição), em
      `test/screens/cadastro_screen_test.dart`

### Implementation for User Story 2

- [X] T014 [US2] Confirmar, a partir de T012/T013, que a inicialização de `_formasPagamento` a partir
      de `widget.initial?.paymentMethods` (T009) já cobre a pré-marcação na edição; ajustar
      `lib/screens/cadastro_screen.dart` se os testes encontrarem lacuna (depende de T009, T012,
      T013)

**Checkpoint**: US1 + US2 funcionais juntas

---

## Phase 5: Polish & Cross-Cutting Concerns

**Purpose**: fechar os gates da constituição e a rastreabilidade acadêmica

- [X] T015 Rodar `flutter analyze` — esperado "No issues found!"
- [X] T016 Rodar `flutter test` — esperado todos os testes passando, incluindo os desta feature
- [ ] T017 Executar os cenários 2 a 5 do `quickstart.md` em aparelho/emulador, incluindo o Cenário 4
      (cadastro de uma instalação anterior a esta feature sendo tratado como corrompido após a
      migração de esquema), e registrar os resultados
- [X] T018 Registrar a feature 005 do motorista no `CLAUDE.md` da raiz do repositório, em commit
      separado desta implementação (Padrão de Commits, granularidade)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: não aplicável
- **Foundational (Phase 2)**: bloqueia as duas user stories — nenhuma pode validar nem persistir um
  cadastro sem `PaymentMethod`, `DriverProfile.paymentMethods` ou a migração de esquema
- **US1 (Phase 3)**: depende do Foundational; introduz o estado `_formasPagamento` e a validação de
  envio, reaproveitados por US2
- **US2 (Phase 4)**: depende de US1 (T009, o estado `_formasPagamento` e sua inicialização a partir de
  `widget.initial`)
- **Polish (Phase 5)**: depende de US1 e US2 completas

### Parallel Opportunities

- T001, T002 (Foundational) em paralelo entre si
- T007, T008 (testes de US1) em paralelo entre si, antes de T009–T011
- T012, T013 (testes de US2) em paralelo entre si, depois de T009

---

## Parallel Example: Foundational

```bash
# Em paralelo:
Task: "Criar PaymentMethod em lib/domain/payment_method.dart"
Task: "Criar teste de PaymentMethod em test/domain/payment_method_test.dart"
```

## Parallel Example: User Story 1

```bash
# Testes de US1 em paralelo:
Task: "Teste de seleção múltipla e envio em test/screens/cadastro_screen_test.dart"
Task: "Teste de envio bloqueado sem nenhuma forma marcada em test/screens/cadastro_screen_test.dart"
```

---

## Implementation Strategy

### MVP First (User Story 1)

1. Completar Phase 2 (Foundational)
2. Completar Phase 3 (US1) — marcar formas de pagamento no cadastro inicial
3. **PARAR e VALIDAR**: cenários 2 e 3 de `quickstart.md`
4. US1 sozinha já cumpre o pedido central da feature; US2 é a mesma capacidade de edição que a
   feature 003 já garante para os demais campos, aplicada a este campo novo

### Incremental Delivery

1. Foundational → base pronta (entidade, esquema migrado)
2. US1 → validar cenários 2 e 3 → seleção e validação no cadastro inicial
3. US2 → validar cenário 5 → correção pela tela de edição
4. Polish → validar cenário 4 (migração em aparelho real), gates da constituição, e registrar no
   `CLAUDE.md`

---

## Notes

- [P] = arquivos diferentes, sem dependência entre as tarefas marcadas
- Commits seguem a seção Padrão de Commits da constituição — uma mudança lógica por commit; T018 é
  necessariamente um commit à parte, depois desta implementação
- Verificar que os testes falham antes de implementar (T007, T008, T012, T013)
- Nenhuma tarefa desta feature introduz ou altera evento Nostr, lista de relays ou marcador — nada a
  replicar em `passenger/`
