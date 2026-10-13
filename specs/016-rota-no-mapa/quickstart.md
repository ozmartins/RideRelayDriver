# Quickstart — Rota da corrida no mapa

Guia de validação em `Prototipo/driver/`. Chave ORS própria é necessária para os cenários 1–5
(`flutter run --dart-define=ORS_API_KEY=...`); sem ela, vale o cenário 6.

## Automatizado

**Resultado em 2026-09-30**: `flutter analyze` — No issues found!; `flutter test` — 335 testes passando (305 antes desta feature).

```bash
cd Prototipo/driver
flutter analyze        # No issues found!
flutter test           # suíte completa
flutter test test/domain/ride_leg_test.dart
```

## Manual (aparelho/emulador; dois aparelhos com relay em comum para o ciclo completo)

Pré-requisito: motorista cadastrado, corrida aceita, "Iniciar corrida" tocado (feature 010).

1. **Trajeto até o embarque (US1)** — estado "Deslocando-se": ver marcador de pessoa no ponto de
   embarque e linha roxa da posição ao embarque; mapa enquadra os dois pontos e **permanece** assim
   enquanto o aparelho se move (não recentraliza sozinho, FR-010); tocar "Centralizar" volta a
   seguir o motorista.
2. **Recálculo (FR-004)** — mover o emulador ≥ 50 m: a linha parte da nova posição. Mover < 50 m:
   sem nova linha/consulta.
3. **Troca para destino (US2)** — o passageiro confirma o encontro (`kind: 20008`): somem o marcador
   e a linha de embarque; surgem a bandeira e a linha até o destino.
4. **Encerramento (US3)** — confirmar o destino (`kind: 20010`): sem linha nem marcador de corrida.
5. **Reinício (FR-006)** — fechar e reabrir o app durante cada trecho: a linha volta sem ação.
6. **Falha (FR-005)** — compilar sem `ORS_API_KEY` (ou modo avião): sem linha, marcador do alvo
   presente, faixa "Não foi possível traçar a rota agora."; localização e confirmações da corrida
   continuam funcionando.
7. **Privacidade (FR-008)** — inspecionar a requisição ao ORS (teste de `trace()`): só as duas
   coordenadas, HTTPS.

## Medições (SC-001, SC-002, SC-004, SC-005)

Registrar aqui, com cronômetro/log, os números medidos — não estimados:

| Critério | Alvo | Medido |
|---|---|---|
| SC-001: abertura do mapa → polilinha visível | ≤ 5 s | _a medir_ |
| SC-002: confirmação de encontro → troca de trecho visível | ≤ 2 s | _a medir_ |
| SC-004: consultas de rota numa corrida simulada de ≥ 1 km | ≤ 1 por 50 m + 1 por trecho | _a medir_ |
| SC-005: só pela tela do mapa, o motorista diz para onde seguir (verificação visual no cenário 1) | sim | _a verificar_ |

Resultados e cenários que falharem devem ser relatados aqui, não omitidos (Fluxo de
Desenvolvimento e Gates, item 3).

## Estado da validação (2026-09-30)

**Validação em aparelho pendente.** A sessão que implementou a feature só tinha o alvo `linux`
(desktop) disponível em `flutter devices` — nenhum aparelho/emulador Android, nem um segundo
dispositivo com relay em comum. Os cenários manuais 1–7 e a tabela de Medições acima **não foram
executados**; o que está coberto é o comportamento no nível de widget (testes de `MapScreen` com
dublês), não a rota real do ORS nem a medição de tempo em hardware.
