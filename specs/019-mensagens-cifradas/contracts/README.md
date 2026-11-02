# Contrato — emenda 17: `content` cifrado (NIP-44) nos kinds com destinatário

Texto a acrescentar às **duas** cópias de `specs/002-nostr-relay-connection/contracts/nostr-events.md`
(motorista e passageiro, mesma alteração, antes de qualquer código — Princípio IV). A cópia do
passageiro atualiza também o cabeçalho de procedência.

## Linha do histórico de emendas

| 17 | 2026-10-06 | Todo `content` dos kinds `20002`–`20012` passa a ser cifrado com NIP-44 v2 ao destinatário (tag `p`) e continua assinado (NIP-01); `20002` ganha a tag `["p", <pubkey do solicitante>]`; o `20001` é a única exceção (só assinado, em claro); nova regra de recepção 7 | Pedido de que toda mensagem entre as apps seja cifrada e assinada com o par de chaves; feature 019 do motorista (define), contrapartida no passageiro na mesma alteração |

## Seção nova: *Cifragem do `content`*

- **Padrão**: NIP-44 v2. Chave de conversa = HKDF-extract(`salt = "nip44-v2"`, ECDH x-only secp256k1
  entre a privada do remetente e a pública do destinatário). `content` = base64 de
  `0x02 ‖ nonce(32) ‖ ChaCha20(texto com padding) ‖ HMAC-SHA256(nonce ‖ texto cifrado)`.
- **Destinatário** = valor da tag `["p", …]`. No `20002`, é a chave do autor do `20001` respondido
  (a tag `p` é **nova** neste kind); nos demais, a do outro participante da corrida, como já nas tags.
- **Assinatura**: o `id` e a `sig` do NIP-01 cobrem o `content` já cifrado.
- **Tags**: `t`, `e`, `p` continuam em claro (filtro e roteamento).
- **Kinds sem dado próprio** (`20003`, `20004`, `20006`, `20007`, `20008`, `20009`, `20010`, `20012`):
  texto de entrada fixo `{}`, pois o padrão rejeita entrada vazia. `content` em claro ou que decifre
  para outro texto é inválido.
- **Exceção — `20001`**: continua em claro e assinado; é anúncio a qualquer motorista, sem
  destinatário, logo sem chave com que cifrar. Posição e destino ficam públicos (justificativa
  expandida na seção de privacidade do kind e na constituição 2.11.0).
- **Fora de escopo**: metadados (autor, `p`, `e`, kind, momento, tamanho) seguem visíveis.

## Regra de recepção 7 (nova)

Para os kinds `20002`–`20012`, **depois** da verificação de assinatura (regra 1), da dedupe e do
marcador: se a tag `p` não for a chave do receptor, ignorar; decifrar o `content`; se a decifração
falhar (versão, MAC, padding, base64, tamanho) ou, nos kinds sem dado próprio, o texto não for `{}`,
descartar sem erro e sem efeito. Um evento em claro nesses kinds é descartado (não há modo de
compatibilidade).

## Ajustes nas seções existentes

- Tabela de kinds: coluna "Proteção" (`cifrado`/`claro — exceção`).
- Cada *Conteúdo do kind N* (20002–20012): o formato descrito passa a ser o **texto de entrada** da
  cifra; a nota de **Privacidade** de cada um troca "publicado sem criptografia" por "cifrado ao
  destinatário (emenda 17)". A de `20001` mantém "sem criptografia", com a exceção explícita.
- *Forma da inscrição*: sem mudança.
