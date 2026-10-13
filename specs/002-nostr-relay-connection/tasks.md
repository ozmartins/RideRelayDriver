---

description: "Task list for feature 002-nostr-relay-connection"
---

# Tasks: Conexão do Motorista com Relays Nostr

**Input**: Design documents from `specs/002-nostr-relay-connection/`

**Prerequisites**: plan.md ✓, spec.md ✓, research.md ✓, data-model.md ✓, contracts/ ✓, quickstart.md ✓

**Tests**: **OBRIGATÓRIOS**, não opcionais. A constituição v1.0.0, Princípio II (NÃO NEGOCIÁVEL), exige
teste do caso válido e do inválido para todo código que assina, verifica assinatura, deriva chaves ou
decide descartar mensagem recebida — executável sem rede e sem relay real.

**Organization**: agrupadas por user story. Caminhos relativos a `Prototipo/driver/`.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: pode rodar em paralelo (arquivos diferentes, sem dependências pendentes)
- **[Story]**: US1 (conexão), US2 (identidade), US3 (publicar/receber), US4 (gestão de relays)

---

## Phase 1: Setup

**Purpose**: cumprir a obrigação do Princípio III **antes** de instalar dependências e preparar a nova
estrutura de pastas

- [X] T001 Registrar em `specs/002-nostr-relay-connection/research.md` a decisão D8 (armazenamento seguro): alternativas avaliadas com versão e data de publicação no pub.dev, critérios, riscos e mitigação — **antes** de qualquer alteração no `pubspec.yaml`, conforme constituição v1.0.0 Princípio III
- [X] T002 Registrar em `specs/002-nostr-relay-connection/research.md` a decisão D9 (persistência da lista de relays) nos mesmos moldes de T001, justificando por que o dado não sensível não usa o armazenamento seguro
- [X] T003 Confirmar a disponibilidade atual dos relays da lista padrão (decisão D7) e registrar os 3 endereços escolhidos, com a data da verificação, em `specs/002-nostr-relay-connection/research.md`
- [X] T004 Adicionar a dependência de armazenamento seguro ao `pubspec.yaml` com `flutter pub add`, somente após T001 estar escrito
- [X] T005 Adicionar a dependência de preferências locais ao `pubspec.yaml` com `flutter pub add`, somente após T002 estar escrito
- [X] T006 Criar a estrutura `lib/domain/`, `lib/services/` e `lib/screens/` em `Prototipo/driver/lib/`, movendo a tela atual de `lib/main.dart` para `lib/screens/home_screen.dart` e movendo `test/home_screen_test.dart` para `test/screens/home_screen_test.dart`, ajustando os imports — os testes da feature 001 são preservados, não reescritos
- [X] T007 Rodar `flutter analyze` e `flutter test` como linha de base, confirmando que a reorganização de T006 não quebrou nada antes de qualquer código novo

**Checkpoint**: dependências justificadas e instaladas, estrutura pronta, base verde

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: entidades de domínio, permissão de rede e composição — bloqueiam todas as user stories

**⚠️ CRITICAL**: nenhuma user story pode começar antes desta fase

- [X] T008 Declarar `android.permission.INTERNET` em `Prototipo/driver/android/app/src/main/AndroidManifest.xml` (FR-016, decisão D6), mantendo o manifesto sem nenhuma outra permissão — constituição, *Restrições de Segurança e Privacidade*: nada de permissão "para o futuro"
- [X] T009 [P] Criar a entidade `Identity` em `Prototipo/driver/lib/domain/identity.dart` com `publicKey` e `privateKey` (hex de 64 caracteres) e validação de formato, sem nenhum `toString` que exponha a chave privada (Princípio I)
- [X] T010 [P] Criar a entidade `Relay` e o enum `RelayStatus` (`connecting`/`connected`/`unavailable`) em `Prototipo/driver/lib/domain/relay.dart`, com `url`, `lastError` e `isDefault`, conforme `data-model.md`
- [X] T011 [P] Criar a entidade `NostrEvent` em `Prototipo/driver/lib/domain/nostr_event.dart` com `id`, `authorPublicKey`, `createdAt`, `kind`, `content` e `isSignatureValid`, usando tipos próprios do projeto e **sem importar `dart_nostr`** (Princípio III)
- [X] T012 Definir a lista padrão de relays como constante única em `Prototipo/driver/lib/services/default_relays.dart`, usando os endereços confirmados em T003
- [X] T013 Compor as dependências em `Prototipo/driver/lib/main.dart`: instanciar os serviços com injeção explícita de armazenamento e transporte, para que os testes possam substituí-los por dublês (decisão D5)
- [X] T014 Implementar a navegação entre as três telas (eventos, relays, identidade) em `Prototipo/driver/lib/main.dart`, mantendo `HomeScreen` como tela inicial

