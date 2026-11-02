# Implementation Plan: Notificar chegada ao passageiro

**Branch**: `master` (commits diretos, sem branch de feature — Padrão de Commits da constituição) | **Date**: 2026-09-21 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/011-notificar-chegada/spec.md`

**Note**: This template is filled in by the `/speckit-plan` command. See `.specify/templates/plan-template.md` for the execution workflow.

## Summary

Enquanto o motorista está "Deslocando-se até o passageiro" (feature 010), o app passa a comparar
cada posição recebida com o ponto de origem da solicitação que gerou a corrida ativa; ao entrar
num raio de 10 m desse ponto, publica um evento de chegada (`kind: 20007`, novo) dirigido ao
passageiro, uma única vez por corrida. Abordagem técnica: reaproveitar a fórmula de distância já
criada na feature 010 (`geo_distance.dart`), e persistir tanto a origem quanto a marca "já avisei"
dentro da própria `ActiveRide` já persistida por `RideStateStore` — sem isso, um reinício do app
dentro do raio de 10 m reenviaria a mensagem, repetindo o mesmo tipo de lacuna que o achado C1 do
`/speckit-analyze` da feature 010 já havia corrigido para a validação do orçamento aceito.

## Technical Context

**Language/Version**: Dart 3 / Flutter (mesma versão já fixada no `pubspec.yaml` do projeto)

**Primary Dependencies**: `dart_nostr` (assinatura, já em uso), `shared_preferences` (via
`KeyValueStore`, já em uso) — nenhuma dependência nova.

**Storage**: `shared_preferences`, através de `RideStateStore` (`ActiveRide` ganha três campos
novos) e `SentQuotesStore` (passa a guardar a origem de cada orçamento enviado, não só o `id`) —
ambos já existentes desde a feature 010, sem novo mecanismo de persistência.

**Testing**: `flutter_test`, com dublês para `KeyValueStore`, `EventFeed`/`RelayService` e
`LocationService` — nenhum teste toca rede, relay ou `SharedPreferences` real (Princípio II).

**Target Platform**: Android (sem mudança)

**Project Type**: mobile-app (Flutter, Android apenas) — mesma estrutura `lib/domain` +
`lib/services` + `lib/screens` da feature 010, sem novo diretório.

**Performance Goals**: mensagem de chegada publicada em até 1 s da atualização de posição que
cruza o raio (SC-001) — mesma ordem de grandeza já medida para outros eventos do protótipo.

**Constraints**: evento publicado sem criptografia, mesma justificativa já registrada para os
kinds 20001-20006 (resposta pública dentro de um fluxo já público entre motorista e passageiro que
já negociaram); nenhum dado além dos identificadores de correlação já usados pelos kinds 20005/20006.

**Scale/Scope**: protótipo de avaliação de viabilidade — sem requisito de escala além do já
estabelecido.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Princípio | Avaliação |
|---|---|
| I. Segredo criptográfico não vaza | PASS. Reaproveita a mesma assinatura por `Identity.privateKey` já testada; nenhum novo caminho de log ou persistência de segredo. |
| II. Assinatura e verificação nascem com teste | PASS (obrigação). O novo evento publicado (`kind: 20007`) MUST ter teste cobrindo a assinatura, mesmo padrão de `signDriverLocation`/`signRideNoLongerAvailable` da feature 010 — registrado como obrigação de `tasks.md`. |
| III. Dependência de terceiros exige decisão registrada | PASS por vacuidade. Nenhuma dependência nova. |
| IV. O contrato de evento vem antes do código | GATE ATIVO — ver Phase 1. Um kind novo (`20007`) é introduzido; o contrato (emenda 09 do `nostr-events.md` único) MUST ser escrito e replicado no passageiro na mesma alteração, mesmo que o passageiro não implemente o consumo agora (mesmo padrão já usado nos kinds anteriores). |
| V. Simplicidade proporcional e rastreabilidade acadêmica | PASS. Reaproveita `ActiveRide`/`RideStateStore`/`SentQuotesStore` já existentes em vez de criar um novo mecanismo de persistência para "já avisei" — decisão registrada em `research.md` (D2). O raio de 10 m vem diretamente do pedido do usuário, não é um valor inventado. |

**Resultado do gate inicial**: PASS, condicionado ao cumprimento do Princípio IV no Phase 1 (contrato escrito e replicado) — sem violação a justificar em Complexity Tracking.

## Project Structure

### Documentation (this feature)

```text
specs/011-notificar-chegada/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md         # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
├── contracts/           # Phase 1 output (/speckit-plan command) — aponta para a emenda no
│                         # contrato único do protótipo, mesmo padrão das features 007/010
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

### Source Code (repository root)

```text
driver/lib/
├── domain/
│   ├── active_ride.dart             # ALTERADO — ganha originLat, originLon, arrivalNotified
│   └── nostr_event.dart             # ALTERADO — nova constante kindArrivalNotice (20007)
├── services/
│   ├── sent_quotes_store.dart       # ALTERADO — passa a guardar a origem de cada quoteId, não
│   │                                 # só o id (originFor, novo método)
│   ├── ride_state_store.dart        # ALTERADO — (de)serializa os três campos novos de ActiveRide
│   └── identity_service.dart        # ALTERADO — signArrivalNotice
└── screens/
    └── map_screen.dart              # ALTERADO — ao enviar orçamento, grava a origem junto do id;
                                      # ao receber posição em "Deslocando-se", compara com a
                                      # origem da corrida ativa e publica a chegada uma única vez

driver/test/
├── domain/
│   └── active_ride_test.dart             # ALTERADO — casos dos três campos novos
├── services/
│   ├── sent_quotes_store_test.dart       # ALTERADO — originFor
│   ├── ride_state_store_test.dart        # ALTERADO — round-trip dos campos novos
│   └── identity_service_test.dart        # ALTERADO — caso do novo kind
└── screens/
    └── map_screen_test.dart              # ALTERADO — cenários da user story

passenger/specs/002-nostr-relay-connection/contracts/nostr-events.md   # ALTERADO (mesma
    # alteração) — réplica idêntica da emenda ao contrato único, Princípio IV
```

**Structure Decision**: mesma estrutura de três camadas já usada desde a feature 003, sem novo
diretório de topo. Nenhum arquivo novo é criado nesta feature — só extensões a arquivos já
existentes da feature 010, por ser uma continuação direta do mesmo fluxo ("Deslocando-se até o
passageiro"). O único artefato fora de `driver/` é a réplica obrigatória do contrato no
`passenger/`, que não implementa consumo nesta feature.

## Complexity Tracking

*Nenhuma violação de princípio a justificar — tabela omitida (Constitution Check: PASS).*
