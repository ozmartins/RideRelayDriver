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
| 8 — rejeições (assinatura inválida, outro avaliado, tag `p` alheia, em claro, duplicado) | **Executado na rodada 2 (abaixo), com um achado.** |

**Medição (tamanho do `content` do `20002`).** Método: teste descartável (removido depois), com recibos reais assinados por chaves de teste, 8 recibos
na cadeia e janela de 5 (`kReputacaoJanela`), orçamento com `etaMinutes`; tamanhos lidos de `utf8.encode(jsonEncode(...))`, `event.content.length`
e da mensagem `["EVENT", payload]` completa. Resultado: reputação (5 recibos) **3178 bytes** de JSON (≈ 606 bytes por recibo); `content` cifrado do `20002`
**4868 bytes** com 5 recibos contra **304 bytes** sem reputação; mensagem `EVENT` completa **5394 bytes**. O limite de entrada do NIP-44 é 65535 bytes, ou seja,
~7% usados no pior caso da janela. Medido no host (VM do Dart/flutter_test), não no aparelho — o tamanho em bytes não depende do aparelho.

**Verificação de não vazamento (Princípio I) — log, rodada 1.** Método: `adb logcat -d -b all` do emulador, 22:25:54–22:39:57 (63 844 linhas, cobre
todo o cenário), buscando termos de segredo e marcadores de conteúdo decifrado. Nas linhas dos apps (tags `flutter`/`corridas`): nenhuma ocorrência de
`nsec|privkey|private|secret|seed`; nenhuma de `guid_corrida`, `hash_anterior`, `id_recibo`, `reputacao`, `pubkey_avaliado`, `"nota"`, `assinatura`; as
chaves públicas dos participantes não aparecem. As 250 linhas com "private/secret" são do teclado (IME) e do sistema. **Limites:** a chave privada
fica no Keystore e não pude ler seu valor, então não procurei o valor em si; e **não inspecionei o tráfego** nos relays (TLS) — o fato de os eventos
`20002`/`20014`/`20015` irem cifrados vem dos testes (`identity_service_receipt_test`: `content` ilegível a terceiros) e do funcionamento ponta a ponta
(o passageiro só exibiu a reputação do motorista porque decifrou o `20002`). O tráfego foi inspecionado na rodada 2.

### Rodada 2 — tráfego nos relays e rejeições (mesmo emulador, 3 relays públicos)

Método: um observador passivo em Node (`WebSocket`), só com `REQ` por `#t = tcc-ufsc-caronas` e os kinds do protótipo, ligado aos três relays padrão
durante uma 3ª corrida completa (passageiro **pulou** a avaliação; motorista deu nota 3). Nada foi publicado pelo observador. Ele guardou os eventos como
chegaram aos relays; depois decodifiquei cada `content` em base64 e procurei nos bytes os marcadores de texto (`guid_corrida`, `hash_anterior`,
`id_recibo`, `reputacao`, `pubkey_avali`, `"nota"`, `assinatura`, `pricePerKm`, `driverName`, `origin`) e sequências de 64 caracteres hexadecimais.

| Kind | `content` nos relays | Resultado |
|---|---|---|
| `20001` | JSON legível (exceção da emenda 17 e da constituição 2.17.0) | campos `origin`, `destination`, `payment`, `reputacao`; `reputacao` com 2 recibos e a chave pública da contraparte à mostra, como o contrato admite |
| `20002`, `20003`, `20008`, `20010`, `20014`, `20015` | base64 NIP-44, primeiro byte `0x02` | nenhum marcador de texto e nenhum hexadecimal de 64 caracteres em claro, em todos os eventos capturados (1 de cada, mais 3 `20014` e 3 `20015` por reenvio e reconfirmação) |

Tamanhos reais capturados: `20014` com 944 caracteres base64 (707 bytes), `20015` com 220 (163 bytes), `20002` com reputação de 2 recibos com 2140 (1603 bytes).
Isso fecha o item de tráfego do gate 4. Continua valendo o limite da rodada 1: o valor da chave privada não foi procurado, porque fica no Keystore.

**Cenário 5, recibo sem nota:** o passageiro tocou em "Pular"; o motorista gravou o recibo com `nota` nula (`seq` 2), e o passageiro recebeu o do motorista (nota 3).
O motorista tem agora 3 recibos reais recebidos e o passageiro 3 emitidos, todos confirmados.

