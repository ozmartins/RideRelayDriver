# Quickstart — Receber solicitação de corrida e enviar orçamento

Guia de validação manual desta feature, em `Prototipo/driver/`. Pressupõe emulador/aparelho Android
disponível e a app do passageiro rodando em outro aparelho/emulador, com um relay em comum entre os
dois (mesma configuração já usada para a interoperabilidade da feature 002).

## Pré-requisitos

1. Obter uma chave de API gratuita em <https://openrouteservice.org/dev/#/signup> (D1 de
   `research.md`) — a mesma chave já usada na feature 007 do passageiro pode ser reaproveitada.
2. Rodar o app passando a chave por `--dart-define`, nunca commitada:

   ```bash
   flutter run --dart-define=ORS_API_KEY=sua-chave-aqui
   ```

   Para os testes automatizados, nenhuma chave real é necessária — dublês substituem o serviço real.

## Cenários de validação (referem os FR/SC de `spec.md`)

### 1. Modal aparece só quando online, com os dados calculados (US1, SC-001)

1. Completar o cadastro do motorista (feature 003), incluindo um preço por quilômetro (feature
   006, ex.: 2,50).
2. Ficar online (feature 004), com posição válida.
3. No app do passageiro, solicitar uma corrida (feature 006 do passageiro) com origem/destino
   dentro de uma distância razoável do motorista.
4. **Esperado**: em até poucos segundos, uma modal aparece no app do motorista com origem, destino,
   as duas distâncias e o total, inicialmente calculado com o preço do cadastro.
5. Repetir com o motorista **offline**: **esperado** nenhuma modal aparecer para a mesma ação do
   passageiro.

### 2. Editar o preço recalcula o total, sem nova chamada de rede (US1)

1. Com a modal aberta (cenário 1), alterar o campo de preço por quilômetro.
2. **Esperado**: o total exibido muda imediatamente, sem espera nem novo indicador de carregamento
   nas distâncias.

### 3. Enviar orçamento publica o evento correto (US2)

1. Com a modal aberta e um preço válido, tocar em "Enviar orçamento".
2. **Esperado**: a modal fecha; inspecionar (via `dart run tool/verify_published.dart <pubkey>` ou
   equivalente) que um evento `kind: 20002` foi publicado, com uma tag `["e", "<id-da-solicitação>"]`
   e `content` contendo `pricePerKm` e `total` coerentes com o exibido.

### 4. Recusar corrida não publica nada (US3)

1. Com uma modal aberta, tocar em "Recusar corrida".
2. **Esperado**: a modal fecha imediatamente; nenhum evento novo aparece na inspeção de publicação.

### 5. Fila: duas solicitações em sequência (Edge Cases)

1. No app do passageiro (ou em dois aparelhos/emuladores de passageiro), disparar duas
   solicitações de corrida em sucessão rápida, antes de responder a primeira no motorista.
2. **Esperado**: apenas uma modal aparece por vez; ao enviar orçamento ou recusar a primeira, a
   segunda aparece imediatamente depois — nunca as duas simultaneamente.

### 6. Falha no cálculo de distância não bloqueia o orçamento (Edge Cases, FR-016)

1. Desligar a rede do aparelho do motorista depois que a modal já estiver aberta e escolher um
   preço válido (ou usar uma chave de API inválida antes de abrir a modal).
2. **Esperado**: a(s) distância(s) que dependem da rede aparecem como "não calculada", sem travar a
   modal; "Enviar orçamento" continua disponível e funcional.

## Verificação automatizada

```bash
flutter analyze                                        # deve dizer "No issues found!"
flutter test test/domain/ride_request_received_test.dart
flutter test test/domain/ride_quote_test.dart
flutter test test/services/route_distance_service_test.dart
flutter test test/screens/ride_request_modal_test.dart
flutter test test/screens/map_screen_test.dart
flutter test                                            # suíte completa
```
