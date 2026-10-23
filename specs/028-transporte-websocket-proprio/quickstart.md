# Quickstart: 028-transporte-websocket-proprio

Guia de validação. Os cenários 3 e 4 só valem com resultado **real**: preencha a seção "Registro de execução" com o
método usado e o que foi observado; falha relatada, não omitida (constituição, Fluxo e Gates, item 3). Nenhum número
daqui vira medição do TCC sem este método (SC-006).

## Pré-requisitos

- Dois emuladores Android (motorista e passageiro), chave do openrouteservice configurada nos dois.
- App do passageiro na `master` de `../RideRelayPassenger` (sem alteração por esta feature).
- Relays: lista padrão das duas apps (inalterada). Rede do emulador controlável por `adb`.

## Cenário 1 — Gates automáticos

```bash
flutter pub get
dart format lib test
flutter analyze        # sem apontamentos
flutter test           # integral, sem teste ignorado
```

Esperado: ambos verdes. Os testes novos (`ws_relay_transport_test`, `relay_protocol_test`, `ws_relay_gateway_test`)
cobrem os casos de SC-002 sem rede.

## Cenário 2 — Confinamento e não vazamento (SC-005, Princípio I)

```bash
grep -rn "import.*dart_nostr" lib         # só: identity_service, event_verifier, ride_rating_signature,
                                          #     receipt_signature (nenhum relay_*, ws_*)
grep -rn "dart:io" lib/domain             # vazio
grep -nE "print\(|debugPrint|log\(" lib/services/ws_relay_*.dart lib/services/relay_protocol.dart lib/services/relay_transport.dart   # vazio
grep -rn "NostrRelayGateway" lib test     # vazio
```

Esperado: as saídas indicadas. Conferir também, no teste do gateway, que o texto enviado no `EVENT` é o payload
assinado, sem campo a mais.

## Cenário 3 — Corrida completa entre os dois apps (US1, SC-003)

1. Motorista: `flutter run` no emulador A, cadastro pronto, **online** dentro do raio.
2. Passageiro: emulador B publica uma solicitação (`20001`).
3. Percorrer a corrida inteira até o recibo: orçamento (`20002`), aceitação (`20003`), localização, confirmações,
   mensagens, fim, avaliação e recibos (`20014`/`20015`).
4. Conferir, em cada etapa, que o evento aparece do outro lado.
5. Ficar offline e online de novo com a corrida parada: o `20001` deixa de ser pedido e volta a ser (sem perder os
   outros eventos). Conferir que, na troca de células, os demais kinds **não** reaparecem como novos (R5).
6. *Opcional*: publicar com um relay que recuse (ex.: um que exija pagamento) e ver a mensagem do relay na tela. Relay
   público assim pode não existir; a prova obrigatória é o teste de `OK false` com mensagem (T008).

Esperado: todos os kinds de `20001` a `20015` cruzam, sem diferença visível em relação à rodada anterior à troca.

## Cenário 4 — Queda de conexão forçada (US2, SC-004)

1. Com o motorista online e a corrida em andamento (ou apenas conectado), anotar a hora e o estado dos relays.
2. No emulador do motorista, sem avisar o app:
   ```bash
   adb shell svc wifi disable; adb shell svc data disable
   ```
   Esperar ~25 s. Religar: `adb shell svc wifi enable; adb shell svc data enable`.
3. Sem tocar no app, observar: relays passam a indisponíveis? voltam a conectados? o app volta a receber eventos
   (publicar uma nova solicitação no passageiro)? Quanto tempo depois de a rede voltar?
4. Repetir uma vez com o app em segundo plano (serviço da feature 025).

Esperado: recuperação sem intervenção, em até ~65 s depois que a rede volta (teto derivado dos parâmetros: 40 s para a
sonda perceber a queda + 15 s de retentativa + 10 s de handshake; não é medição). Passar disso: registrar e investigar. Se a rede voltar antes de o ping ou a sonda perceberem a queda, a conexão
antiga pode seguir válida; registrar qual caminho foi observado (queda detectada ou conexão que sobreviveu).

## Registro de execução

*A preencher na execução; não preencher de memória.*

| Cenário | Data | Método (aparelho, relays, comandos) | Resultado |
|---|---|---|---|
| 1 | | | |
| 2 | | | |
| 3 | | | |
| 4 | | | |
