# Implementation Plan: Conexão do Motorista com Relays Nostr

**Branch**: `002-nostr-relay-connection` (a criar) | **Date**: 2026-09-15 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/002-nostr-relay-connection/spec.md`

## Summary

Dar ao aplicativo do motorista uma identidade Nostr persistente, conexão simultânea a múltiplos relays e
a capacidade de publicar e receber eventos assinados — a prova de conceito central do TCC, executada sem
nenhum servidor próprio.

A abordagem usa a biblioteca **`dart_nostr ^10.0.1`**, já instalada no projeto, para assinatura,
serialização de eventos e gerenciamento das conexões WebSocket; `flutter_secure_storage` para guardar a
chave privada no Keystore do Android; e `shared_preferences` para a lista de relays, que não é sensível.
A camada de domínio deixa de ser postergada: esta feature introduz a primeira separação real entre UI e
serviços, porque três estados assíncronos independentes (identidade, conexões, fluxo de eventos) passam a
coexistir.

## Technical Context

**Language/Version**: Dart 3.13.3 (Flutter 3.47.4, stable) — inalterado em relação à feature 001

**Primary Dependencies**:
- `dart_nostr ^10.0.1` — protocolo Nostr (chaves, assinatura, eventos, relays) — **já instalada**
- `flutter_secure_storage` — chave privada no Android Keystore (a adicionar)
- `shared_preferences` — persistência da lista de relays (a adicionar)
- `flutter_test` + `flutter_lints` (dev, já presentes)

**Storage**: armazenamento local do aparelho, em dois níveis — Keystore (chave privada) e preferências
(lista de relays). Nenhum banco de dados; eventos recebidos ficam apenas em memória nesta etapa.

**Testing**: `flutter test` com testes de unidade dos serviços (identidade, relays, deduplicação de
eventos) usando dublês para relay e armazenamento; testes de widget das telas; `flutter analyze` como
gate. Testes não devem depender de relay público real — ver decisão D5 em `research.md`.

**Target Platform**: Android apenas (inalterado). `android.permission.INTERNET` passa a ser **obrigatória
no manifesto principal**, não só em debug (FR-016).

**Project Type**: mobile-app

**Performance Goals**: primeiro relay conectado em ≤ 5 s (SC-001); ida e volta de evento em ≤ 5 s
(SC-002); UI responsiva sob rajada de ≥ 100 eventos (SC-006)

**Constraints**: sem backend próprio; chave privada nunca sai do aparelho, não vai a log nem a tela
(FR-005/SC-007); falha de um relay não pode derrubar os demais (FR-003); reconexão automática após queda
de rede (FR-014)

**Scale/Scope**: 3 telas (principal/eventos, relays, identidade), 3 serviços, ~3 entidades de domínio

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

**Estado da constituição**: em vigor na versão **1.1.0** (ratificada como 1.0.0 em 2026-09-15 e emendada
no mesmo dia; 5 princípios, dois deles NÃO NEGOCIÁVEIS). Esta seção foi reavaliada após a ratificação e
revista após a emenda; a avaliação original ("PASS por vacuidade") está superada.

**Resultado do gate**: PASS, com obrigações explícitas herdadas de cada princípio.

| Princípio | Avaliação desta feature |
|-----------|-------------------------|
| I. Segredo criptográfico não vaza | **Atendido por desenho**: chave privada só no Keystore (D2), FR-005 proíbe exibição/log/envio, SC-007 exige verificação por inspeção e o cenário 3 do `quickstart.md` executa essa inspeção via `adb logcat`. |
| II. Assinatura e verificação nascem com teste | **Obriga escopo adicional**: a verificação de assinatura (FR-009) e a deduplicação (FR-010) precisam de teste do caso válido **e** do inválido — assinatura adulterada, autor divergente, campo ausente —, todos com dublês e sem rede (D5). `tasks.md` deve gerar essas tarefas como obrigatórias, não opcionais. |
| III. Dependência de terceiros exige decisão registrada | **Atendido para `dart_nostr`** (D1, com alternativas, versões e datas). **Pendente**: `flutter_secure_storage` e `shared_preferences` ainda não têm entrada própria em `research.md` — devem ser registradas antes de serem adicionadas ao `pubspec.yaml`. A confinação de tipos da biblioteca em `lib/services/` já está prevista na Structure Decision. |
| IV. O contrato de evento vem antes do código (v1.1.0) | **Atendido**: `contracts/nostr-events.md` existe antes da implementação e já fixa as regras de recepção (verificar antes de processar, deduplicar, tratar conteúdo como dado, ignorar kinds desconhecidos). **Obrigação**: o contrato precisa chegar à app do passageiro na mesma alteração — por relato explícito ao autor (T034), já que esta sessão não escreve em `Prototipo/passenger`. Forma admitida pela emenda 1.1.0, motivada pelo achado D1 do analyze. |
| V. Simplicidade proporcional e rastreabilidade | **Atendido com justificativa**: a introdução de `domain/services/screens` está fundamentada pela necessidade de testar sem relay real (Structure Decision), não por estética. Nenhuma camada adicional é criada. Os números de SC-001/SC-002/SC-006 precisam ser **medidos**, com método descrito, e não estimados. |

**Restrições de Segurança e Privacidade**: a feature declara apenas `INTERNET` (D6), permissão exigida
por funcionalidade já especificada — sem permissão "para o futuro". Não há acesso a localização,
contatos ou armazenamento externo. Os eventos desta etapa são públicos e não carregam dado pessoal, o
que está declarado nas *Assumptions* do spec.

**Fluxo de Desenvolvimento e Gates**: `flutter analyze` e `flutter test` limpos, execução dos 10
cenários do `quickstart.md` com relato honesto de falhas, e a verificação de não vazamento do Princípio I
registrada — todos condições para declarar a feature concluída.

## Project Structure

### Documentation (this feature)

```text
specs/002-nostr-relay-connection/
├── plan.md              # Este arquivo
├── research.md          # Fase 0 — inclui a decisão da biblioteca (FR-017)
├── data-model.md        # Fase 1
├── quickstart.md        # Fase 1
├── contracts/
│   └── nostr-events.md  # Fase 1 — formato dos eventos trafegados
├── checklists/
│   └── requirements.md
└── tasks.md             # Fase 2 (/speckit-tasks)
```

Ao contrário da feature 001, **há `contracts/`**: os eventos publicados são a interface externa do
aplicativo — é por eles, e somente por eles, que a app do passageiro vai interoperar. O contrato precisa
existir por escrito antes de qualquer código, porque terá de ser replicado de forma idêntica do outro
lado.

### Source Code (repository root)

```text
Prototipo/driver/
├── lib/
│   ├── main.dart                      # entrypoint + composição das dependências
│   ├── domain/
│   │   ├── identity.dart              # identidade do motorista (chave pública/privada)
│   │   ├── relay.dart                 # relay + estado de conexão
│   │   └── nostr_event.dart           # evento (id, autor, horário, tipo, conteúdo)
│   ├── services/
│   │   ├── identity_service.dart      # cria/recupera identidade; assina o evento de teste
│   │   ├── key_store.dart             # interface do armazenamento seguro + impl. Keystore
│   │   ├── key_value_store.dart       # interface de preferências locais + impl. shared_preferences
│   │   ├── relay_service.dart         # conexões, estados, reconexão, publicação
│   │   ├── relay_gateway.dart         # interface do transporte de relay (injetável nos testes)
│   │   ├── nostr_relay_gateway.dart   # transporte real sobre dart_nostr, uma instância por relay
│   │   ├── relay_repository.dart      # persiste a lista de relays nas preferências locais
│   │   ├── default_relays.dart        # lista padrão embutida (decisão D7), constante única
│   │   ├── prototype_marker.dart      # marcador do protótipo e sua verificação (emenda 01)
│   │   ├── event_verifier.dart        # recalcula o id canônico e verifica a assinatura
│   │   └── event_feed.dart            # descarte de inválidos/sem marcador, dedup e janela
│   └── screens/
│       ├── home_screen.dart           # eventos recebidos + publicar evento de teste
│       ├── relays_screen.dart         # listar/adicionar/remover relays
│       └── identity_screen.dart       # exibir chave pública
├── test/
│   ├── services/
│   │   ├── identity_service_test.dart
│   │   ├── relay_service_test.dart
│   │   ├── relay_repository_test.dart
│   │   └── event_feed_test.dart       # inclui os casos da emenda 01
│   ├── screens/
│   │   ├── home_screen_test.dart
│   │   ├── relays_screen_test.dart
│   │   └── identity_screen_test.dart
│                                       # o test/home_screen_test.dart da feature 001 é movido
│                                       # para test/screens/ em T006, não duplicado
└── android/app/src/main/AndroidManifest.xml   # + android.permission.INTERNET
```

Os três arquivos que conhecem tipos de `dart_nostr` são `identity_service.dart`,
`nostr_relay_gateway.dart` e `event_verifier.dart` — nenhum outro, por exigência do Princípio III.

**Structure Decision**: introduz-se agora a separação `domain/` + `services/` + `screens/`, abandonando o
`main.dart` plano da feature 001. A justificativa é concreta, não estética: a lógica de assinatura,
deduplicação e reconexão precisa ser testável **sem** relay real e sem árvore de widgets — mantê-la
dentro dos widgets tornaria SC-002, SC-003 e SC-006 verificáveis apenas manualmente. Nenhuma camada
adicional (repositórios, casos de uso) é introduzida: não há consumidor para ela.

Observação de coerência entre as duas apps: `Prototipo/passenger` adotou `lib/main.dart` +
`screens/` + `shared/`. A estrutura aqui é compatível em espírito; o que **precisa** ser idêntico entre
as apps não é o layout de pastas, e sim o contrato de eventos em `contracts/nostr-events.md`.

## Complexity Tracking

> Nenhuma violação de constituição a justificar (ver Constitution Check).
