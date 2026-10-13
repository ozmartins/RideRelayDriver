# Research — Mensagens cifradas entre as apps (motorista)

## D1 — Como obter NIP-44 (Princípio III)

**Decision**: implementar NIP-44 v2 em `lib/services/nip44.dart`, usando `pointycastle` (ChaCha20
RFC 8439 via `ChaCha7539Engine`, curva secp256k1 para o ECDH) e `crypto` (`Hmac`/`sha256`, HKDF
extract/expand escritos sobre `Hmac`, ~15 linhas). Os dois pacotes já estão no grafo (transitivos de
`dart_nostr`, `pointycastle 3.9.1`, `crypto 3.0.7`) e são promovidos a dependências diretas — não
entra código de terceiros novo no app. Validação contra os vetores oficiais (D5).

**Rationale**: `dart_nostr 10.0.1` não tem NIP-44 nem NIP-04 (verificado nas fontes). O único pacote
atual com NIP-44, `nostr 2.0.0` (ethicnology), **não resolve** junto de `dart_nostr`: ele exige
`bip340 ^0.3.1` → `pointycastle ^4`, enquanto `dart_nostr` traz `bip32_bip44` → `pointycastle ^3.1.3`
(`flutter pub add nostr --dry-run` falhou em 2026-10-06). Os pacotes antigos que resolveriam
(`nostr_tools`, `nostr_core_dart`) são de 2023, sem NIP-44. Trocar `dart_nostr` por `nostr` 2.x
reescreveria o transporte e a assinatura das duas apps, desproporcional ao pedido (Princípio V). O
NIP-44 v2 é pequeno e bem especificado, com vetores oficiais que tornam a implementação verificável.

**Alternatives**: `dependency_overrides` forçando `pointycastle ^4` — rejeitado: arrisca quebrar
`bip32_bip44`/`dart_nostr` em silêncio; trocar de biblioteca Nostr — rejeitado (acima); `ndk` —
rejeitado: arrasta dezenas de dependências (Rust toolchain, sembast, rxjs) por uma função; NIP-04 —
rejeitado na clarificação (depreciado, sem autenticação).

## D2 — Texto de entrada nos kinds sem conteúdo

**Decision**: nos kinds hoje de `content` vazio (20003, 20004, 20006, 20007, 20008, 20009, 20010,
20012), cifrar o marcador fixo `{}`. O receptor exige que o texto decifrado seja exatamente `{}`.

**Rationale**: o NIP-44 rejeita texto de entrada de 0 byte (vetor inválido oficial
`encrypt_msg_lengths: [0, …]`). `{}` (2 bytes) vira 32 bytes após o padding do padrão, indistinguível
de qualquer outra mensagem curta. Exigir exatamente `{}` impede que um campo extra passe despercebido.

**Alternatives**: espaço em branco ou `"-"` — rejeitado: arbitrário, sem semântica; JSON `{}` já é o
formato dos demais `content`.

## D3 — Onde decifrar na recepção

**Decision**: o `EventFeed` segue sem tocar o segredo: continua verificando assinatura, marcador e
duplicidade e entregando o `content` cifrado. A decifração acontece no consumo (`MapScreen`
`_processarAceitacaoRecebida`, `_processarConfirmacaoDeEncontro`, `_processarConfirmacaoDeDestino`)
chamando `IdentityService.decryptContent`, que antes confere a tag `p` == chave do motorista. Falha →
`return` silencioso.

**Rationale**: o `EventFeed` é construído antes da identidade existir (`main.dart`) e é também usado
com `kind: 1` e `20001`, que não são cifrados; empurrar o segredo para ele ampliaria a superfície do
Princípio I. A ordem do FR-006 é preservada: assinatura (feed) → destinatário → decifração (consumo).
`IdentityService` já é o único ponto que toca a chave privada.

**Alternatives**: decifrar no `EventFeed` com um decifrador injetado — rejeitado (acima).

## D4 — Desempenho: chave de conversa em cache

**Decision**: `MessageCipher` guarda, em memória, a chave de conversa derivada por chave pública do
par. O ECDH (multiplicação escalar) roda uma vez por par; cada mensagem custa HKDF-expand + ChaCha20 +
HMAC.

**Rationale**: a localização sai a cada 5 s e a multiplicação escalar em Dart puro é o passo caro;
a chave de conversa é simétrica ao par (A↔B), logo serve para cifrar e decifrar. Cache pequeno
(uma corrida ativa, poucos pares de orçamento); limpo ao reiniciar o app; nunca persistido (I).

