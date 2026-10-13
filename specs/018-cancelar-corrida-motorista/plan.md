# Implementation Plan: Cancelar corrida (motorista)

**Branch**: `master` (commits diretos, sem branch de feature — Padrão de Commits da constituição) | **Date**: 2026-10-04 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/018-cancelar-corrida-motorista/spec.md`

## Summary

Em "Deslocando-se até o passageiro" e em "Em corrida", o mapa do motorista passa a mostrar a ação
"Cancelar corrida". Ela abre uma modal de confirmação (`CancelRideModal`); confirmar volta o estado
a "Aguardando solicitação de corrida", zera e persiste a `ActiveRide`, limpa a rota do mapa (por
consequência de `RideLeg.of` passar a `null`), cessa a publicação de localização e publica ao
passageiro um evento novo, `kind: 20012` ("Corrida cancelada"), definido pela emenda 14 do contrato
e replicado no passageiro na mesma alteração. Diferente da conclusão normal, não abre a modal de
avaliação. Falha de publicação é absorvida (sem fila nem reenvio, como na 017). Nenhuma persistência
nova: o mesmo `RideStateStore` já grava o par estado + corrida. Estritamente do lado do motorista;
o consumo, a modal e o encerramento no app do passageiro são a feature irmã dele (`019`).

## Technical Context

**Language/Version**: Dart 3 / Flutter (versão já fixada no `pubspec.yaml`)

**Primary Dependencies**: `dart_nostr` (assinatura, já em uso) — **nenhuma dependência nova**.

**Storage**: sem mudança — `RideStateStore` (`KeyValueStore`) já persiste `(status, ActiveRide?)`;
cancelar é `save(aguardandoSolicitacao, null)`, o mesmo que a conclusão normal faz.

**Testing**: `flutter_test` com os dublês já existentes (`RelayService`, `RideStateStore`,
`LocationService`, `RouteDistanceService`); nenhum teste toca rede (Princípio II). Assinatura do
`kind: 20012` tem teste próprio; a regra de transição é função pura em `domain/`.

**Target Platform**: Android (sem mudança)

**Project Type**: mobile-app (Flutter, Android apenas)

**Performance Goals**: efeito local imediato (SC-001, ≤ 1 s); publicação só depende da assinatura
local.

**Constraints**: um aviso por corrida (FR-004); sem criptografia e sem dado além dos identificadores
de correlação (D5); modal e botão seguem a seção Identidade Visual da constituição.

**Scale/Scope**: uma corrida ativa; um evento por cancelamento.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Princípio / restrição | Avaliação |
|---|---|
| I. Segredo criptográfico não vaza | PASS. Mesma assinatura por `Identity.privateKey` dos demais kinds; nenhum caminho novo de log nem persistência de segredo. |
| II. Assinatura/verificação nascem com teste | PASS (obrigação). `IdentityService.signRideCancelled` (novo) MUST ter teste de assinatura no padrão de `signArrivalNotice`. |
| III. Dependência exige decisão registrada | PASS por vacuidade — nenhuma dependência nova. |
| IV. Contrato antes do código, replicado | **GATE ATIVO.** A emenda 14 (kind `20012`) MUST ser escrita nas duas cópias do contrato **antes** do código, na mesma alteração; ver `contracts/README.md`. A cópia do passageiro ganha a nova seção e o cabeçalho de procedência atualizado. |
| V. Simplicidade e medição | PASS. Reaproveita `_signCorrelatedEvent`, `RideStateStore` e o descarte de rota por `RideLeg`; sem sinalizador persistido novo nem reenvio (D4). Nada a medir: o evento é vazio. |
| Restrições de Segurança e Privacidade | PASS sem emenda — o evento vai só a relays Nostr, para o passageiro da própria corrida, sem posição nem motivo (D5). |
| Identidade Visual e Design | **APLICA.** Botão e modal novos MUST seguir a seção: modal `ModalTematizado` (ação primária `roxo` 48 px, secundária em texto `roxo`); botão no padrão de "faixa de estado" em alerta (`campo`, raio 16, ícone e texto em `ColorScheme.error`). Sem valor de cor fixo para o erro. |

Pós-design (Phase 1): inalterado; o gate IV é cumprido pelo primeiro item de `tasks.md`.

## Project Structure

### Documentation (this feature)

```text
specs/018-cancelar-corrida-motorista/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/README.md   # texto da emenda 14 a inserir nas duas cópias do contrato
├── checklists/requirements.md
└── tasks.md              # /speckit-tasks
```

### Source Code

```text
lib/
├── domain/
│   ├── driver_ride_status.dart      # + DriverRideRules.canCancelRide
│   └── nostr_event.dart             # + kindRideCancelled = 20012
├── services/identity_service.dart   # + signRideCancelled (usa _signCorrelatedEvent)
└── screens/
    ├── cancel_ride_modal.dart       # NOVO: modal de confirmação (apresentacional)
    └── map_screen.dart              # botão "Cancelar corrida" + _cancelarCorrida/_publicarCancelamento

test/
├── domain/driver_ride_status_test.dart    # + canCancelRide
├── services/identity_service_test.dart    # + signRideCancelled
└── screens/
    ├── cancel_ride_modal_test.dart        # NOVO
    └── map_screen_test.dart               # + cancelar nos dois estados, desistir, ignora tardios, reinício

specs/002-nostr-relay-connection/contracts/nostr-events.md   # + emenda 14 (e a cópia do passageiro)
```

**Structure Decision**: mesma divisão `domain/` + `services/` + `screens/` do restante do app; sem
serviço novo. A inscrição do motorista (`kinds`) não muda — ele só publica este kind.

## Complexity Tracking

Sem violações a justificar.
