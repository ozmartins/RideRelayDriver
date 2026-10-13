# Implementation Plan: Cadastro do Motorista

**Branch**: `003-cadastro-motorista` (a criar) | **Date**: 2026-09-17 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/003-cadastro-motorista/spec.md`

## Summary

Exibir, na primeira abertura do aplicativo do motorista, um formulário obrigatório que colete nome,
UF e cidade de atuação (validadas contra listas oficiais — UF fixa, cidade contra a lista do IBGE
filtrada pela UF) e os dados do veículo (marca, modelo, cor, placa — validada nos dois formatos
vigentes no Brasil). Os dados são persistidos em SQLite local (exigência explícita da feature) e,
depois de cadastrados uma vez, o formulário deixa de aparecer; uma nova tela de edição, ao lado das já
existentes (Eventos, Relays, Identidade), permite corrigi-los depois.

A abordagem usa `sqflite` para a persistência, uma interface própria (`CadastroStore`) para manter o
tipo da biblioteca confinado à camada de serviços, e dados de UF/município **embutidos** no
aplicativo (sem chamada de rede), coerente com o modo de operação já assumido pela feature 002.

## Technical Context

**Language/Version**: Dart 3.13.3 (Flutter, stable) — inalterado em relação às features 001 e 002

**Primary Dependencies**:
- `sqflite ^2.4.4` — persistência do cadastro em SQLite (a adicionar; D1 de `research.md`)
- `flutter_test` + `flutter_lints` (dev, já presentes)
- Nenhum pacote novo para UF/município: dado embutido no próprio código (D2 de `research.md`)

**Storage**: banco de dados SQLite local (aparelho), uma única tabela (`driver_profile`, ver
`data-model.md`) restrita a no máximo uma linha. Não substitui nem interage com o Keystore (identidade)
nem com as preferências (lista de relays) das features anteriores — são armazenamentos independentes.

**Testing**: `flutter test` com testes de unidade dos serviços (validação de UF/cidade/placa, combinação
UF+cidade, tratamento de dado corrompido) usando um dublê de `CadastroStore` em memória — nenhum teste
toca `sqflite` real, seguindo o mesmo padrão já usado para `KeyStore` e `KeyValueStore` (Princípio II);
testes de widget do formulário e da tela de edição; `flutter analyze` como gate.

**Target Platform**: Android apenas (inalterado). Nenhuma permissão nova: `sqflite` usa armazenamento
privado do aplicativo, sem exigir declaração adicional no manifesto.

**Project Type**: mobile-app

**Performance Goals**: cadastro completo em até 2 minutos em condições normais de digitação (SC-001)

**Constraints**: funciona inteiramente offline (sem chamada de rede para validar UF ou cidade,
D2 de `research.md`); formulário bloqueante — nenhuma outra tela é acessível antes do cadastro
concluído (Assumptions do `spec.md`); combinação UF/cidade nunca pode ficar inconsistente (FR-009)

**Scale/Scope**: 1 tela nova reutilizada em dois modos (cadastro inicial e edição), 1 serviço de
persistência, 3 entidades de domínio (`DriverProfile`, `UF`, `Municipio`), 1 arquivo de dados estáticos
com ~5.570 municípios

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

**Estado da constituição**: em vigor na versão **2.1.0** (5 princípios, dois deles NÃO NEGOCIÁVEIS).

**Resultado do gate**: PASS.

| Princípio | Avaliação desta feature |
|-----------|-------------------------|
| I. Segredo criptográfico não vaza | **Não se aplica diretamente**: esta feature não toca chave privada nem qualquer material de assinatura. O cadastro do motorista (nome, veículo) não é segredo criptográfico — corrupção ou perda leva a pedir o preenchimento de novo (FR-010), nunca ao tratamento de vazamento irreversível que o Princípio I exige para a identidade. |
| II. Assinatura e verificação nascem com teste | **Não se aplica**: esta feature não assina nem verifica eventos. O princípio equivalente que **se aplica** por analogia — código que decide aceitar ou rejeitar um dado MUST ter teste do caso válido e do inválido — é seguido para a validação de UF, cidade, placa e para o tratamento de cadastro corrompido (FR-010), com testes sem SQLite real (D1 de `research.md`). |
| III. Dependência de terceiros exige decisão registrada | **Atendido**: `sqflite` está registrado em D1 de `research.md`, com alternativas avaliadas, versões e datas. A decisão de **não** adicionar pacote para UF/município está registrada em D2, pelo mesmo padrão de rigor — inclusive tendo descartado uma opção por incompatibilidade de SDK. Tipos de `sqflite` ficam confinados a `lib/services/` (Structure Decision). |
| IV. O contrato de evento vem antes do código | **Não se aplica**: esta feature não cria nem altera nenhum evento Nostr — o cadastro é dado puramente local, sem contrapartida no contrato de eventos, como registrado nas Assumptions do `spec.md`. Nada precisa ser replicado em `Prototipo/passenger`. |
| V. Simplicidade proporcional e rastreabilidade acadêmica | **Atendido com justificativa**: D2 de `research.md` descarta explicitamente três pacotes de terceiros por adicionarem estrutura (geração de código, banco NoSQL embutido, chamada de rede) desproporcional a uma lista estática de UF/município. Nenhuma camada nova é introduzida além do padrão já existente (`domain/services/screens`); a tela de cadastro é reaproveitada para os dois modos (criação e edição) em vez de duplicada. |

**Restrições de Segurança e Privacidade**: nenhuma permissão nova é declarada — `sqflite` usa
armazenamento privado do aplicativo. Não há acesso a localização, contatos, câmera nem armazenamento
externo. Os dados coletados (nome, UF, cidade, dados do veículo) permanecem apenas no aparelho: esta
feature não publica nada em relay, então a regra de "dado pessoal em relay público" das Restrições de
Segurança e Privacidade não é acionada.

**Fluxo de Desenvolvimento e Gates**: `flutter analyze` e `flutter test` limpos, e execução dos 7
cenários do `quickstart.md` com relato honesto de falhas — condições para declarar a feature concluída.

## Project Structure

### Documentation (this feature)

```text
specs/003-cadastro-motorista/
├── plan.md              # Este arquivo
├── research.md          # Fase 0 — D1 (sqflite), D2 (dados de UF/município), D3 (validação de placa)
├── data-model.md         # Fase 1
├── quickstart.md         # Fase 1
├── checklists/
│   └── requirements.md
└── tasks.md              # Fase 2 (/speckit-tasks)
```

Sem `contracts/`: esta feature não expõe nem consome nenhuma interface externa (não há evento Nostr
envolvido, ver Princípio IV acima) — a interface é só a tela do próprio aplicativo.

### Source Code (repository root)

```text
Prototipo/driver/
├── lib/
│   ├── main.dart                        # + carrega CadastroStore no bootstrap; decide entre
│   │                                     #   CadastroScreen (bloqueante) e o Shell existente;
│   │                                     #   adiciona a aba "Cadastro" à navegação existente
│   ├── domain/
│   │   ├── driver_profile.dart          # DriverProfile + normalização/validação de placa
│   │   ├── uf.dart                      # UF (sigla, nome) + lista fixa das 27 unidades
│   │   └── municipio.dart               # Municipio (nome, uf)
│   ├── services/
│   │   ├── cadastro_store.dart          # interface CadastroStore (injetável nos testes) +
│   │   │                                #   CadastroStoreUnavailable
│   │   ├── sqflite_cadastro_store.dart  # implementação real sobre sqflite (único arquivo que
│   │   │                                #   conhece package:sqflite, Princípio III)
│   │   └── ibge_municipios.dart         # dado estático gerado a partir da API do IBGE (D2),
│   │                                     #   com a data da consulta em comentário
│   └── screens/
│       └── cadastro_screen.dart         # formulário; um parâmetro distingue o modo bloqueante
│                                         #   (cadastro inicial, sem navegação de volta) do modo
│                                         #   de edição (acessível pela navegação existente)
├── test/
│   ├── services/
│   │   └── cadastro_store_test.dart     # dublê em memória; cobre corrupção (FR-010)
│   ├── domain/
│   │   └── driver_profile_test.dart     # validação de UF, cidade, placa (D3), combinação UF+cidade
│   └── screens/
│       └── cadastro_screen_test.dart    # os dois modos; bloqueio de envio com campo inválido
└── android/app/src/main/AndroidManifest.xml   # inalterado — nenhuma permissão nova
```

O único arquivo que conhece tipos de `sqflite` é `sqflite_cadastro_store.dart` — nem `domain/`, nem
`screens/`, nem o restante de `services/` o importam (Princípio III).

**Structure Decision**: mantém-se a separação `domain/` + `services/` + `screens/` já estabelecida
pela feature 002 — não há motivo para introduzir nada além disso aqui. A novidade é reaproveitar uma
única tela (`cadastro_screen.dart`) para os dois modos de uso (criação bloqueante e edição), em vez de
duplicar o formulário: a validação de campos é idêntica nos dois casos, e uma segunda cópia do
formulário divergiria com o tempo sem nenhum benefício correspondente (Princípio V).

Observação de coerência com o restante do protótipo: assim como a feature 002, esta feature não tem
nenhuma contrapartida em `Prototipo/passenger` — o cadastro do motorista é informação local dele, sem
papel na interoperabilidade entre as duas apps, e por isso não está sujeita ao Princípio IV.

## Complexity Tracking

> Nenhuma violação de constituição a justificar (ver Constitution Check).