O **primeiro** ECDH de cada par roda na thread de UI (ao enviar o orçamento e ao receber o `20003`) e
é medido à parte em D6.

**Alternatives**: recalcular a cada mensagem — rejeitado: custo desnecessário no ciclo de 5 s;
`Isolate` — adiado: só se a medição (D6) falhar SC-004, em especial no primeiro ECDH.

## D5 — Verificação (Princípio II)

**Decision**: `test/fixtures/nip44.vectors.json` copiado de `paulmillr/nip44` (v2, MIT): `get_conversation_key`,
`get_message_keys`, `calc_padded_len`, `encrypt_decrypt` (nonce fixo → payload exato),
`encrypt_decrypt_long_msg`, e os `invalid` (`encrypt_msg_lengths`, `get_conversation_key`, `decrypt`).
Mais testes de política: destinatário errado, `content` em claro, MAC adulterado, `{}` obrigatório.

**Rationale**: vetores oficiais tornam a cifra própria verificável independentemente do autor; é o
que justifica não depender de biblioteca (D1).

## D6 — Medição de tempo e tamanho

**Decision**: `tool/probe_cipher_size.dart` (offline) mede o tempo do **primeiro ECDH**, o de cifrar/decifrar depois dele e o tamanho do
`20011` cifrado com 1000 pontos reais; resultado registrado aqui na implementação. Estimativa prévia:
~20,6 KB de `content` → padding a 24 576 B → base64 ≈ 32,8 KB + envelope, ≈ 25 % do menor
`max_message_length` (131 072 B). Se passar de ~50 %, revisar o teto de pontos (FR-012).

**Rationale**: Princípio V — medição que foi medida de fato. O limite de 1000 pontos da 017 foi
definido sobre o tamanho em claro.

**Resultado (2026-10-06, `dart run tool/probe_cipher_size.dart`, VM do Dart no computador de
desenvolvimento — referência relativa, **não** o aparelho):**

| Medida | Valor |
|---|---|
| Primeiro ECDH + cifrar, par novo (10 pares) | mediana 5,2 ms, máximo 19,9 ms |
| Cifrar / decifrar uma localização (176 B de payload), depois do primeiro ECDH | 0,15 ms / 0,06 ms (média de 200) |
| Rota de 1000 pontos (20 709 B de texto): cifrar / decifrar | 1,6 ms / 1,9 ms |
| Mensagem `EVENT` do `20011` cifrado | 33 386 B = 25,5 % de 131 072 B (em claro: 21 237 B) |

**SC-005 atendido** (25,5 % < 50 %): o teto de 1000 pontos da feature 017 fica. **SC-004 ainda não
está comprovado no aparelho:** na VM do computador o primeiro ECDH fica ~20× abaixo de 100 ms, mas o
alvo é o emulador `Pixel_6_API34_1` / aparelho físico, em modo release (AOT, mais lento que a VM). Se
lá o primeiro ECDH passar de ~100 ms, a cifra vai para um `Isolate` (D4). Não foi medida a aceitação
pelos relays reais da mensagem de 33 KB (a `tool/probe_ride_route.dart` mede só a mensagem em claro);
o limite anunciado deixa 4× de folga.
## D7 — Constituição

**Decision**: emenda **2.11.0** nas duas constituições, com Sync Impact Report atualizado no topo e propagação verificada nos templates de `.specify/templates/` e nas specs que declaram "sem criptografia" (006 e 007 do passageiro/motorista, contrato) — a Governance exige as duas coisas (e conferência de que a de `Prototipo/` não
muda): na seção Restrições de Segurança e Privacidade, a regra "dado pessoal sem criptografia exige
justificativa" ganha o complemento: toda mensagem de domínio com destinatário conhecido MUST ser
cifrada ao destinatário e assinada; o `kind: 20001` é a única exceção registrada (anúncio sem
destinatário). Commit separado, antes do código; Princípio IV já cobre a replicação do contrato.

**Rationale**: a regra existente permite, mas não exige, cifrar; o pedido vira política do projeto.

## D8 — Metadados e escopo

**Decision**: autor, destinatário (`p`), referência (`e`), kind, momento e tamanho continuam visíveis
no relay; ocultá-los (NIP-59, gift wrap) está fora de escopo, registrado no contrato.

**Rationale**: o pedido é cifrar e assinar o conteúdo; esconder metadados exigiria quebrar o filtro
por tag em que a inscrição se apoia.
