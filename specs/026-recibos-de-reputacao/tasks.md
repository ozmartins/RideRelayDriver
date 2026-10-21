# Tarefas: 026-recibos-de-reputacao

**Entrada**: `specs/026-recibos-de-reputacao/` (plan.md, spec.md, data-model.md, research.md, contracts/, quickstart.md)
**Testes**: obrigatórios aqui — Princípio II (assina, verifica, descarta ⇒ teste junto, caso válido e inválido, sem rede,
SQLite ou relay reais) e spec §FR-021/FR-022. Cada tarefa de implementação traz o teste na mesma tarefa ou imediatamente antes.
**Formato**: `- [ ] ID [P?] [US?] Descrição com caminho`. `[P]` = arquivos distintos, sem dependência de tarefa aberta.
**Commits**: um por mudança lógica, em português do BR, direto na `master`, com o trailer `Co-Authored-By`; o commit
da constituição e o do contrato vêm **antes** de qualquer código (Princípio IV, emenda 2.17.0).

**Pré-requisito externo**: a contrapartida no app do passageiro (emissão como avaliador do motorista, recepção, `reputacao` no `20001`) é feature própria em `../RideRelayPassenger` e não faz parte destas tarefas; os cenários 4–8 do quickstart (T035) dependem dela. Aqui só se replicam constituição, contrato e vetores (T001, T002, T016).

## Fase 1: Preparação (gates anteriores ao código)

- [x] T001 Emendar a constituição para 2.17.0 em `.specify/memory/constitution.md` (texto proposto no plan.md, seção Verificação da constituição): exceção do `kind: 20001` passa a admitir `reputacao`; atualizar o Sync Impact Report. Replicar com texto idêntico em `../RideRelayPassenger/.specify/memory/constitution.md`; conferir os dois corpos por `diff`. Commit separado.
- [x] T002 Aplicar a emenda 25 em `specs/002-nostr-relay-connection/contracts/nostr-events.md` seguindo `contracts/reputacao-recibos.md`: linha 25 no histórico, kinds `20014`/`20015` na tabela, campo `reputacao` em `20001`/`20002`, seções "Conteúdo do kind 20014/20015", "kinds `20002`–`20015`" na cifragem e na regra 7, "Forma da inscrição" com os dois kinds, seção "Reputação por recibos". Replicar idêntico em `../RideRelayPassenger/specs/002-nostr-relay-connection/contracts/nostr-events.md` e conferir o trecho "Reputação por recibos" por `diff`. Commit separado, antes do código.
- [x] T003 Verificar que `crypto`, `pointycastle` e `sqflite` já constam em `pubspec.yaml` (nenhuma dependência nova; nada a registrar no research.md).

## Fase 2: Fundação (bloqueia todas as histórias)

