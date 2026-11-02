# Implementation Plan: Integridade das avaliações (Row Signing)

**Branch**: `master` (commits diretos, sem branch de feature — Padrão de Commits da constituição) | **Date**: 2026-09-23 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/014-integridade-row-signing/spec.md`

**Note**: This template is filled in by the `/speckit-plan` command. See `.specify/templates/plan-template.md` for the execution workflow.

## Summary

`ride_ratings` (feature `013-avaliar-corrida`) ganha duas colunas — `signature` e `tampered` — e
`SqfliteRideRatingStore` passa a assinar cada avaliação ao gravar e a validar a assinatura ao ler,
usando a identidade Nostr já existente do motorista (nenhuma chave nova). Canonicalização,
assinatura e verificação vivem em funções puras e testáveis (`RideRatingSignature`), reaproveitando
`Nostr.instance.services.keys.sign`/`.verify` do `dart_nostr` (já uma dependência do projeto) —
que já fazem SHA-256 do payload internamente antes de assinar/verificar com a chave secp256k1 da
identidade, dispensando qualquer hashing manual. Mesma decisão de design da feature irmã do
passageiro (`passenger/specs/012-integridade-row-signing/`), reaplicada aqui de forma independente
sobre o código do motorista — as duas apps não são espelho de código.

`RideRatingStore.save`/`forRide` passam a receber `Identity` por parâmetro. Diferença em relação
ao passageiro: `widget.identity` do motorista é `Identity?` (nulo se a identidade não pôde ser
criada/recuperada no início — `_startupError`), então `MapScreen._mostrarModalAvaliacao` MUST
verificar `identity != null` antes de assinar, mesmo padrão de guarda já usado por
`_enviarOrcamento`/`_confirmarEncontro`/etc.; se nulo, a avaliação não é persistida (sem crash),
consequência aceita — nenhuma mensagem de erro nova na `RideRatingModal`, que não tem esse
mecanismo hoje (fora de escopo desta feature, ver Assumptions).

## Technical Context

**Language/Version**: Dart 3 / Flutter (mesma versão já fixada no `pubspec.yaml` do projeto)

**Primary Dependencies**: `dart_nostr` (já em uso, via `nostr.Nostr.instance.services.keys.sign`/
`.verify` — mesma API de baixo nível já usada por `IdentityService`) — nenhuma dependência nova.

**Storage**: SQLite, tabela `ride_ratings` existente (feature 013) migrada da versão 1 para a 2
(`signature TEXT`, `tampered INTEGER NOT NULL DEFAULT 0`).

**Testing**: `flutter_test`. A canonicalização/assinatura/verificação (`RideRatingSignature`) é
pura e testável diretamente, cobrindo caso válido e inválido (Princípio II, não negociável, já que
este código assina e verifica assinaturas). O contrato de `RideRatingStore` (validar, marcar,
excluir) é testado contra um dublê em memória que reproduz a mesma lógica —
`SqfliteRideRatingStore` continua sem teste de integração SQLite real, mesma decisão já registrada
em `specs/013-avaliar-corrida/research.md` (D1), agora estendida: a lógica de decisão fica em
funções puras testadas, e só a mecânica SQL (ler/escrever coluna) permanece confiada por analogia.

**Target Platform**: Android (sem mudança)

**Project Type**: mobile-app (Flutter, Android apenas) — mesma estrutura já usada pelo motorista.

**Performance Goals**: a validação de uma leitura MUST completar dentro da mesma ordem de grandeza
já observada para outras operações locais do protótipo (sub-segundo).

**Constraints**: a chave privada, a assinatura e o processo de validação MUST NOT ser transmitidos
a nenhum relay nem serviço externo (FR-008) — mecanismo inteiramente local, mesma garantia já
verificada para a identidade Nostr (Princípio I).

**Scale/Scope**: protótipo de avaliação de viabilidade — sem requisito de escala além do já
estabelecido.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Princípio | Avaliação |
|---|---|
| I. Segredo criptográfico não vaza (NÃO NEGOCIÁVEL) | GATE ATIVO — esta feature assina com a chave privada da identidade. `Identity.toString()` já omite as chaves (herdado, sem alteração); a assinatura resultante nunca é publicada nem logada — verificação explícita de não vazamento incluída nos critérios de aceitação (task de Polish, inspeção de log/tráfego). PASS, condicionado a essa verificação. |
| II. Assinatura e verificação nascem com teste (NÃO NEGOCIÁVEL) | GATE ATIVO — `RideRatingSignature.sign`/`.verify` MUST ter teste cobrindo o caso válido (assinatura própria valida) e o caso inválido (dado adulterado depois de assinado; assinatura de outra identidade) — nenhuma rede nem relay envolvido. PASS, condicionado a essa cobertura. |
| III. Dependência de terceiros exige decisão registrada | PASS. Nenhuma dependência nova — `dart_nostr` já registrado (feature 002); reaproveitar `services.keys.sign`/`.verify` é decisão de uso, não de dependência nova (registrada em `research.md`, D1, por transparência). |
| IV. O contrato de evento vem antes do código | PASS por vacuidade. Nenhum evento Nostr novo — a assinatura de linha nunca é publicada nem trafega entre as duas apps. |
| V. Simplicidade proporcional e rastreabilidade acadêmica | PASS. Canonicalização por concatenação simples; lógica de decisão extraída para funções puras só porque isso é o que a torna testável sem duplicar SQLite em teste — não é abstração especulativa. A guarda de `identity != null` reaproveita o padrão já existente, sem mecanismo novo de tratamento de erro. |

**Resultado do gate inicial**: PASS, com dois itens do Fluxo de Desenvolvimento e Gates (verificação
de não vazamento; cobertura de teste válido/inválido) explicitados como tarefas obrigatórias na
Phase 2 — sem violação a justificar em Complexity Tracking.

## Project Structure

### Documentation (this feature)

```text
specs/014-integridade-row-signing/
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
└── services/
    ├── ride_rating_signature.dart   # NOVO — canonicalPayload/sign/verify puros, sobre
    │                                 # nostr.Nostr.instance.services.keys (único ponto novo que
    │                                 # toca dart_nostr diretamente para isto, Princípio III)
    └── ride_rating_store.dart       # ALTERADO — RideRatingStore.save/forRide passam a receber
                                      # Identity; SqfliteRideRatingStore migra para v2
                                      # (signature, tampered), assina ao salvar, valida e marca ao
                                      # ler, exclui violados

driver/lib/screens/
└── map_screen.dart                  # ALTERADO — _mostrarModalAvaliacao.onConfirm passa a checar
                                      # widget.identity != null antes de chamar
                                      # RideRatingStore.save (guarda já usada por outros métodos
                                      # desta tela); se nulo, não persiste, só fecha a modal

driver/test/
└── services/
    ├── ride_rating_signature_test.dart   # NOVO — caso válido e inválido (Princípio II)
    └── ride_rating_store_test.dart       # NOVO — dublê em memória do contrato (validar, marcar,
                                           # excluir); SqfliteRideRatingStore permanece sem teste
                                           # de integração real (D2 de research.md)
```

**Structure Decision**: mesma estrutura de três camadas já usada desde a feature 002 do
motorista, sem novo diretório de topo. Nenhum arquivo de contrato Nostr é tocado.

## Complexity Tracking

*Nenhuma violação de princípio a justificar — tabela omitida (Constitution Check: PASS).*
