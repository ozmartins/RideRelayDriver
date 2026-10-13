# Implementation Plan: Formas de pagamento aceitas

**Branch**: `005-formas-pagamento` (a criar) | **Date**: 2026-09-20 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/005-formas-pagamento/spec.md`

## Summary

Acrescentar ao formulário de cadastro do motorista (feature 003) a seleção das formas de pagamento
aceitas — Dinheiro, PIX e Cartão, não mutuamente exclusivas, ao menos uma obrigatória. `DriverProfile`
ganha um `Set<PaymentMethod>`; a tabela SQLite `driver_profile` ganha a coluna `payment_methods`, com
migração de esquema (versão 1 → 2). Um cadastro de uma instalação anterior a esta feature, sem nenhuma
forma de pagamento, é tratado pela mesma regra já existente de campo obrigatório ausente (FR-010 da
feature 003) — sem caminho de migração especial, por decisão deliberada (Princípio V).

## Technical Context

**Language/Version**: Dart 3.13.3 (Flutter, stable) — inalterado em relação às features anteriores

**Primary Dependencies**: nenhuma nova. Reaproveita `sqflite` (já usado por `SqfliteCadastroStore`,
decisão D1 de `specs/003-cadastro-motorista/research.md`) e `package:flutter` (`CheckboxListTile`) —
ambos já dependências do projeto.

**Storage**: SQLite via `sqflite`, mesma tabela `driver_profile` da feature 003, com migração de
esquema (versão 1 → 2, D2 de `research.md`) para a coluna `payment_methods`.

**Testing**: `flutter test` com testes de unidade de `PaymentMethod` (rótulo, serialização) e de
`DriverProfile` (validade exigindo conjunto não vazio, `toMap`/`fromMap`, `copyWith`, igualdade),
testes de `SqfliteCadastroStore`/`CadastroStore` cobrindo a migração de esquema (linha da versão 1
carregando com conjunto vazio, tratada como corrompida) sem SQLite real, e testes de widget de
`CadastroScreen` cobrindo seleção independente das três opções e bloqueio de envio sem nenhuma
marcada. `flutter analyze` como gate.

**Target Platform**: Android apenas (inalterado). Nenhuma permissão nova.

**Project Type**: mobile-app

**Performance Goals**: preenchimento do formulário completo (incluindo formas de pagamento) em até 2
minutos, consistente com SC-001 da feature 003, medido no `quickstart.md` — não estimado.

**Constraints**: as três opções são fixas, sem fonte externa (D1 de `research.md`); nenhum caminho de
migração de dado além do `ALTER TABLE` (D2, decisão deliberada de simplicidade).

**Scale/Scope**: uma tela modificada (`CadastroScreen`), uma entidade nova (`PaymentMethod`), uma
entidade existente estendida (`DriverProfile`), um esquema SQLite migrado (`driver_profile`, versão 1
→ 2); não introduz nenhum evento Nostr novo, logo não toca o Princípio IV.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

**Estado da constituição**: em vigor na versão **2.2.0**.

**Resultado do gate**: PASS.

| Princípio | Avaliação desta feature |
|-----------|--------------------------|
| I. Segredo criptográfico não vaza | Não se aplica — esta feature não toca chave privada nem material de assinatura; formas de pagamento aceitas não são segredo criptográfico, mesma categoria do restante do cadastro (FR-010 da feature 003). |
| II. Assinatura e verificação nascem com teste | Não se aplica diretamente — esta feature não assina nem verifica eventos. Por analogia (mesmo padrão já aplicado à validação de UF/cidade/placa na feature 003), o código que decide "cadastro válido ou corrompido" (`DriverProfile.isValido`, agora incluindo `paymentMethods.isNotEmpty`) tem teste do caso válido e do inválido, sem SQLite real. |
| III. Dependência de terceiros exige decisão registrada | PASS por vacuidade — nenhuma dependência nova em `pubspec.yaml`; `sqflite` e `package:flutter` já são dependências registradas em features anteriores. |
| IV. O contrato de evento vem antes do código | Não se aplica — esta feature não cria nem altera nenhum evento Nostr; as formas de pagamento aceitas são dado puramente local do cadastro do motorista, sem contrapartida no contrato de eventos (Assumptions do `spec.md`). Nada precisa ser replicado em `Prototipo/passenger`. |
| V. Simplicidade proporcional e rastreabilidade acadêmica | Atendido com justificativa. D2 de `research.md` descarta uma tabela associativa e uma coluna JSON por desproporcionais a um conjunto de no máximo 3 elementos fixos; a decisão de **não** introduzir um caminho de migração de dado especial (FR-006 do `spec.md`) é, ela mesma, uma aplicação direta deste princípio — o protótipo não tem base instalada de usuários reais a proteger. |

**Restrições de Segurança e Privacidade**: nenhuma permissão nova é declarada. As formas de pagamento
aceitas permanecem apenas no aparelho (SQLite local) — esta feature não publica nada em relay, então a
regra de "dado pessoal em relay público" não é acionada.

**Fluxo de Desenvolvimento e Gates**: `flutter analyze` e `flutter test` limpos, e execução dos
cenários do `quickstart.md` (incluindo o Cenário 4, migração de esquema em aparelho real) são gates
desta feature, conforme a seção "Fluxo de Desenvolvimento e Gates" da constituição.

Nenhuma violação sem exceção registrada. Gate PASS.

## Project Structure

### Documentation (this feature)

```text
specs/005-formas-pagamento/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md         # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

Sem `contracts/`: esta feature não expõe nenhuma interface externa nova (nem evento Nostr, nem serviço
de terceiros) — só estende uma entidade e uma tela já existentes, e o único contrato interno que muda
(`CadastroStore`) já está descrito em `data-model.md`, sem exigir um arquivo próprio (mesmo padrão de
economia de estrutura da feature 004, que também não teve `contracts/`).

### Source Code (repository root)

```text
lib/
├── domain/
│   ├── payment_method.dart       # novo — enum PaymentMethod (cash/pix/card) + rótulos
│   └── driver_profile.dart       # modificado — ganha paymentMethods (Set<PaymentMethod>),
│                                  # isValido exige não vazio, toMap/fromMap, copyWith, ==/hashCode
└── services/
    └── sqflite_cadastro_store.dart  # modificado — versão do banco 1 → 2, onUpgrade com ALTER TABLE,
                                      # serialização de payment_methods

lib/screens/
└── cadastro_screen.dart          # modificado — três CheckboxListTile (D3 de research.md), validação
                                   # de envio exige ao menos uma marcada

test/
├── domain/
│   ├── payment_method_test.dart     # novo
│   └── driver_profile_test.dart     # modificado — cobre paymentMethods em isValido/toMap/fromMap
├── services/
│   └── cadastro_store_test.dart     # modificado — cobre migração de esquema e conjunto vazio
└── screens/
    └── cadastro_screen_test.dart    # modificado — cobre seleção das formas de pagamento
```

**Structure Decision**: mantém a mesma divisão em `domain/` + `services/` + `screens/` já usada pelas
features anteriores do motorista; nenhuma camada nova. A migração de esquema é tratada inteiramente
dentro de `SqfliteCadastroStore` (já o único arquivo que conhece `package:sqflite`, Princípio III),
sem introduzir um serviço de migração à parte.

## Complexity Tracking

Nenhuma violação de constituição sem exceção já registrada — tabela não aplicável.
