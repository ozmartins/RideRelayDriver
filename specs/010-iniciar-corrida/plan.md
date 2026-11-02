# Implementation Plan: Iniciar corrida após aceitação e deslocamento até o passageiro

**Branch**: `master` (commits diretos, sem branch de feature — Padrão de Commits da constituição) | **Date**: 2026-09-21 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/010-iniciar-corrida/spec.md`

**Note**: This template is filled in by the `/speckit-plan` command. See `.specify/templates/plan-template.md` for the execution workflow.

## Summary

O motorista passa a reagir à aceitação de um orçamento (`kind: 20003`, já definida no contrato
desde a feature 008 do passageiro, mas nunca consumida do lado do motorista): uma modal avisa que
o orçamento foi aceito e, ao tocar "Iniciar corrida", o motorista entra num novo estado local
persistido, "Deslocando-se até o passageiro". Esse estado (a) bloqueia a exibição de modais de
novas solicitações de corrida (`kind: 20001`) até uma feature futura devolver o motorista a
"Aguardando solicitação de corrida", e (b) liga a publicação periódica da localização atual do
motorista, a cada 50 m percorridos, num novo evento (`kind: 20005`) dirigido ao passageiro daquela
corrida. Uma segunda aceitação chegando enquanto o motorista já está comprometido publica, em vez
de abrir modal, um aviso de recusa num terceiro evento novo (`kind: 20006`) ao passageiro que a
enviou. Abordagem técnica: reaproveitar os padrões já estabelecidos nas features 007/008/009
(fila sequencial de modais, `KeyValueStore` para dado local pequeno, `LocationService` já existente
para a origem da posição) — nenhuma dependência nova.

## Technical Context

**Language/Version**: Dart 3 / Flutter (mesma versão já fixada no `pubspec.yaml` do projeto)

**Primary Dependencies**: `dart_nostr` (assinatura/serialização, já em uso), `shared_preferences`
(via `KeyValueStore`/`PreferencesStore`, já em uso), `geolocator` (via `LocationService`, já em
uso) — nenhuma dependência nova é introduzida por esta feature.

**Storage**: `shared_preferences` (através da abstração `KeyValueStore` já existente), para os dois
novos dados locais persistidos — estado do motorista (`RideStateStore`) e orçamentos enviados com
sucesso (`SentQuotesStore`, D6 de `research.md`) — mesmo mecanismo já usado por `RelayRepository`.
`sqflite` (via `CadastroStore`) continua servindo só o cadastro, sem mudança.

**Testing**: `flutter_test`, com dublês para `KeyValueStore`, `EventFeed`/`RelayService` e
`LocationService` — nenhum teste toca rede, relay ou `SharedPreferences` real (Princípio II).

**Target Platform**: Android (mesmo escopo do projeto; sem mudança)

**Project Type**: mobile-app (Flutter, Android apenas) — estrutura `lib/domain` + `lib/services` +
`lib/screens` já estabelecida, sem novo diretório de topo.

**Performance Goals**: modal de aceitação exibida em até 1s da chegada do evento (SC-001); aviso de
recusa por corrida já em andamento publicado em até 1s (SC-005) — mesma ordem de grandeza já medida
para outros eventos deste protótipo (não uma medição nova desta feature).

**Constraints**: eventos publicados neste protótipo continuam sem criptografia (mesma justificativa
já registrada para os kinds 20001-20004: resposta pública a um fluxo já público entre motorista e
passageiro que já trocaram orçamento); nenhum dado além de posição/identificadores de correlação
(`id` de orçamento, chave pública) trafega nos novos eventos.

**Scale/Scope**: protótipo de avaliação de viabilidade, uso individual por sessão de teste — sem
requisito de escala além do já estabelecido pelas features anteriores.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Princípio | Avaliação |
|---|---|
| I. Segredo criptográfico não vaza | PASS. Nenhum material de chave privada é tocado por esta feature além do já existente `IdentityService.signRideQuote`-equivalente para os novos eventos, que reaproveita a mesma assinatura por `Identity.privateKey` já testada; nenhum novo caminho de log ou persistência de segredo é introduzido. |
| II. Assinatura e verificação nascem com teste | PASS (obrigação, não isenção). Os novos eventos publicados (`kind: 20005`, `kind: 20006`) e a leitura do `kind: 20003` MUST ter teste cobrindo assinatura válida e conteúdo malformado/id desconhecido, seguindo o padrão já usado para `kind: 20001`/`20002` na feature 007. Registrado como obrigação de `tasks.md`, não como exceção. |
| III. Dependência de terceiros exige decisão registrada | PASS por vacuidade. Nenhuma dependência nova é adicionada ao `pubspec.yaml` — todos os serviços reaproveitados (`shared_preferences`, `geolocator`, `dart_nostr`) já têm decisão registrada em `research.md` de features anteriores (003, 004, 002 respectivamente). |
| IV. O contrato de evento vem antes do código | GATE ATIVO — ver Phase 1. Esta feature introduz dois kinds novos (`20005`, `20006`) e a primeira consumidora do `kind: 20003` do lado do motorista; o contrato (emenda ao `nostr-events.md` único do protótipo) MUST ser escrito e replicado na app do passageiro na mesma alteração de código, mesmo que o passageiro não implemente o consumo agora (mesmo padrão já usado para o `kind: 20001` no motorista, emenda 04). Verificado no Phase 1 abaixo. |
| V. Simplicidade proporcional e rastreabilidade acadêmica | PASS. O novo estado do motorista reaproveita `KeyValueStore`, já existente, em vez de introduzir uma nova tabela SQLite ou um novo mecanismo de persistência — decisão registrada em `research.md` (D1). O limiar de 50 m reaproveita um valor já medido/justificado por outra feature (`passenger/specs/007-rota-ate-destino/research.md`, D2), em vez de introduzir um novo número arbitrário. |

**Resultado do gate inicial**: PASS, condicionado ao cumprimento do Princípio IV no Phase 1 (contrato escrito e replicado) — sem violação a justificar em Complexity Tracking.

## Project Structure

### Documentation (this feature)

```text
specs/010-iniciar-corrida/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md         # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
├── contracts/           # Phase 1 output (/speckit-plan command) — aponta para a emenda no
│                         # contrato único do protótipo, mesmo padrão da feature 007
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

