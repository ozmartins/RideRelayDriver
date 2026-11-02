# Contrato: reputação por recibos (emenda 25)

**Feature**: `026-recibos-de-reputacao` · **Destino**: `specs/002-nostr-relay-connection/contracts/nostr-events.md`
das duas apps, na mesma alteração em que o código muda (Princípio IV).

Este arquivo é a especificação prévia exigida pelo Princípio IV. O texto de "Reputação por recibos" abaixo é a
seção 1 de `especificacao-motorista.md`, copiada literalmente (MUST ser idêntica à do passageiro); depois dele vêm
as alterações pontuais nas seções existentes do contrato.

## Reputação por recibos

> Esta seção MUST ser copiada **literalmente** para `specs/002-nostr-relay-connection/contracts/nostr-events.md` das duas apps, na mesma alteração em que o código muda (Princípio IV). É o único acoplamento entre as apps.

### 1.1 Objetivo

Reputação **sem backend e sem guardar avaliações em relays**: cada corrida concluída gera um **recibo assinado** pelo avaliador, entregue ao avaliado, que o guarda localmente e o apresenta (últimos N) quando for avaliado por outro usuário. Os recibos de cada avaliado formam uma **cadeia numerada e encadeada por hash**.

### 1.2 Recibo

Objeto JSON, **sem** o campo `assinatura` para fins de hash:

| Campo | Tipo | Regra |
|---|---|---|
| `v` | int | `1` |
| `guid_corrida` | string hex(64) | `id` do evento `kind: 20002` aceito (`quoteId`). Já é comum às duas apps |
| `pubkey_avaliador` | string hex(64) | autor do recibo |
| `pubkey_avaliado` | string hex(64) | quem recebe o recibo |
| `nota` | int 1–5, **opcional** | chave omitida se o avaliador não avaliou (conta como corrida, não como avaliação) |
| `criado_em` | int | epoch em segundos (só informativo; NUNCA usado para ordenar com segurança, regra 5) |
| `seq` | int ≥ 0 | posição na cadeia **do avaliado** |
| `hash_anterior` | string hex(64), **opcional** | `id_recibo` do recibo `seq−1`; omitido quando `seq = 0` |
| `id_recibo` | string hex(64) | SHA-256 de `canonico(recibo)` (abaixo) |
| `assinatura` | string hex(128) | Schnorr (BIP-340) do avaliador sobre `id_recibo` |

**Forma canônica** (UTF-8, campos separados por `|`, ausente = `-`):

```text
tcc-recibo-v1|<guid_corrida>|<pubkey_avaliador>|<pubkey_avaliado>|<nota|->|<criado_em>|<seq>|<hash_anterior|->
```

`id_recibo = SHA-256(canonico)` em hex minúsculo. A assinatura usa a mesma API que `RideRatingSignature` já usa (`nostr.Nostr.instance.services.keys.sign/verify`). A chave privada **nunca** entra em hash, log ou evento (constituição).

### 1.3 Cadeia

- Há uma cadeia **por avaliado**. `seq` começa em `0` e cresce de 1 em 1.
- O avaliador copia `seq` e `hash_anterior` do **estado declarado pelo avaliado** (1.5), depois de verificá-lo (1.6).
- Recibos chegando fora de ordem são aceitos; a ordem é por `seq`. Ramos (dois recibos com o mesmo `seq`, de corridas diferentes) são tolerados e exibidos como tal; o `seq` repetido em recibo recebido **para a mesma corrida** é rejeitado.

### 1.4 Novos kinds (efêmeros, cifrados NIP-44 ao destinatário, tags `t`, `e`, `p` como nos demais)

| Kind | Nome | Autor → destinatário | `e` | `content` (antes de cifrar) |
|---|---|---|---|---|
| `20014` | Recibo de avaliação | avaliador → avaliado | `guid_corrida` | o recibo completo (JSON, com `assinatura`) |
| `20015` | Confirmação de recibo | avaliado → avaliador | `guid_corrida` | `{"id_recibo":"<hex>"}` |

Entram na lista de cifragem da emenda 17 ("kinds 20002 a 20015") e na regra de recepção 7. Ambos os papéis (motorista e passageiro) consomem os dois kinds: **acrescentar `20014` e `20015` ao conjunto de kinds consumidos** de cada app (e à documentação "Forma da inscrição").

