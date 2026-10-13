---

description: "Task list for feature 004-mapa-status-motorista"
---

# Tasks: Mapa e Status de Disponibilidade do Motorista

**Input**: Design documents from `specs/004-mapa-status-motorista/`

**Prerequisites**: plan.md ✓, spec.md ✓, research.md ✓, data-model.md ✓, quickstart.md ✓ (sem
`contracts/` — feature sem interface externa, ver Constitution Check do `plan.md`)

**Tests**: por analogia ao Princípio II da constituição (NÃO NEGOCIÁVEL para código de assinatura e
verificação), código que decide o status de disponibilidade — exigir posição válida para ficar online,
forçar offline quando a posição some — MUST ter teste do caso permitido e do impedido, com dublê de
localização, sem sensor real. Por isso as tarefas de teste abaixo são obrigatórias, não opcionais.

**Organization**: agrupadas por user story. Caminhos relativos a `Prototipo/driver/`.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: pode rodar em paralelo (arquivos diferentes, sem dependências pendentes)
- **[Story]**: US1 (ver a própria posição no mapa), US2 (ficar online ou offline)

---

## Phase 1: Setup

**Purpose**: preparar as dependências de mapa e localização, e a permissão do sistema, antes de
qualquer código de domínio ou de tela

- [X] T001 Adicionar a dependência `geolocator ^14.0.3` ao `pubspec.yaml` com `flutter pub add`,
  conforme a decisão D1 já registrada em `specs/004-mapa-status-motorista/research.md`
- [X] T002 Adicionar as dependências `flutter_map ^8.3.2` e `latlong2 ^0.10.1` ao `pubspec.yaml` com
  `flutter pub add`, conforme a decisão D2 já registrada em `research.md`
- [X] T003 Declarar a permissão de localização em primeiro plano
  (`android.permission.ACCESS_FINE_LOCATION` e `android.permission.ACCESS_COARSE_LOCATION`) em
  `android/app/src/main/AndroidManifest.xml`, com comentário justificando o uso — constituição,
  *Restrições de Segurança e Privacidade*: nada de permissão "para o futuro", e esta é a feature que
  justifica por escrito o acesso a este dado sensível

**Checkpoint**: dependências justificadas e instaladas, permissão declarada com justificativa

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: entidades de domínio e o serviço de localização — bloqueiam todas as user stories

**⚠️ CRITICAL**: nenhuma user story pode começar antes desta fase

- [X] T004 [P] Criar a entidade `DriverPosition` em `lib/domain/driver_position.dart`, com `latitude`,
  `longitude` e `capturedAt` (`data-model.md`)
- [X] T005 [P] Criar o enum `AvailabilityStatus` (`online`/`offline`) e a regra
  `AvailabilityRules.canGoOnline({required bool hasValidPosition})` em
  `lib/domain/availability_status.dart` (FR-008, `data-model.md`)
- [X] T006 Escrever os testes de `AvailabilityRules` em `test/domain/availability_status_test.dart`:
  `canGoOnline` verdadeiro com posição válida, falso sem posição (Princípio II por analogia, caso
  permitido **e** impedido)
- [X] T007 Definir a interface `LocationService` em `lib/services/location_service.dart` — fluxo de
  `DriverPosition?` (nulo enquanto indisponível) e verificação/pedido de permissão —, mais as exceções
  `LocationPermissionDenied` e `LocationUnavailable`, seguindo o mesmo padrão de `CadastroStore` e
  `KeyStore` (Princípio III)
- [X] T008 Implementar `GeolocatorLocationService` em `lib/services/geolocator_location_service.dart`
  sobre `geolocator` — único arquivo que importa `package:geolocator` (Princípio III)

**Checkpoint**: domínio e serviço de localização prontos; `flutter analyze`/`flutter test` seguem
limpos com o código já existente das features anteriores

---

## Phase 3: User Story 1 - Ver a própria posição no mapa ao abrir o aplicativo (Priority: P1)

