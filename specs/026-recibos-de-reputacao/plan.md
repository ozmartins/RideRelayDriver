# Plano de implementação: 026-recibos-de-reputacao

**Spec**: [spec.md](spec.md) · **App**: `driver/` · **Data**: 2026-10-20 · **Entrada**: `especificacao-motorista.md`

## Resumo

O motorista passa a (1) emitir um **recibo assinado** ao passageiro quando a modal de avaliação fecha, reenviando-o
até a confirmação; (2) **receber** recibos do passageiro, guardá-los de forma imutável e declarar a própria
reputação (últimos 5 recibos + contagens) em cada orçamento; (3) **verificar e exibir** a reputação do passageiro que
chega na solicitação, separando "verificado" de "declarado". O contrato muda (emenda 25: `20014`, `20015`, campo
`reputacao`), então a especificação do contrato vem antes do código e é replicada no passageiro na mesma alteração.
A verificação é uma função pura; o armazenamento, atrás de interface com dublê em memória; a assinatura reusa a API
`keys.sign/verify` que `RideRatingSignature` já usa. Sem dependência nova.

## Contexto técnico

- **Linguagem/SDK**: Dart ^3.13.3, Flutter 3.47.7, Android apenas.
- **Dependências**: nenhuma nova. `crypto` (SHA-256) e `pointycastle` já estão no `pubspec.yaml`; `sqflite` já é
  usado por `SqfliteRideRatingStore`. Logo, nenhuma entrada de dependência em `research.md` é exigida (Princípio III).
- **Armazenamento**: banco SQLite novo `receipts.db` (v1) com três tabelas; interface `ReceiptStore` + dublê em
  memória. Sem alteração de `ride_ratings.db` nem de `SentQuotesStore`.
- **Testes**: `flutter_test` com dublês; nenhum teste toca SQLite, relay, plugin ou rede reais.
- **Alvo**: Android. Sem permissão nova.
- **Restrições**: chave privada só em `IdentityService`; `20014`/`20015` sempre cifrados (nunca em claro); assinatura
  verificada antes de tudo; `content` é dado; marcador `tcc-ufsc-caronas` em tudo; `prototype_marker` intocado.
- **Escala**: janela fixa de 5 recibos; um `20002` com reputação fica na ordem de 5 KB, longe dos 65 535 bytes do NIP-44.
  (Estimativa de projeto, não medição; a medição do tamanho real entra no quickstart, cenário 7.)

## Verificação da constituição (2.16.0)

| Princípio / restrição | Situação |
|---|---|
| I — segredo não vaza | OK por construção: só `IdentityService` assina/cifra; `ReceiptService` recebe a identidade já em memória e nunca a registra. O serviço em segundo plano só repassa `20014`/`20015` (cifrados, assinados) e **não** decifra. Verificação de não vazamento (log e tráfego) entra em tarefa e no quickstart. |
| II — assinatura nasce com teste | OK: `ReceiptSignature`, `ReputationVerifier`, `ReceiptStore` (revalidação na leitura) e `ReceiptService` (descarte) têm testes válido+inválido junto da implementação, com dublês. |
| III — dependência registrada | Sem dependência nova. Tipos de `sqflite` só em `SqfliteReceiptStore`; `domain/` não importa terceiros. |
| IV — contrato antes do código | [contracts/reputacao-recibos.md](contracts/reputacao-recibos.md) escreve a emenda 25 antes do código; a tarefa de contrato precede toda tarefa de código e é replicada no passageiro na mesma alteração. |
| V — simplicidade | `ReceiptStore` nasce com duas implementações (SQLite e memória); `ReputationVerifier` é função pura com consumidor imediato (solicitação **e** emissão). Nada de camada sem uso. |
| Permissões | Nenhuma nova. |
| Mensagens cifradas ao destinatário | `20014`/`20015` cifrados NIP-44 ao destinatário. **Atenção ao `20001`**: a exceção do `20001` ("só assinado, com posição e destino públicos") passa a carregar também recibos (chaves públicas de contrapartes e notas). "Toda exceção nova MUST ser registrada nesta seção … antes de ser implementada" ⇒ **emenda 2.17.0 da constituição** nas duas apps, em commit separado **antes** do código (gate, como na 025). Texto proposto abaixo. |
| Serviço em segundo plano | Sem mudança de natureza: só entram dois kinds no conjunto consumido; o serviço continua sem chave, sem decifrar, e **não** notifica por `20014`/`20015`. |
| Identidade visual | Reputação na modal da solicitação segue `screens/identidade_visual.dart` (verificado em destaque, declarado em texto menor, "inconsistente" com a cor de alerta já definida lá). |

