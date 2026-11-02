# Tasks: Mensagens cifradas entre as apps (motorista)

**Input**: Design documents from `/specs/019-mensagens-cifradas/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/README.md, quickstart.md

**Tests**: **obrigatórios** (Princípio II; nenhum teste toca rede). A cifra nasce com os vetores oficiais do NIP-44; a política (destinatário, marcador `{}`, descarte) e cada `signX` têm teste direto; o fluxo no mapa usa os dublês já existentes de `test/screens/map_screen_test.dart`.

**Organization**: três gates bloqueiam o código — emenda de constituição (2.11.0, commit separado), contrato (emenda 17 nas duas cópias) e dependência (Princípio III). US1 (publicar cifrado, P1) e US2 (receber cifrado, P1) compartilham a Foundational (cifra + política); US3 (consistência contrato/constituição, P2) é fechada nos gates e verificada no fim.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: pode rodar em paralelo
- Caminhos relativos a `Prototipo/driver/`, salvo indicação (`../passenger/` = `Prototipo/passenger/`)

---

## Phase 1: Gates — constituição, contrato, dependência (bloqueiam todo o código)

- [X] T001 [US3] Emendar `.specify/memory/constitution.md` para **2.11.0** conforme `research.md` D7: na seção Restrições de Segurança e Privacidade, toda mensagem de domínio com destinatário conhecido MUST ser cifrada ao destinatário e assinada; `kind: 20001` é a única exceção registrada (anúncio sem destinatário, posição e destino públicos). Atualizar o **Sync Impact Report** no topo, a versão/data (`Version`/`Last Amended`) e verificar a propagação (Governance): `.specify/templates/` (plan/spec/tasks) e as specs que dizem "sem criptografia" (ex.: `specs/007-receber-solicitacao-corrida/spec.md`, contrato) — anotar no relatório o que foi checado e se algo precisa de ajuste.
- [X] T002 [US3] Replicar a mesma emenda e o mesmo Sync Impact Report em `../passenger/.specify/memory/constitution.md` (2.11.0, só nome/escopo/perspectiva diferem), verificar a propagação nas specs do passageiro (ex.: `../passenger/specs/006-solicitar-corrida/spec.md`) e conferir `diff` dos corpos entre as duas constituições: vazio. Conferir que `../.specify/memory/constitution.md` (Prototipo) não precisa mudar. **Commitar T001+T002 juntos, separado do código** (Governance).
- [X] T003 [US3] Inserir a emenda 17 em `specs/002-nostr-relay-connection/contracts/nostr-events.md` conforme `specs/019-mensagens-cifradas/contracts/README.md`: linha 17 no *Histórico de emendas*, coluna "Proteção" na tabela de kinds, seção *Cifragem do `content`*, regra de recepção 7, tag `["p", …]` no `20002` (seção *Conteúdo do kind 20002* e tags) e a nota de privacidade de cada kind `20002`–`20012` trocada para "cifrado ao destinatário (emenda 17)", mantendo `20001` como exceção explícita.
- [X] T004 [US3] Replicar T003 em `../passenger/specs/002-nostr-relay-connection/contracts/nostr-events.md`, atualizando só o cabeçalho de procedência (2026-10-06, "emenda 17, feature 019 do motorista, replicada pela feature irmã do passageiro"). Conferir com `diff` ignorando o cabeçalho: vazio. **Commitar T003+T004 juntos, antes do código.**
- [X] T005 Em `pubspec.yaml`, promover `pointycastle: ^3.9.1` e `crypto: ^3.0.7` a dependências diretas (já transitivas; `research.md` D1), rodar `flutter pub get` e confirmar que o `pubspec.lock` só muda o campo `dependency: direct` desses dois. Não adicionar `nostr`.

**Checkpoint**: constituição e contrato idênticos nas duas apps e commitados; `flutter pub get` limpo.

---

## Phase 2: Foundational — cifra NIP-44 e política (bloqueia US1 e US2)

- [X] T006 [P] Copiar os vetores oficiais para `test/fixtures/nip44.vectors.json` (fonte: `https://raw.githubusercontent.com/paulmillr/nip44/main/nip44.vectors.json`, v2; registrar a origem e a licença em comentário no teste, já que JSON não admite comentário).
- [X] T007 [P] Escrever `test/services/nip44_test.dart` contra os vetores (falha antes de T009): `get_conversation_key` (válidos e inválidos), `get_message_keys`, `calc_padded_len`, `encrypt_decrypt` (com nonce fixo: payload exato; e decifrar), `encrypt_decrypt_long_msg`, `invalid.encrypt_msg_lengths` (0, 65536… lançam `Nip44Exception`), `invalid.decrypt` (MAC, versão, base64, tamanho lançam `Nip44Exception`); a mensagem de toda `Nip44Exception` **não contém** o hex de nenhuma chave nem o texto de entrada (FR-009).
- [X] T008 [P] Escrever `test/services/message_cipher_test.dart` (falha antes de T010): ida e volta entre duas identidades; terceiro com outra chave não decifra (retorna `null`); `content` em claro retorna `null`; payload adulterado (1 byte) retorna `null`; `{}` obrigatório nos kinds sem dado (outro texto, inclusive `''`, retorna `null`); a chave de conversa é calculada **uma vez** por par (contador no cache) e é simétrica (A→B decifra com B←A); `decryptFrom` não lança nem ecoa chave/texto em nenhuma falha (FR-009).
- [X] T009 Criar `lib/services/nip44.dart`: `Nip44Exception`; `Nip44.conversationKey(privHex, pubHex)` (ECDH x-only secp256k1 sobre `pointycastle`, HKDF-extract com salt `nip44-v2` via `Hmac(sha256)` de `crypto`); `encrypt(plaintext, conversationKey, {nonce})`/`decrypt(payload, conversationKey)` conforme NIP-44 v2 (padding `calc_padded_len`, ChaCha20 RFC 8439 via `ChaCha7539Engine`, MAC sobre `nonce ‖ texto cifrado`, comparação de MAC em tempo constante, nonce de `Random.secure()`). Nenhuma exceção ecoa chave nem texto. T007 passa.
- [X] T010 Criar `lib/services/message_cipher.dart`: `MessageCipher` com cache em memória da chave de conversa por chave pública do par (`research.md` D4; nunca persistido nem logado); `encryptFor(identity, peerPubkey, plaintext)` (texto vazio → `{}`, `research.md` D2) e `decryptFrom(identity, peerPubkey, payload, {bool emptyMarker})` → texto ou `null` (qualquer `Nip44Exception` vira `null`; com `emptyMarker` exige `{}`). T008 passa.

