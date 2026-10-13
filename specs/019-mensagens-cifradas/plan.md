# Implementation Plan: Mensagens cifradas entre as apps (motorista)

**Branch**: `master` (commits diretos, sem branch de feature — Padrão de Commits da constituição) | **Date**: 2026-10-06 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/019-mensagens-cifradas/spec.md`

## Summary

Todo evento de domínio com destinatário conhecido (kinds 20002–20012) passa a levar o `content`
cifrado com NIP-44 v2 (ECDH secp256k1 + HKDF + ChaCha20 + HMAC-SHA256) entre a chave privada do
remetente e a pública do destinatário (tag `p`), sempre assinado como hoje. O `20001` fica como
exceção deliberada (anúncio sem destinatário). O motorista cifra o que publica (`20002`, `20005`,
`20006`, `20007`, `20009`, `20011`, `20012`) dentro de `IdentityService` — onde já assina — e decifra
o que recebe (`20003`, `20008`, `20010`) em `MapScreen`, depois da verificação de assinatura que o
`EventFeed` já faz e da conferência da tag `p`; o que não decifra é descartado em silêncio. Os kinds
de `content` hoje vazio cifram o marcador `{}`, porque o padrão proíbe entrada vazia (D2).

Nenhuma biblioteca Nostr disponível traz NIP-44 de forma compatível com o `dart_nostr` já em uso
(D1), então o padrão é implementado em `services/` sobre `pointycastle` e `crypto` (já transitivos,
promovidos a diretos) e validado contra os vetores de teste oficiais do NIP-44. Esta feature **define o
contrato** (emenda 17, replicada no passageiro na mesma alteração) e exige uma emenda de constituição
(2.11.0, nas duas apps, commit separado).

## Technical Context

**Language/Version**: Dart 3 / Flutter (versão já fixada no `pubspec.yaml`)

**Primary Dependencies**: `dart_nostr` (assinatura, chaves — sem mudança). **Duas promoções de
transitiva a direta**, sem código de terceiros novo no grafo: `pointycastle ^3.9.1` (ChaCha20 RFC 8439,
curva secp256k1) e `crypto ^3.0.7` (HMAC/SHA-256, HKDF). Decisão e alternativas em `research.md` D1
(Princípio III).

**Storage**: sem mudança. Chave de conversa por par em **memória** apenas (D4), nunca persistida.

**Testing**: `flutter_test`; vetores oficiais do NIP-44 (`paulmillr/nip44`, v2) copiados em
`test/fixtures/nip44.vectors.json` (conversa, chaves de mensagem, padding, ida e volta, inválidos);
dublês já existentes. Nenhum teste toca rede (Princípio II).

**Target Platform**: Android (sem mudança)

**Project Type**: mobile-app (Flutter, Android apenas)

**Performance Goals**: cifrar uma mensagem < 100 ms (SC-004), **medindo também o primeiro ECDH de
cada par**, que roda na thread de UI; ECDH feito uma vez por par e reaproveitado (D4); localização
segue a cada 5 s. Se o primeiro ECDH passar de ~100 ms, a cifra vai para um `Isolate` (D4).

**Constraints**: nunca publicar em claro como alternativa (FR-004); ordem de recepção assinatura →
destinatário → decifração (FR-006); tamanho do `20011` dentro do menor `max_message_length` dos relays
padrão (FR-012, D6).

**Scale/Scope**: um par motorista-passageiro por corrida; 7 kinds publicados, 3 recebidos.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Princípio / restrição | Avaliação |
|---|---|
| I. Segredo criptográfico não vaza | PASS (obrigação). A chave privada só é lida em `IdentityService`; a chave de conversa derivada vive em memória, não é logada nem exibida nem persistida; falha de decifração não ecoa o conteúdo. |
| II. Assinatura/verificação nascem com teste | PASS (obrigação). Cifragem/decifração nascem com os vetores oficiais, ida e volta, destinatário errado, MAC adulterado, `content` em claro e marcador `{}`; `signX` ganham teste de conteúdo cifrado + assinatura válida. |
| III. Dependência exige decisão registrada | **GATE ATIVO.** `pointycastle` e `crypto` viram diretas; `research.md` D1 registra necessidade, alternativas (`nostr` 2.x, outros) e por que implementar à mão foi escolhido. |
| IV. Contrato antes do código, replicado | **GATE ATIVO.** A emenda 17 MUST ser escrita nas duas cópias do contrato **antes** do código, na mesma alteração; ver `contracts/README.md`. A feature irmã do passageiro entra na mesma alteração de contrato. |
| V. Simplicidade e medição | PASS com medição devida: ~150 linhas de cifra própria, sem camada genérica; SC-004 (tempo) e SC-005 (tamanho do `20011` cifrado) MUST ser medidos de fato (`tool/`, D6), não presumidos. |
| Restrições de Segurança e Privacidade | **EMENDA NECESSÁRIA** (D7; com Sync Impact Report e propagação verificada, como exige a Governance): a seção hoje só exige justificativa escrita para dado pessoal sem cifra; passa a exigir cifragem entre pares para kinds com destinatário e a registrar o `20001` como única exceção. Emenda 2.11.0 nas duas constituições, commit separado, antes do código. |
| Identidade Visual e Design | N/A — sem tela nova nem alterada. |

Pós-design (Phase 1): inalterado; gates III, IV e a emenda 2.11.0 viram os primeiros itens de `tasks.md`.

## Project Structure

### Documentation (this feature)

```text
specs/019-mensagens-cifradas/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/README.md   # emenda 17 do contrato, a replicar no passageiro
└── tasks.md              # /speckit-tasks
```

### Source Code (repository root: `Prototipo/driver/`)

```text
lib/
├── domain/
│   └── nostr_event.dart            # + constante do marcador de conteúdo vazio, se couber (D2)
├── services/
│   ├── nip44.dart                  # NOVO — NIP-44 v2 puro: chave de conversa, cifrar, decifrar
│   ├── message_cipher.dart         # NOVO — cache de chave de conversa por par + política do contrato
│   ├── identity_service.dart       # signX passam a cifrar; novo decryptContent(...)
│   └── event_feed.dart             # sem mudança (a decifração fica no consumo, D3)
└── screens/map_screen.dart         # _processar{Aceitacao,ConfirmacaoDeEncontro,ConfirmacaoDeDestino}
                                    # decifram antes de agir
tool/probe_cipher_size.dart         # NOVO — mede tempo e tamanho cifrados (SC-004/SC-005)
test/
├── fixtures/nip44.vectors.json     # vetores oficiais (v2)
└── services/{nip44,message_cipher,identity_service}_test.dart; test/screens/map_screen_test.dart
```

**Structure Decision**: a cifra mora em `services/` (único lugar com segredo, tipos de `dart_nostr`
confinados lá); `nip44.dart` não conhece o domínio e é testado só com os vetores; `message_cipher.dart`
aplica a política do contrato (quais kinds, o marcador `{}`, conferência de `p`).

## Complexity Tracking

Sem violações a justificar.