**Checkpoint**: domínio e composição prontos; app ainda compila e os testes existentes passam

---

## Phase 3: User Story 2 - Identidade Nostr própria e estável (Priority: P1)

**Goal**: o aplicativo cria uma identidade na primeira execução e a recupera nas seguintes, sem jamais
expor a chave privada.

**Independent Test**: anotar a chave pública, fechar e reabrir o app 5 vezes, verificando que é a mesma.

**Nota de ordem**: esta história vem antes da US1 apesar de o spec listá-la depois, porque a US3
(publicar) depende dela e ela não depende de nenhuma outra.

- [X] T015 [US2] Escrever os testes de `IdentityService` em `Prototipo/driver/test/services/identity_service_test.dart` com armazenamento dublê em memória, cobrindo: criação na primeira execução, recuperação da mesma identidade na segunda, chave recuperada em formato inválido tratada como armazenamento corrompido (não como identidade válida), e falha do armazenamento seguro reportada em vez de gerar identidade nova silenciosamente (Princípio II, edge case do spec)
- [X] T016 [US2] Implementar `IdentityService` em `Prototipo/driver/lib/services/identity_service.dart` usando `dart_nostr` para gerar o par de chaves e o armazenamento seguro injetado para persistir, até os testes de T015 passarem (FR-004, FR-005)
- [X] T017 [US2] Implementar `Prototipo/driver/lib/screens/identity_screen.dart` exibindo a chave pública em formato legível e copiável, sem exibir a chave privada por padrão (FR-006, FR-005)
- [X] T018 [US2] Escrever o teste de widget em `Prototipo/driver/test/screens/identity_screen_test.dart` verificando que a chave pública aparece e que a chave privada **não** aparece em nenhum ponto da árvore de widgets (SC-007)
- [X] T019 [US2] Documentar na `identity_screen` que desinstalar o aplicativo destrói a identidade de forma irreversível (US2 cenário 4)
- [X] T020 [US2] Executar a verificação de não vazamento do Princípio I: rodar o app, publicar nada ainda, e inspecionar `adb logcat` em busca da chave privada e de qualquer sequência hex de 64 caracteres; registrar o resultado no `quickstart.md` (cenário 3)

**Checkpoint**: identidade estável, verificada por teste e por inspeção de log

---

## Phase 4: User Story 1 - Conectar-se a relays e enxergar o estado (Priority: P1)

**Goal**: o app conecta-se a todos os relays da lista e mostra o estado real de cada um, sem que a falha
de um afete os demais.

**Independent Test**: abrir o app com a lista padrão e observar os estados evoluírem de "conectando" para
"conectado" ou "indisponível", com a interface responsiva.