**Cenário 8, eventos forjados.** Método: um teste descartável (removido depois) gerou, com chaves de teste descartáveis e o código do app, sete eventos `20014` endereçados à
chave real do motorista de teste; um script publicou os eventos nos três relays públicos (todos responderam `OK`); com o motorista em primeiro plano, comparei o `receipts.db`
antes e depois. Foram publicados 7 eventos de teste com o marcador do protótipo, endereçados só a essa chave de teste.

| Forjado | Efeito no motorista |
|---|---|
| assinatura inválida (avaliador A, assinado por B) | ignorado |
| avaliado diferente do motorista (tag `p` do evento é o motorista) | ignorado |
| em claro | ignorado |
| duplicado diferente (mesma corrida de um recibo já guardado) | ignorado |
| tag `p` alheia (cifrado a terceiro) | ignorado |
| avaliador diferente do autor do evento | ignorado |

Em todos, `recibos_recebidos` ficou em 3 e nenhum `20015` saiu. **Controle:** um recibo **válido**, assinado por um estranho, com `guid_corrida` inventado e nota 1, foi
**aceito e gravado** (`recibos_recebidos` foi a 4, com `seq` 0 e nota 1), o que também prova que o motorista estava recebendo os eventos naquele instante.

**Achado (não é defeito de implementação, é lacuna do contrato 1.8).** A recepção valida assinatura, avaliado, avaliador e corrida (tag `e`), mas não exige que a corrida
exista nem que tenha sido do próprio avaliado: qualquer pessoa que conheça a chave pública de um usuário pode lhe enviar recibos válidos com corridas inventadas. Aqui o
recibo de nota 1 entrou em `corridas`, `avaliacoes` e `media` **declaradas** pelo motorista (de 5,00 para ≈ 3,67 nas contas da agregação) e em `seq_proximo`. A janela
apresentada ficaria correta neste caso só porque os recibos reais são mais recentes por `criado_em`. Os "Limites conhecidos" (1.9) não citam isso. Mitigação possível, que
exige emenda do contrato nas duas apps: só aceitar recibo cujo `guid_corrida` seja um orçamento que o próprio receptor enviou ou recebeu e foi aceito (o motorista já guarda
os orçamentos enviados; o passageiro, os recebidos). Corrigido pela **emenda 26** (contrato 1.8: só grava recibo de corrida conhecida com o avaliador), implementada nos dois apps; o teste automatizado reproduz o caso do estranho com corrida inventada. A mitigação não impede que quem negociou com o avaliado lhe emita recibo de corrida que não houve (1.9).

### Rodada 3 — verificação da emenda 26 em emulador (mesmo emulador, 3 relays públicos)

Com os dois apps reconstruídos (APKs de debug) e instalados por cima, preservando os dados:

- **Corrida legítima (4ª):** pedido, orçamento, aceitação, encontro, destino e avaliação pelos dois lados. Os dois `receipts.db` ganharam o recibo `seq` 3 (motorista:
  nota 5 do passageiro; passageiro: nota 4 do motorista) e todos os `recibos_emitidos` ficaram com `pendente = 0`. Antes da corrida, a modal do motorista mostrou
  "Reputação verificada: 4,00 ★ em 3 recibos". A regra da emenda 26 não barrou a corrida real.
- **Recibo válido de um estranho, com corrida inventada e nota 1** (assinado com chave descartável, cifrado ao destinatário): publicado nos relays para o **motorista**
  (`recibos_recebidos` ficou em 5) e para o **passageiro** (ficou em 4), cada um com o app em primeiro plano. Os dois ignoraram. No cenário 8 da rodada 2, o mesmo tipo
  de recibo tinha sido aceito.
- Dois dos três relays públicos aceitaram os eventos; `offchain.pub` rejeitou ("pubkey is not in our web of trust"). Observação: os dois eventos de teste ficam nos
  relays com o marcador do protótipo, efêmeros, endereçados às chaves de teste.
- O que **não** foi exercitado em emulador: recibo de uma negociação real, mas ligada a outro avaliador (coberto só por teste automatizado nos dois apps).
