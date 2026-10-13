# Quickstart — Corrida cancelada pelo passageiro (motorista)

Validação em `Prototipo/driver/`. Para o ponta a ponta completo, dois aparelhos/emuladores Android com um relay
em comum e a feature `023-cancelar-corrida-passageiro` do passageiro (botão e publicação do `20013`); sem ela,
basta injetar o evento pelos testes automatizados.

## Automatizados

```bash
flutter analyze        # "No issues found!"
flutter test test/domain/driver_ride_status_test.dart
flutter test test/screens/ride_cancelled_by_passenger_modal_test.dart
flutter test test/screens/map_screen_test.dart
flutter test           # suíte completa
```

## Cenários manuais (referem FR/SC de `spec.md`)

### 1. Passageiro cancela com o motorista a caminho (US1, SC-001)

1. Corrida aceita e iniciada; motorista em "Deslocando-se até o passageiro".
2. No passageiro: "Cancelar corrida" e confirmar.
3. **Esperado**: no motorista, modal "O passageiro cancelou a corrida" com "OK"; estado "Aguardando solicitação
   de corrida"; marcador de embarque e rota somem; deixa de publicar `kind: 20005`.

### 2. Passageiro cancela com a corrida em andamento (US2)

1. Passageiro confirma o encontro; motorista "Em corrida". Passageiro cancela.
2. **Esperado**: mesmos efeitos; marcador de destino e rota somem; **sem** modal de avaliação (FR-006).

### 3. Avisos inválidos (US3, SC-002, SC-003)

Nos testes automatizados: autor errado, `quoteId` de outra corrida, `p` de outro motorista, em claro, texto ≠
`{}`, em "Aguardando"; e o mesmo aviso reentregue. **Esperado**: nenhum muda estado nem abre modal; o duplicado
tem um único efeito.

### 4. Reinício e nova corrida (US4, SC-004, SC-005)

1. Processar o cancelamento, fechar e reabrir o app.
2. **Esperado**: abre em "Aguardando solicitação de corrida", sem corrida ativa nem publicação de localização.
   Aceitar e concluir outra corrida normalmente.

### 5. Confirmação aberta (D4)

1. Motorista abre "Cancelar corrida?" e, sem confirmar, o passageiro cancela.
2. **Esperado**: a confirmação fecha e a modal informativa abre; nada é publicado ao passageiro.

## Estado da validação

- **Automatizados** (2026-10-07): `flutter analyze` sem problemas; `flutter test` com 434 testes passando
  (414 antes desta feature, +20: regra de transição, modal e o grupo de recepção do `20013`).
- **Em aparelho**: **pendente** — cenários 1 a 5 não executados; o ponta a ponta depende da feature `023` do passageiro,
  ainda não implementada.