**Checkpoint**: `flutter test test/services/nip44_test.dart test/services/message_cipher_test.dart` verde.

---

## Phase 3: User Story 1 — Mensagens do motorista ilegíveis para terceiros (Priority: P1) 🎯 MVP

**Goal**: 20002, 20005, 20006, 20007, 20009, 20011 e 20012 saem com `content` cifrado ao destinatário e assinados; nunca em claro.

**Independent Test**: publicar cada kind com o dublê de transporte e verificar `content` opaco, assinatura válida, tags `t`/`e`/`p` em claro e decifração só pelo destinatário.

- [X] T011 [P] [US1] Acrescentar a `test/services/identity_service_test.dart` o grupo `conteúdo cifrado (feature 019)`: para cada `signRideQuote`, `signDriverLocation`, `signRideNoLongerAvailable`, `signArrivalNotice`, `signDestinationArrival`, `signRideRoute`, `signRideCancelled`: `content` ≠ texto original e não contém `lat`/`total`/`points`; a identidade do destinatário decifra para o texto original (`{}` nos sem dado); a assinatura é válida **sobre o `content` cifrado**; terceiro não decifra; tags `t`, `e`, `p` presentes. `signRideQuote` leva também `["p", passengerPubkey]` (FR-001a). Falha antes de T013/T014.
- [X] T012 [US1] (FR-001a) Acrescentar `passengerPubkey` (obrigatório) a `RideRequestReceived` (`lib/domain/ride_request_received.dart`, copiado de `event.authorPublicKey` em `fromNostrEvent`) e a `RideQuote` (`lib/domain/ride_quote.dart`), e ajustar os pontos que os constroem (`lib/screens/map_screen.dart`, `lib/screens/ride_request_modal.dart`) e os testes/dublês que os instanciam.
- [X] T013 [US1] Em `lib/services/identity_service.dart`, injetar `MessageCipher` (construtor, padrão `MessageCipher()`); `signRideQuote` passa a cifrar o JSON do orçamento para `quote.passengerPubkey` e a incluir `["p", quote.passengerPubkey]`; `_signCorrelatedEvent` cifra `content` (vazio → `{}`) para `passengerPubkey` antes de assinar. `signTextNote` não muda (kind 1). Falha de cifragem lança (nada é assinado nem publicado em claro, FR-004).
- [X] T014 [US1] Em `lib/screens/map_screen.dart`, garantir que cada ponto que chama `signX` (`_enviarOrcamento`, `_publicarLocalizacao`, `signRideNoLongerAvailable`, `signArrivalNotice`, `signDestinationArrival`, `signRideRoute`, `signRideCancelled`) absorva a exceção de cifragem com o mesmo tratamento já dado à falha de publicação do kind (`_enviarOrcamento` devolve a mensagem de erro; os demais ignoram sem fila, como na 017/018). Acrescentar a `test/screens/map_screen_test.dart` um teste: falha de cifragem simulada não publica nada e não derruba o app. T011 passa. **Na mesma tarefa**, ajustar os testes existentes de `test/screens/map_screen_test.dart` e `test/services/identity_service_test.dart` que liam o `content` publicado em claro (ex.: `jsonDecode(evento.content)` de 20002/20005/20011) para decifrar com a identidade do passageiro de teste; `flutter test` verde ao fim da tarefa.