- [x] T004 [P] Teste primeiro: `test/domain/receipt_test.dart` — forma canônica estável com vetor fixo (`tcc-recibo-v1|…`, ausente = `-`); `id_recibo` muda ao alterar qualquer campo; `toJson` omite `nota`/`hash_anterior` nulos; `fromJson` lança `FormatException` com campo faltando, tipo errado, hex de tamanho errado, `nota` 0 ou 6.
- [x] T005 [P] Implementar `lib/domain/receipt.dart`: `Receipt` imutável, `canonical`, `static computeId(...)` (SHA-256 via `package:crypto`, hex minúsculo), `toJson`/`fromJson` estritos (data-model.md).
- [x] T006 [P] Teste + implementação de `lib/domain/reputation.dart` e `lib/domain/reputation_view.dart` (com `kReputacaoJanela = 5`, `Reputation.empty()`, `toJson/fromJson` com `seq_proximo`/`head`/`recibos`); teste em `test/domain/reputation_test.dart` (round-trip, `media` omitida sem avaliações, `fromJson` estrito).
- [x] T007 [P] Acrescentar `kindReceipt = 20014` e `kindReceiptAck = 20015` em `lib/domain/nostr_event.dart`; incluí-los em `driverConsumedKinds` em `lib/services/consumed_kinds.dart`; teste em `test/services/consumed_kinds_test.dart` (contém os dois kinds e continua batendo com `RelayService.subscriptionKinds` e `EventFeed.acceptedKinds`).
- [x] T008 [P] Teste primeiro: `test/services/receipt_signature_test.dart` — assina e verifica; chave diferente falha; qualquer campo adulterado falha; assinatura mal formada devolve falso sem lançar.
- [x] T009 Implementar `lib/services/receipt_signature.dart`: `ReceiptSignature.sign(receipt, identity)` (assina `id_recibo` com `Nostr.instance.services.keys.sign`) e `verify(receipt)`, no estilo de `ride_rating_signature.dart`; a chave privada nunca entra em log. (depende de T005)
- [x] T010 Teste primeiro: `test/services/reputation_verifier_test.dart` — um caso por regra 1.6: (a) `id_recibo` não confere, (b) assinatura inválida, (c) avaliado ≠ autor, (d) `v ≠ 1` e `nota` fora de 1–5, (e) `seq` não decrescente, (f) `guid_corrida` repetido, (g) avaliador == avaliado, (h) `head` ausente da lista → inconsistente, (i) `hash_anterior` quebrado, lacunas de `seq` ("N não apresentados"); caso válido completo; média/contagem verificadas só sobre válidos; `declared` separado. Chaves de teste reais, sem rede.
- [x] T011 Implementar `lib/services/reputation_verifier.dart`: função pura `ReputationView verify(Reputation, {required String authorPubkey})` conforme 1.6 (a–i), sem I/O; recibo inválido é descartado e contado. (depende de T005, T006, T009, T010)
- [x] T012 [P] Teste primeiro: `test/services/reputation_aggregator_test.dart` para a função pura `Reputation aggregateReputation(List<Receipt>)` (corridas/avaliacoes/media/seqProximo/head e os 5 mais recentes por `seq`; ramos com mesmo `seq`; lista vazia) e `test/services/receipt_store_test.dart` (contra o dublê em memória): `saveReceived` imutável (segunda gravação da mesma corrida devolve falso e não altera); `myReputation()` delega à agregação; linha com assinatura adulterada é ignorada e não conta; `saveIssued` pendente → `pendingIssued()` → `markAcked`; `saveDeclared`/`declaredFor` (inclusive reputação vazia).
- [x] T013 Implementar `lib/services/receipt_store.dart`: `abstract class ReceiptStore`, `SqfliteReceiptStore` (`receipts.db` v1, três tabelas do data-model.md, `INSERT` sem `replace`, leitura revalida assinatura e `id_recibo`) e `InMemoryReceiptStore` com a mesma semântica (dublê em `test/support/in_memory_receipt_store.dart`). A agregação de `myReputation()` é a função pura `aggregateReputation` em `lib/services/reputation_aggregator.dart`, usada pelas duas implementações — nenhuma duplica a regra. O SQL real (imutabilidade, revalidação na leitura) é coberto pelos cenários do quickstart. (depende de T005, T006, T009, T012)
- [x] T014 [P] Teste primeiro em `test/services/identity_service_test.dart` (ampliar): `signReceipt` produz `kind 20014` com tags `[t]`, `e = guid`, `p = avaliado` e `content` cifrado (ilegível a terceiros, decifrável pelo avaliado); `signReceiptAck` produz `kind 20015` com `{"id_recibo": …}`; `signRideQuote` inclui `reputacao` quando passada e **omite a chave** quando nula; nenhum conteúdo em claro.
- [x] T015 Implementar em `lib/services/identity_service.dart`: `signReceipt({identity, receipt})`, `signReceiptAck({identity, guid, idRecibo, avaliadorPubkey})` (mesmo padrão de `_signCorrelatedEvent`, `content` próprio e cifrado, não `{}`), e parâmetro `Reputation? reputation` em `signRideQuote` (campo `reputacao` omitido se nulo, como `etaMinutes`); acrescentar `Reputation? reputation` a `lib/domain/ride_quote.dart`. (depende de T005, T006, T014)
- [x] T016 [P] Criar o vetor compartilhado `test/fixtures/receipt_vectors.json` por script reproduzível em `tool/gen_receipt_vectors.dart` (chaves de teste fixas, não de usuário; valores de `id_recibo`/`assinatura` produzidos pelo código), cobrindo os casos de `contracts/reputacao-recibos.md`; teste `test/services/receipt_contract_vectors_test.dart` (verifica a assinatura, compara igualdade só de forma canônica e `id_recibo`). Copiar byte a byte para `../RideRelayPassenger/test/fixtures/receipt_vectors.json` e conferir por `diff`. (depende de T005, T009, T011)

**Ponto de controle**: `flutter analyze` e `flutter test` limpos antes das histórias.

## Fase 3: História 1 — Ver a reputação do passageiro na solicitação (P1) 🎯 MVP

**Meta**: a solicitação mostra reputação verificada × declarada, "inconsistente", "N recibos não apresentados" e "sem histórico".
**Teste independente**: entregar solicitações com `reputacao` válida, com recibo adulterado, ausente e malformada e observar cada uma.

