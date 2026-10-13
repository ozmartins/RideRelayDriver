# Quickstart — Cancelar corrida (motorista)

Validação em `Prototipo/driver/`. Para o ponta a ponta completo, dois aparelhos/emuladores Android
com um relay em comum e a feature 019 do passageiro; sem ela, basta observar o evento publicado.

## Automatizados

```bash
flutter analyze        # "No issues found!"
flutter test test/domain/driver_ride_status_test.dart
flutter test test/services/identity_service_test.dart
flutter test test/screens/cancel_ride_modal_test.dart
flutter test test/screens/map_screen_test.dart
flutter test           # suíte completa
```

## Cenários manuais (referem FR/SC de `spec.md`)

### 1. Cancelar a caminho do passageiro (US1, SC-001, SC-002)

1. Motorista com corrida aceita e iniciada ("Deslocando-se até o passageiro").
2. Tocar em "Cancelar corrida" e confirmar.
3. **Esperado**: volta a "Aguardando solicitação de corrida"; marcador de embarque e rota somem;
   deixa de publicar `kind: 20005`; aparece um `kind: 20012` com `["e", ...]` e `["p", ...]` da
   corrida e `content` vazio (`dart run tool/verify_published.dart <pubkey-do-motorista>` — kind
   efêmero: conferir por assinante ao vivo).

### 2. Desistir do cancelamento (US1, SC-003)

1. Tocar em "Cancelar corrida" e, na modal, em "Voltar".
2. **Esperado**: nada muda; nenhum evento publicado.

### 3. Cancelar em "Em corrida" (US2)

1. Passageiro publica `kind: 20008`; motorista em "Em corrida". Cancelar e confirmar.
2. **Esperado**: mesmos efeitos do cenário 1, marcador de destino e rota somem, **sem** modal de
   avaliação (FR-006).

### 4. Botão ausente em repouso (FR-001)

1. Em "Aguardando solicitação de corrida", olhar o mapa.
2. **Esperado**: sem "Cancelar corrida".

### 5. Reinício e nova corrida (US3, SC-004, SC-005)

1. Cancelar, fechar e reabrir o app.
2. **Esperado**: abre em "Aguardando solicitação de corrida", sem rota nem publicação de
   localização. Aceitar e concluir outra corrida normalmente.

### 6. Sem relay (FR-008)

1. Desconectar todos os relays e cancelar.
2. **Esperado**: motorista fica livre; nada é publicado; sem erro visível.

## Estado da validação (2026-10-04)

- **Automatizados**: `flutter analyze` sem problemas; `flutter test` com 371 testes passando.
- **Em aparelho**: **pendente** — cenários 1 a 6 não executados (sem emulador/aparelho na sessão que
  implementou). O ponta a ponta (cenários 1, 3 e 5 com o aviso chegando ao passageiro) também
  depende da feature 019 do passageiro, já implementada.