**Checkpoint**: nenhum evento 20002–20012 do motorista sai em claro (SC-001); localização continua a cada 5 s.

---

## Phase 4: User Story 2 — Mensagens do passageiro lidas só pelo motorista certo (Priority: P1)

**Goal**: 20003, 20008 e 20010 recebidos cifrados produzem o mesmo efeito de hoje; o resto é descartado em silêncio.

**Independent Test**: entregar os três kinds cifrados ao motorista e verificar modal, transição e encerramento; entregar variantes inválidas e verificar descarte sem efeito.

- [X] T015 [P] [US2] Acrescentar a `test/services/identity_service_test.dart` o grupo `decryptContent (feature 019)`: evento 20003/20008/20010 cifrado ao motorista → texto `{}`; `p` de outro destinatário → `null` sem tentar decifrar; cifrado a outra chave → `null`; em claro → `null`; MAC adulterado → `null`. Falha antes de T016.
- [X] T016 [US2] Acrescentar a `IdentityService` (`lib/services/identity_service.dart`) `decryptContent({identity, NostrEvent event})` → `String?`: confere a tag `p` == `identity.publicKey`, decifra com a chave do autor do evento via `MessageCipher.decryptFrom(..., emptyMarker: true)`; nunca lança, nunca loga. T015 passa.
- [X] T017 [P] [US2] Acrescentar a `test/screens/map_screen_test.dart` os casos de recepção: (a) `20003` cifrado e válido → modal "Orçamento aceito" como antes; (b) `20008` cifrado → "Em corrida"; (c) `20010` cifrado → "Aguardando" + modal de avaliação; (d) para cada um, variantes inválidas (em claro, cifrado a outro destinatário, `p` alheia, MAC adulterado, texto ≠ `{}`) → nenhum efeito, nenhuma modal, nenhum erro. Falha antes de T018.
- [X] T018 [US2] Em `lib/screens/map_screen.dart`, `_processarAceitacaoRecebida`, `_processarConfirmacaoDeEncontro` e `_processarConfirmacaoDeDestino` chamam `widget.identityService.decryptContent` logo na entrada (com `widget.identity` não nulo) e retornam em silêncio se `null`, antes de qualquer outra checagem; o resto da lógica não muda (FR-011). `EventFeed` **não** muda (`research.md` D3). T017 passa. **Na mesma tarefa**, ajustar os testes existentes que injetam 20003/20008/20010 (`test/screens/map_screen_test.dart` e outros) para entregá-los já cifrados ao motorista de teste (helper de teste que cifra com a identidade do passageiro de teste); `flutter test` verde ao fim da tarefa.

