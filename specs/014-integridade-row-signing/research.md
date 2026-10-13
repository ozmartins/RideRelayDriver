# Phase 0 — Research: Integridade das avaliações (Row Signing)

## D1 — Assinatura: reaproveitar `Nostr.instance.services.keys.sign`/`.verify` (atende FR-002/
FR-003; nenhuma dependência nova ao `pubspec.yaml`)

**Decision**: usar `nostr.Nostr.instance.services.keys.sign(privateKey: ..., message: ...)` e
`.verify(publicKey: ..., message: ..., signature: ...)`, do `dart_nostr` (já dependência do
projeto desde a feature 002) — a mesma identidade Nostr do usuário assina e valida as linhas de
`ride_ratings`, sem chave nova. Mesma decisão da feature irmã do passageiro (D1 de
`passenger/specs/012-integridade-row-signing/research.md`), verificada aqui de forma independente:
`lib/services/identity_service.dart` do motorista já importa `dart_nostr` como `nostr` e usa
`nostr.Nostr.instance.services.keys.derivePublicKey`/`generateKeyPair` — a mesma classe expõe
`sign`/`verify`.

**Contexto da decisão**: o pedido do usuário descreve o mecanismo em três passos —
canonicalizar, gerar hash SHA-256, assinar o hash com a chave privada. `NostrKeys.sign` (`dart_nostr`,
`nostr/instance/keys/keys.dart`) já faz isso internamente: recebe uma `message` (string), calcula
`NostrCryptoUtils.sha256Hash(message)` e assina o hash com `NostrKeyPairs.sign` (Schnorr sobre
secp256k1, o mesmo esquema usado para assinar eventos Nostr); `NostrKeys.verify` faz o inverso. Os
três passos pedidos pelo usuário mapeiam diretamente para "canonicalizar → chamar
`sign(message: canonicalizado)`" — o hashing SHA-256 acontece dentro da chamada.

### Alternativas avaliadas

| Opção | Observação |
|-------|------------|
| `Nostr.instance.services.keys.sign`/`.verify` (escolhida) | Já expõe exatamente o par SHA-256 + assinatura Schnorr pedido, sobre a mesma identidade já usada para tudo mais no app; nenhuma dependência nova. |
| `NostrKeyPairs.sign(hash)`/`NostrKeyPairs.verify(pubkey, hash, sig)` diretamente (API de baixo nível) | Rejeitada: espera um hash já calculado como `message` — usá-la exigiria calcular o SHA-256 manualmente, redundante com o que `NostrKeys.sign` já faz internamente. |
| Pacote de criptografia dedicado (ex.: `crypto` + `pointycastle`/`elliptic`) | Rejeitada: dependência nova sem necessidade, mesma razão já registrada na feature irmã do passageiro. |

### Riscos assumidos e mitigação

- A assinatura resultante depende da identidade atual do usuário; se o usuário perder ou trocar de
  identidade, avaliações antigas deixam de validar — comportamento aceito (Edge Case do
  `spec.md`).
- `widget.identity` do motorista é `Identity?` (nulo em caso de falha de inicialização, diferente
  do passageiro, onde é sempre não nulo por essa altura) — ver D3 abaixo.

## D2 — Canonicalização: concatenação de campos em ordem fixa, com separador dedicado (atende
FR-001)

**Decision**: `canonicalPayload(rating) = '${rating.rideId}|${rating.stars}|
${rating.ratedAt.toIso8601String()}'` — os três campos de dado de `RideRating`, sempre nesta
ordem, unidos por `|`. Mesma fórmula da feature irmã do passageiro (D2 de
`passenger/specs/012-integridade-row-signing/research.md`), já que `RideRating` tem os mesmos três
campos nos dois apps.

**Contexto da decisão**: os três campos têm formato controlado e não podem conter `|`: `rideId` é
um `id` de evento Nostr (64 caracteres hexadecimais, mesma referência de `ActiveRide.quoteId`),
`stars` é um inteiro convertido para string, `ratedAt` é uma data serializada em ISO-8601. Um
separador que não ocorre em nenhum dos três evita a ambiguidade citada no Edge Case do `spec.md`.

### Alternativas avaliadas

| Opção | Observação |
|-------|------------|
| Concatenação com separador dedicado, ordem fixa (escolhida) | Atende literalmente ao pedido; simples de auditar e testar; segura para os tipos de campo específicos desta entidade. |
| JSON canônico (`jsonEncode` de um mapa com chaves em ordem fixa) | Rejeitada: mais estrutura do que o pedido pede — mesma razão já registrada na feature irmã. |
| Concatenação sem separador | Rejeitada: viola a exigência de "forma estrita" — mesmo Edge Case do `spec.md`. |

