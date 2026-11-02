# Data Model — Mensagens cifradas entre as apps (motorista)

Nenhuma entidade persistida nova, nenhuma migração. Persistência e `ActiveRide` inalterados.

## Kinds e proteção do `content`

| Kind | Publica | `content` em claro (entrada da cifra) | Protegido? | Chave pública usada |
|---|---|---|---|---|
| `1` | motorista | texto de teste | não (teste de conectividade) | — |
| `20001` | passageiro | JSON da solicitação | **não — exceção** | — |
| `20002` | motorista | JSON do orçamento (emenda 06) | sim | autor da solicitação `20001` respondida |
| `20003` | passageiro | `{}` | sim | motorista (`p`) |
| `20004` | passageiro | `{}` | sim | motorista (`p`) |
| `20005` | motorista | `{"lat","lon"}` | sim | passageiro da corrida (`p`) |
| `20006` | motorista | `{}` | sim | passageiro da aceitação (`p`) |
| `20007` | motorista | `{}` | sim | passageiro (`p`) |
| `20008` | passageiro | `{}` | sim | motorista (`p`) |
| `20009` | motorista | `{}` | sim | passageiro (`p`) |
| `20010` | passageiro | `{}` | sim | motorista (`p`) |
| `20011` | motorista | `{"points":[…]}` | sim | passageiro (`p`) |
| `20012` | motorista | `{}` | sim | passageiro (`p`) |

Nota: o `20002` hoje só leva `["e", requestId]`; passa a levar também `["p", <pubkey do solicitante>]`
(preciso para o destinatário filtrar e para o FR-001), o que muda o formato — está na emenda 17.

## `content` cifrado

String base64 do payload NIP-44 v2: `0x02 ‖ nonce(32) ‖ texto cifrado ‖ MAC(32)`. Texto de entrada em
UTF-8, 1 a 65 535 bytes, com o padding do padrão.

## Serviços

- `Nip44` (`lib/services/nip44.dart`, puro): `conversationKey(privHex, pubHex)` → 32 B;
  `encrypt(plaintext, conversationKey, {nonce})` → base64; `decrypt(payload, conversationKey)` →
  texto, lançando `Nip44Exception` em qualquer defeito (versão, MAC, padding, base64, tamanho).
- `MessageCipher` (`lib/services/message_cipher.dart`): cache em memória de chave de conversa por
  chave pública do par; `encryptFor(identity, peerPubkey, plaintext)`; `decryptFrom(identity,
  peerPubkey, payload)` → texto ou `null`; marcador `{}` e conferência do texto vazio aqui.
- `IdentityService`: `signX` cifram antes de assinar (a assinatura cobre o `content` cifrado);
  `decryptContent(identity, NostrEvent)` → texto ou `null`, conferindo antes a tag `p`.

## Regras de recepção do motorista (por kind)

| Kind | Depois de assinatura + marcador + dedupe | Efeito se decifra | Se não decifra / `p` alheia |
|---|---|---|---|
| `20003` | `p` == motorista; decifra == `{}` | fluxo atual (modal "Orçamento aceito") | descartado, sem erro |
| `20008` | idem | "Deslocando-se" → "Em corrida" | idem |
| `20010` | idem | "Em corrida" → "Aguardando" + avaliação | idem |