**Checkpoint**: fluxo aceitação → encontro → destino funciona com eventos cifrados (SC-002, SC-003).

---

## Phase 5: User Story 3 — Contrato e exceção do 20001 registrados (Priority: P2)

**Goal**: contrato e constituições refletem o novo formato e a exceção, idênticos nas duas apps.

**Independent Test**: revisar contrato e constituições; `diff` vazio entre as cópias.

- [X] T019 [US3] Rever o contrato (T003/T004) contra o código final: cada kind `20002`–`20012` consta como cifrado; `20001` como exceção; formato do texto de entrada igual ao que `identity_service.dart` produz; `p` no `20002`. Corrigir o texto, nas duas cópias, se o código divergir. `diff` das duas cópias (menos o cabeçalho) vazio (SC-006).

---

## Phase 6: Polish & Cross-Cutting

- [X] T020 Criar `tool/probe_cipher_size.dart` (offline, sem rede): mede o tempo do **primeiro ECDH** de um par, o tempo médio de cifrar/decifrar depois dele e o tamanho do `content` e da mensagem `EVENT` do `20011` cifrado com 1000 pontos; imprime o resultado. Executar e registrar os valores e a conclusão em `research.md` D6 (SC-004: < 100 ms, **inclusive o primeiro ECDH**, no emulador `Pixel_6_API34_1` e, se disponível, num aparelho físico; SC-005: < 50 % de 131 072 B). Se SC-004 falhar, mover a cifra a um `Isolate` (`research.md` D4) antes de seguir. **Feito só na VM do computador** (resultado em `research.md` D6: SC-005 ok, 25,5 %); a medição do SC-004 no emulador/aparelho em modo release segue **pendente**.
- [X] T021 [P] Atualizar `../CLAUDE.md` (raiz): entrada da feature `019-mensagens-cifradas` do motorista (cifragem NIP-44 própria sobre `pointycastle`/`crypto`, emenda 17, exceção do `20001`, constituição 2.11.0, marcador `{}`), corrigir "50 m" → "5 s" do `kind: 20005` (divergência achada em 2026-10-06) e a nota de que `20003`/`20008`/`20010` agora chegam cifrados. Commit à parte.
- [X] T022 Rodar `flutter analyze` ("No issues found!") e `flutter test` (suíte completa verde); executar os cenários 1–5 de `quickstart.md` que não dependem do passageiro e marcar o restante como **validação em aparelho pendente** (depende da feature irmã do passageiro). **Não declarar a feature concluída** antes de a feature irmã do passageiro estar especificada e implementada (Princípio IV: o formato quebra nos dois sentidos); registrar isso no `CLAUDE.md` (T021).

---

## Dependencies & Execution Order

- Phase 1 (gates) bloqueia tudo; T001+T002 e T003+T004 são commits separados do código.
- Phase 2 (T006–T010) bloqueia US1 e US2. Dentro dela: T006/T007/T008 em paralelo → T009 → T010.
- US1 (Phase 3) e US2 (Phase 4) dependem só da Phase 2 e podem seguir em paralelo (arquivos de teste compartilhados — `identity_service_test.dart`, `map_screen_test.dart` — pedem sequência na prática).
- US3 verificada em Phase 5 depois do código; Polish por último.
- **Ordem entre apps**: a feature irmã do passageiro precisa dos mesmos T003/T004 (contrato); testes ponta a ponta só depois das duas.

### Parallel opportunities

T006/T007/T008; T011 com T015 e T017; T020 com T021.

## Implementation Strategy

1. **MVP = Phase 1 + 2 + US1**: o motorista já publica tudo cifrado (o passageiro ainda não decifra até sua feature — por isso as duas entram na mesma alteração de contrato).
2. US2 fecha a via de volta; US3 e Polish fecham consistência e medição.
3. Commits (Padrão de Commits, direto na `master`): constituição (T001+T002) → contrato (T003+T004) → dependências (T005) → cifra (T006–T010) → publicação cifrada (US1) → recepção cifrada (US2) → sonda e docs.
