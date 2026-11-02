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

### Matriz SC-002 (item → teste)

| Item de SC-002 | Arquivo | Teste (trecho do nome) |
|---|---|---|
| Handshake com sucesso | `ws_relay_transport_test` / `ws_relay_gateway_test` | `handshake com sucesso` / `connect registra o relay` |
| Handshake com falha | `ws_relay_transport_test` / `ws_relay_gateway_test` | `falha do handshake` (nos dois) |
| Handshake com prazo estourado | `ws_relay_transport_test` / `ws_relay_gateway_test` | `handshake que passa do prazo` / `handshake com prazo estourado` |
| Socket tardio é fechado | `ws_relay_transport_test` | `socket que chega depois do prazo é fechado` |
| `EVENT` malformado ou truncado, descartado sem erro | `relay_protocol_test` / `ws_relay_gateway_test` | `EVENT sem objeto`, `JSON truncado no meio` / `frames hostis não derrubam a conexão` |
| `OK` aceito e recusado com mensagem | `ws_relay_gateway_test` | `OK aceito`, `OK recusado traz a mensagem do relay` |
| Publicação sem resposta | `ws_relay_gateway_test` | `relay que não responde: recusado por prazo` |
| Queda estabelecida emite uma única vez | `ws_relay_gateway_test` | `fim do socket estabelecido emite connectionLost uma única vez` (e a variante de erro) |
| Desconexão pedida não emite | `ws_relay_gateway_test` | `desconexão pedida não emite connectionLost` |
| Sonda responde com qualquer mensagem; falha sem conexão | `ws_relay_gateway_test` | `completa com qualquer mensagem do relay`, `sem conexão falha na hora` |
| Troca de células refaz só o `20001` | `ws_relay_gateway_test` | `refaz só a inscrição do 20001` |
| Troca de células vale para relay tardio | `ws_relay_gateway_test` | `relay que conecta depois recebe as células vigentes` |
| Limite de tamanho não derruba | `relay_protocol_test` / `ws_relay_gateway_test` | `um caractere além do limite` / `texto acima do limite` |
| Tag mal formada recusada pelo relay não derruba | `ws_relay_gateway_test` | `OK false com tag mal formada`, `CLOSED da inscrição do 20001` |
| Verificação a jusante não enfraqueceu | `ws_relay_gateway_test` | `assinatura adulterada chega bruta e o EventFeed a descarta` |
| `RelayService` reconecta e reinscreve sobre o gateway novo | `relay_service_ws_gateway_test` | `queda da conexão: unavailable; reconexão reinscreve` |


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
| 1 | 2026-10-25 | `dart format lib test`, `flutter analyze`, `flutter test` na máquina de desenvolvimento, após a troca em `main.dart` e no `RelayTaskHandler` | `flutter analyze`: sem apontamentos. `flutter test`: 1009 testes passaram, nenhum ignorado (linha de base antes da feature: 908). |
| 2 | 2026-10-25 | Os quatro comandos do cenário, rodados na raiz do repositório | `import.*dart_nostr` em `lib`: só `event_verifier`, `identity_service`, `ride_rating_signature`, `receipt_signature`. `dart:io` em `lib/domain`: vazio. `print`/`debugPrint`/`log(` nos arquivos novos: vazio. `NostrRelayGateway` em `lib` e `test`: vazio. |
| 3 | — | **Não executado**: `adb devices` não listou nenhum emulador nem aparelho nesta sessão, e o cenário exige dois (motorista e passageiro) com relays públicos. | Pendente. |
| 4 | — | **Não executado**: mesmo motivo do cenário 3. | Pendente. |
