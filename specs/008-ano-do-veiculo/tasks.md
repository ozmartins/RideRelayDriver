---

description: "Task list for 008-ano-do-veiculo"

---

# Tasks: Ano do veículo no cadastro

**Input**: Design documents from `specs/008-ano-do-veiculo/`

**Tests**: incluídos, mesmo padrão das features 003/005/006.

**Organization**: US1 é P1, US2 é P2.

---

## Phase 1: Setup

Não aplicável — sem dependência nova (Princípio III por vacuidade).

---

## Phase 2: Foundational

- [x] T001 Estender `DriverProfile` com `anoVeiculo` (`int`) e `parseAnoVeiculo(String raw)`
  (D1 de `research.md`); atualizar `isValido`, `copyWith`, `toMap`/`fromMap`, `==`/`hashCode`, em
  `lib/domain/driver_profile.dart`
- [x] T002 Atualizar `test/domain/driver_profile_test.dart`: `perfilValido()` ganha `anoVeiculo`;
  cobrir `parseAnoVeiculo` (válido, vazio, poucos/muitos dígitos, não numérico, antes de 1900,
  depois do corrente+1) e `isValido`/`toMap`/`fromMap`/igualdade com `anoVeiculo` (depende de T001)
- [x] T003 Subir a versão do banco de `SqfliteCadastroStore` de `3` para `4`: `onCreate` cria a
  coluna `ano_veiculo INTEGER NOT NULL DEFAULT 0`; `onUpgrade` de 3 para 4 executa o `ALTER TABLE`,
  empilhado aos passos já existentes, em `lib/services/sqflite_cadastro_store.dart` (depende de
  T001)
- [x] T004 Atualizar `test/services/cadastro_store_test.dart`: `perfilValido()` ganha `anoVeiculo`;
  cobrir que um cadastro com `anoVeiculo` zerado é tratado como corrompido (depende de T003)

**Checkpoint**: `flutter analyze`/`flutter test` passam; formulário ainda não expõe o campo — isso é
US1.

---

## Phase 3: User Story 1 — Informar o ano no cadastro inicial (Priority: P1) 🎯 MVP

### Tests

- [x] T005 [P] [US1] Teste: informar "2018" no campo de ano habilita o envio; `DriverProfile`
  recebido tem `anoVeiculo == 2018`, em `test/screens/cadastro_screen_test.dart`
- [x] T006 [P] [US1] Teste: vazio, "18", "20199", "abcd", "1899", ano corrente+2 mantêm o envio
  desabilitado, em `test/screens/cadastro_screen_test.dart`

### Implementação

- [x] T007 [US1] Acrescenta `TextField` de ano (teclado numérico, `maxLength: 4`) ao formulário,
  em `lib/screens/cadastro_screen.dart` (depende de T005, T006)
- [x] T008 [US1] Inclui a validação de `parseAnoVeiculo` em `_formularioValido` e `anoVeiculo` na
  construção do `DriverProfile` em `_enviar`, em `lib/screens/cadastro_screen.dart` (depende de
  T001, T007)
- [x] T009 [US1] Atualiza `_preencherValido` de `test/screens/cadastro_screen_test.dart` para
  também informar um ano válido, preservando os testes já existentes que dependem dele (depende de
  T007, T008)

**Checkpoint**: US1 completa e testável de forma independente.

---

## Phase 4: User Story 2 — Corrigir o ano depois do cadastro (Priority: P2)

### Tests

- [x] T010 [P] [US2] Teste: edição pré-preenchida com um ano, alterar e salvar reflete o novo
  valor, em `test/screens/cadastro_screen_test.dart`
- [x] T011 [P] [US2] Teste: apagar o campo de ano na edição desabilita salvar, em
  `test/screens/cadastro_screen_test.dart`

### Implementação

- [x] T012 [US2] Confirma que a inicialização do controlador a partir de `widget.initial?.anoVeiculo`
  (T007) já cobre a pré-marcação; ajustar se os testes encontrarem lacuna (depende de T007, T010,
  T011)

**Checkpoint**: US1 + US2 completas.

---

## Phase 5: Polish

- [x] T013 [P] Roda `flutter analyze`
- [x] T014 Roda `flutter test` completo
- [x] T015 Registra a feature no `CLAUDE.md` da raiz, em commit separado (Padrão de Commits)
