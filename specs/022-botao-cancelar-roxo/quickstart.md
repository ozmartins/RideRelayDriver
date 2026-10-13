# Quickstart — Botões de cancelar corrida em roxo (motorista)

Validação em `Prototipo/driver/`.

## Automatizados

```bash
flutter analyze        # "No issues found!"
flutter test test/screens/cancel_ride_modal_test.dart
flutter test test/screens/map_screen_test.dart --plain-name "cancelar corrida"
flutter test           # suíte completa
diff <(sed -n '/^## Identidade Visual e Design/,/^## Fluxo de Desenvolvimento/p' .specify/memory/constitution.md) \
     <(sed -n '/^## Identidade Visual e Design/,/^## Fluxo de Desenvolvimento/p' ../passenger/.specify/memory/constitution.md)
```

## Cenários manuais (referem FR/SC de `spec.md`)

1. **Botão do mapa (US1, SC-001/002)**: com uma corrida aceita, em "Deslocando-se até o passageiro" e depois em
   "Em corrida", abrir o mapa. **Esperado**: "Cancelar corrida" com fundo roxo, ícone e texto brancos; mesma
   posição, tamanho e rótulo de antes.
2. **Confirmação (US2, SC-003)**: tocar nele. **Esperado**: a modal abre e o botão "Cancelar corrida" dela tem a
   mesma cor de fundo e de texto que o do mapa.
3. **Comportamento intacto (FR-006)**: confirmar. **Esperado**: volta a "Aguardando", rota e marcador somem, o
   passageiro recebe o aviso — exatamente como antes.

## Estado da validação

- **Automatizados** (2026-10-07): `flutter analyze` sem problemas; `flutter test` com 444 testes passando (440
  antes: 3 testes novos em `map_screen_test.dart` — aparência nos dois estados e igualdade com a modal — e 1 em
  `cancel_ride_modal_test.dart`). Emenda 2.12.0 commitada antes do código; seção de Identidade Visual das duas
  constituições conferida por `diff` (idêntica).
- **Em aparelho**: **pendente**.
