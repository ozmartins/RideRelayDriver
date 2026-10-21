# Contrato: tag `g` e inscrição por célula (emenda 27)

**Feature**: `027-filtro-geografico-solicitacoes` · **Destino**: `specs/002-nostr-relay-connection/contracts/nostr-events.md`
das duas apps, na mesma alteração em que o código muda (Princípio IV).

Este arquivo é a especificação prévia exigida pelo Princípio IV. As quatro alterações abaixo MUST ser aplicadas
**literalmente** nos dois contratos; depois disso, os dois arquivos MUST ficar idênticos (conferir com `diff`).

## 1. Linha nova na tabela de emendas

| 27 | 2026-10-21 | Define a tag `["g", "<geohash>"]` do `kind: 20001` (seção *Tag `g` do `20001`*), publicada pelo passageiro em **três precisões** (5, 4 e 3 caracteres) sobre a origem da corrida, sem alterar o `content`; a inscrição do motorista no `20001` passa a ser um filtro **à parte**, com `#g` = célula da posição de referência + 8 vizinhas (seção *Forma da inscrição* atualizada); nova regra de recepção 8 (só motorista) | Pedido do autor: o motorista recebia solicitações de qualquer lugar (ruído, banda, e o `limit: 50` preenchido por pedidos distantes). Definido pela feature 027 do motorista (raio de atendimento) e replicado no passageiro, na mesma alteração (Princípio IV). Kind e campo novos só como tag: nenhum formato de `content` muda. O raio e a posição de referência do motorista nunca saem do aparelho; o `#g` revela ao relay só a região aproximada (9 células) |

## 2. Tabela de kinds — célula do `20001`

Acrescentar ao fim da coluna *Formato do `content`* do `20001`: "; tags `t` e `g` (emenda 27)".
Na seção *Conteúdo do kind 20001*, a linha **Tags** passa de "exatamente a tag de marcador" para "a tag de marcador e, desde a emenda 27, três tags `g`".

## 3. Nova seção *Tag `g` do `20001`* (logo após *Conteúdo do kind 20001*)

O passageiro MUST acrescentar ao `20001`, além do marcador `t`, **três** tags `g`, todas derivadas do ponto
`origin` do `content` (latitude/longitude em graus decimais, a mesma do evento):

```json
["g", "<geohash de 5 caracteres>"],
["g", "<geohash de 4 caracteres>"],
["g", "<geohash de 3 caracteres>"]
```

- **Geohash** padrão (Niemeyer): alfabeto `0123456789bcdefghjkmnpqrstuvwxyz`, minúsculas, bits alternando
  longitude e latitude a partir da longitude. Os valores de 4 e 3 caracteres são prefixos do de 5.
- **Por que três precisões**: o relay compara o valor da tag por igualdade exata, não por prefixo. Uma única
  tag de 5 caracteres (célula de ~4,9 km) obrigaria o motorista com raio grande a listar centenas de células;
  com três precisões ele escolhe a que cobre o raio com 9 células (ver *Forma da inscrição*) e o relay ainda
  casa. Valores de comprimentos diferentes nunca colidem.
- **Células** (altura × largura no equador; a largura encolhe com `cos(latitude)`):

  | Precisão | Altura | Largura (equador) |
  |---|---|---|
  | 5 | ~4,9 km | ~4,9 km |
  | 4 | ~19,5 km | ~39,1 km |
  | 3 | ~156,4 km | ~156,4 km |

  (Calculadas de 180°/2^bits e 360°/2^bits com 111,195 km/grau; cálculo, não medição.)
- A tag `g` é só um **pré-filtro barato**: a origem exata continua sendo a do `content`, e o motorista confere a
  distância sobre ela (regra 8). Uma `g` incoerente com o `content` só prejudica quem a publicou.
- O `content` do `20001` **não muda**. A tag fica em claro, como o resto do `20001` (exceção da emenda 17, que já
  admite a origem em claro): a tag não expõe nada além do que o `content` já expõe.
