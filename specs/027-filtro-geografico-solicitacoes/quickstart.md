# Quickstart de validação: 027-filtro-geografico-solicitacoes

Os cenários 1–3 rodam sem aparelho; 4–8 usam dois emuladores (motorista e passageiro) com um relay real de teste e os
dois apps com a emenda 27. Os cenários que falharem MUST ser relatados, não omitidos.

## Pré-requisitos

- `flutter pub get`; `assets/ors_api_key.txt` ou `--dart-define=ORS_API_KEY=...`.
- App do passageiro (`../RideRelayPassenger`) já publicando a tag `g` (contrapartida da emenda 27).
- Contrato: `specs/002-nostr-relay-connection/contracts/nostr-events.md` contém a emenda 27 e é idêntico ao do
  passageiro (`diff` dos dois arquivos, sem saída). Constituição 2.18.0 idêntica nos dois (`diff` do corpo).

## 1. Portões automáticos

```bash
flutter analyze        # sem apontamentos
flutter test           # inteira, sem teste ignorado
```

Arquivos de teste novos ou ampliados: `geohash_test`, `driver_coverage_test`, `geohash_contract_vectors_test`,
`ride_request_filter_test`, `event_feed_test`, `driver_profile_test`, `cadastro_store_test`,
`cadastro_screen_test`, `relay_service_test`, `remote_relay_connection_test`, `relay_host_core_test`,
`map_screen_test`, `consumed_kinds_test`.

## 2. Vetores compartilhados

`flutter test test/services/geohash_contract_vectors_test.dart` aqui e o equivalente no passageiro; depois
`diff test/fixtures/geohash_vectors.json ../RideRelayPassenger/test/fixtures/geohash_vectors.json` sem saída.

## 3. O relay respeita `#g`? (medição, R7 do research)

```bash
dart run tool/probe_geohash_filter.dart   # um relay por vez, da lista padrão
```

A sonda assina e publica duas solicitações de teste (uma dentro da célula, uma fora), abre a inscrição com `#g` e
anota, **por relay**: se a de fora chegou, se a de dentro chegou, e se o `CLOSE` ao trocar a inscrição foi aceito.
Registrar o resultado em `research.md` (R7) **com** a data e o método. Não afirmar que um relay respeita o filtro
sem esta medição.

## 4. Chega o que está dentro, não chega o que está fora

Motorista com raio de 10 km, online em Araranguá (posição simulada no emulador). Passageiro solicita corrida
(a) a ~3 km, (b) em São Paulo. Esperado: (a) abre a modal e notifica; (b) nada na tela, nada de notificação.
Em depuração, o contador de descartes geográficos do `EventFeed` sobe com (b) mesmo se o relay a entregar.

## 5. Raio no limite e borda de célula

Repetir com origens a ~9,5 km e a ~10,5 km (entre as duas, só a primeira chega) e com uma origem a poucos metros
de uma borda de célula (chega). Repetir com raio 25 km (precisão 3) e origem a 24 e a 26 km.

## 6. Cadastro: raio inicial, edição, limites

Cadastro novo: o campo "Raio de atendimento (km)" vem com 10; apagar, `0`, `101`, `abc`, `2,5` impedem o avanço com
mensagem dos limites; `1` e `100` passam. Em app já cadastrado antes da feature (instalar a versão anterior,
cadastrar, atualizar): aparece 10 sem refazer o wizard. Editar o raio com o motorista online: a tela avisa que
vale na próxima vez que ficar online, e a cobertura em uso não muda (nova solicitação a 12 km, com raio antigo de
10, continua não chegando).

## 7. Referência fixa e ciclo online/offline

Online no ponto A; deslocar o emulador 30 km; uma solicitação perto de A ainda chega, uma perto do novo ponto não.
Ficar offline: nenhuma solicitação (a inscrição de `20001` some; conferir no relay). Online de novo no novo ponto:
agora a segunda chega e a primeira não. GPS desligado ao tentar ficar online: permanece offline com o aviso de
sempre.

## 8. Serviço em segundo plano e retomada

Online, app em segundo plano, solicitação dentro do raio: notificação; fora: nada. Fechar o app online e reabri-lo:
volta online na primeira posição válida, a solicitação recebida durante o intervalo é reavaliada contra a nova
referência. Matar o processo online (`adb shell am kill`/*swipe* com o sistema): relatar o que ocorreu — o
esperado é que **não** haja solicitações até abrir o app (limite conhecido, R5).

## 9. Não vazamento (privacidade)

Com `adb logcat -s flutter` e a captura de rede do cliente de teste durante 4–8: a posição de referência e o raio
não aparecem em nenhum evento publicado, em nenhuma notificação nem no log; o `REQ` mostra só as células `#g`.
