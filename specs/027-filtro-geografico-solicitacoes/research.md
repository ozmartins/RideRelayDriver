# Pesquisa: 027-filtro-geografico-solicitacoes

Decisões de projeto não óbvias, com alternativas descartadas (Princípio V). Nenhuma dependência nova é instalada
(Princípio III); a decisão sobre biblioteca de geohash está em R1. Nenhum número abaixo é medição, salvo onde
escrito "medido"; os demais são cálculo, e dizem isso.

## R1 — Geohash em casa, sem dependência

**Decisão**: `lib/domain/geohash.dart`, Dart puro: `encode`, `neighbors` (a célula + 8 vizinhas) e dimensões de
célula. Cerca de 60 linhas.

**Alternativas**: pacote `dart_geohash` (ou similar) — descartado: a única operação não trivial é a vizinhança,
a conta da cobertura (R3) é nossa de qualquer forma, o domínio não pode importar terceiros (CLAUDE.md) e um
pacote exigiria um wrapper em `services/` só para devolver *strings*. É o mesmo raciocínio do NIP-44 feito em
casa. Risco: erro sutil de bits/vizinhança → mitigado por vetores compartilhados com o passageiro
(`test/fixtures/geohash_vectors.json`), com dois pontos de âncora independentes publicados na descrição do
geohash (Wikipédia: `42.605, -5.603 → ezs42`; `57.64911, 10.40744 → u4pruydqqvj`), conferidos no teste.

## R2 — A tag `g` em três precisões (desvio da redação do pedido, a confirmar com o autor)

**Problema**: o pedido diz "tag `g` com precisão fixa (sugestão: 5)" e, ao mesmo tempo, "raio maior que o coberto
pelas 9 células ⇒ precisão menor, ex.: 4". O filtro `#g` de um relay compara por **igualdade exata** de valor
(NIP-01): um filtro com `"6gkz"` (4 caracteres) não casa com uma tag `"6gkzw"` (5). As duas frases só convivem se
o evento carregar a tag nas precisões que o motorista pode pedir.

**Decisão**: o passageiro publica `["g", p5]`, `["g", p4]`, `["g", p3]` (prefixos do mesmo geohash). O motorista
usa uma única precisão por inscrição, a maior que cobre o raio (R3). Custo: duas tags a mais por solicitação
(~20 bytes cada), em claro, que não expõem nada além da `origin` já pública do `20001`.

**Alternativas**: (a) tag única de 5 com raio máximo ~4 km — rejeitada: o padrão de 10 km já não caberia;
(b) tag única de 5 e o motorista lista as células de 5 que cobrem o raio — rejeitada: ~441 células para 50 km, e
filtros enormes; (c) filtro por precisão grossa sem tag grossa, deixando o relay ignorar — rejeitada: o recorte
deixaria de acontecer no relay, e o `limit: 50` voltaria ao problema original; (d) `#g` por prefixo — não existe
no protocolo. **Ponto aberto**: se o autor preferir (a)/(b), muda a emenda 27 antes de qualquer código.

## R3 — Regra de escolha da precisão

Geohash alterna bits de longitude e latitude, então as células não são quadradas. Para `p` caracteres há `5p` bits;
longitude recebe `⌈5p/2⌉` e latitude `⌊5p/2⌋`:

| p | altura | largura (equador) | cobertura garantida em lat −29° |
|---|---|---|---|
| 5 | 4,89 km | 4,89 km | 4,28 km |
| 4 | 19,55 km | 39,09 km | 19,55 km |
| 3 | 156,37 km | 156,37 km | 136,89 km |

(Cálculo com 111,195 km/grau; a coluna da direita é `min(altura, largura·cos φ)`.)

**Cobertura garantida**: a referência está dentro da célula central; no pior caso ela encosta numa borda, e a
borda do bloco 3×3 fica a uma célula de distância. Logo, as 9 células cobrem o círculo de raio `R` se
`R ≤ min(altura, largura·cos φ')`, onde `φ'` é a latitude mais afastada do equador que o círculo alcança
(`|lat| + R/111,195 °`, limitado a 89°). **Regra**: maior `p ∈ {5, 4, 3}` que cobre `R`; se nenhum cobre, `p = 3`
(só ocorre acima de ~49° de latitude, fora da região de uso; registrado no contrato).

Exemplos (cálculo): Araranguá (≈ −28,9°), `R ≤ 4` → 5; `R` 5–19 → 4 (o padrão de 10 km cai aqui); `R` 20–100 → 3.

**Limites do raio** (1–100 km, padrão 10): o máximo é o que a precisão 3 cobre com folga até ~49° de latitude (a
cobertura em 49° é ≈ 100,5 km, cálculo); o mínimo evita raios abaixo do erro típico de GPS (5–15 m) e da
origem (a busca de endereço do passageiro pode errar centenas de metros, emenda 23). O padrão de 10 km é escolha
desta feature: uma corrida urbana típica sai do bairro, e o motorista já pode ajustar.

