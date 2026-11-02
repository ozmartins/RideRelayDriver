# Implementation Plan: Preço padrão por quilômetro

**Branch**: `006-preco-por-km` (a criar) | **Date**: 2026-09-20 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/006-preco-por-km/spec.md`

## Summary

Acrescentar ao formulário de cadastro do motorista (feature 003, já estendido pela feature 005) um
campo para o preço padrão por quilômetro, em reais, com no máximo duas casas decimais, obrigatório e
maior que zero, acompanhado de um texto explicando que é um valor sugerido, ajustável pelo motorista
em cada corrida aceita (ajuste esse que é trabalho de uma feature futura, fora de escopo aqui).
`DriverProfile` ganha um `double precoPorKm`; a tabela SQLite `driver_profile` ganha a coluna
`preco_por_km`, com migração de esquema (versão 2 → 3). Um cadastro de uma instalação anterior a esta
feature, sem preço registrado, é tratado pela mesma regra já existente de campo obrigatório ausente —
sem caminho de migração especial, replicando a decisão da feature 005 (Princípio V).

## Technical Context

**Language/Version**: Dart 3.13.3 (Flutter, stable) — inalterado em relação às features anteriores

**Primary Dependencies**: nenhuma nova. Reaproveita `sqflite` (já usado por `SqfliteCadastroStore`) e
`package:flutter` (`TextField` com `TextInputType.numberWithOptions(decimal: true)`) — ambos já
dependências do projeto.

**Storage**: SQLite via `sqflite`, mesma tabela `driver_profile` das features 003/005, com migração
de esquema (versão 2 → 3, D2 de `research.md`) para a coluna `preco_por_km`.

**Testing**: `flutter test` com testes de unidade de `DriverProfile.parsePrecoPorKm` (aceita
vírgula/ponto, recusa vazio/zero/negativo/mais de duas casas decimais) e de `DriverProfile.isValido`
(exigindo `precoPorKm > 0`), `toMap`/`fromMap`/`copyWith`/igualdade, testes de
`SqfliteCadastroStore`/`CadastroStore` cobrindo a migração de esquema (linha das versões 1/2
carregando com `precoPorKm == 0`, tratada como corrompida) sem SQLite real, e testes de widget de
`CadastroScreen` cobrindo o campo e sua validação. `flutter analyze` como gate.

**Target Platform**: Android apenas (inalterado). Nenhuma permissão nova.

**Project Type**: mobile-app

**Performance Goals**: preenchimento do formulário completo (incluindo o preço) sem passo adicional
além de digitar o valor (SC-002 do `spec.md`), medido no `quickstart.md` — não estimado.

**Constraints**: valor sempre maior que zero, no máximo duas casas decimais (FR-001, FR-002); nenhum
caminho de migração de dado além do `ALTER TABLE` (D2, decisão deliberada de simplicidade, já
estabelecida pela feature 005).

**Scale/Scope**: uma tela modificada (`CadastroScreen`), uma entidade existente estendida
(`DriverProfile`), um esquema SQLite migrado (`driver_profile`, versão 2 → 3); não introduz nenhum
evento Nostr novo, logo não toca o Princípio IV.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

**Estado da constituição**: em vigor na versão **2.2.0**.

**Resultado do gate**: PASS.

| Princípio | Avaliação desta feature |
|-----------|--------------------------|
| I. Segredo criptográfico não vaza | Não se aplica — esta feature não toca chave privada nem material de assinatura; preço por quilômetro não é segredo criptográfico, mesma categoria do restante do cadastro. |
| II. Assinatura e verificação nascem com teste | Não se aplica diretamente — esta feature não assina nem verifica eventos. Por analogia (mesmo padrão já aplicado a placa/UF/cidade na feature 003 e a formas de pagamento na feature 005), o código que decide "cadastro válido ou corrompido" (`DriverProfile.isValido`, agora incluindo `precoPorKm > 0`) e o parsing de entrada (`parsePrecoPorKm`) têm teste do caso válido e do inválido, sem SQLite real. |
| III. Dependência de terceiros exige decisão registrada | PASS por vacuidade — nenhuma dependência nova em `pubspec.yaml`; `sqflite` e `package:flutter` já são dependências registradas em features anteriores. |
| IV. O contrato de evento vem antes do código | Não se aplica — esta feature não cria nem altera nenhum evento Nostr; o preço padrão é dado puramente local do cadastro do motorista, sem contrapartida no contrato de eventos (Assumptions do `spec.md`). Nada precisa ser replicado em `Prototipo/passenger`. |
| V. Simplicidade proporcional e rastreabilidade acadêmica | Atendido com justificativa. D1/D2 de `research.md` descartam representar o valor em centavos (`int`) ou usar um pacote de formatação de moeda por desproporcionais a um único campo sem aritmética; a decisão de **não** introduzir um caminho de migração de dado especial (FR-006 do `spec.md`) replica a mesma escolha já justificada pela feature 005. |

**Restrições de Segurança e Privacidade**: nenhuma permissão nova é declarada. O preço por quilômetro
permanece apenas no aparelho (SQLite local) — esta feature não publica nada em relay.

**Fluxo de Desenvolvimento e Gates**: `flutter analyze` e `flutter test` limpos, e execução dos
cenários do `quickstart.md` (incluindo o Cenário 4, migração de esquema em aparelho real) são gates
desta feature.

Nenhuma violação sem exceção registrada. Gate PASS.

## Project Structure

### Documentation (this feature)

```text
specs/006-preco-por-km/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md         # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

Sem `contracts/`: mesma razão já registrada pela feature 005 — nenhuma interface externa nova, e o
único contrato interno que muda (`CadastroStore`) já está descrito em `data-model.md`.

### Source Code (repository root)

```text
lib/
├── domain/
│   └── driver_profile.dart       # modificado — ganha precoPorKm (double) e parsePrecoPorKm,
│                                  # isValido exige > 0, toMap/fromMap, copyWith, ==/hashCode
└── services/
    └── sqflite_cadastro_store.dart  # modificado — versão do banco 2 → 3, onUpgrade com ALTER TABLE

lib/screens/
└── cadastro_screen.dart          # modificado — campo de preço por quilômetro com texto explicativo
                                   # (D3 de research.md), validação de envio exige valor > 0

test/
├── domain/
│   └── driver_profile_test.dart     # modificado — cobre parsePrecoPorKm e precoPorKm em
│                                     # isValido/toMap/fromMap
├── services/
│   └── cadastro_store_test.dart     # modificado — cobre preço zerado como corrompido
└── screens/
    └── cadastro_screen_test.dart    # modificado — cobre o campo e sua validação
```

**Structure Decision**: mantém a mesma divisão em `domain/` + `services/` + `screens/` já usada pelas
features anteriores do motorista; nenhuma camada nova. A migração de esquema é tratada inteiramente
dentro de `SqfliteCadastroStore`, empilhando mais um passo de `onUpgrade` ao lado do já existente da
feature 005 — sem introduzir um serviço de migração à parte.

## Complexity Tracking

Nenhuma violação de constituição sem exceção já registrada — tabela não aplicável.
