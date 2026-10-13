# Quickstart — Publicar ao passageiro a rota da corrida

Validação em `Prototipo/driver/`. Para o ponta a ponta completo, dois aparelhos/emuladores Android
com um relay em comum e a feature 018 do passageiro; sem ela, basta observar os eventos publicados.

## Automatizados

```bash
flutter analyze        # "No issues found!"
flutter test test/domain/ride_route_content_test.dart
flutter test test/services/identity_service_test.dart
flutter test test/screens/map_screen_test.dart
flutter test           # suíte completa
```

## Cenários manuais (referem FR/SC de `spec.md`)

### 1. Publica a rota ao entrar em "Em corrida" (US1, SC-001)

1. Motorista com corrida aceita em "Deslocando-se até o passageiro", chave ORS configurada
   (`--dart-define=ORS_API_KEY=...`). Passageiro (ou ferramenta de teste) publica `kind: 20008`.
2. **Esperado**: ao mapa traçar o trajeto até o destino, aparece um `kind: 20011` com `["e", ...]` e
   `["p", ...]` da corrida e `content` com `points`. Conferir com
   `dart run tool/verify_published.dart <pubkey-do-motorista>`.

### 2. Republica a cada recálculo (US1)

1. Em "Em corrida", deslocar o aparelho/emulador mais de 50 m.
2. **Esperado**: novo `kind: 20011` com a rota recalculada; nenhuma nova consulta ao ORS além da
   que já redesenha o mapa (SC-003).

### 3. Nada fora de "Em corrida" (US2, SC-002)

1. Em "Deslocando-se até o passageiro" com trajeto traçado: **nenhum** `kind: 20011`.
2. Confirmar o destino (`kind: 20010`) com um cálculo em voo: **nenhum** `kind: 20011` após a
   volta a "Aguardando solicitação".

### 4. Falha não publica (US3, SC-005)

1. Em "Em corrida", remover a chave ORS ou cortar a rede do aparelho.
2. **Esperado**: faixa de aviso do mapa (feature 016), **nenhum** `kind: 20011` novo, e a
   localização (`kind: 20005`) segue sendo publicada.

### 5. Tamanho (SC-004)

1. Usar uma rota longa (≥ 30 km, ex.: Araranguá → Florianópolis).
2. **Esperado**: `content` com ≤ 1000 pontos, primeiro e último iguais aos da rota calculada;
   evento aceito pelos três relays padrão e entregue a uma conexão inscrita (kind efêmero: não há
   recuperação posterior). Sonda: `dart run tool/probe_ride_route.dart`.

**Resultado (2026-10-03, sonda com 2500 pontos reduzidos a 1000)**: `content` 20 709 B, mensagem 21 237 B;
`nos.lol`, `relay.primal.net` e `offchain.pub` — OK `true` e entrega à 2ª conexão `true` nos três.

## Estado da validação (2026-10-03)

- **Automatizados**: `flutter analyze` sem problemas; `flutter test` com 352 testes passando.
- **Relay real (cenário 5)**: verificado pela sonda, acima.
- **Em aparelho (cenários 1 a 4): PENDENTE.** A sessão só enxergava o alvo `linux` (nenhum AVD Android
  listado); o ponta a ponta exige dois aparelhos/emuladores e a chave `ORS_API_KEY`.