- [X] T021 [US1] Escrever os testes de `RelayService` em `Prototipo/driver/test/services/relay_service_test.dart` com transporte dublê, cobrindo: transição `connecting → connected`, transição `connecting → unavailable` com motivo preenchido, isolamento (um relay em falha não altera o estado dos demais — FR-003/SC-003), timeout de relay que aceita a conexão e nunca responde, reconexão automática após perda e retorno de rede (FR-014) e **reconexão em que o relay reentrega eventos já recebidos antes da queda** — a troca Wi-Fi ↔ dados móveis não pode produzir evento duplicado na lista, cruzando FR-014 com a deduplicação de FR-010 (edge case do spec)
- [X] T022 [US1] Implementar `RelayService` em `Prototipo/driver/lib/services/relay_service.dart` gerenciando as conexões via `dart_nostr`, expondo o estado de cada relay como fluxo observável e mantendo os tipos da biblioteca confinados a este arquivo (Princípio III), até os testes de T021 passarem
- [X] T023 [US1] Exibir o estado de cada relay em `Prototipo/driver/lib/screens/home_screen.dart`, atualizando em tempo real e mostrando o motivo resumido quando indisponível (FR-002, US1 cenário 2)
- [X] T024 [US1] Tratar a ausência total de rede com mensagem compreensível, sem erro técnico cru nem travamento, em `Prototipo/driver/lib/screens/home_screen.dart` (FR-015, US1 cenário 3)
- [X] T025 [US1] **Acrescentar** ao `Prototipo/driver/test/screens/home_screen_test.dart` movido em T006 — sem remover os testes da feature 001 — a verificação de que os três estados de relay e a mensagem de ausência de rede são renderizados corretamente a partir de um serviço dublê
- [X] T026 [US1] Medir o tempo até o primeiro relay conectado em 10 aberturas do aplicativo e registrar os números e o método em `specs/002-nostr-relay-connection/quickstart.md` (SC-001) — Princípio V: número apresentado como medição precisa ter sido medido

**Checkpoint**: conectividade observável e resiliente a falha individual de relay

---

## Phase 5: User Story 3 - Publicar um evento assinado e recebê-lo de volta (Priority: P1)

**Goal**: a prova de conceito central — publicar e receber eventos assinados sem servidor próprio.

**Independent Test**: publicar o evento de teste e vê-lo retornar pela inscrição, exibido uma única vez.

**Depende de**: US2 (identidade para assinar) e US1 (relays conectados).

- [X] T027 [US3] Escrever os testes de `EventFeed` em `Prototipo/driver/test/services/event_feed_test.dart`, sem rede, cobrindo: evento com assinatura válida é aceito, evento com assinatura adulterada é descartado, evento cujo autor diverge da assinatura é descartado, evento com campo obrigatório ausente é descartado (FR-009, Princípio II — caso válido **e** inválido), o mesmo `id` entregue por dois relays é exibido uma vez (FR-010) e kind desconhecido é ignorado sem erro (contrato)
- [X] T028 [US3] Implementar `EventFeed` em `Prototipo/driver/lib/services/event_feed.dart` com verificação de assinatura **antes** de qualquer outro processamento, deduplicação por `id` e janela limitada de eventos em memória, até os testes de T027 passarem (FR-008, FR-009, FR-010, SC-006)
- [X] T029 [US3] Implementar a publicação de evento assinado em `Prototipo/driver/lib/services/relay_service.dart`, reportando por relay se foi aceito ou recusado, incluindo recusa por exigência de pagamento ou autenticação (FR-007, edge case do spec)
- [X] T030 [US3] Implementar a ação de publicar o evento de teste `kind: 1` em `Prototipo/driver/lib/screens/home_screen.dart`, em conformidade com `specs/002-nostr-relay-connection/contracts/nostr-events.md`
- [X] T031 [US3] Impedir a publicação quando nenhum relay estiver conectado, com explicação e sem perda silenciosa do conteúdo digitado, em `Prototipo/driver/lib/screens/home_screen.dart` (US3 cenário 5)
- [X] T032 [US3] Exibir os eventos recebidos com autor, horário e conteúdo em `Prototipo/driver/lib/screens/home_screen.dart`, renderizando `content` como **texto simples**, nunca como marcação (contrato, regra de recepção 3)
- [X] T033 [US3] Medir a responsividade sob rajada em `Prototipo/driver/lib/screens/home_screen.dart`: provocar a chegada de **ao menos 100 eventos marcados** — publicando a sequência por outro cliente com a tag do protótipo, ou removendo temporariamente o filtro `#t` para reproduzir a condição pré-emenda 01 — e registrar em `specs/002-nostr-relay-connection/quickstart.md` (cenário 9) o método usado, se houve congelamento perceptível e se o consumo de memória estabilizou com a janela limitada implementada em T028 (SC-006) — Princípio V: medir, não estimar
- [X] T034 [US3] Entregar o contrato à app do passageiro na mesma alteração que o implementa aqui (Princípio IV, constituição v1.1.0): consolidar o estado final de `specs/002-nostr-relay-connection/contracts/nostr-events.md`, incluindo qualquer ajuste feito durante T028–T032, e **relatar explicitamente ao autor** o arquivo e o que mudou, para repasse à sessão que mantém `Prototipo/passenger`. Não escrever naquele diretório a partir desta sessão
- [X] T035 [US3] Medir o tempo de ida e volta do evento em 10 publicações e registrar os números e o método em `specs/002-nostr-relay-connection/quickstart.md` (SC-002)