### Riscos assumidos e mitigação

- Canonicalização específica dos três campos de `RideRating`, não uma função genérica — mesmo
  risco/mitigação já registrado na feature irmã do passageiro (D2 dela): sem abstração
  especulativa para uma segunda tabela hipotética (Princípio V).

## D3 — Guarda de identidade nula em `_mostrarModalAvaliacao` (atende FR-002; divergência
deliberada da feature irmã do passageiro)

**Decision**: `MapScreen._mostrarModalAvaliacao`, no callback `onConfirm` da `RideRatingModal`,
passa a checar `widget.identity != null` antes de chamar `RideRatingStore.save` — mesmo padrão de
guarda já usado por `_enviarOrcamento`/`_confirmarEncontro`/`_confirmarDestino` e outros métodos
desta tela que assinam algo. Se `identity` for nulo, a avaliação não é persistida (sem lançar
exceção) e a modal apenas fecha, igual ao caminho de "pular".

**Contexto da decisão**: diferente do passageiro, onde `MapScreen.identity` é `Identity`
(não-nulo, já garantido pela tela anterior à montagem do mapa), o motorista tem
`MapScreen.identity` como `Identity?` — nulo quando a identidade não pôde ser criada/recuperada na
inicialização (`_startupError` em `main.dart`). Como `RideRatingStore.save` agora exige uma
`Identity` para assinar (D1), o ponto de chamada precisa lidar com essa possibilidade, mesmo sendo
uma borda rara (exigiria uma corrida já "Em corrida" persistida antes de a identidade falhar).

### Alternativas avaliadas

| Opção | Observação |
|-------|------------|
| Guarda `if (identity == null) return;`, sem persistir (escolhida) | Consistente com o padrão já estabelecido nesta tela para qualquer ação que precise assinar algo; não introduz mecanismo de erro novo numa modal que hoje não tem um (Princípio V). |
| Adicionar mensagem de erro visível na `RideRatingModal` (like `DestinationArrivedModal`) | Rejeitada: exigiria mudar a assinatura pública de `RideRatingModal.onConfirm` (de `void Function(int)` para `Future<String?> Function(int)`) só para uma borda que, na prática, significa que o app inteiro já está em estado de inicialização falha — fora de proporção para o que esta feature pede (Princípio V). |

### Riscos assumidos e mitigação

- Nessa borda específica (identidade nula com uma corrida "Em corrida" já persistida), a
  avaliação daquela corrida se perde silenciosamente — aceito, já que o app inteiro está numa
  condição de erro de inicialização nesse momento, fora do que qualquer fluxo normal de avaliação
  cobre.

## D4 — Estratégia de teste: lógica de decisão em funções puras, mecânica SQL sem teste de
integração real (atende ao Princípio II sem contradizer o D1 de `specs/013-avaliar-corrida/
research.md`)

**Decision**: `RideRatingSignature` (canonicalização, assinatura, verificação) é um conjunto de
funções puras, sem `sqflite`, testadas diretamente com casos válido e inválido. O contrato de
`RideRatingStore` (persistir assinatura; validar, marcar e excluir na leitura) é testado contra um
dublê em memória que usa as mesmas funções puras. `SqfliteRideRatingStore` continua sem teste de
integração SQLite real — mesma decisão da feature irmã do passageiro (D3 do `research.md` dela),
e consistente com o padrão já aceito para `SqfliteCadastroStore`/`SqfliteReceivedQuoteStore`.

### Alternativas avaliadas

| Opção | Observação |
|-------|------------|
| Funções puras testadas + dublê em memória do contrato da store (escolhida) | Cumpre o Princípio II diretamente; mantém a consistência com a ausência de teste de integração SQLite já estabelecida no projeto. |
| `sqflite_common_ffi` + teste de integração real de `SqfliteRideRatingStore` | Rejeitada pela mesma razão já registrada em `specs/013-avaliar-corrida/research.md` (D1). |
| Testar só via `MapScreen` (widget test) | Rejeitada: `MapScreen` só chama `save`, nunca `forRide` (leitura fora do escopo de UI, FR-010) — não haveria como exercitar a validação/exclusão na leitura por esse caminho. |

### Riscos assumidos e mitigação

- A mecânica SQL de `SqfliteRideRatingStore` fica sem verificação automatizada direta — mesmo
  risco já aceito para todas as demais stores SQLite do protótipo, mitigado pela simplicidade do
  código.
