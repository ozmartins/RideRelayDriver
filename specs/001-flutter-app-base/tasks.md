---

description: "Task list for feature 001-flutter-app-base"
---

# Tasks: Aplicativo Mobile Base (Motorista)

**Input**: Design documents from `specs/001-flutter-app-base/`

**Prerequisites**: plan.md ✓, spec.md ✓, research.md ✓, data-model.md ✓, quickstart.md ✓ (sem `contracts/` — app base não expõe interface externa)

**Tests**: tarefas de teste **incluídas** — exigidas por FR-007 e pela User Story 3 do spec.

**Organization**: agrupadas por user story, para que cada uma seja implementável e testável de forma independente.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: pode rodar em paralelo (arquivos diferentes, sem dependências pendentes)
- **[Story]**: user story à qual a tarefa pertence (US1, US2, US3)
- Caminhos são relativos a `Prototipo/driver/` (raiz do projeto Flutter), salvo indicação contrária

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: gerar o scaffold Flutter restrito a Android dentro do diretório que já contém o spec-kit

- [X] T001 Gerar o projeto Flutter sobre o diretório existente executando, em `Prototipo/driver/`: `flutter create . --project-name driver --org br.ufsc.tcc.corridas --platforms android --description "Aplicativo do motorista do protótipo de corridas P2P sobre Nostr (TCC UFSC)"` — cria `lib/main.dart`, `test/`, `android/`, `pubspec.yaml`, `analysis_options.yaml`, `.gitignore` (decisões D2, D3, D4, D5 de `specs/001-flutter-app-base/research.md`)
- [X] T002 Confirmar que o scaffold não tocou o spec-kit: rodar `git status --short` em `Prototipo/driver/` e verificar que `.specify/`, `.claude/` e `specs/` não aparecem como modificados; se `.specify/feature.json` ou qualquer arquivo de `specs/` tiver sido alterado, restaurar com `git checkout --` antes de prosseguir (risco registrado em D5)
- [X] T003 Verificar que nenhum diretório de plataforma fora de escopo foi criado em `Prototipo/driver/` (`ios/`, `web/`, `linux/`, `macos/`, `windows/`); remover os que existirem, conforme FR-004
- [X] T004 Resolver dependências com `flutter pub get` em `Prototipo/driver/` e confirmar em `pubspec.yaml` que não há nenhuma dependência de terceiros além de `flutter`, `cupertino_icons`, `flutter_test` e `flutter_lints` (decisão D8)
- [X] T005 [P] Confirmar que `Prototipo/driver/analysis_options.yaml` inclui `package:flutter_lints/flutter.yaml` e que `flutter analyze` roda sobre o projeto (gate de análise estática, D7)
- [X] T006 [P] Confirmar que `Prototipo/driver/.gitignore` ignora `build/`, `.dart_tool/`, `.flutter-plugins*` e `*.iml`, atendendo FR-008

**Checkpoint**: projeto Flutter válido, somente Android, sem dependências extras e sem artefatos de build versionados

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: identidade do aplicativo no sistema operacional — bloqueia a verificação de qualquer user story, porque os critérios de aceitação referenciam nome e identificador

**⚠️ CRITICAL**: nenhuma user story pode ser validada antes desta fase

- [X] T007 Verificar em `Prototipo/driver/android/app/build.gradle.kts` que `namespace` e `applicationId` são `br.ufsc.tcc.corridas.driver`; corrigir se o scaffold divergir (FR-003)
- [X] T008 Definir o nome de exibição do aplicativo alterando `android:label` para `Corridas Motorista` em `Prototipo/driver/android/app/src/main/AndroidManifest.xml` (FR-003, User Story 1 cenário 3)
- [X] T009 Verificar que `Prototipo/driver/android/app/src/main/AndroidManifest.xml` não declara nenhuma permissão além do padrão do scaffold — em especial nada de `INTERNET`, localização ou armazenamento — atendendo FR-005 e SC-005

**Checkpoint**: aplicativo identificado como "Corridas Motorista" / `br.ufsc.tcc.corridas.driver`, sem permissões

---

## Phase 3: User Story 1 - Executar o aplicativo base em um dispositivo (Priority: P1) 🎯 MVP

**Goal**: o app compila, instala e abre em um dispositivo Android exibindo uma tela inicial vazia identificada como o app do motorista.

**Independent Test**: instalar em emulador/aparelho e verificar que abre sem erros exibindo "Corridas Motorista", sem contador e sem diálogo de permissão.

