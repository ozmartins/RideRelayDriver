# Quickstart de validação: 026-recibos-de-reputacao

Valida a feature ponta a ponta. Os cenários 1–3 rodam sem aparelho; 4–8 usam dois emuladores (motorista e passageiro)
com um relay real de teste e os dois apps com a emenda 25. Os cenários que falharem MUST ser relatados, não omitidos.

## Pré-requisitos

- `flutter pub get`; `assets/ors_api_key.txt` ou `--dart-define=ORS_API_KEY=...` (rota; sem chave cai em fallback).
- App do passageiro (`../RideRelayPassenger`) já com a contrapartida da emenda 25.
- Contrato: `specs/002-nostr-relay-connection/contracts/nostr-events.md` contém a emenda 25 e é idêntico ao do
  passageiro (conferir o trecho "Reputação por recibos" com `diff`).

## 1. Portões automáticos

```bash
flutter analyze        # sem apontamentos
flutter test           # inteira, sem teste ignorado
```

Esperado: ambos limpos. Arquivos de teste novos: `receipt_test`, `receipt_signature_test`,
`reputation_verifier_test`, `receipt_store_test`, `receipt_service_test`, `ride_request_received_test` (ampliado),
`identity_service_test` (ampliado), `consumed_kinds_test`, teste de vetores de contrato.

## 2. Vetores compartilhados

`flutter test test/services/receipt_contract_vectors_test.dart` e o equivalente no passageiro; depois
`diff driver/test/fixtures/receipt_vectors.json passenger/test/fixtures/receipt_vectors.json` sem saída.

## 3. Não vazamento (Princípio I)

Rodar o app com `flutter run` capturando `adb logcat -s flutter` durante os cenários 4–7 e procurar a chave
privada de teste (hex de 64) e trechos de `content` decifrado (`"reputacao"`, `"nota"`): nenhuma ocorrência. Inspecionar
no relay (ou no `read_network_requests` do cliente de teste) que `20014`/`20015`/`20002` têm `content` em base64 NIP-44,
nunca JSON legível; só o `20001` leva `reputacao` em claro.

## 4. Reputação do passageiro visível na solicitação

Passageiro com 2 recibos (de corridas anteriores) solicita corrida; motorista online recebe. Esperado: modal mostra
média e contagem **verificadas** e, menor, as **declaradas**. Repetir com passageiro sem histórico ("sem histórico")
e com um recibo adulterado injetado (descartado e sinalizado; reputação "inconsistente" se o `head` não fecha).

## 5. Emissão e confirmação

Concluir a corrida, avaliar com nota 5 no motorista. Esperado: recibo `20014` publicado, linha em `recibos_emitidos`
com `pendente = 1` antes da publicação, `20015` do passageiro recebido e `pendente = 0`. Repetir pulando a avaliação:
recibo sem `nota`.

## 6. Queda no meio (critério de aceite)

Repetir o cenário 5 matando o app do motorista entre a emissão e o `20015` (`adb shell am force-stop`). Reabrir.
Esperado: o pendente é reenviado ao abrir e confirmado; sem ação do usuário, em até 60 s com relay conectado.

## 7. Recepção e declaração própria

Passageiro avalia o motorista. Esperado: `20014` aceito, `20015` enviado, `myReputation()` reflete (contagem,
média, `seq_proximo`, `head`) e o **próximo** orçamento sai com `reputacao`. Medir o tamanho do `content` do `20002`
com 5 recibos (método: tamanho em bytes do JSON antes de cifrar, impresso por teste) e registrar o número aqui
**depois de medido** — não estimar.

## 8. Rejeições

Injetar no motorista (dublê/script de teste): recibo com assinatura inválida, de outro avaliado, com tag `p` alheia,
em claro e duplicado diferente. Esperado: nenhum altera `myReputation()`; duplicado idêntico só reenvia `20015`.
Corrida cancelada: nenhum recibo. Reputação inconsistente do passageiro: nenhum recibo e aviso de uma linha.

## Resultados

_Preencher na execução, com data e ambiente; cenário não executado é relatado como tal._
