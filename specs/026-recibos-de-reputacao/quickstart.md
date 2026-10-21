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

Executado em 2026-10-20 (22:25–22:40, horário do emulador). **Desvios do roteiro, todos relatados:**

- **Um emulador, não dois.** Os dois AVDs (`Pixel_6_API34_1` e `_2`) não ficaram de pé juntos: ao subir o segundo, o primeiro encerrava
  (log: pedido de desligamento do emulador anterior). A causa não foi confirmada; havia ~3 GB livres de 14 GB e cada emulador usa ~3,8 GB,
  então suspeito de falta de memória. Os dois apps (motorista e passageiro, APKs de debug) foram instalados no **mesmo** emulador
  (`Pixel_6_API34_2`, Android 14, headless), com identidades diferentes, e alternados em primeiro plano. Os dois ficam com a mesma posição
  (`adb emu geo fix`), então "a caminho" e "chegada" ocorrem de imediato. Não é o cenário de dois aparelhos.
- **Relays públicos.** Sem relay local; usou-se a lista padrão (3 relays públicos), como no quickstart da 025. Eventos efêmeros de teste.
- Cadastro do motorista e do passageiro feitos pela interface com dados fictícios (Motorista Teste / Passageira Teste).

| Cenário | Resultado |
|---|---|
| 4 — reputação do passageiro na solicitação | **OK.** 1ª corrida: modal do motorista mostrou "Reputação do passageiro: sem histórico". 2ª corrida, depois de trocados os recibos: "Reputação verificada: 5,00 ★ em 1 recibo" e, em texto menor, "Declarada pelo passageiro: 1 corrida, média 5,00". Não foram testados recibo adulterado nem `head` inconsistente na interface real (só em teste automatizado). |
| 4b — reputação do motorista no orçamento (lado do passageiro) | **OK.** 1ª corrida: "Sem histórico de avaliações". 2ª: "Verificado nos últimos 1: ★ 5.0 / Declarado: 1 corridas · 1 avaliações · média 5.00". |
| 5 — emissão e confirmação | **OK com ressalva.** Notas dadas: 1ª corrida, 5 dos dois lados; 2ª corrida, 5 do passageiro e 4 do motorista. "Pular" (recibo sem nota) **não** foi exercitado no emulador, só em teste automatizado. Conferido nos `receipts.db` puxados por `run-as`: `recibos_emitidos` gravado antes da confirmação, `recibos_recebidos` do outro lado com o mesmo `id_recibo`, `seq` 0 e 1, e `pendente` virando 0. **Observação:** na 1ª corrida o primeiro envio do motorista não foi processado pelo passageiro enquanto este estava em segundo plano; o recibo ficou `pendente = 1` e só foi confirmado depois de um reenvio do motorista (temporizador de 60 s ou reconexão; não distingui qual), com o passageiro já em primeiro plano. Não investiguei por que o app do passageiro não tratou o evento em segundo plano. |
| 6 — matar o app entre emissão e confirmação | **OK.** 2ª corrida: motorista avaliou (nota 4), `am force-stop` ~1,5 s depois (22:39:18); `receipts.db` mostrou o recibo emitido com `pendente = 1`. Reaberto às 22:39:26, 20 s depois estava `pendente = 0`, e o passageiro tinha o recibo (nota 4, `seq` 1). O passageiro já recebera o primeiro envio antes do kill, então o que a reabertura provou foi o reenvio e a nova confirmação (o passageiro reconfirma o duplicado idêntico, como manda 1.8), não uma primeira entrega. |
| 7 — recepção e declaração própria | **OK.** O motorista recebeu os recibos do passageiro (`seq` 0 e 1, nota 5, encadeados), respondeu `20015` e o 2º orçamento saiu com a reputação própria (visível no passageiro, ver 4b). |
| 8 — rejeições (assinatura inválida, outro avaliado, tag `p` alheia, em claro, duplicado) | **Não executado no emulador.** Exigiria injetar eventos forjados nos relays. Coberto por testes automatizados (`receipt_service_test`, `reputation_verifier_test`, `map_screen_test`), todos verdes. |

**Medição (tamanho do `content` do `20002`).** Método: teste descartável (removido depois), com recibos reais assinados por chaves de teste, 8 recibos
na cadeia e janela de 5 (`kReputacaoJanela`), orçamento com `etaMinutes`; tamanhos lidos de `utf8.encode(jsonEncode(...))`, `event.content.length`
e da mensagem `["EVENT", payload]` completa. Resultado: reputação (5 recibos) **3178 bytes** de JSON (≈ 606 bytes por recibo); `content` cifrado do `20002`
**4868 bytes** com 5 recibos contra **304 bytes** sem reputação; mensagem `EVENT` completa **5394 bytes**. O limite de entrada do NIP-44 é 65535 bytes, ou seja,
~7% usados no pior caso da janela. Medido no host (VM do Dart/flutter_test), não no aparelho — o tamanho em bytes não depende do aparelho.

**Verificação de não vazamento (Princípio I) — parcial.** Método: `adb logcat -d -b all` do emulador, 22:25:54–22:39:57 (63 844 linhas, cobre
todo o cenário), buscando termos de segredo e marcadores de conteúdo decifrado. Nas linhas dos apps (tags `flutter`/`corridas`): nenhuma ocorrência de
`nsec|privkey|private|secret|seed`; nenhuma de `guid_corrida`, `hash_anterior`, `id_recibo`, `reputacao`, `pubkey_avaliado`, `"nota"`, `assinatura`; as
chaves públicas dos participantes não aparecem. As 250 linhas com "private/secret" são do teclado (IME) e do sistema. **Limites:** a chave privada
fica no Keystore e não pude ler seu valor, então não procurei o valor em si; e **não inspecionei o tráfego** nos relays (TLS) — o fato de os eventos
`20002`/`20014`/`20015` irem cifrados vem dos testes (`identity_service_receipt_test`: `content` ilegível a terceiros) e do funcionamento ponta a ponta
(o passageiro só exibiu a reputação do motorista porque decifrou o `20002`). O item de tráfego do gate 4 continua pendente.