- Vetores: `test/fixtures/geohash_vectors.json`, gerado por `tool/gen_geohash_vectors.dart` e **idêntico byte a
  byte** nas duas apps; cobre `encode` (as três precisões de cada ponto) e as 9 células de cada ponto.

## 4. *Forma da inscrição* — substituir o exemplo e acrescentar o parágrafo do motorista

O exemplo único

```text
["REQ", "<id-da-inscrição>", {"kinds": [20001], "#t": ["tcc-ufsc-caronas"], "limit": 50}]
```

passa a valer **só para o passageiro**, com os kinds que ele consome (sem `20001`). O **motorista** passa a usar
dois filtros no mesmo `REQ`:

```text
["REQ", "<id-da-inscrição>",
  {"kinds": [<kinds do motorista exceto 20001>], "#t": ["tcc-ufsc-caronas"], "limit": 50},
  {"kinds": [20001], "#t": ["tcc-ufsc-caronas"], "#g": ["<célula>", ... até 9 ...], "limit": 50}]
```

- O **segundo filtro só existe com o motorista online**. Offline, o motorista inscreve só o primeiro: não pede
  solicitações. Ao ficar online (ou ao reconectar a um relay estando online), inscreve os dois; ao ficar
  offline, volta a um filtro só. Muda-se o `REQ` fechando a inscrição anterior (`CLOSE`) e abrindo outra.
- **Células**: a célula da posição de referência do motorista (a posição em que ficou online) e as 8 vizinhas
  (sem repetição; sem vizinha além do polo; a longitude dá a volta no antimeridiano), **todas de uma mesma
  precisão**, escolhida entre 5, 4 e 3 como a **maior** em que as 9 células cobrem o círculo de raio R em
  torno da referência. A cobertura garantida de uma precisão é `min(altura, largura × cos(φ'))`, com
  `φ' = min(|lat| + R/111,195 °, 89°)` — a distância da referência até a borda do bloco 3×3 é, no pior caso,
  uma célula. Se nem a precisão 3 cobre (latitudes acima de ~49°), usa-se a 3 mesmo assim: limite do protótipo,
  fora da região de uso.
- O raio é entre **1 e 100 km** e fica só no aparelho do motorista; **a posição de referência e o raio nunca
  são publicados em evento**. O filtro `#g` revela ao relay, porém, a região aproximada do motorista (as 9
  células); isso MUST ser aceito como custo desta emenda e registrado no `research.md` da feature.
- O `limit: 50` vale por filtro e só limita o histórico entregue ao abrir a inscrição.
- O relay pode ignorar `#g` (como pode ignorar `#t`): por isso a regra 8 vale sempre, e o filtro por célula não
  é mecanismo de segurança nem substitui a conferência de distância.

## 5. Regra de recepção 8 (só motorista; acrescentar após a regra 7)

> 8. **Recorte geográfico do `20001` (emenda 27).** Depois de verificar a assinatura e o marcador, e **antes** de
>    deduplicar, o motorista online com posição de referência MUST descartar, sem erro e sem avisar a rede, o
>    `20001` que (a) não tenha nenhuma tag `g` bem formada (valor de comprimento 3–5 no alfabeto de geohash)
>    igual a uma das células da inscrição vigente; ou (b) tenha a `origin` do `content` a mais de R km da
>    posição de referência (distância de Haversine). O motorista offline, ou online sem posição de referência,
>    MUST NOT **aceitar** `20001` — isto é, não o exibir, notificar nem responder; essa recusa é feita pelo filtro
>    de solicitações (que conhece o estado online), e o conferidor de recepção, sem referência, nada descarta por
>    geografia. A conferência vem **antes** da deduplicação para que um evento descartado numa
>    sessão online (outra referência) não seja tratado como repetido na seguinte. Tags `g` fora de padrão são
>    ignoradas na busca da célula; sem nenhuma tag válida e coincidente, o evento é descartado.

## Consumo pelo passageiro

Nenhum: o passageiro **publica** a tag `g` e não valida nem filtra por ela. Solicitações sem `g` (anteriores à
emenda) continuam válidas para o protocolo, mas nenhum motorista com a emenda as aceita.