- [X] T010 [US1] Substituir o boilerplate de contador em `Prototipo/driver/lib/main.dart` por um `MaterialApp` stateless: `title` "Corridas Motorista", `themeMode: ThemeMode.system` com `ThemeData` claro e escuro padrão do Material, e `home` apontando para uma `HomeScreen` (decisão D6)
- [X] T011 [US1] Implementar `HomeScreen` como `StatelessWidget` em `Prototipo/driver/lib/main.dart`: `Scaffold` com `AppBar(title: Text('Corridas Motorista'))` e corpo centralizado com um texto de placeholder identificando o app do motorista; sem `FloatingActionButton`, sem `setState`, sem estado mutável (FR-002, D6, `specs/001-flutter-app-base/data-model.md`)
- [X] T012 [US1] Remover de `Prototipo/driver/lib/main.dart` todo resquício do template (`MyHomePage`, `_MyHomePageState`, `_counter`, `_incrementCounter`, comentários instrucionais do scaffold), deixando apenas o entrypoint e a tela inicial
- [X] T013 [US1] Verificar que o app compila para Android executando `flutter build apk --debug` em `Prototipo/driver/` (quickstart cenário 6)
- [X] T014 [US1] Executar o app no emulador (`flutter emulators --launch Pixel_6_API34_1` seguido de `flutter run` em `Prototipo/driver/`) e confirmar os três cenários de aceitação da User Story 1: abre em ≤ 5 s exibindo a tela inicial (SC-002), sobrevive a ir para segundo plano e voltar na mesma tela, e aparece como "Corridas Motorista" na lista de aplicativos do sistema
- [X] T015 [US1] Confirmar durante a execução de T014 que nenhum diálogo de permissão do sistema é exibido na primeira abertura (SC-005)
- [X] T016 [US1] Verificar legibilidade da tela inicial alternando o tema do sistema Android entre claro e escuro e repetindo em um segundo perfil de resolução/densidade, sem conteúdo cortado ou sobreposto (SC-004, edge cases do spec)

**Checkpoint**: MVP entregue — existe um app do motorista que abre e é demonstrável

---

## Phase 4: User Story 2 - Reproduzir o ambiente de desenvolvimento a partir do repositório (Priority: P2)

**Goal**: qualquer avaliador consegue clonar o repositório e executar o app seguindo apenas documentação.

**Independent Test**: em máquina limpa com ambiente mobile instalado, seguir o `README.md` do zero até o app aberto, sem passo não documentado.

- [X] T017 [US2] Criar `Prototipo/driver/README.md` documentando: propósito do app (motorista do protótipo de corridas sobre Nostr), versões exatas de Flutter/Dart (3.47.4 / 3.13.3), `flutter doctor` como primeiro passo com a ressalva de que apenas o grupo Android precisa estar ✓, e os comandos `flutter pub get`, `flutter run`, `flutter analyze`, `flutter test` e como rodar um único teste (FR-006, decisões D1 e D9)
- [X] T018 [US2] Registrar no `README.md` de `Prototipo/driver/` o escopo desta etapa e seus limites: Android apenas, tela vazia, sem rede, sem permissões, sem integração Nostr ainda, e que o app do passageiro é um projeto independente em `Prototipo/passenger` (FR-004, FR-005, FR-009). **Verificação de FR-009 nesta etapa é por inspeção**, não automatizada: confirmar que nenhum arquivo em `Prototipo/driver/lib/`, `pubspec.yaml` ou `android/` referencia `passenger` ou caminhos fora de `Prototipo/driver/`. A verificação de não-acoplamento com código real dos dois lados passa a ser responsabilidade da feature do passageiro
- [X] T019 [US2] Atualizar a seção "Protótipo" de `/home/oseias/Documentos/ufsc/TCC/CLAUDE.md` com o estado real de `driver/` (app Flutter existente) e os comandos de build, execução, lint e teste, incluindo como rodar um único teste — o arquivo hoje declara que não existe código nem comandos
- [X] T020 [US2] Validar a reprodutibilidade executando `git clean -nxd` em `Prototipo/driver/` para confirmar que nada essencial está apenas em arquivos ignorados, e revisar o `README.md` seguindo-o literalmente do início ao fim (SC-001, quickstart cenário 8)

**Checkpoint**: protótipo reprodutível por terceiros a partir da documentação

---

## Phase 5: User Story 3 - Verificação automatizada mínima (Priority: P3)

**Goal**: uma verificação automatizada protege a tela inicial contra regressões antes de novas funcionalidades entrarem.

**Independent Test**: rodar a suíte e ver o teste da tela inicial passar; quebrar a tela de propósito e ver o teste falhar.

