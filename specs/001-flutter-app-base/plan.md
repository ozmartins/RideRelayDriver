# Implementation Plan: Aplicativo Mobile Base (Motorista)

**Branch**: `001-flutter-app-base` | **Date**: 2026-09-15 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/001-flutter-app-base/spec.md`

## Summary

Criar o esqueleto executável do aplicativo do motorista do protótipo de caronas P2P: um projeto Flutter
mínimo em `Prototipo/driver`, com uma única tela inicial sem lógica de negócio, identificado como
"Caronas Motorista" (`br.ufsc.tcc.caronas.driver`), rodando apenas em Android, com um teste de widget de
sanidade, análise estática limpa e um `README.md` documentando instalação, execução e testes.

A abordagem é usar o scaffold oficial (`flutter create`) restrito a Android, remover o boilerplate de
contador gerado pelo template, substituí-lo por uma tela inicial vazia e converter o teste de contador
gerado em um teste de sanidade da tela inicial. Nenhuma dependência externa é adicionada nesta etapa —
Nostr, rede, permissões e persistência ficam para features posteriores.

## Technical Context

**Language/Version**: Dart 3.13.3 (Flutter 3.47.4, canal stable — versão já instalada na máquina de desenvolvimento)

**Primary Dependencies**: apenas `flutter` SDK + `flutter_test` e `flutter_lints` (dev). Zero pacotes de terceiros nesta etapa.

**Storage**: N/A — a feature não persiste dados (FR-005)

**Testing**: `flutter test` (widget test via `flutter_test`) + `flutter analyze` como gate de análise estática

**Target Platform**: Android apenas (minSdk padrão do Flutter; validado no emulador `Pixel_6_API34_1`, API 34). iOS/web/desktop fora de escopo (FR-004)

**Project Type**: mobile-app (uma das duas apps do protótipo; a app do passageiro é um projeto independente)

**Performance Goals**: cold start até a primeira tela em ≤ 5 s no dispositivo de referência (SC-002); UI a 60 fps (padrão do framework, sem carga nesta etapa)

**Constraints**: nenhuma permissão Android declarada além do padrão do scaffold; nenhum acesso a rede; sem backend próprio; app não pode depender da app do passageiro

**Scale/Scope**: 1 tela, 0 entidades de domínio, 1 teste de widget

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

**Estado da constituição**: `.specify/memory/constitution.md` é o **template não preenchido** — todos os
princípios ainda são placeholders (`[PRINCIPLE_1_NAME]`, …) e não há versão ratificada.

**Resultado do gate**: PASS por vacuidade — não existe nenhum princípio ratificado que este plano possa
violar. Nenhuma violação a justificar, portanto a seção Complexity Tracking permanece vazia.

**Nota posterior (2026-09-15)**: a constituição foi ratificada na versão 1.0.0 **depois** desta feature
ser implementada. Avaliação retroativa: a base vazia não toca material criptográfico (Princípio I não
se aplica), não assina nem verifica eventos (Princípio II não se aplica), não adicionou dependência de
terceiros (Princípio III atendido de forma trivial), não define contrato de evento (Princípio IV não se
aplica) e mantém estrutura mínima com decisões registradas em `research.md` (Princípio V atendido).
Os gates de `flutter analyze`/`flutter test` do Fluxo de Desenvolvimento passaram. Nenhuma correção
retroativa é necessária. O texto abaixo preserva o estado no momento do planejamento.

**Ressalva registrada**: até que `/speckit-constitution` seja executado, este projeto não tem gates de
governança (ex.: TDD obrigatório, exigência de observabilidade, política de dependências). O plano adota
por conta própria os padrões conservadores coerentes com um protótipo de TCC: zero dependências de
terceiros, análise estática ativa e ao menos um teste automatizado. Se uma constituição for ratificada
depois, este plano deve ser reavaliado contra ela.

## Project Structure

### Documentation (this feature)

```text
specs/001-flutter-app-base/
├── plan.md              # Este arquivo
├── research.md          # Fase 0
├── data-model.md        # Fase 1
├── quickstart.md        # Fase 1
├── checklists/
│   └── requirements.md  # Checklist de qualidade do spec
└── tasks.md             # Fase 2 (/speckit-tasks)
```

Nenhum diretório `contracts/` é gerado: o app base não expõe nenhuma interface externa (sem API, sem CLI,
sem formato de evento Nostr nesta etapa) — a regra do template manda pular contratos para projetos
puramente internos. Os contratos de eventos Nostr entre motorista e passageiro serão definidos nas
features de comunicação.

### Source Code (repository root)

O repositório do TCC é a raiz do git; a app do motorista vive em `Prototipo/driver`, que já hospeda o
scaffold do spec-kit. O `flutter create` é aplicado **sobre esse diretório existente**, adicionando:

```text
Prototipo/driver/
├── lib/
│   └── main.dart            # entrypoint + tela inicial vazia (CaronasDriverApp, HomeScreen)
├── test/
│   └── home_screen_test.dart # teste de sanidade: a tela inicial monta e exibe o título
├── android/                 # projeto Android gerado (applicationId br.ufsc.tcc.caronas.driver)
├── pubspec.yaml             # nome do pacote: driver; sem dependências de terceiros
├── analysis_options.yaml    # flutter_lints
├── README.md                # comandos de setup, execução e teste (FR-006)
├── .gitignore               # ignora build/, .dart_tool/, etc. (FR-008)
├── .specify/                # pré-existente (spec-kit) — não tocar
├── .claude/                 # pré-existente (skills) — não tocar
└── specs/                   # pré-existente (documentação de features)
```

**Structure Decision**: projeto Flutter único e plano (`lib/` + `test/`), sem camadas de arquitetura
antecipadas. Com uma tela e nenhuma entidade, criar `models/`/`services/`/`repositories/` agora seria
estrutura vazia sem consumidor. A separação que importa neste protótipo já existe em nível de
repositório: `driver/` e `passenger/` são projetos independentes que só se falam por relays Nostr, de modo
que não há código compartilhado a fatorar nesta etapa. A camada de domínio será introduzida quando a
primeira feature de eventos Nostr exigir.

Diretórios de plataforma fora de escopo (`ios/`, `web/`, `linux/`, `macos/`, `windows/`) **não** são
gerados, conforme FR-004.

### Arquivo tocado fora da árvore do projeto

Além de `Prototipo/driver/`, esta feature altera **um** arquivo na raiz do repositório do TCC:

```text
CLAUDE.md    # seção "Protótipo": estado de driver/ + comandos de build, execução, lint e teste
```

Justificativa: o `CLAUDE.md` da raiz hoje afirma que `driver/` não tem código de aplicação e que não
existem comandos de build/teste no repositório. Deixar essa afirmação desatualizada faria qualquer sessão
futura partir de premissa falsa, então a atualização faz parte do escopo de documentação da User Story 2
(tarefa T019). Nenhum outro arquivo fora de `Prototipo/driver/` é criado ou modificado.

## Complexity Tracking

> Nenhuma violação de constituição a justificar (ver Constitution Check).