**Efeito colateral aceito**: com raio maior que ~19 km o relay entrega o bloco 3×3 de precisão 3 (~470 × 410 km),
muito maior que o círculo; o `limit: 50` do histórico pode ser gasto por pedidos entre o círculo e o bloco. O
corte exato fica no motorista (R6). Não afeta eventos ao vivo.

## R4 — Duas camadas de filtro, mais a exata

1. **Relay**: filtro `#g` (barato; só se o relay respeitar).
2. **Recepção, célula**: o relay pode ignorar `#g`; o motorista confere se alguma tag `g` bem formada é uma das
   células da inscrição. Descarta sem tag, mal formada, ou fora das células.
3. **Exata**: distância de Haversine (`geo_distance.dart`, já existente) da referência à `origin` do `content`.

A tag `g` nunca é autoridade: um passageiro que mente na tag só some das telas dos motoristas que ele mesmo errou.
Por isso **não** há conferência de coerência entre a `g` e a `origin` (custo sem ganho de segurança).

**Ordem**: a conferência geográfica vem **antes** da deduplicação. Se viesse depois, um evento descartado com a
referência A entraria no conjunto de vistos e seria tratado como repetido quando o relay o reentregasse depois de
o motorista ficar offline e online em B, perdendo uma solicitação legítima.

## R5 — Estado, ciclo de vida e o serviço em segundo plano

- **Referência** (`DriverCoverage`): posição do momento em que o motorista fica online, mais o raio vigente
  naquele momento (instantâneo: mudar o raio depois não altera a cobertura, FR-006). Só em memória; nunca em
  `ServiceState` (que é persistido por `toStorageJson`), `KeyValueStore` ou evento.
- **Quem a segura**: `MapScreen` cria a cobertura ao ficar online e a anula ao ficar offline (inclusive o offline
  forçado por perda de localização) e a entrega à conexão (`RelayConnection.applyCoverage`).
- **No serviço** (feature 025): o serviço **precisa** da referência exata para decidir notificar com a mesma regra
  da interface (FR-012). Ela chega por uma mensagem nova, `ServiceSetCoverage`, separada de `ServiceStateUpdate`
  de propósito: o estado é persistido, a cobertura não. O serviço só a guarda em memória e não a escreve em
  `ServiceStateStore`, log nem notificação. Ele continua sem acessar sensor de localização: **recebe** a posição
  que a interface já tem.
- **Isso exige emenda 2.18.0 da constituição**, porque a exceção do serviço diz que a decisão de notificar
  "usa apenas dados públicos do evento e o estado persistido pela interface" e que o serviço não acessa a
  localização (ver plano, Verificação da constituição).
- **Retomada** (FR-012 da 025): se o serviço sobrevive e a interface recomeça, ele mantém a cobertura anterior
  até a interface mandar outra (a referência original continua válida: o motorista não ficou offline). A
  interface retomada fica "online sem referência" até a primeira posição válida; nesse intervalo, o filtro
  recusa `20001` (`semReferencia`) e a interface **estaciona** a solicitação para reavaliá-la contra a nova
  cobertura. Se o processo inteiro morreu, o serviço reinicia online (estado persistido) **sem cobertura**:
  reconecta, mas não pede nem aceita `20001` até a interface voltar e mandar uma. **Limite conhecido**: um
  motorista online com o app fechado e o processo morto pelo sistema deixa de ser avisado até abrir o app; a
  alternativa — persistir a referência — foi vetada pela especificação (FR-005).

**Alternativa descartada**: pôr a cobertura dentro de `ServiceState`. Reaproveitaria o canal e o filtro
`RideRequestFilter.evaluate(event, state)`, mas persistiria a posição ao reiniciar (ou exigiria excluir o campo
em `toStorageJson`, regra fácil de esquecer) e dispararia a igualdade de estado a cada posição.

## R6 — Ordem das regras em `RideRequestFilter`

`offline → emCorrida → malformada → (nova) geográfica → pagamentoNaoAceito`. A geográfica vai depois de
`malformada` porque precisa da `origin` do `content`, e antes do pagamento porque descarta mais. Dois motivos de
recusa novos: `semReferencia` (online sem cobertura; só existe na retomada) e `foraDaCobertura` (sem `g`, fora das
células ou além do raio). O `EventFeed` aplica a mesma função (via `DriverCoverage.acceptsRideRequest`) **antes**
de deduplicar, para que o evento fora do raio não entre na lista de eventos (SC-001).

## R7 — Mudar a inscrição em tempo de execução

