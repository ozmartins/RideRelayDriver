# Quickstart — Chegada periódica à origem (motorista)

Validação em `Prototipo/driver/`. Para o ponta a ponta, dois aparelhos/emuladores Android com um relay em comum
(o passageiro, já pronto para repetições, precisa estar em "motorista a caminho").

## Automatizados

```bash
flutter analyze        # "No issues found!"
flutter test test/domain/active_ride_test.dart
flutter test test/services/ride_state_store_test.dart
flutter test test/screens/map_screen_test.dart
flutter test           # suíte completa
```

## Cenários manuais (referem FR/SC de `spec.md`)

### 1. Parado na origem (US1, SC-001)

1. Corrida iniciada; levar o motorista a até 30 m da origem e ficar parado por 30 s.
2. **Esperado**: um `kind: 20007` na primeira posição e depois um a cada 5 s (inspecionar por assinante ao vivo
   no relay); no passageiro, a tela "Motorista chegou" abre uma vez.

### 2. Sair do raio (US2)

1. Afastar-se > 30 m. **Esperado**: nenhum `20007`; voltar ao raio retoma respeitando os 5 s.

### 3. Encontro confirmado e cancelamento (US2, SC-003)

1. Passageiro confirma o encontro. **Esperado**: motorista em "Em corrida" e nenhum `20007` novo.
2. Repetir cancelando a corrida pelo motorista ou pelo passageiro: nenhum `20007` novo.

### 4. Reinício e falha (US3, SC-004, SC-005)

1. Fechar e reabrir o app dentro do raio: o `20007` volta na primeira posição.
2. Sem relay conectado: nada é publicado, sem erro.

## Estado da validação

- **Automatizados** (2026-10-07): `flutter analyze` sem problemas; `flutter test` com 440 testes passando (434
  antes desta feature: o grupo da 011 foi reescrito, com testes novos para o intervalo de 5 s, a saída do raio, o
  encerramento da corrida, o reinício e a falha de relay).
- **Em aparelho**: **pendente**.