- [ ] T017 [P] [US1] Teste primeiro em `test/domain/ride_request_received_test.dart` (ampliar): `reputacao` presente é lida; ausente → `null`; malformada (tipo errado, recibo sem campo) → `null` **sem** invalidar a solicitação; campo obrigatório faltando continua lançando `FormatException`.
- [ ] T018 [US1] Implementar em `lib/domain/ride_request_received.dart`: `Reputation? reputation` lido em tentativa própria dentro de `fromNostrEvent`. (depende de T006, T017)
- [ ] T019 [US1] Teste de widget em `test/screens/` (arquivo existente da modal/lista de solicitações, ou novo `ride_request_reputation_test.dart`): média e contagem verificadas em destaque e declaradas em texto menor; recibo inválido descartado sinalizado; reputação inconsistente destacada; lacuna "N recibos não apresentados"; sem reputação → "sem histórico".
- [ ] T020 [US1] Exibir `ReputationView` do passageiro (`ReputationVerifier.verify(rep, authorPubkey: passengerPubkey)`) na modal de solicitação recebida em `lib/screens/` (localizar com `grep RideRequestReceived lib/screens`), seguindo `lib/screens/identidade_visual.dart`; widget separado e reutilizável (ex.: `lib/screens/reputation_summary.dart`). Nenhum tipo de terceiros. (depende de T011, T018, T019)

**Ponto de controle**: US1 demonstrável sozinha (a reputação chega e aparece), sem emissão nem recepção.

## Fase 4: História 4 — Guardar a reputação declarada pelo passageiro (P2, pré-requisito da US2)

**Meta**: a reputação do passageiro daquela corrida fica gravada no envio do orçamento.
**Teste independente**: enviar orçamento a uma solicitação com reputação e recuperar `declaredFor(quoteId)` após reinício.

- [ ] T021 [US4] Teste em `test/screens/` (teste do envio de orçamento existente, ampliado): após o relay aceitar, `receiptStore.saveDeclared(signed.event.id, passengerPubkey, reputação do passageiro)` é chamado; sem reputação, grava `Reputation.empty()` (R4); nenhum registro se nenhum relay aceitar.
- [ ] T022 [US4] Em `lib/screens/map_screen.dart` (`_enviarOrcamento`): ler `receiptStore.myReputation()` (nula se `corridas == 0`) e passá-la a `signRideQuote`; depois da publicação aceita e de `sentQuotesStore.add`, chamar `saveDeclared`. Falha de gravação não impede o envio. (depende de T013, T015, T018, T021)

## Fase 5: História 3 — Receber recibos e declarar a própria reputação (P1)

**Meta**: `20014` válido é gravado e confirmado; inválidos nunca alteram `myReputation()`; o próximo orçamento carrega a reputação (já ligado em T022).
**Teste independente**: entregar recibos válido, adulterado, de outro avaliado, tag `p` alheia, duplicado e em claro.

- [ ] T023 [US3] Teste primeiro: `test/services/receipt_service_test.dart` (parte de recepção, dublês de store/identidade/publicação): recibo válido é gravado e `20015` publicado; assinatura inválida, adulterado, avaliado ≠ própria chave, avaliador ≠ autor do evento, `guid` ≠ tag `e` → ignorados sem efeito; duplicado idêntico só reenvia `20015`; duplicado diferente ignorado; `20014` em claro descartado; `onAckEvent`: autor ≠ avaliado ou `id_recibo` diferente ignorado, válido chama `markAcked`.
- [ ] T024 [US3] Implementar `lib/services/receipt_service.dart` (parte de recepção): `onReceiptEvent(NostrEvent)` (valida 1.6 a–d, g via verificador/assinatura; grava; publica `20015` com `signReceiptAck`) e `onAckEvent(NostrEvent)`; recebe identidade, store, `IdentityService` e função de publicação por construtor (injeção explícita, sem plugin). Nunca registra chave nem conteúdo decifrado. (depende de T013, T015, T023)
- [ ] T025 [US3] Em `lib/screens/map_screen.dart` (`_aoAtualizarFeed`): tratar `kindReceipt` → `identityService.decryptContent` (regra 7, sem `emptyMarker`) → `receiptService.onReceiptEvent`, e `kindReceiptAck` → `onAckEvent`, com `_idsProcessados`; descarte silencioso quando `decryptContent` devolve `null`. Teste de tela correspondente em `test/screens/`. (depende de T024)
- [ ] T026 [US3] Em `lib/main.dart`: instanciar `SqfliteReceiptStore` e `ReceiptService` (parâmetros opcionais de injeção em `CorridasDriverApp` para os testes, como `_rideRatingStore`), repassar a `MapScreen`. Ajustar os testes existentes de `main`/`MapScreen` para passarem o dublê. (depende de T013, T024)

## Fase 6: História 2 — Emitir o recibo ao concluir a corrida e garantir a entrega (P1)

**Meta**: fechar a modal de avaliação emite o recibo, pendente antes de publicar, reenviado até o ack.
**Teste independente**: concluir, avaliar, matar o app antes do `20015`, reabrir e ver reenvio e confirmação.

