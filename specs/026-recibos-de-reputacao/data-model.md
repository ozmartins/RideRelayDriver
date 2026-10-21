# Modelo de dados: 026-recibos-de-reputacao

## Domínio (`lib/domain/`, sem importar terceiros)

### `Receipt` (imutável)

| Campo | Tipo | Regra |
|---|---|---|
| `v` | int | `1` |
| `guidCorrida` | String (hex 64) | `id` do `20002` aceito (`quoteId`) |
| `pubkeyAvaliador` | String (hex 64) | autor do recibo |
| `pubkeyAvaliado` | String (hex 64) | destinatário |
| `nota` | int? | 1–5; ausente se o avaliador não avaliou |
| `criadoEm` | int | epoch em segundos; informativo |
| `seq` | int | ≥ 0 |
| `hashAnterior` | String? | `idRecibo` do `seq − 1`; ausente se `seq = 0` |
| `idRecibo` | String (hex 64) | SHA-256 de `canonical` |
| `assinatura` | String (hex 128) | Schnorr do avaliador sobre `idRecibo` |

- `canonical` = `tcc-recibo-v1|<guid>|<avaliador>|<avaliado>|<nota|->|<criadoEm>|<seq>|<hashAnterior|->`.
- `static computeId(...)` = SHA-256 hex minúsculo de `canonical` (UTF-8).
- `toJson` omite `nota` e `hash_anterior` quando nulos; chaves em snake_case do contrato. `fromJson` lança
  `FormatException` para campo faltando, tipo errado ou hex de tamanho errado. **Não** julga valores (`v`, faixa da
  `nota`): recibo com `v ≠ 1` ou nota fora de 1–5 é descartado e contado pelo verificador (1.6 d), sem derrubar a
  reputação inteira. Também não verifica assinatura nem `idRecibo`.

### `Reputation`

`corridas` (int ≥ 0), `avaliacoes` (int ≥ 0, ≤ `corridas`), `media` (double?; omitida se `avaliacoes = 0`),
`seqProximo` (int ≥ 0), `head` (String?; omitido se `seqProximo = 0`), `recibos` (`List<Receipt>`, do mais novo
ao mais antigo, no máximo `kReputacaoJanela`). Constante `kReputacaoJanela = 5` neste arquivo. Construtor
`Reputation.empty()`. `toJson/fromJson` com chaves do contrato (`seq_proximo`, `head`, `recibos`); `fromJson` rejeita mais de
`kReputacaoJanela` recibos (ver R9 em research.md).

### `ReputationView` (resultado de 1.6)

`verifiedCount`, `verifiedAverage` (double?; nulo sem notas válidas), `declared` (`corridas`, `avaliacoes`,
`media?` como informados), `invalidDiscarded`, `gaps` (nº de recibos não apresentados), `inconsistent` (bool),
`hasHistory` (derivado: reputação presente com `declared.corridas > 0` ou recibos). Nunca contém uma "nota
única" mesclando verificado e declarado.

### Alterações em tipos existentes

- `NostrEvent`: `kindReceipt = 20014`, `kindReceiptAck = 20015`.
- `RideRequestReceived`: `Reputation? reputation`.
- `RideQuote`: `Reputation? reputation`.

## Persistência (`receipts.db`, versão 1, via `SqfliteReceiptStore`)

```sql
CREATE TABLE recibos_recebidos (
  guid_corrida TEXT PRIMARY KEY,
  id_recibo    TEXT UNIQUE NOT NULL,
  seq          INTEGER NOT NULL,
  avaliador    TEXT NOT NULL,
  nota         INTEGER CHECK (nota BETWEEN 1 AND 5),
  json         TEXT NOT NULL
);
CREATE TABLE recibos_emitidos (
  guid_corrida TEXT PRIMARY KEY,
  id_recibo    TEXT NOT NULL,
  avaliado     TEXT NOT NULL,
  json         TEXT NOT NULL,
  pendente     INTEGER NOT NULL DEFAULT 1
);
CREATE TABLE reputacao_declarada (
  quote_id TEXT PRIMARY KEY,
  avaliado TEXT NOT NULL,
  json     TEXT NOT NULL
);
```

- `recibos_recebidos` é imutável: `INSERT` sem `replace`; conflito de chave é "já existe" (o serviço decide
  idêntico × diferente lendo `receivedFor`). Leitura revalida assinatura **e** `id_recibo`; linha que falha é
  ignorada e não conta.
- `recibos_emitidos`: gravado com `pendente = 1` antes de publicar; `markAcked(idRecibo)` põe `0`.
- `reputacao_declarada`: reputação do **passageiro** como veio no `20001` da corrida; linha com reputação vazia
  quando ele não declarou (R4).
- Sem *row signing* (feature 014): os recibos se autenticam pela assinatura do avaliador. Os registros de
  `recibos_emitidos` e `reputacao_declarada` não são assinados: adulterá-los exige acesso ao armazenamento do
  aparelho e só pode causar emissão de recibo com `seq` errado — que o passageiro verifica contra a própria cadeia.

## Interface `ReceiptStore`

`saveReceived(Receipt)` → bool (false se já existe a corrida) · `receivedFor(guid)` → `Receipt?` ·
`myReputation()` → `Reputation` · `saveIssued(Receipt)` (pendente) · `pendingIssued()` → `List<Receipt>` ·
`markAcked(idRecibo)` · `saveDeclared(quoteId, avaliado, Reputation)` · `declaredFor(quoteId)` → `Reputation?`.

## Transições do recibo emitido

`(inexistente) —issueFor→ pendente —20015 válido→ confirmado`. Reenvio não altera o estado; `20015` com autor
diferente do avaliado ou `id_recibo` diferente é ignorado e o recibo segue pendente.

## Eventos

| Kind | Autor → destinatário | Tags | `content` cifrado (NIP-44) |
|---|---|---|---|
| `20014` | motorista → passageiro (emissão) / passageiro → motorista (recepção) | `t`, `e = guid`, `p = avaliado` | recibo completo (JSON) |
| `20015` | avaliado → avaliador | `t`, `e = guid`, `p = avaliador` | `{"id_recibo":"<hex>"}` |

`20001`/`20002` ganham `reputacao` opcional (ver `contracts/reputacao-recibos.md`).
