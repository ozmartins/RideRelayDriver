# Implementation Plan: Chegada periódica à origem (motorista)

**Branch**: `master` (commits diretos, sem branch de feature) | **Date**: 2026-10-07 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/021-chegada-periodica/spec.md`

## Summary

`_talvezNotificarChegada` (feature 011) deixa de publicar uma única vez, guardando `ActiveRide.arrivalNotified`,
e passa a publicar o `kind: 20007` a cada 5 s enquanto o motorista está em "Deslocando-se até o passageiro" a até
10 m da origem — mesmo critério de tempo do `kind: 20005` (`posicao.capturedAt` contra o instante da última
publicação, estado só em memória). A marca persistida `arrivalNotified` é removida de `ActiveRide` e de
`RideStateStore`. A emenda 20 do contrato (já commitada nas duas cópias) descreve a nova regra; o formato do
evento não muda; o passageiro não muda de código.

## Technical Context

**Language/Version**: Dart 3 / Flutter (versão fixada no `pubspec.yaml`)

**Primary Dependencies**: nenhuma nova — reaproveita `metersBetween`, `IdentityService.signArrivalNotice`,
`RelayService.publish`.

**Storage**: `RideStateStore` perde uma chave (`arrivalNotified`), sem migração: o JSON antigo com a chave é lido e
a chave ignorada.

**Testing**: `flutter_test` com os dublês existentes; nenhum teste toca rede (Princípio II).

**Target Platform**: Android (sem mudança)

**Project Type**: mobile-app (Flutter, Android apenas)

**Performance Goals**: no máximo uma publicação a cada 5 s (SC-001); cálculo de distância por posição, como hoje.

**Constraints**: nunca em claro (emenda 17); falha de publicação absorvida (FR-005).

**Scale/Scope**: uma corrida ativa; ≈ 12 eventos por minuto dentro do raio.

## Constitution Check

| Princípio / restrição | Avaliação |
|---|---|
| I. Segredo criptográfico não vaza | PASS. Nenhum caminho novo de chave, log ou persistência. |
| II. Assinatura/verificação nascem com teste | PASS. Nenhum código de assinatura novo (`signArrivalNotice` já testado); a regra nova tem testes próprios. |
| III. Dependência exige decisão registrada | PASS por vacuidade. |
| IV. Contrato antes do código, replicado | PASS. Emenda 20 nas duas cópias (commit `7c77d9a`), antes do código; conferir por `diff`. |
| V. Simplicidade e medição | PASS. Remove estado persistido que perdeu a função e reaproveita o padrão do `20005`; nada a medir (≤ 1 evento a cada 5 s, já o ritmo do `20005`). |
| Restrições de Segurança e Privacidade | PASS sem emenda — mesmo evento, mesmo destinatário, mesmo conteúdo cifrado. Repetir só aumenta a frequência de um evento já público no relay (sem posição). |
| Identidade Visual e Design | N/A — sem tela nova. |

## Project Structure

```text
specs/021-chegada-periodica/{plan,research,data-model,quickstart,tasks}.md, contracts/README.md, checklists/requirements.md

lib/
├── domain/active_ride.dart            # - arrivalNotified
├── services/ride_state_store.dart     # - chave arrivalNotified
└── screens/map_screen.dart            # _talvezNotificarChegada periódica + _ultimaChegadaEm

test/
├── domain/active_ride_test.dart
├── services/ride_state_store_test.dart
└── screens/map_screen_test.dart       # grupo da 011 reescrito
```

**Structure Decision**: sem arquivo novo em `lib/`; a regra de intervalo vive no `MapScreen`, ao lado do relógio do
`20005`, como a 011 já fazia com a regra anterior.

## Complexity Tracking

Sem violações a justificar.