### Source Code (repository root)

```text
driver/lib/
├── domain/
│   ├── driver_ride_status.dart      # NOVO — enum + regras de transição (por analogia a
│   │                                 # availability_status.dart)
│   ├── active_ride.dart             # NOVO — quoteId + pubkey do passageiro da corrida em
│   │                                 # andamento (par persistido junto do status)
│   ├── quote_accepted.dart          # NOVO — leitura do kind 20003 (por analogia a
│   │                                 # ride_request_received.dart)
│   └── nostr_event.dart             # ALTERADO — novas constantes kindQuoteAccepted (20003),
│                                     # kindDriverLocation (20005), kindRideNoLongerAvailable
│                                     # (20006)
├── services/
│   ├── ride_state_store.dart        # NOVO — abstração + implementação sobre KeyValueStore
│   │                                 # (por analogia a relay_repository.dart)
│   ├── sent_quotes_store.dart       # NOVO — orçamentos publicados com sucesso, para validar
│   │                                 # FR-011 mesmo após reinício (D6 de research.md)
│   └── identity_service.dart        # ALTERADO — signDriverLocation, signRideNoLongerAvailable
├── screens/
│   ├── quote_accepted_modal.dart    # NOVO — modal com mensagem informativa + "Iniciar corrida"
│   └── map_screen.dart              # ALTERADO — fila de modais passa a incluir aceitações;
│                                     # bloqueio de kind 20001 fora do estado "Aguardando";
│                                     # assinatura de posição publica localização quando
│                                     # "Deslocando-se"
└── main.dart                        # ALTERADO — injeta RideStateStore; EventFeed passa a
                                      # aceitar kindQuoteAccepted

driver/test/
├── domain/
│   ├── driver_ride_status_test.dart      # NOVO
│   ├── active_ride_test.dart             # NOVO
│   └── quote_accepted_test.dart          # NOVO
├── services/
│   ├── ride_state_store_test.dart        # NOVO
│   ├── sent_quotes_store_test.dart       # NOVO
│   └── identity_service_test.dart        # ALTERADO — casos dos dois novos kinds
└── screens/
    └── map_screen_test.dart              # ALTERADO — cenários das quatro user stories

passenger/specs/002-nostr-relay-connection/contracts/nostr-events.md   # ALTERADO (mesma
    # alteração) — réplica idêntica da emenda ao contrato único, Princípio IV
```

**Structure Decision**: mantém a estrutura de três camadas já usada nas features 003–009 do
motorista (`domain/` puro, `services/` com tipos de terceiros confinados, `screens/` com widgets),
sem novo diretório de topo. O único artefato fora de `driver/` é a réplica obrigatória do contrato
no `passenger/`, que não implementa consumo nesta feature (mesmo padrão já usado para os kinds
20001/20002/20003/20004).

## Complexity Tracking

*Nenhuma violação de princípio a justificar — tabela omitida (Constitution Check: PASS).*
