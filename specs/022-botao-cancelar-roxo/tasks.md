# Tasks: Botões de cancelar corrida em roxo (motorista)

**Input**: `specs/022-botao-cancelar-roxo/` (spec.md, plan.md, research.md, quickstart.md)
**Tests**: incluídos — a constituição exige `flutter test` integral (gate de conclusão) e SC-003 pede teste automatizado.

## Phase 1: Setup — emenda de constituição (bloqueia o código; commit separado, ANTES do código)

- [x] T001 Emendar `.specify/memory/constitution.md` (driver) para 2.12.0: no bloco Componentes da seção Identidade Visual e Design, trocar "Botão de ação destrutiva" (fundo `ColorScheme.error`) por "Botão de cancelamento de corrida" (largura total, 48 px, raio 16 px, fundo `roxo`, ícone e texto brancos 16 px / 700 — mesma aparência da ação primária); atualizar o Sync Impact Report (motivador: pedido do autor de unificar os botões de cancelar corrida em roxo, o que substitui o componente de ação destrutiva em vermelho que ele próprio havia aprovado na 2.10.0; propagação: espelho, código) e a linha `**Version**`/`Last Amended` (2026-10-07).
- [x] T002 Aplicar o mesmo texto em `../passenger/.specify/memory/constitution.md` (espelho, mesma alteração) e conferir por `diff` dos corpos que ficaram idênticos (salvo nome/escopo/perspectiva).
- [x] T003 Commitar T001+T002 juntos, separados do código, no padrão de commits da constituição (português, verbo no presente, direto na `master`).

**Checkpoint**: emenda commitada; só então seguir.

## Phase 2: Foundational

Nenhuma — o estilo (`IdentidadeVisual.estiloAcaoPrimaria`) já existe em `lib/screens/identidade_visual.dart` e `map_screen.dart` já o importa.

## Phase 3: User Story 1 — Botão de cancelar do mapa em roxo (P1) 🎯 MVP

**Goal**: o botão do cartão de status do mapa fica roxo com texto e ícone brancos (FR-001, FR-002, FR-005).
**Independent Test**: em "Deslocando-se até o passageiro" e em "Em corrida", o botão `botao-cancelar-corrida` resolve fundo `IdentidadeVisual.roxo` e texto/ícone branco.

- [x] T004 [US1] Escrever em `test/screens/map_screen_test.dart`, no grupo "MapScreen — cancelar corrida (feature 018)", um teste (vermelho primeiro) que, nos dois estados, lê o `ButtonStyle` do `FilledButton` de chave `botao-cancelar-corrida` e espera `backgroundColor == IdentidadeVisual.roxo` e `foregroundColor == Colors.white` (resolvidos com `WidgetState` vazio), e que a razão de contraste WCAG entre as duas (luminância relativa) é ≥ 4,5:1 (FR-002, SC-002); confirma também que rótulo "Cancelar corrida", ícone `Icons.close` e a altura de 48 continuam.
- [x] T005 [US1] Em `lib/screens/map_screen.dart`, classe `_CorridaEmAndamento`: trocar o `style: FilledButton.styleFrom(backgroundColor: cores.error, foregroundColor: cores.onError, …)` por `IdentidadeVisual.estiloAcaoPrimaria(altura: 48)`; remover a variável `cores` se ficar sem uso. Não mexer em chave, rótulo, ícone, `SizedBox` nem `onPressed`.
- [x] T006 [US1] Rodar `flutter test test/screens/map_screen_test.dart --plain-name "cancelar corrida"` e confirmar que T004 passa e que os testes de comportamento da 018/020 seguem verdes sem alteração (SC-004).

## Phase 4: User Story 2 — Botão da modal igual ao do mapa (P2)

**Goal**: o botão de confirmação da modal tem as mesmas cores do botão do mapa e assim permanece (FR-003, SC-003).
**Independent Test**: teste que compara as cores resolvidas dos dois botões.

- [x] T007 [P] [US2] Em `test/screens/cancel_ride_modal_test.dart`, acrescentar teste que abre `CancelRideModal`, lê o `ButtonStyle` do `FilledButton` "Cancelar corrida" e espera fundo `IdentidadeVisual.roxo` e texto branco.
- [x] T008 [US2] Em `test/screens/map_screen_test.dart` (mesmo grupo da T004), acrescentar teste que, com a modal aberta a partir do botão do mapa, compara fundo e texto resolvidos do botão do mapa com os do botão `confirmar` da modal e espera igualdade (SC-003).
- [x] T009 [US2] Rodar `flutter test test/screens/cancel_ride_modal_test.dart` e o teste da T008; nenhum código de `lib/screens/cancel_ride_modal.dart` deve precisar mudar (já usa `estiloAcaoPrimaria`).

## Phase 5: Polish

- [x] T010 `flutter analyze` ("No issues found!") e `flutter test` integral, sem teste ignorado.
- [x] T011 Preencher "Estado da validação" de `specs/022-botao-cancelar-roxo/quickstart.md` com a contagem real de testes; marcar a validação em aparelho como **pendente** se não houver aparelho/emulador.
- [x] T012 Commitar o código e os testes (T004–T009) num commit próprio; depois registrar a feature 022 do motorista no `../CLAUDE.md` e commitar à parte (padrão do repositório). Lembrar no registro que a contrapartida do passageiro é feature própria em `passenger/`.

## Dependencies & Order

T001→T002→T003 (emenda primeiro) → T004→T005→T006 (US1) → T007 [P] ∥ T008→T009 (US2; T008 depende de T005 para a cor do mapa já estar roxa) → T010→T011→T012.

## Parallel Example

T007 (arquivo `cancel_ride_modal_test.dart`) pode rodar em paralelo com T004–T006 (outro arquivo).

## Implementation Strategy

MVP = Phase 1 + User Story 1 (emenda + botão do mapa). User Story 2 só adiciona testes que travam a igualdade.
