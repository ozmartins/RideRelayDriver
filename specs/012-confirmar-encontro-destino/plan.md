# Implementation Plan: Confirmar encontro e notificar chegada ao destino

**Branch**: `master` (commits diretos, sem branch de feature — Padrão de Commits da constituição) | **Date**: 2026-09-21 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/012-confirmar-encontro-destino/spec.md`

**Note**: This template is filled in by the `/speckit-plan` command. See `.specify/templates/plan-template.md` for the execution workflow.

## Summary

O motorista ganha um terceiro estado, "Em corrida", entre "Deslocando-se até o passageiro" e o
retorno a "Aguardando solicitação de corrida": passa a consumir a confirmação de encontro do
passageiro (transição para "Em corrida"), a detectar a proximidade de 5 m do destino durante esse
estado e publicar um aviso de chegada, e a consumir a confirmação de destino do passageiro
(retorno a "Aguardando", encerrando a corrida). Introduz três kinds novos no contrato único do
protótipo (emenda 11), reaproveitando integralmente os padrões já estabelecidos pelas features
010/011: `ActiveRide`/`RideStateStore` para o novo estado e os dados por-corrida, `SentQuotesStore`
para capturar a coordenada de destino no envio do orçamento (mesmo mecanismo já usado para a
origem), e `geo_distance.dart` para a checagem de proximidade.

## Technical Context

**Language/Version**: Dart 3 / Flutter (mesma versão já fixada no `pubspec.yaml` do projeto)

**Primary Dependencies**: `dart_nostr` (assinatura, já em uso), `shared_preferences` (via
`KeyValueStore`, já em uso) — nenhuma dependência nova.

**Storage**: `shared_preferences`, através de `RideStateStore` (`ActiveRide` ganha campos novos) e
`SentQuotesStore` (passa a guardar também o destino de cada orçamento enviado) — ambos já
existentes desde as features 010/011.

**Testing**: `flutter_test`, com dublês para `KeyValueStore`, `EventFeed`/`RelayService` e
`LocationService` — nenhum teste toca rede, relay ou `SharedPreferences` real (Princípio II).

**Target Platform**: Android (sem mudança)

**Project Type**: mobile-app (Flutter, Android apenas) — mesma estrutura das features 010/011.

**Performance Goals**: cada transição de estado e cada publicação automática desta feature ocorre
em até 1 s do evento que a dispara (SC-001, SC-002, SC-004) — mesma ordem de grandeza já medida
para os demais eventos do protótipo.

**Constraints**: eventos publicados sem criptografia, mesma justificativa já registrada para os
kinds anteriores; nenhum dado além dos identificadores de correlação já usados pelos kinds
20005-20007.

**Scale/Scope**: protótipo de avaliação de viabilidade — sem requisito de escala além do já
estabelecido.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Princípio | Avaliação |
|---|---|
| I. Segredo criptográfico não vaza | PASS. Reaproveita a mesma assinatura por `Identity.privateKey` já testada; nenhum novo caminho de log ou persistência de segredo. |
| II. Assinatura e verificação nascem com teste | PASS (obrigação). `IdentityService.signDestinationArrival` (novo) MUST ter teste cobrindo a assinatura, mesmo padrão de `signArrivalNotice`/`signRideNoLongerAvailable`. A decisão de agir (ou não) sobre uma confirmação de encontro/destino recebida — por analogia às decisões de aceitar/descartar já cobertas por teste nas features 010/011 — MUST ter teste cobrindo os casos aceitos e ignorados. Registrado como obrigação de `tasks.md`. |
| III. Dependência de terceiros exige decisão registrada | PASS por vacuidade. Nenhuma dependência nova. |
| IV. O contrato de evento vem antes do código | GATE ATIVO — ver Phase 1. Três kinds novos (confirmação de encontro, chegada ao destino, confirmação de destino) MUST ser especificados na emenda 11 do `nostr-events.md` único, replicada no passageiro na mesma alteração — mesmo quando dois deles são publicados pelo passageiro (precedente já aceito: `kind: 20005`, definido pela feature 010 do motorista, publicado só por ele). |
| V. Simplicidade proporcional e rastreabilidade acadêmica | PASS. Reaproveita `ActiveRide`/`RideStateStore`/`SentQuotesStore`/`geo_distance.dart` já existentes, sem introduzir nenhum mecanismo novo de persistência ou cálculo — só extensão dos já existentes (decisão registrada em `research.md`, D2). O raio de 5 m vem diretamente do pedido do usuário. Nenhuma entidade de domínio nova para as confirmações recebidas: a correlação por `quoteId` já é suficiente, sem repetir o padrão de `QuoteAccepted` (que existe porque, ao contrário daqui, cria a `ActiveRide` pela primeira vez) — decisão registrada em `research.md` (D3). |

**Resultado do gate inicial**: PASS, condicionado ao cumprimento do Princípio IV no Phase 1 (contrato escrito e replicado) — sem violação a justificar em Complexity Tracking.

## Project Structure

### Documentation (this feature)

```text
specs/012-confirmar-encontro-destino/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md         # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
├── contracts/           # Phase 1 output (/speckit-plan command) — aponta para a emenda no
│                         # contrato único do protótipo, mesmo padrão das features 010/011
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

### Source Code (repository root)

```text
driver/lib/
├── domain/
│   ├── driver_ride_status.dart      # ALTERADO — novo valor emCorrida + regras de transição
│   └── nostr_event.dart             # ALTERADO — kindMeetingConfirmed (20008),
│                                     # kindDestinationArrival (20009),
│                                     # kindDestinationConfirmed (20010)
│   └── active_ride.dart             # ALTERADO — destinationLat, destinationLon,
│                                     # destinationArrivalNotified
├── services/
│   ├── sent_quotes_store.dart       # ALTERADO — passa a guardar também o destino de cada
│   │                                 # quoteId, não só a origem
│   ├── ride_state_store.dart        # ALTERADO — (de)serializa os campos novos de ActiveRide
│   └── identity_service.dart        # ALTERADO — signDestinationArrival
└── screens/
    └── map_screen.dart              # ALTERADO — grava destino ao enviar orçamento; consome
                                      # confirmação de encontro (→ Em corrida) e de destino (→
                                      # Aguardando); checa proximidade do destino durante Em
                                      # corrida e publica a chegada

driver/test/
├── domain/
│   ├── driver_ride_status_test.dart      # ALTERADO
│   └── active_ride_test.dart             # ALTERADO
├── services/
│   ├── sent_quotes_store_test.dart       # ALTERADO
│   ├── ride_state_store_test.dart        # ALTERADO
│   └── identity_service_test.dart        # ALTERADO
└── screens/
    └── map_screen_test.dart              # ALTERADO — cenários das três user stories

passenger/specs/002-nostr-relay-connection/contracts/nostr-events.md   # ALTERADO (mesma
    # alteração) — réplica idêntica da emenda ao contrato único, Princípio IV
```

**Structure Decision**: mesma estrutura de três camadas já usada desde a feature 003, sem novo
diretório de topo e sem nenhum arquivo novo — só extensões a arquivos já existentes das features
010/011, por ser uma continuação direta do mesmo fluxo. O único artefato fora de `driver/` é a
réplica obrigatória do contrato no `passenger/`, que implementa seu lado (publicar/consumir) numa
feature própria, especificada em seguida.

## Complexity Tracking

*Nenhuma violação de princípio a justificar — tabela omitida (Constitution Check: PASS).*