O gateway guarda a lista de células (como já guarda `_kinds`) e, ao mudar, fecha a inscrição de cada relay
conectado e abre outra; ao (re)conectar um relay, abre-a já com as células vigentes. **Risco a medir** (quickstart,
cenário 3): (a) se cancelar o `StreamSubscription` do `dart_nostr` envia `CLOSE` ao relay — se não enviar, o
gateway chama `closeEventsSubscription(subscriptionId)` explicitamente, com o `subscriptionId` fixado na
`NostrRequest`; (b) quantos relays padrão **respeitam** o filtro `#g` — `tool/probe_geohash_filter.dart` publica
duas solicitações de teste (uma dentro, uma fora da célula), inscreve-se com `#g` e registra, por relay, se a de fora
chegou. **Medição (2026-10-22T00:53Z, `dart run tool/probe_geohash_filter.dart`, uma execução, computador do autor, sem os apps
abertos).** Método: por relay, duas conexões WebSocket e chaves descartáveis; (A) `REQ` com `#t` e `#g` das 9
células de Araranguá (precisão 4, raio de 10 km), publicação de um `20001` de teste com origem a ~3 km de
Araranguá e de outro em São Paulo, ambos com as três tags `g`; (B) `CLOSE` da inscrição e nova publicação em
Araranguá; (C) novo `REQ` com as células de São Paulo e publicação de um `20001` de cada cidade. Espera de 5 s
por fase (3 s depois do `CLOSE`).

| Relay | Publicação aceita (`OK`) | A: dentro / fora chegaram | B: chegou depois do `CLOSE` | C: Araranguá / São Paulo chegaram | EOSE do `REQ` com `#g` |
|---|---|---|---|---|---|
| `wss://nos.lol` | sim, as 6 | sim / não | não | não / sim | 240 ms |
| `wss://relay.primal.net` | sim, as 6 | sim / não | não | não / sim | 226 ms |
| `wss://offchain.pub` | sim, as 6 | sim / não | não | não / sim | 192 ms |

Os três relays padrão **respeitaram o `#g`** (só entregaram o evento da célula pedida), **honraram o `CLOSE`**
(nada chegou à inscrição fechada) e a troca de células com um novo `REQ` funcionou. Limites da medição: uma única
execução em um instante e uma rede só; só os três relays da lista padrão; a latência do EOSE é de uma conexão
isolada, não do app; o que cada relay faz sob carga, com filtros maiores ou em outro dia não foi medido. A sonda
foi validada antes contra um relay local de teste nos três modos (respeita, ignora `#g`, ignora `CLOSE`), o que
valida a lógica dela, não o comportamento de relays reais. O app continua conferindo na recepção (regra 8), então
um relay que passe a ignorar o `#g` degrada o ruído e o `limit: 50`, não a correção.

## R8 — Privacidade (exigência do pedido e do contrato)

- O filtro `#g` revela ao relay, e a quem o opera, a **região aproximada** do motorista: as 9 células (~14 × 14 km
  na precisão 5; ~58 × 117 km na 4; ~470 × 410 km na 3) enquanto ele estiver online. Escolher raio maior revela
  uma região maior. O relay também aprende o instante em que o motorista ficou online/offline pela abertura e
  pelo fechamento da inscrição.
- Não sai do aparelho: o **raio** e a **posição exata** da referência. Nenhum evento os carrega; a inscrição só
  leva as células.
- Já era público: a `origin` do `20001` (em claro, exceção da emenda 17). A tag `g` não acrescenta nada a isso.
- Custo aceito do protótipo, sem backend e sem relay de confiança. Mitigação futura registrada, não implementada:
  inscrever só nas precisões mais grossas, ao custo de mais ruído.

## R9 — Onde o raio mora no cadastro

**Decisão**: etapa 1 do cadastro (`DriverPersonalData`, junto da "cidade de atuação") — é o dado de território. Coluna
nova `raio_atendimento_km INTEGER NOT NULL DEFAULT 10` em `driver_personal`; o `onUpgrade` do banco (versão 5 → 6)
faz `ALTER TABLE … ADD COLUMN` e, graças ao `DEFAULT`, o motorista já cadastrado ganha 10 km sem refazer o wizard
(FR-003, SC-005). `DriverProfile` ganha `raioAtendimentoKm` com valor padrão no construtor, para não tocar nos
construtores dos testes existentes.

**Alternativas**: etapa 3 (financeiro, junto do preço por km) — descartada: não é financeiro; `KeyValueStore` —
descartada: o cadastro já é a casa dos dados do motorista e tem tela de edição.

## R10 — Mudança do raio com o motorista online

Vale na próxima vez em que ficar online (decidido na spec). A cobertura carrega o raio copiado quando foi criada;
a tela de cadastro, ao salvar com o motorista online, mostra um aviso curto. Reinscrever na hora criaria um
segundo critério de "sessão" e mudaria a referência sem o motorista ter ido offline.

## R11 — O que fica de fora

Nenhum círculo no mapa; nenhuma mudança no passageiro além de publicar a tag e replicar o contrato; nenhuma
permissão Android nova; o passageiro não filtra por `g`; nenhum recálculo da referência com o motorista em
movimento.
