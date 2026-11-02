# Implementation Plan: Avaliar corrida (motorista)

**Branch**: `master` (commits diretos, sem branch de feature — Padrão de Commits da constituição) | **Date**: 2026-09-23 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/013-avaliar-corrida/spec.md`

**Note**: This template is filled in by the `/speckit-plan` command. See `.specify/templates/plan-template.md` for the execution workflow.

## Summary

Ao receber a confirmação de destino do passageiro (`kind: 20010`, tratada hoje por
`_processarConfirmacaoDeDestino` em `map_screen.dart`, que encerra a corrida e volta o motorista a
"Aguardando solicitação de corrida"), o app passa a exibir, na sequência, uma tela de avaliação da
corrida com cinco estrelas. Selecionar uma estrela de posição N marca as estrelas 1..N; confirmar
persiste a nota (1 a 5) numa tabela SQLite nova, associada ao `quoteId` da corrida encerrada
(`ActiveRide.quoteId`, lido antes de zerá-la). Uma ação de pular fecha a tela sem persistir nada.
Nenhum estado novo é adicionado a `ActiveRide`/`RideStateStore`: a exibição é disparada uma única
vez, no mesmo instante em que a corrida é encerrada, e não é retomada depois de o app fechar
(mesma decisão já tomada pela feature irmã do passageiro) — dispensa qualquer sinalizador
persistido de "já visto". Nenhum evento Nostr novo é definido; a contrapartida do passageiro já
está implementada em `passenger/specs/011-avaliar-corrida/`.

## Technical Context

**Language/Version**: Dart 3 / Flutter (mesma versão já fixada no `pubspec.yaml` do projeto)

**Primary Dependencies**: `sqflite` (já em uso pelo motorista desde a feature `003-cadastro-
motorista`, para `driver_profile`) — nenhuma dependência nova.

**Storage**: SQLite, nova tabela `ride_ratings` (um banco próprio, `ride_ratings.db`), por
analogia estrutural direta a `received_quote_store.dart` do passageiro (tabela isolada, sem a
lógica de exceção/linha única de `SqfliteCadastroStore`, que resolve um problema diferente — um
cadastro obrigatório de no máximo uma linha) — sem alteração ao esquema de `driver_profile`.

**Testing**: `flutter_test`, com um dublê em memória de `RideRatingStore` para os testes de tela —
nenhum teste toca SQLite real (Princípio II, mesma situação já aceita para
`SqfliteReceivedQuoteStore` do passageiro e, agora, `SqfliteRideRatingStore` dele — ver D1 de
`research.md`).

**Target Platform**: Android (sem mudança)

**Project Type**: mobile-app (Flutter, Android apenas) — mesma estrutura já usada pelo motorista.

**Performance Goals**: a tela de avaliação aparece em até 2 s do encerramento da corrida (SC-001);
a nota confirmada é encontrada no banco local imediatamente depois (SC-002) — mesma ordem de
grandeza já observada nas demais persistências locais do protótipo.

**Constraints**: nenhum evento Nostr novo, nenhuma informação da avaliação trafega para o outro
app nem para relay (FR-005) — persistência estritamente local.

**Scale/Scope**: protótipo de avaliação de viabilidade — sem requisito de escala além do já
estabelecido; uma corrida ativa por vez (mesma premissa de `ActiveRide`/`DriverRideStatus`).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Princípio | Avaliação |
|---|---|
| I. Segredo criptográfico não vaza | PASS por vacuidade. Nenhum material de chave é tocado — a avaliação nunca é assinada nem publicada, é só uma nota numérica em SQLite local. |
| II. Assinatura e verificação nascem com teste | PASS por vacuidade — não há assinatura nem verificação nesta feature. A regra geral de teste automatizado (não a específica de assinatura) ainda cobre o fluxo, via o Fluxo de Desenvolvimento e Gates. |
| III. Dependência de terceiros exige decisão registrada | PASS. Nenhuma dependência nova ao `pubspec.yaml` — `sqflite` já está registrado (feature 003); reaproveitado sem nova decisão de dependência (decisão de esquema registrada em `research.md`, que não é uma dependência de terceiros). |
| IV. O contrato de evento vem antes do código | PASS por vacuidade. Nenhum evento Nostr novo — a avaliação nunca sai do app que a coletou (FR-005), então não há contrato a definir nem replicar. |
| V. Simplicidade proporcional e rastreabilidade acadêmica | PASS. Reaproveita o padrão já estabelecido por `received_quote_store.dart` do passageiro (tabela isolada, uma responsabilidade) em vez de generalizar `SqfliteCadastroStore` ou introduzir uma camada comum entre os dois; nenhum sinalizador "já avaliado" persistido é introduzido — a mesma decisão da feature irmã do passageiro (D3 do `research.md` dela) já estabeleceu que estado em memória basta. |

**Resultado do gate inicial**: PASS — sem violação a justificar em Complexity Tracking.

## Project Structure

### Documentation (this feature)

```text
specs/013-avaliar-corrida/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md         # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

Sem diretório `contracts/`: nenhum evento Nostr novo é definido por esta feature.

### Source Code (repository root)

```text
driver/lib/
├── domain/
│   └── ride_rating.dart          # NOVO — rideId (= ActiveRide.quoteId), stars (1-5), ratedAt;
│                                  # mesma forma conceitual da entidade equivalente do passageiro
├── services/
│   └── ride_rating_store.dart    # NOVO — RideRatingStore (abstrata) + SqfliteRideRatingStore,
│                                  # por analogia direta a received_quote_store.dart do passageiro
└── screens/
    ├── ride_rating_modal.dart    # NOVO — cinco estrelas selecionáveis, "Confirmar" e "Pular"
    └── map_screen.dart           # ALTERADO — em _processarConfirmacaoDeDestino, antes de zerar
                                   # _activeRide, guarda o quoteId e abre a modal de avaliação via
                                   # showDialog (mesmo padrão de _mostrarModalAceitacao, não o
                                   # Stack usado pelo passageiro — as duas apps não são espelho de
                                   # código); persiste via RideRatingStore ao confirmar, ou só
                                   # fecha ao pular

driver/test/
├── domain/
│   └── ride_rating_test.dart           # NOVO
└── screens/
    └── map_screen_test.dart            # ALTERADO — cenários da user story nova
```

**Structure Decision**: mesma estrutura de três camadas já usada desde a feature 002 do
motorista, sem novo diretório de topo. Nenhum arquivo de contrato Nostr é tocado.

## Complexity Tracking

*Nenhuma violação de princípio a justificar — tabela omitida (Constitution Check: PASS).*