**Checkpoint**: prova de conceito completa — evento assinado sai, volta e é exibido uma única vez

---

## Phase 6: User Story 4 - Gerenciar a lista de relays (Priority: P2)

**Goal**: o motorista adiciona e remove relays, e a lista sobrevive ao reinício do aplicativo.

**Independent Test**: adicionar, remover, reabrir o app e verificar que a lista persistiu.

- [X] T036 [US4] Escrever os testes do repositório de relays em `Prototipo/driver/test/services/relay_repository_test.dart` com armazenamento dublê, cobrindo: persistir e restaurar a lista, rejeitar endereço inválido, rejeitar duplicado, remover relay e restaurar a lista padrão quando vazia (FR-011, FR-012, FR-013)
- [X] T037 [US4] Implementar o repositório de relays em `Prototipo/driver/lib/services/relay_repository.dart` serializando a lista como JSON nas preferências locais, até os testes de T036 passarem
- [X] T038 [US4] Implementar `Prototipo/driver/lib/screens/relays_screen.dart` com listagem, adição e remoção de relays, exibindo o estado de conexão de cada um
- [X] T039 [US4] Conectar a adição e a remoção ao `RelayService` em `Prototipo/driver/lib/services/relay_service.dart`, de modo que adicionar dispare tentativa de conexão e remover encerre a conexão existente (US4 cenários 1 e 3)
- [X] T040 [US4] Tratar a lista vazia em `Prototipo/driver/lib/screens/relays_screen.dart`, explicando a situação e oferecendo restaurar a lista padrão (FR-013, US4 cenário 5)
- [X] T041 [US4] Escrever o teste de widget em `Prototipo/driver/test/screens/relays_screen_test.dart` verificando a recusa de endereço inválido e de duplicado, com a lista permanecendo inalterada (US4 cenário 2)

**Checkpoint**: lista de relays gerenciável e persistente

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: fechar os gates da constituição (seção *Fluxo de Desenvolvimento e Gates*)

- [X] T042 Executar `flutter analyze` em `Prototipo/driver/` até obter `No issues found!` (gate 1)
- [X] T043 [P] Executar `dart format lib test` em `Prototipo/driver/` e confirmar que nada ficou fora do padrão
- [X] T044 Executar `flutter test` em `Prototipo/driver/` e confirmar aprovação integral, **sem nenhum teste ignorado ou marcado como pendente** (gate 2)
- [X] T045 Executar os 10 cenários de `specs/002-nostr-relay-connection/quickstart.md`, registrando o resultado de cada um — cenários que falharem devem ser **relatados, não omitidos** (gate 3)
- [X] T046 Executar a verificação final de não vazamento do Princípio I após publicação de eventos: inspecionar `adb logcat` e o conteúdo efetivamente enviado aos relays em busca da chave privada, e registrar o resultado (gate 4, SC-007)
- [X] T047 Gerar a build de release com `flutter build apk --release` em `Prototipo/driver/` e confirmar com `aapt2 dump permissions` que `android.permission.INTERNET` está declarada e que nenhuma outra permissão aparece (quickstart cenário 10)
- [X] T048 [P] Atualizar `Prototipo/driver/README.md` com o escopo desta feature, as novas dependências e a advertência de que desinstalar o app destrói a identidade
- [X] T049 [P] Atualizar a seção "Protótipo" de `/home/oseias/Documentos/ufsc/TCC/CLAUDE.md` com o novo estado do `driver/` e os comandos que mudarem
- [X] T050 Commitar em português descrevendo a mudança de comportamento, não os arquivos tocados (gate 5)

---

## Phase 8: Emenda 01 ao contrato — filtragem por marcador

**Purpose**: aplicar a emenda 01 (16/09/2026) do contrato de eventos, acordada com a sessão que mantém
`Prototipo/passenger`. Sem ela, a inscrição entrega o tráfego social público da rede inteira.