**Goal**: a tela inicial do aplicativo é um mapa centrado na posição real do aparelho, com um indicador
que acompanha o deslocamento, e trata com clareza a ausência de permissão ou de localização.

**Independent Test**: abrir o aplicativo com localização disponível e verificar que a tela inicial é um
mapa centrado na posição real, com indicador; sem localização, verificar a mensagem compreensível.

- [X] T009 [US1] Escrever os testes de `LocationService` em `test/services/location_service_test.dart`
  com um dublê em memória, cobrindo: o fluxo emite as posições publicadas, a ausência de permissão
  surge como `LocationPermissionDenied`, e a indisponibilidade (sinal perdido) surge como
  `LocationUnavailable`, distinta da ausência de permissão (FR-004, FR-005)
- [X] T010 [US1] Implementar `MapScreen` em `lib/screens/map_screen.dart`: mapa via `flutter_map` com
  mosaicos do OpenStreetMap (atribuição visível, `userAgentPackageName` configurado — D2 de
  `research.md`), centrado na última `DriverPosition` recebida, com um indicador visual naquele ponto,
  atualizado a cada nova posição do fluxo (FR-001, FR-002, FR-003)
- [X] T011 [US1] Em `MapScreen`, solicitar a permissão de localização ao entrar na tela quando ainda
  não concedida, explicando o motivo, e exibir mensagem compreensível — sem travar nem erro técnico
  cru — quando a permissão for negada ou a localização estiver indisponível (FR-004, FR-005, edge case
  de permissão negada permanentemente)
- [X] T012 [US1] No `main.dart`, no bootstrap, instanciar `LocationService` e tornar `MapScreen` a
  primeira aba da navegação existente, deslocando Eventos, Relays, Identidade e Cadastro para as
  posições seguintes (Structure Decision do `plan.md`)
- [X] T013 [US1] Escrever o teste de widget em `test/screens/map_screen_test.dart` verificando: o
  indicador de posição aparece quando o dublê de `LocationService` emite uma posição, e a mensagem de
  indisponibilidade aparece no lugar dele quando o dublê emite ausência ou lança as exceções de T009

**Checkpoint**: abrir o app mostra o mapa na posição real (ou a mensagem adequada), e o indicador
acompanha novas posições emitidas

---

## Phase 4: User Story 2 - Ficar online ou offline (Priority: P1)

**Goal**: um botão na tela de mapa alterna o motorista entre online e offline, sempre exigindo posição
válida para ficar online, voltando a offline sozinho se a posição sumir, e sempre começando offline.

**Independent Test**: com o mapa exibido e localização disponível, tocar no botão de status e verificar
a alternância, com o estado sempre visível; sem localização, verificar que a tentativa é bloqueada.

**Depende de**: US1 (a tela e o `LocationService` que esta história reaproveita).

- [X] T014 [US2] Acrescentar a `MapScreen` (T010) o estado `AvailabilityStatus` (inicial sempre
  `offline`, FR-010) e um controle visível para alternar, usando `AvailabilityRules.canGoOnline` (T005)
  para decidir se o toque em "ficar online" é aceito ou recusado com explicação (FR-006, FR-007,
  FR-008). Enquanto uma transição estiver em andamento, o controle MUST ignorar novos toques — dois
  toques rápidos e seguidos não podem produzir um estado inconsistente (Edge Cases do `spec.md`)
- [X] T015 [US2] Em `MapScreen`, reagir à perda de `DriverPosition` (fluxo emite ausência ou lança
  `LocationUnavailable`) colocando o status `offline` automaticamente quando ele estava `online`, com
  explicação do motivo (FR-009)
- [X] T016 [US2] Escrever os testes de widget em `test/screens/map_screen_test.dart` cobrindo: tentar
  ficar online sem posição válida é recusado e o status permanece offline (SC-004); com posição válida,
  o toque alterna para online e um segundo toque volta a offline; ficar online e em seguida perder a
  posição no dublê de `LocationService` força o status de volta a offline automaticamente (FR-009); o
  estado inicial de `MapScreen`, com qualquer dublê, é sempre offline (FR-010, SC-005); e dois toques
  disparados em sequência rápida no controle de status resultam em um único estado final consistente,
  não em um estado intermediário ou contraditório (edge case de toques repetidos)

