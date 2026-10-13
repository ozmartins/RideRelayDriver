# Implementation Plan: Mapa e Status de Disponibilidade do Motorista

**Branch**: `004-mapa-status-motorista` (a criar) | **Date**: 2026-09-17 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/004-mapa-status-motorista/spec.md`

## Summary

Tornar a tela inicial do aplicativo do motorista um mapa centrado na posição real do aparelho, com um
indicador visual dessa posição atualizado continuamente, e um controle na mesma tela para alternar
entre ficar online e offline — condição que, em feature futura, vai decidir se solicitações de corrida
chegam a ser notificadas. O status volta sempre a offline a cada abertura do aplicativo, e ficar online
exige uma posição válida disponível no momento.

A abordagem usa `geolocator` para permissão e leitura contínua de posição, e `flutter_map` com mosaicos
do OpenStreetMap para o mapa em si — sem exigir chave nem conta de nenhum provedor de terceiro, o que
manteria o protótipo executável por qualquer avaliador sem credencial própria.

## Technical Context

**Language/Version**: Dart 3.13.3 (Flutter, stable) — inalterado em relação às features anteriores

**Primary Dependencies**:
- `geolocator ^14.0.3` — permissão e leitura contínua de posição (a adicionar; D1 de `research.md`)
- `flutter_map ^8.3.2` + `latlong2 ^0.10.1` — mapa com mosaicos do OpenStreetMap (a adicionar; D2)

**Storage**: nenhuma. Posição e status de disponibilidade existem só em memória, durante a sessão
(`data-model.md`) — ao contrário do cadastro (feature 003), que fica em SQLite.

**Testing**: `flutter test` com testes de unidade cobrindo, via dublê de `LocationService` (sem sensor
real, Princípio II por analogia): posição exibida quando disponível, mensagem quando indisponível,
transição para online bloqueada sem posição válida, transição automática para offline quando a posição
some, e status sempre offline ao iniciar. Testes de widget da tela de mapa. `flutter analyze` como
gate.

**Target Platform**: Android apenas (inalterado). Nova permissão exigida: localização em primeiro
plano (`ACCESS_FINE_LOCATION`, com `ACCESS_COARSE_LOCATION` como alternativa de menor precisão que o
próprio `geolocator` já solicita em conjunto) — permissão perigosa, com diálogo ao usuário, justificada
por esta feature.

**Project Type**: mobile-app

**Performance Goals**: posição exibida em ≤ 5 s após abrir o app (SC-001); indicador reflete
deslocamento em ≤ 10 s (SC-002); alternância de status refletida em ≤ 1 s (SC-003)

**Constraints**: sem chave nem conta de provedor de mapa de terceiro (D2); nada de posição ou status
persistido ou enviado a relay nesta feature (Assumptions do `spec.md`); ficar online exige posição
válida (FR-008); perda de posição estando online força offline automaticamente (FR-009)

**Scale/Scope**: 1 tela nova (mapa, tela inicial), 1 serviço de localização, 2 entidades de domínio
(`DriverPosition`, `AvailabilityStatus`), 1 permissão nova no manifesto

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

**Estado da constituição**: em vigor na versão **2.1.0** (5 princípios, dois deles NÃO NEGOCIÁVEIS).

**Resultado do gate**: PASS.

| Princípio | Avaliação desta feature |
|-----------|-------------------------|
| I. Segredo criptográfico não vaza | **Não se aplica**: esta feature não toca chave privada nem material de assinatura. |
| II. Assinatura e verificação nascem com teste | **Não se aplica diretamente**: não há assinatura nem verificação de evento aqui. Por analogia, código que decide o status de disponibilidade (a regra de exigir posição válida para ficar online, e de forçar offline quando a posição some) MUST ter teste do caso permitido e do impedido, com dublê de localização — sem sensor real. |
| III. Dependência de terceiros exige decisão registrada | **Atendido**: `geolocator` (D1) e `flutter_map`/`latlong2` (D2) registrados em `research.md`, com alternativas avaliadas, versões e datas — incluindo a rejeição explícita de `google_maps_flutter` e `mapbox_maps_flutter` por exigirem credencial de terceiro. Tipos de ambos os pacotes ficam confinados a `lib/services/` e à tela de mapa (Structure Decision). |
| IV. O contrato de evento vem antes do código | **Não se aplica**: nenhum evento Nostr é criado ou alterado. Posição e status permanecem locais ao aparelho (Assumptions do `spec.md`). Nada precisa ser replicado em `Prototipo/passenger`. |
| V. Simplicidade proporcional e rastreabilidade acadêmica | **Atendido com justificativa**: `research.md` descarta duas alternativas de mapa por exigirem infraestrutura de terceiro desproporcional a um protótipo acadêmico (reprodutibilidade sem credencial paga). Nenhuma camada nova além do padrão já existente (`domain/services/screens`). |

**Restrições de Segurança e Privacidade**: esta feature é a que **justifica por escrito** o acesso à
localização do aparelho — dado sensível que a constituição proíbe acessar sem feature própria que o
declare. A Assumption correspondente do `spec.md` descreve o dado coletado (coordenadas atuais), seu
uso (centrar o mapa, indicador de posição, pré-condição para ficar online) e seu tempo de vida (memória
da sessão, nunca persistido nem enviado a terceiros). A permissão de localização é solicitada somente
ao abrir a tela de mapa, nunca antecipadamente.

**Fluxo de Desenvolvimento e Gates**: `flutter analyze` e `flutter test` limpos, e execução dos 8
cenários do `quickstart.md` com relato honesto de falhas — condições para declarar a feature concluída.

## Project Structure

### Documentation (this feature)

```text
specs/004-mapa-status-motorista/
├── plan.md              # Este arquivo
├── research.md          # Fase 0 — D1 (geolocator), D2 (flutter_map + latlong2)
├── data-model.md         # Fase 1
├── quickstart.md         # Fase 1
├── checklists/
│   └── requirements.md
└── tasks.md              # Fase 2 (/speckit-tasks)
```

Sem `contracts/`: esta feature não expõe nem consome nenhuma interface externa — nenhum evento Nostr
está envolvido (Princípio IV, avaliado acima).

### Source Code (repository root)

```text
Prototipo/driver/
├── lib/
│   ├── main.dart                          # + carrega LocationService no bootstrap; MapScreen
│   │                                       #   passa a ser a primeira aba da navegação
│   ├── domain/
│   │   ├── driver_position.dart           # DriverPosition (latitude, longitude, capturedAt)
│   │   └── availability_status.dart       # enum AvailabilityStatus (online/offline)
│   ├── services/
│   │   ├── location_service.dart          # interface LocationService (injetável nos testes) +
│   │   │                                   #   exceções de permissão negada / indisponibilidade
│   │   └── geolocator_location_service.dart  # implementação real sobre geolocator (único
│   │                                          #   arquivo que conhece package:geolocator,
│   │                                          #   Princípio III)
│   └── screens/
│       └── map_screen.dart                # mapa (flutter_map) + indicador de posição + botão
│                                           #   de status; único arquivo que conhece
│                                           #   package:flutter_map além de main.dart
├── test/
│   ├── services/
│   │   └── location_service_test.dart     # dublê em memória; cobre permissão negada,
│   │                                       #   indisponibilidade e a perda de posição online
│   ├── domain/
│   │   └── availability_status_test.dart  # transições permitidas e bloqueadas
│   └── screens/
│       └── map_screen_test.dart           # indicador exibido/ausente, botão de status,
│                                           #   mensagens de indisponibilidade
└── android/app/src/main/AndroidManifest.xml   # + permissão de localização em primeiro plano
```

O único arquivo que conhece tipos de `geolocator` é `geolocator_location_service.dart`; o único que
conhece tipos de `flutter_map` é `map_screen.dart` — nem `domain/`, nem o restante de `services/`, nem
qualquer outra tela os importam (Princípio III).

**Structure Decision**: mantém-se a separação `domain/` + `services/` + `screens/` já estabelecida.
`MapScreen` passa a ocupar a primeira posição da navegação em `main.dart`, com as abas já existentes
(Eventos, Relays, Identidade, Cadastro) deslocadas para as posições seguintes — nenhuma delas é
removida (Assumptions do `spec.md`).

## Complexity Tracking

> Nenhuma violação de constituição a justificar (ver Constitution Check).