- [X] T051 Aplicar as três mudanças da emenda em `specs/002-nostr-relay-connection/contracts/nostr-events.md`: marcador na linha de `tags`, seção *Forma da inscrição* e regra de recepção 6, mais o histórico de emendas
- [X] T052 Registrar a emenda em `specs/002-nostr-relay-connection/spec.md`: clarificação da sessão 16/09, FR-018, FR-019, SC-009 e o cenário 6 da User Story 3
- [X] T053 Publicar com o marcador em `Prototipo/driver/lib/services/identity_service.dart`, acrescentando a tag `["t", "tcc-ufsc-caronas"]` ao evento assinado (FR-018)
- [X] T054 Filtrar a inscrição por marcador em `Prototipo/driver/lib/services/nostr_relay_gateway.dart`, usando `#t` além de `kinds` (FR-018)
- [X] T055 Descartar evento sem o marcador em `Prototipo/driver/lib/services/event_feed.dart`, mesmo quando o relay o entregar (FR-019, regra 6 do contrato)
- [X] T056 Acrescentar os testes da emenda em `Prototipo/driver/test/services/event_feed_test.dart` e `Prototipo/driver/test/services/identity_service_test.dart`: evento sem marcador é descartado, evento com marcador é aceito, evento publicado carrega a tag
- [X] T057 Medir SC-009 no emulador e registrar o resultado em `specs/002-nostr-relay-connection/quickstart.md`, comparando com a medição anterior sem filtro

---

## Dependencies & Execution Order

```text
Phase 1 (Setup: T001–T007)
    T001/T002 → T004/T005   (registro da decisão ANTES de instalar — Princípio III)
        ↓
Phase 2 (Foundational: T008–T014)
        ↓
Phase 3 (US2 · identidade: T015–T020)
        ↓                    ↘
Phase 4 (US1 · conexão: T021–T026)
        ↓                    ↙
Phase 5 (US3 · publicar/receber: T027–T035)   ← exige US1 + US2
        ↓
Phase 6 (US4 · gestão de relays: T036–T041)
        ↓
Phase 7 (Polish: T042–T050)
```

- **T001/T002 bloqueiam T004/T005**: instalar dependência antes de registrar a decisão viola o
  Princípio III. Esta é a única dependência do plano imposta por governança, não por técnica.
- **US2 e US1 são independentes entre si** e podem ser desenvolvidas em paralelo por pessoas diferentes
  após a Phase 2 (arquivos disjuntos: `identity_service`/`identity_screen` vs `relay_service`).
- **US3 depende de US2** (identidade para assinar) **e de US1** (relays conectados).
- **US4 depende de US1** (o `RelayService` que ela manipula) e é a única P2 — pode ser adiada sem
  comprometer a prova de conceito.
- **T034 cruza projetos**: é a última tarefa da US3 por construção — o contrato só pode ser entregue
  depois de estabilizado pela implementação (T028–T032). A entrega é por relato ao autor, não por
  edição direta em `Prototipo/passenger` (Princípio IV, constituição v1.1.0).

## Parallel Opportunities

- Phase 2: `T009`, `T010` e `T011` em paralelo (três arquivos de domínio distintos).
- Phase 3 × Phase 4: após o checkpoint da Phase 2, as trilhas de identidade e de conexão não compartilham
  arquivos e podem correr simultaneamente.
- Phase 7: `T043`, `T048` e `T049` em paralelo.
- Dentro de cada história, teste → implementação é sequencial por construção (Princípio II).

## Implementation Strategy

**MVP (prova de conceito do TCC)**: Phases 1–5 (T001–T035). Ao final existe um aplicativo que tem
identidade própria, conecta-se a múltiplos relays e publica e recebe eventos assinados sem servidor
próprio — que é exatamente a hipótese que o trabalho precisa demonstrar.

**Incremento 2**: Phase 6 (T036–T041) — gestão de relays, que permite comparar provedores diferentes e
enriquece a análise de viabilidade.

**Fechamento**: Phase 7 (T042–T050) — os cinco gates da constituição.

**Total**: 57 tarefas (Setup 7, Foundational 7, US2 6, US1 6, US3 9, US4 6, Polish 9, Emenda 01 7).