**Nota sobre FR-011**: esta feature não implementa nenhum mecanismo de notificação de solicitação de
corrida — isso é escopo de uma feature futura, por pedido explícito do usuário. FR-011 fica satisfeita
aqui só pela existência do `AvailabilityStatus` como o interruptor que aquela feature futura vai
consultar; não há tarefa própria porque não há, ainda, nada que a notificação dependa de acionar. Isto
não é um requisito esquecido.

**Checkpoint**: o status nunca fica online sem posição válida, sempre volta a offline se a posição
sumir, e sempre começa offline

---

## Phase 5: Polish & Cross-Cutting Concerns

**Purpose**: fechar os gates da constituição (seção *Fluxo de Desenvolvimento e Gates*)

- [X] T017 Executar `flutter analyze` em `Prototipo/driver/` até obter `No issues found!` (gate 1)
- [X] T018 [P] Executar `dart format lib test` em `Prototipo/driver/` e confirmar que nada ficou fora
  do padrão
- [X] T019 Executar `flutter test` em `Prototipo/driver/` e confirmar aprovação integral, **sem
  nenhum teste ignorado ou marcado como pendente** (gate 2)
- [X] T020 Executar os 8 cenários de `specs/004-mapa-status-motorista/quickstart.md` em
  emulador/aparelho com localização simulável, registrando o resultado de cada um — cenários que
  falharem devem ser **relatados, não omitidos** (gate 3), com o tempo de SC-001/SC-002/SC-003
  efetivamente medido, não estimado (Princípio V)
- [X] T021 [P] Atualizar `Prototipo/driver/README.md` com o escopo desta feature e as novas
  dependências
- [X] T022 [P] Atualizar a seção "Protótipo" de `/home/oseias/Documentos/ufsc/TCC/CLAUDE.md` com o
  novo estado do `driver/`
- [X] T023 Commitar em português descrevendo a mudança de comportamento, não os arquivos tocados
  (gate 5, Padrão de Commits) — sem contrapartida em `Prototipo/passenger`, pois esta feature não toca
  o contrato de eventos (Constitution Check do `plan.md`)

---

## Dependencies & Execution Order

```text
Phase 1 (Setup: T001–T003)
        ↓
Phase 2 (Foundational: T004–T008)
        ↓
Phase 3 (US1 · mapa e posição: T009–T013)
        ↓
Phase 4 (US2 · online/offline: T014–T016)   ← reaproveita MapScreen e LocationService de US1
        ↓
Phase 5 (Polish: T017–T023)
```

- **T001–T003 não dependem de nenhum registro pendente**: D1 e D2 já estão em `research.md` desde a
  fase de planejamento, resolvidos antes da geração de tarefas.
- **US2 depende de US1** na prática (reaproveita a tela e o serviço), embora seja independentemente
  **testável** uma vez que US1 exista — mesma relação já usada entre US1 e US3 da feature 003.

## Parallel Opportunities

- Phase 2: `T004` e `T005` em paralelo (entidades de domínio sem dependência mútua).
- Phase 5: `T018`, `T021` e `T022` em paralelo.
- Dentro de cada história, teste → implementação é sequencial por construção (Princípio II por
  analogia).

## Implementation Strategy

**MVP**: Phases 1–3 (T001–T013). Ao final, o motorista abre o aplicativo e vê sua posição real no
mapa — a demonstração central desta feature.

**Incremento 2**: Phase 4 (T014–T016) — o status de disponibilidade, que dá sentido a "ficar
disponível para corridas" e prepara o terreno para a notificação de solicitações, tratada em feature
futura.

**Fechamento**: Phase 5 (T017–T023) — os gates da constituição.

**Total**: 23 tarefas (Setup 3, Foundational 5, US1 5, US2 3, Polish 7).