- [X] T021 [US3] Substituir o teste de contador gerado pelo scaffold criando `Prototipo/driver/test/home_screen_test.dart` e removendo `Prototipo/driver/test/widget_test.dart` (decisão D7)
- [X] T022 [US3] Escrever em `Prototipo/driver/test/home_screen_test.dart` o teste "exibe o título do aplicativo": bombear o app raiz com `tester.pumpWidget` e verificar via `find.text('Corridas Motorista')` que o título da tela inicial é exibido (FR-007)
- [X] T023 [US3] Adicionar em `Prototipo/driver/test/home_screen_test.dart` o teste de regressão do boilerplate: verificar que não existe nenhum `FloatingActionButton` nem o texto do contador do template na árvore de widgets (protege a decisão D6)
- [X] T024 [US3] Executar `flutter test` em `Prototipo/driver/` e confirmar 100% de aprovação (SC-003)
- [X] T025 [US3] Validar a contraprova do teste: alterar temporariamente o título em `Prototipo/driver/lib/main.dart`, confirmar que `flutter test` falha apontando o texto ausente, e desfazer a alteração (User Story 3 cenário 2, quickstart cenário 3)

**Checkpoint**: base coberta por verificação automatizada mínima

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: fechar os gates de qualidade e deixar o repositório limpo

- [X] T026 Executar `flutter analyze` em `Prototipo/driver/` e resolver todo apontamento até obter `No issues found!` (SC-003)
- [X] T027 [P] Executar `dart format lib test` em `Prototipo/driver/` e confirmar que nenhum arquivo permanece fora do padrão de formatação
- [X] T028 [P] Executar `git status --short` na raiz do repositório e confirmar que nenhum artefato de build (`build/`, `.dart_tool/`) aparece como não rastreado (FR-008, quickstart cenário 7)
- [X] T029 Percorrer `specs/001-flutter-app-base/quickstart.md` do cenário 1 ao 8 e confirmar que todos passam com os resultados esperados
- [X] T030 Fazer o commit em português descrevendo a mudança (ex.: "Cria o aplicativo Flutter base do motorista com tela inicial, teste de sanidade e documentação de execução"), conforme a convenção de commits do repositório

---

## Dependencies & Execution Order

```text
Phase 1 (Setup: T001–T006)
        ↓
Phase 2 (Foundational: T007–T009)   ← bloqueia a validação de todas as stories
        ↓
Phase 3 (US1 · P1 · MVP: T010–T016)
        ↓
Phase 4 (US2 · P2: T017–T020)       ← depende do US1: documenta comandos já comprovados
        ↓
Phase 5 (US3 · P3: T021–T025)       ← depende do US1: testa a tela que US1 criou
        ↓
Phase 6 (Polish: T026–T030)
```

- **T001 é raiz de tudo**: nenhuma outra tarefa faz sentido antes de o scaffold existir.
- **US1 é independente** e sozinha já entrega valor demonstrável (MVP).
- **US2 e US3 dependem de US1**, mas são independentes entre si — podem ser feitas em qualquer ordem ou
  em paralelo por pessoas diferentes (arquivos disjuntos: `README.md`/`CLAUDE.md` vs. `test/`).
- **Phase 6** exige US1, US2 e US3 concluídas.
- **FR-009** não gera tarefa de implementação: `Prototipo/passenger` ainda não existe, então "não acoplado"
  é hoje uma propriedade do que **não** se faz. T018 registra a verificação por inspeção.

## Parallel Opportunities

- Phase 1: `T005` e `T006` em paralelo (arquivos distintos: `analysis_options.yaml` vs `.gitignore`).
- Phase 4 × Phase 5: após o checkpoint da US1, a trilha de documentação (T017–T020) e a de testes
  (T021–T025) não compartilham arquivos e podem correr simultaneamente.
- Phase 6: `T027` e `T028` em paralelo.
- Dentro da US1 não há paralelismo real: T010–T012 editam o mesmo arquivo (`lib/main.dart`) e T013–T016
  são verificações sequenciais sobre o resultado.

## Implementation Strategy

**MVP (escopo mínimo entregável)**: Phase 1 + Phase 2 + Phase 3 (T001–T016). Ao fim, existe um app do
motorista instalável que abre em Android com a tela inicial correta — suficiente para demonstrar a base do
protótipo na defesa.

**Incremento 2**: Phase 4 (T017–T020) — reprodutibilidade documentada, requisito do TCC para avaliação
por terceiros.

**Incremento 3**: Phase 5 (T021–T025) — rede de segurança automatizada antes de começar as features de
Nostr.

**Fechamento**: Phase 6 (T026–T030) — gates de qualidade e commit.

**Total**: 30 tarefas (Setup 6, Foundational 3, US1 7, US2 4, US3 5, Polish 5).
