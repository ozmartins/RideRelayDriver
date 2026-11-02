# Implementation Plan: Ano do veículo no cadastro

**Branch**: `008-ano-do-veiculo` | **Date**: 2026-09-20 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/008-ano-do-veiculo/spec.md`

## Summary

Acrescenta `anoVeiculo` (`int`, 4 dígitos, 1900 até ano corrente + 1) ao `DriverProfile`, ao
formulário de cadastro (`CadastroScreen`) e ao esquema SQLite (`driver_profile`, versão 3 → 4) —
mesmo padrão das features 005 e 006.

## Technical Context

**Language/Version**: Dart 3.x / Flutter (sem mudança)

**Primary Dependencies**: nenhuma nova

**Storage**: SQLite via `sqflite`, migração de esquema (D1 de `research.md`)

**Testing**: `flutter_test`, mesmo padrão de dublê de armazenamento das features 003/005/006

**Target Platform**: Android

**Project Type**: mobile-app (Flutter), único projeto

**Performance Goals**: N/A — campo de formulário simples

**Constraints**: cadastro de instalação anterior sem o campo MUST ser tratado como corrompido
(FR-004), sem caminho de migração especial

**Scale/Scope**: um campo, um formulário, uma migração de esquema

## Constitution Check

Avaliação contra `.specify/memory/constitution.md` v2.4.0:

| Princípio / Restrição | Avaliação |
|---|---|
| I. Segredo criptográfico não vaza | N/A — não toca identidade Nostr. |
| II. Assinatura e verificação nascem com teste | N/A — não toca código de assinatura/verificação. |
| III. Dependência de terceiros exige decisão registrada | N/A — nenhuma dependência nova (vacuidade). |
| IV. O contrato de evento vem antes do código | N/A — `anoVeiculo` é dado de cadastro local; não é publicado em nenhum evento por esta feature (isso é a feature 009). |
| V. Simplicidade proporcional | **Aplica-se.** Faixa de validação (1900–ano corrente+1) e ausência de validação cruzada com marca/modelo são decisões registradas em `research.md`. **PASS.** |

**Resultado**: PASS. Nenhuma entrada em Complexity Tracking é necessária.

## Project Structure

### Source Code (repository root)

```text
lib/
├── domain/driver_profile.dart          # alterado — ganha anoVeiculo + parseAnoVeiculo
├── services/sqflite_cadastro_store.dart # alterado — versão 3 → 4, coluna ano_veiculo
└── screens/cadastro_screen.dart         # alterado — campo de ano no formulário

test/
├── domain/driver_profile_test.dart
├── services/cadastro_store_test.dart
└── screens/cadastro_screen_test.dart
```

**Structure Decision**: mesmos arquivos já tocados pelas features 005/006 — sem estrutura nova.

## Complexity Tracking

Nenhuma violação — seção não aplicável.