- [ ] T027 [US2] Teste primeiro: `test/services/receipt_service_test.dart` (parte de emissão): emite com `seq`/`hash_anterior` corretos a partir de `declaredFor`; sem nota emite sem o campo; reputação vazia → `seq = 0`; linha ausente → não emite; reputação inconsistente → **não emite** e devolve o motivo; grava `pendente` **antes** de publicar (ordem verificada no dublê); falha de publicação não lança e deixa pendente; `retryPending` republica até chegar `onAckEvent`, depois para; recibo reenviado sai como evento novo (R2).
- [ ] T028 [US2] Implementar em `lib/services/receipt_service.dart`: `issueFor(ActiveRide ride, int? stars)` (1.7 passos 1–4 + publicação), `retryPending()` e o `Timer.periodic(60 s)` com `start()`/`dispose()`; a falha de publicação é absorvida. (depende de T024, T027)
- [ ] T029 [US2] Teste de tela: fechar `RideRatingModal` com nota e com "pular" chama `receiptService.issueFor(ride, stars)` **depois** de `RideRatingStore.save`; falha de `issueFor` não bloqueia a interface; reputação inconsistente mostra aviso de uma linha; corrida cancelada não chama `issueFor`.
- [ ] T030 [US2] Em `lib/screens/map_screen.dart`: `_mostrarModalAvaliacao` recebe a `ActiveRide`; `onConfirm`/`onSkip` chamam `unawaited(issueFor)` dentro de `try/catch` depois de gravar a nota; exibir o aviso de uma linha quando inconsistente. (depende de T028, T029)
- [ ] T031 [US2] Em `lib/main.dart` (onde já se escuta `_relayService.statusChanges`): chamar `retryPending()` ao abrir o app (identidade pronta), a cada `statusChanges` com relay conectado e iniciar o temporizador de 60 s do `ReceiptService`; teste com `FakeAsync` em `test/services/receipt_service_test.dart` (reenvio a cada 60 s, ao reconectar e ao abrir). (depende de T028, T026)

## Fase 7: Acabamento e portões

- [ ] T032 Confirmar que `lib/services/background/` não decifra nem notifica por `20014`/`20015` (só repassa) e que o teste de `RelayHostCore` continua verde com os dois kinds no conjunto; acrescentar caso de teste que um `20014` válido é repassado ao canal sem notificação, em `test/services/background/`.
- [ ] T033 Verificação de não vazamento (Princípio I): executar o cenário 3 do `quickstart.md`, registrar o resultado na seção "Resultados" do quickstart (log e conteúdo dos `20014`/`20015`/`20002`).
- [ ] T034 Rodar `dart format lib test`, `flutter analyze` (sem apontamentos) e `flutter test` (inteira, sem teste ignorado); corrigir o que aparecer.
- [ ] T035 Executar os cenários 4–8 do `quickstart.md` em dois emuladores, medir de fato o tamanho do `content` do `20002` com 5 recibos (cenário 7, método descrito) e registrar tudo — inclusive o que falhar — em `quickstart.md` "Resultados".
- [ ] T036 Atualizar `CLAUDE.md` (novos serviços, kinds consumidos, `receipts.db`) em **commit separado**, depois dos commits das mudanças que ele descreve.

## Dependências e ordem

- Fase 1 (T001–T002) bloqueia todo código; commits próprios, antes de qualquer outro.
- Fase 2 bloqueia as histórias. Dentro dela: T005→T009→T011; T005/T006/T009→T013; T015 depende de T005/T006; T016 depende de T011.
- US1 (Fase 3) depende só da Fase 2. US4 (Fase 4) depende de T013/T015/T018 (e portanto de US1 para `reputation` na solicitação). US3 (Fase 5) depende da Fase 2. US2 (Fase 6) depende de US3 (reaproveita `ReceiptService` e `onAckEvent`) e, para uso real, de US4.
- Fase 7 por último.

## Paralelismo

- Fase 2: T004, T006, T007, T008, T012, T014 em paralelo (arquivos distintos); depois as implementações respectivas.
- US1: T017 e T019 em paralelo; US3 e US1 podem andar juntas por pessoas diferentes após a Fase 2 (US3 toca `map_screen.dart` só em T025 — coordenar com T022/T030, que editam o mesmo arquivo: **não** paralelizar esses três).

## Estratégia de implementação

1. **MVP**: Fases 1–3 — contrato, fundação e US1 (ver a reputação do passageiro). Já demonstra verificação ponta a ponta no lado de leitura.
2. Incrementar: US4 → US3 → US2 (o recibo só tem sentido com a recepção e o ack prontos).
3. Fase 7 fecha os portões da constituição (analyze, test, quickstart, não vazamento).
4. Não implementar nada fora do spec: sem backend, sem recibo retroativo, sem tocar em `prototype_marker`.
