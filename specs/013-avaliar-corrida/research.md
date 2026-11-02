# Phase 0 — Research: Avaliar corrida (motorista)

## D1 — Persistência: reaproveitar `sqflite`, banco próprio, sem teste de integração real
(atende FR-004/FR-005; nenhuma dependência nova ao `pubspec.yaml`)

**Decision**: nova tabela `ride_ratings`, em um banco SQLite próprio (`ride_ratings.db`), usando
`sqflite` — mesma biblioteca já registrada pela feature `003-cadastro-motorista`, sem nova entrada
ao `pubspec.yaml` e sem novo tipo de terceiros exposto fora de `lib/services/`. Sem teste de
integração SQLite real: nem `SqfliteCadastroStore` (motorista) nem `SqfliteReceivedQuoteStore`
(passageiro) têm um — o padrão estabelecido no protótipo é dublê em memória para os testes de
tela, e adicionar `sqflite_common_ffi` só para esta feature violaria os Princípios III (dependência
sem decisão registrada) e V (estrutura sem consumidor real).

**Contexto da decisão**: a avaliação é um dado local, estruturado (uma nota inteira por corrida,
correlacionada por `rideId`) — mesmo formato de problema já resolvido, do lado do passageiro, por
`SqfliteReceivedQuoteStore` (`passenger/specs/008-receber-orcamentos/research.md`, D1) e, para
esta mesma feature, por `SqfliteRideRatingStore` dele (`passenger/specs/011-avaliar-corrida/
research.md`, D1). Um banco separado (em vez de uma tabela a mais em `cadastro_motorista.db`)
mantém cada `Store` dona de um único banco, mesmo padrão de isolamento já usado no motorista
(`SqfliteCadastroStore` não compartilha banco com nenhum outro store).

### Alternativas avaliadas

| Opção | Observação |
|-------|------------|
| `sqflite`, tabela em banco próprio, sem teste de integração (escolhida) | Reaproveita a biblioteca já registrada e o padrão de implementação (`Store` abstrata + implementação `Sqflite*`) já validado por `received_quote_store.dart` do passageiro; nenhuma dependência nova, nenhum desvio do padrão de teste já aceito no protótipo. |
| `sqflite`, seguindo o estilo de `SqfliteCadastroStore` (exceções `*Unavailable`/`Corrupted*`, migração de versão) | Rejeitada: aquele estilo resolve um problema diferente — um cadastro obrigatório de exatamente uma linha, com histórico de migrações de esquema. `ride_ratings` é uma tabela de acréscimo simples (uma linha por corrida, sem campo que possa faltar de uma versão anterior) — replicar a complexidade de exceções e `onUpgrade` seria estrutura sem requisito (Princípio V). |
| `KeyValueStore` (mesmo mecanismo de `SentQuotesStore`/`RideStateStore`), um mapa `rideId → stars` serializado em JSON | Rejeitada: funcionaria, mas o pedido do usuário fala explicitamente em "banco de dados", e a feature irmã do passageiro já decidiu por `sqflite` para o mesmo problema — manter a mesma tecnologia dos dois lados para o mesmo tipo de dado evita duas soluções diferentes para o mesmo requisito dentro do protótipo (mesmo raciocínio do D1 da feature 008 do passageiro). |
| `sqflite_common_ffi` + teste de integração real | Rejeitada: nenhuma outra feature do motorista (nem do passageiro) paga esse custo para uma tabela SQLite; seria uma dependência de teste nova sem um problema real que a justifique (Princípio III). |
| Manter só em memória, sem persistir | Rejeitada: contraria FR-004 (persistência local explícita) e a redação literal do pedido do usuário ("fica salva no banco de dados"). |

### Riscos assumidos e mitigação

- Nenhum risco novo — mesmo padrão de uso já validado pela feature 003 do motorista e pela
  feature 011 do passageiro.

## D2 — Esquema: uma tabela plana, `ride_id` como chave primária (atende FR-004/FR-006)

**Decision**: tabela `ride_ratings`, com `ride_id` (o `ActiveRide.quoteId` da corrida avaliada)
como chave primária — garante por construção, via `ConflictAlgorithm.replace` sem duplicar linha,
que uma corrida não é avaliada duas vezes de forma inconsistente (FR-006), sem precisar de um
índice separado. Esquema idêntico ao da feature irmã do passageiro
(`passenger/specs/011-avaliar-corrida/research.md`, D2), por não haver motivo para divergir num
problema idêntico.

```sql
CREATE TABLE ride_ratings (
  ride_id   TEXT PRIMARY KEY,
  stars     INTEGER NOT NULL CHECK (stars BETWEEN 1 AND 5),
  rated_at  TEXT NOT NULL
);
```

`rated_at` como texto ISO-8601 (`DateTime.toIso8601String()`), mesmo formato já usado nos demais
carimbos de tempo do projeto.

### Alternativas avaliadas

| Opção | Observação |
|-------|------------|
| `ride_id` como chave primária (escolhida) | Uma avaliação por corrida é a própria regra de negócio (FR-006); a chave primária torna isso uma restrição de esquema, não só de código de aplicação. |
| `id` autoincremento + índice único em `ride_id` | Rejeitada por V (simplicidade): mesmo efeito prático, uma coluna e um índice a mais sem consumidor. |

### Riscos assumidos e mitigação

- Nenhum risco novo.

## D3 — Disparo da tela: estado em memória, sem sinalizador persistido de "já visto"

**Decision**: a tela de avaliação é aberta uma única vez, no mesmo `setState` que processa
`_processarConfirmacaoDeDestino` (recebimento de `kind: 20010`) — sem adicionar nenhum campo novo
a `ActiveRide`/`RideStateStore`. O `quoteId` da corrida é lido de `ativa.quoteId` **antes** de
`_activeRide` ser zerado nesse mesmo método.

**Contexto da decisão**: mesma decisão já tomada pela feature irmã do passageiro (D3 de
`passenger/specs/011-avaliar-corrida/research.md`), reaplicada aqui pela Clarification desta spec:
se o app fechar antes da avaliação (ou de pulá-la), a oportunidade se perde — a tela não reaparece
numa reabertura do app. Isso dispensa o padrão usado por sinalizadores persistidos como
`ArrivalRide.arrivalNotified`/`destinationArrivalNotified`: o próprio fato de
`_processarConfirmacaoDeDestino` já ser guardado contra reentrada
(`DriverRideRules.canConfirmDestinationArrival`, que exige o estado "Em corrida") garante no
máximo uma exibição por corrida dentro da mesma sessão do app.

### Alternativas avaliadas

| Opção | Observação |
|-------|------------|
| Estado em memória, sem persistência de "já visto" (escolhida) | Mais simples (Princípio V) e é exatamente o que a Clarification pede — qualquer persistência aqui seria estrutura sem requisito. |
| Sinalizador `ratingShown` persistido em `ActiveRide`, mesmo padrão de `arrivalNotified` | Rejeitada: resolveria um requisito que a Clarification explicitamente descartou (reexibir após reabrir o app), e a corrida já é zerada (`_activeRide = null`) no mesmo método — não haveria onde persistir o sinalizador sem reintroduzir a entidade que acabou de ser removida. |

### Riscos assumidos e mitigação

- Se o processo do app for encerrado entre o processamento da confirmação de destino (que já
  encerrou a corrida) e a interação do usuário com a tela de avaliação, a corrida fica sem nota —
  comportamento intencional (FR-009, resposta da Clarification), não um defeito a mitigar.