**Emenda 2.17.0 (texto proposto, em Restrições de Segurança e Privacidade, junto da exceção do `20001`):** "O
`content` do `kind: 20001` pode conter, além da posição e do destino, o campo opcional `reputacao` (resumo e até 5
recibos assinados do solicitante, feature `026-recibos-de-reputacao` do motorista). Justificativa: o motorista que
recebe o anúncio precisa avaliar o solicitante antes de existir destinatário conhecido; sem backend, a reputação
só pode viajar com o próprio usuário. Custo aceito: cada recibo expõe em claro as chaves públicas das contrapartes
anteriores e as notas dadas; alternativa futura registrada no contrato (resumo no `20001`, recibos após o orçamento).
O `20002` leva a reputação do motorista cifrada, como o resto do conteúdo."

## Estrutura do código

```text
driver/lib/
├── domain/
│   ├── receipt.dart                # novo: Receipt imutável, canonical, computeId, toJson/fromJson estritos
│   ├── reputation.dart             # novo: Reputation (+ kReputacaoJanela = 5), toJson/fromJson
│   ├── reputation_view.dart        # novo: resultado da verificação (verificado × declarado)
│   ├── nostr_event.dart            # + kindReceipt = 20014, kindReceiptAck = 20015
│   ├── ride_request_received.dart  # + Reputation? reputation (malformada → null)
│   └── ride_quote.dart             # + Reputation? reputation (própria, declarada no orçamento)
├── services/
│   ├── receipt_signature.dart      # novo: sign/verify do recibo (estilo ride_rating_signature.dart)
│   ├── reputation_verifier.dart    # novo: função pura 1.6 (a–i), sem I/O
│   ├── reputation_aggregator.dart  # novo: função pura aggregateReputation (usada pelas duas implementações do store)
│   ├── receipt_store.dart          # novo: ReceiptStore + SqfliteReceiptStore (receipts.db v1)
│   ├── receipt_service.dart        # novo: issueFor, onReceiptEvent, onAckEvent, retryPending
│   ├── identity_service.dart       # + signReceipt, signReceiptAck; signRideQuote ganha reputation
│   └── consumed_kinds.dart         # + 20014, 20015 em driverConsumedKinds
├── screens/
│   ├── map_screen.dart             # trata 20014/20015 no feed; passa reputação ao orçamento; chama
│   │                               #   saveDeclared; chama issueFor após fechar a modal de avaliação
│   └── (modal/lista de solicitações) # exibe ReputationView do passageiro
└── main.dart                       # compõe SqfliteReceiptStore + ReceiptService; injeção opcional p/ testes
specs/002-nostr-relay-connection/contracts/nostr-events.md   # emenda 25 (colar contracts/reputacao-recibos.md)
driver/test/{domain,services,screens,fixtures}/…                     # ver quickstart e tasks
```

**Decisão de estrutura**: arquivos planos em `services/`, como `ride_rating_*`; nenhum módulo novo. O tipo de
armazenamento reflete o padrão de `SqfliteRideRatingStore` (banco próprio por feature, sem migração compartilhada).

## Fluxo e pontos de decisão

1. **Chegada do `20001`** → `RideRequestReceived.fromNostrEvent` lê `reputacao` em bloco `try` próprio: qualquer erro
   vira `null`, a solicitação segue válida. A tela chama `ReputationVerifier.verify(rep, authorPubkey: passageiro)` e
   exibe o resultado (não persiste).
2. **Envio do orçamento** (`_enviarOrcamento`): lê `receiptStore.myReputation()` (nula se `corridas == 0`), passa ao
   `signRideQuote`; após o relay aceitar, `saveDeclared(signed.event.id, repDoPassageiro)`. Linha **sempre** gravada,
   com reputação vazia se o passageiro não declarou — a presença da linha significa "esta corrida foi registrada
   por esta versão do app"; ver R4.
3. **Fim da corrida**: `_mostrarModalAvaliacao` passa a receber a `ActiveRide` (tem `passengerPubkey`); após
   `RideRatingStore.save` (ou "pular"), `unawaited(receiptService.issueFor(ride, stars))` dentro de `try/catch`.
4. **`issueFor`**: `declaredFor(quoteId)`; sem linha → não emite (corrida anterior à feature, sem aviso);
   verificar; inconsistente → não emite e devolve o motivo para a tela avisar em uma linha; senão monta, assina,
   `saveIssued(pendente: 1)`, publica `20014`.
5. **Feed**: `20014` → `decryptContent` (regra 7) → `onReceiptEvent`; `20015` → `decryptContent` → `onAckEvent`.
   Descarte silencioso para claro/destinatário errado/adulterado.
6. **Reenvio**: `retryPending()` ao abrir o app (após identidade pronta), em cada mudança de `statusChanges` com ao
   menos um relay conectado, e `Timer.periodic(60 s)` dono do `ReceiptService` no isolate da interface. O reenvio
   reassina/recifra um evento novo com o mesmo recibo (ver R2).

## Riscos e mitigação

- **Divergência entre as apps**: o vetor compartilhado (`test/fixtures/receipt_vectors.json`) é exercitado nas duas
  suítes; a tarefa de cópia confere os arquivos com `diff`.
- **Reenvio só com a interface viva** (R3): documentado como limite; o recibo pendente sobrevive em disco.
- **Recibo grande demais**: janela fixa de 5 limita o `content`; medido no quickstart.