### 1.5 Campo `reputacao` (em `20001` e `20002`)

Acrescentado ao JSON de `content` do `20001` (passageiro, **em claro**) e do `20002` (motorista, cifrado). **Opcional**: ausente = usuário sem histórico.

```json
"reputacao": {
  "corridas": 12,
  "avaliacoes": 9,
  "media": 4.78,
  "seq_proximo": 12,
  "head": "<id_recibo do seq 11>",
  "recibos": [ { …recibo completo… }, … ]
}
```

- `corridas` = nº de recibos guardados; `avaliacoes` = nº com `nota`; `media` = média das notas (omitir se `avaliacoes = 0`). **Declarados**; só os `recibos` são verificáveis.
- `seq_proximo` = próximo `seq` a ser usado; `head` = `id_recibo` do recibo `seq_proximo−1` (omitido se `seq_proximo = 0`).
- `recibos` = os **N mais recentes** por `seq` (N = 5, constante `kReputacaoJanela`), do mais novo para o mais antigo. Uma lista com **mais de N** recibos torna a `reputacao` **malformada** (emenda 26): é tratada como ausente, sem verificar nenhum recibo dela.
- Limite de tamanho do `content`: continua 65 535 bytes (NIP-44).

### 1.6 Verificação ao receber uma `reputacao` (função pura, testável)

Para cada recibo: (a) `id_recibo` recalculado confere; (b) assinatura válida para `pubkey_avaliador`; (c) `pubkey_avaliado` == autor do evento (`pubkey` do `20001`/`20002`); (d) `v == 1`, `nota` ∈ 1..5 se presente; (e) `seq` estritamente decrescente na lista; (f) `guid_corrida` sem repetição; (g) `pubkey_avaliador != pubkey_avaliado`. Recibo inválido é **descartado e contado**. Depois: (h) `head` MUST ser o `id_recibo` do recibo de `seq = seq_proximo−1` presente na lista, senão a reputação é marcada **inconsistente**; (i) para recibos consecutivos na lista, `hash_anterior` do mais novo MUST ser o `id_recibo` do `seq−1` se este estiver presente; lacunas de `seq` são exibidas ("N recibos não apresentados").

Resultado exibido: **"verificado nos últimos N"** (média e contagem calculadas só sobre recibos válidos) separado do **"declarado"** (`corridas`, `avaliacoes`, `media`). Nunca misturar os dois numa só nota.

### 1.7 Emissão do recibo (avaliador)

1. Ao encerrar a corrida (modal de avaliação fechada, com ou sem nota), obter a `reputacao` que o **avaliado declarou nesta corrida** (guardada no momento do orçamento/solicitação, 2.x).
2. Verificar (1.6). Se **inconsistente**, NÃO emitir recibo, avisar o usuário em uma linha; a nota local (`ride_ratings`) continua gravada.
3. `seq = seq_proximo`, `hash_anterior = head`; montar, calcular `id_recibo`, assinar.
4. Gravar em `recibos_emitidos` com `pendente = 1` **antes** de publicar (sobrevive a reinício).
5. Publicar `kind: 20014`. Reenviar enquanto `pendente = 1`: a cada reconexão de relay, ao abrir o app e a cada 60 s enquanto a interface do app estiver ativa (temporizador próprio do serviço de recibos; o serviço em segundo plano não tem a chave privada e não reenvia). Para quando chegar `20015` com o `id_recibo` correspondente.
6. Corrida cancelada ou não concluída: **nenhum recibo**.

### 1.8 Recepção do recibo (avaliado)

Depois das regras 1, 2, 6 e 7 de recepção: validar (1.6 a–d, g) com `pubkey_avaliado == minha chave` e `pubkey_avaliador == autor do evento`; `guid_corrida` == tag `e`; **o `guid_corrida` ser de uma corrida conhecida do avaliado com o avaliador** (abaixo, emenda 26); não existir recibo salvo para o mesmo `guid_corrida` (se existir e for idêntico, apenas reenviar `20015`; se diferente, ignorar). Gravar em `recibos_recebidos` (imutável) e publicar `20015`. Recalcular `corridas`, `avaliacoes`, `media`, `seq_proximo = max(seq)+1`, `head` = `id_recibo` do maior `seq`.

