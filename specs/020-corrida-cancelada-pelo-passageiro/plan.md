# Implementation Plan: Corrida cancelada pelo passageiro (motorista)

**Branch**: `master` (commits diretos, sem branch de feature — Padrão de Commits da constituição) | **Date**: 2026-10-07 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/020-corrida-cancelada-pelo-passageiro/spec.md`

## Summary

O motorista passa a se inscrever em `kind: 20013` ("Corrida cancelada pelo passageiro", emenda 19 do
contrato, já commitada nas duas cópias). Ao chegar um aviso válido — decifra para `{}`, autor = passageiro
da corrida ativa, `["e", quoteId]` da corrida ativa, estado "Deslocando-se até o passageiro" ou "Em
corrida" — `MapScreen` encerra a corrida no instante do recebimento (mesmo efeito local de
`_cancelarCorrida`: `aguardandoSolicitacao`, `ActiveRide` zerada e persistida, `_sincronizarRota()` limpa
rota e marcador, a publicação de `20005` cessa por consequência do estado) e abre uma modal informativa
com "OK". Sem avaliação, sem publicar nada. Só consumo: nenhuma assinatura nova, nenhuma persistência
nova, nenhuma dependência nova. A contrapartida (botão e publicação) é a feature `023` do passageiro.

## Technical Context

**Language/Version**: Dart 3 / Flutter (versão já fixada no `pubspec.yaml`)

**Primary Dependencies**: nenhuma nova — reaproveita `IdentityService.decryptContent` (via
`_decifraSemDadoProprio`), `RideStateStore`, `EventFeed`, `ModalTematizado`.

**Storage**: sem mudança — `RideStateStore.save(aguardandoSolicitacao, null)`, o mesmo da conclusão e do
cancelamento do próprio motorista.

**Testing**: `flutter_test` com os dublês existentes; nenhum teste toca rede (Princípio II). Cifra de
entrada gerada com a mesma `MessageCipher` dos testes da feature 019 (`recepção cifrada`).

**Target Platform**: Android (sem mudança)

**Project Type**: mobile-app (Flutter, Android apenas)

**Performance Goals**: efeito local imediato (SC-001, ≤ 1 s); sem I/O além da escrita do `RideStateStore`.

**Constraints**: um efeito por evento (`_idsProcessados`); decifrar só depois da assinatura (feito pelo
`EventFeed`); modal segue a seção Identidade Visual da constituição.

**Scale/Scope**: uma corrida ativa; um evento por cancelamento.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Princípio / restrição | Avaliação |
|---|---|
| I. Segredo criptográfico não vaza | PASS. Só decifra com a chave da identidade, pelo caminho já existente; nenhuma chave de conversa nova persistida nem logada. |
| II. Assinatura/verificação nascem com teste | PASS. Nenhum código de assinatura/verificação novo (a verificação é do `EventFeed`; a decifração é a de `decryptContent`). Os testes novos cobrem as conferências de autor, correlação e `{}` desta feature. |
| III. Dependência exige decisão registrada | PASS por vacuidade — nenhuma dependência nova. |
| IV. Contrato antes do código, replicado | PASS. A emenda 19 já está nas duas cópias (commit `747f944`), antes do código; esta feature só consome. Conferir por `diff` no fim. |
| V. Simplicidade e medição | PASS. Reaproveita `_decifraSemDadoProprio`, `_idsProcessados` e o efeito local de `_cancelarCorrida`; sem sinalizador persistido novo (D3). Nada a medir. |
| Restrições de Segurança e Privacidade | PASS sem emenda — evento cifrado ao motorista (2.11.0), sem dado além dos identificadores de correlação. |
| Identidade Visual e Design | **APLICA.** A modal nova MUST usar `ModalTematizado` (ação primária `roxo` 48 px), como `QuoteAcceptedModal`/`CancelRideModal`. |

Pós-design (Phase 1): inalterado.

## Project Structure

### Documentation (this feature)

```text
specs/020-corrida-cancelada-pelo-passageiro/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/README.md   # aponta a emenda 19 (já aplicada); nada a inserir
├── checklists/requirements.md
└── tasks.md              # /speckit-tasks
```

### Source Code

```text
lib/
├── domain/
│   ├── driver_ride_status.dart      # + DriverRideRules.canBeCancelledByPassenger
│   └── nostr_event.dart             # + kindRideCancelledByPassenger = 20013
├── main.dart                        # + o kind em _consumedKinds (inscrição real e EventFeed)
└── screens/
    ├── ride_cancelled_by_passenger_modal.dart   # NOVO: modal informativa (apresentacional)
    └── map_screen.dart              # + ramo em _aoAtualizarFeed, _processarCancelamentoDoPassageiro

test/
├── domain/driver_ride_status_test.dart                       # + canBeCancelledByPassenger
├── screens/ride_cancelled_by_passenger_modal_test.dart       # NOVO
└── screens/map_screen_test.dart                              # + recepção do 20013 (válido e inválidos)
```

**Structure Decision**: mesma divisão `domain/` + `screens/` do restante do app; sem serviço novo e sem
mudança em `IdentityService` (só recebe). A inscrição do motorista ganha um kind.

## Complexity Tracking

Sem violações a justificar.
