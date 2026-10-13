# Implementation Plan: Botões de cancelar corrida em roxo (motorista)

**Branch**: `master` (commits diretos, sem branch de feature) | **Date**: 2026-10-07 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/022-botao-cancelar-roxo/spec.md`

## Summary

O botão "Cancelar corrida" do cartão de status do mapa (`_CorridaEmAndamento`, `map_screen.dart`) deixa de usar
`ColorScheme.error`/`onError` e passa a usar `IdentidadeVisual.estiloAcaoPrimaria(altura: 48)` — o mesmo estilo
que o botão de confirmação de `CancelRideModal` já usa. Os dois botões passam a vir da mesma fonte, de modo que
não podem divergir. Antes do código, o componente "Botão de ação destrutiva" da seção Identidade Visual e Design
é emendado nas duas constituições espelho (2.12.0), em commit separado. Sem contrato, sem estado, sem
persistência, sem dependência.

## Technical Context

**Language/Version**: Dart 3 / Flutter (versão fixada no `pubspec.yaml`)

**Primary Dependencies**: nenhuma nova.

**Storage**: N/A.

**Testing**: `flutter_test`; testes de widget que leem o estilo resolvido dos dois botões.

**Target Platform**: Android (sem mudança)

**Project Type**: mobile-app (Flutter, Android apenas)

**Performance Goals**: N/A (troca de cor).

**Constraints**: contraste texto/fundo ≥ 4,5:1 (branco sobre `roxo` ≈ 6,2:1, calculado pela fórmula WCAG);
posição, tamanho, forma, rótulo, ícone e chave `botao-cancelar-corrida` intactos (FR-005).

**Scale/Scope**: 1 widget alterado, 1 emenda de constituição por app.

## Constitution Check

| Princípio / restrição | Avaliação |
|---|---|
| I. Segredo criptográfico não vaza | PASS. Sem material criptográfico. |
| II. Assinatura/verificação nascem com teste | PASS por vacuidade. |
| III. Dependência exige decisão registrada | PASS por vacuidade. |
| IV. Contrato antes do código, replicado | PASS. Nenhum contrato muda; a regra equivalente é a emenda de constituição nas duas apps na mesma alteração. |
| V. Simplicidade e medição | PASS. Reaproveita o estilo existente em vez de criar um novo. |
| Segurança e Privacidade | PASS. Nada trafega. |
| Identidade Visual e Design | **GATE**: o componente "Botão de ação destrutiva" (fundo `ColorScheme.error`) contradiz o pedido. Resolvido emendando-o (2.12.0) antes do código — ver research D1. Sem a emenda o código violaria a constituição. |
| Governance: emenda em commit separado | Será cumprida: emenda → CLAUDE.md → código. |

Pós-design: PASS, condicionado à emenda 2.12.0 ser a primeira das alterações.

## Project Structure

```text
specs/022-botao-cancelar-roxo/{plan,research,data-model,quickstart,tasks}.md, contracts/README.md, checklists/requirements.md

.specify/memory/constitution.md                 # emenda 2.12.0 (driver) — espelhada em ../passenger
lib/screens/map_screen.dart                     # _CorridaEmAndamento: estilo do botão
test/screens/map_screen_test.dart               # cores do botão do mapa; igualdade com o da modal
test/screens/cancel_ride_modal_test.dart        # cores do botão de confirmação
```

**Structure Decision**: nenhum arquivo novo em `lib/`; o estilo vem de `IdentidadeVisual` (`identidade_visual.dart`).

## Complexity Tracking

Sem violações a justificar além da emenda já prevista.