**Corrida conhecida (emenda 26).** O `guid_corrida` é o `id` de um `20002`, publicado por um motorista e endereçado a um passageiro. Quem recebe o recibo só o grava se **já conhecia, por conta própria, essa negociação com o avaliador**: o motorista, por ter enviado esse orçamento àquele passageiro (o avaliador); o passageiro, por tê-lo recebido daquele motorista (o avaliador). Recibo cujo `guid_corrida` o receptor não conhece, ou que o liga a outra contraparte, é descartado sem erro e sem `20015`. Sem backend, o receptor não tem como saber se a corrida foi aceita ou concluída, então a regra só barra quem **nunca negociou** com ele. O receptor MUST guardar, junto da negociação, a chave da contraparte, e a consulta MUST usar só esse registro local, nunca dados do próprio recibo.

### 1.9 Limites conhecidos (documentar no contrato, não esconder)

- O avaliado controla o que apresenta: pode omitir recibos ruins **recentes** se criar uma cadeia sem eles; a cadeia + `head` conferido pelo avaliador só **reduz** isso, não elimina.
- Quem recria a identidade (nova chave) zera o histórico (Sybil). Perder o app/chave perde a reputação.
- `corridas/avaliacoes/media` declarados não são verificáveis além da janela de N.
- Quem **negociou** com o avaliado (recebeu ou enviou o orçamento) pode lhe emitir um recibo válido para uma corrida que não aconteceu: o avaliado não tem como saber se houve aceitação, e a emenda 26 só barra quem nunca negociou com ele. Antes da emenda 26, qualquer pessoa que conhecesse a chave pública do avaliado podia lhe enviar recibos com corridas inventadas (medido em emulador: um recibo de nota 1 de um estranho foi aceito e baixou a média declarada).
- O `20001` é público: os recibos nele expõem as chaves públicas das contrapartes. Aceito no protótipo; alternativa futura: enviar só o resumo no `20001` e os recibos após o orçamento.

---

## Alterações nas seções existentes de `nostr-events.md`

1. **Histórico de emendas**: nova linha **25** — data da alteração; "Define `kind: 20014` (recibo de avaliação) e
   `kind: 20015` (confirmação de recibo) e o campo opcional `reputacao` em `20001` e `20002`; ambos os papéis passam a
   se inscrever em `20014` e `20015`"; origem: pedido do autor — reputação sem backend e sem guardar avaliações em
   relays. Definido pela feature 026 do motorista e replicado no passageiro na mesma alteração.
2. **Tabela de kinds**: linhas `20014` (avaliador → avaliado) e `20015` (avaliado → avaliador), ambas "cifrado ao
   destinatário (emenda 17)".
3. **Seções de conteúdo**: `20001` e `20002` ganham o campo opcional `reputacao`; novas seções "Conteúdo do kind
   20014" e "Conteúdo do kind 20015".
4. **Linha `content` da tabela de campos**: "Kinds `20002`–`20015`".
5. **Cifragem do `content`**: "kinds `20002` a `20015`"; `20014` (dado próprio: o recibo) e `20015` (dado próprio:
   `{"id_recibo": …}`) **não** usam o marcador `{}`.
6. **Regra de recepção 7**: "kinds `20002`–`20015`".
7. **Forma da inscrição**: o motorista passa a incluir `20014` e `20015` (e o passageiro, idem).
8. **Limites conhecidos (1.9)**: copiados como estão — não se escondem.

9. **Emenda 26** (mesma alteração das seções acima, em data posterior): linha 26 no histórico; 1.5 (mais de N recibos = reputação malformada), 1.8 (corrida conhecida do receptor com o avaliador) e 1.9 (limite correspondente), como aparecem na seção *Reputação por recibos* acima.

## Vetor de teste compartilhado

`test/fixtures/receipt_vectors.json` (motorista) e o arquivo de mesmo conteúdo no passageiro — **byte a byte iguais**.
Cada vetor: recibo completo (com `id_recibo` e `assinatura` reais, gerados por script reprodutível a partir de
chaves de teste fixas, nunca chaves de usuário), a forma canônica esperada e o veredito esperado (`valid` ou o motivo
da rejeição). Cobre no mínimo: recibo `seq = 0` sem nota; recibo com nota e `hash_anterior`; `id_recibo` adulterado;
assinatura de outra chave; `avaliador == avaliado`; `v = 2`; `nota = 6`.
