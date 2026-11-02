# Especificação: Filtro geográfico de solicitações de corrida (motorista)

**Feature**: `027-filtro-geografico-solicitacoes` · **App**: `driver/` · **Data**: 2026-10-21 · **Status**: Draft
**Contrato de eventos**: **muda** — emenda 27 (tag `g` no `20001` e nova forma da inscrição do `20001`).
Contrapartida obrigatória no app do passageiro, na mesma alteração (Princípio IV).
**Ramo**: nenhum — o projeto trabalha direto na `master` (CLAUDE.md).
**Entrada**: "Filtro geográfico de solicitações de corrida: raio de atendimento do motorista + geohash".

## Problema

Hoje o motorista se inscreve no `kind: 20001` filtrando só por kind e pelo marcador `t`. Recebe solicitações de
qualquer lugar (outro estado, outra cidade), o que gera ruído, gasto de banda e o risco de o `limit: 50` ser
preenchido por pedidos distantes, deixando os locais de fora.

O motorista passa a informar um **raio de atendimento**. Ao ficar online, a posição do momento vira a
**referência fixa** do raio, e só chegam à tela e à notificação as solicitações cuja origem está dentro dele. O
recorte é feito em três camadas: o relay (filtro por célula de geohash), a validação na recepção (a célula da
tag) e o filtro exato final (distância até a origem lida do `content`).

## Cenários de usuário

### US1 — Receber só solicitações dentro do meu raio (P1)
Com o motorista online em Araranguá e raio de X km, uma solicitação cuja origem está a menos de X km da posição em
que ele ficou online aparece (modal e notificação, como hoje); uma de São Paulo não aparece, não notifica e não
entra na lista de eventos recebidos.

**Teste independente**: com posição de referência fixa e raio conhecido, entregar ao app solicitações de origem
próxima, no limite, logo além do raio, na borda de uma célula, em outra cidade, sem tag `g` e com tag `g`
incoerente, e observar quais chegam à tela.

1. **Dado** o motorista online com referência em Araranguá e raio X, **quando** chega uma solicitação com origem a
   menos de X km, **então** ela é tratada como hoje (modal, notificação).
2. **Dado** o mesmo estado, **quando** chega uma solicitação com origem em São Paulo, **então** nada é exibido,
   notificado nem registrado na lista de eventos.
3. **Dado** uma origem dentro do raio mas perto da borda da célula da referência, **então** ela chega (coberta
   pelas células vizinhas).
4. **Dado** uma origem na célula certa mas além do raio, **então** é descartada pelo filtro exato.
5. **Dado** uma solicitação sem tag `g` (por exemplo, publicada antes da emenda 27), **então** é descartada, mesmo
   que o relay a entregue e a origem esteja dentro do raio.
6. **Dado** uma solicitação cuja tag `g` está fora das células da inscrição, **então** é descartada, mesmo que a
   origem lida do `content` esteja dentro do raio.
7. **Dado** que o relay ignora o filtro por célula e entrega tudo, **então** o resultado para o motorista é o
   mesmo dos cenários acima.

### US2 — Informar e alterar o raio de atendimento (P1)
No cadastro inicial o motorista informa o raio de atendimento em km; depois, o altera nas telas de cadastro/perfil
já existentes. Valores fora dos limites são recusados com mensagem clara.

**Teste independente**: preencher o cadastro com raio válido, inválido (vazio, zero, negativo, não numérico, abaixo
do mínimo, acima do máximo), salvar, reabrir e editar.

1. **Dado** o cadastro inicial, **quando** o motorista informa um raio válido, **então** ele é salvo junto ao
   restante do cadastro e reaparece ao reabrir.
2. **Dado** um raio inválido ou fora dos limites, **então** o cadastro não é salvo e o campo indica o motivo e os
   limites.
3. **Dado** um motorista já cadastrado antes desta feature, **então** o app usa o raio padrão sem exigir novo
   cadastro, e o campo aparece preenchido com ele ao editar.
4. **Dado** o raio alterado com o motorista online, **então** a alteração vale a partir da próxima vez em que ele
   ficar online, e a tela avisa isso.

### US3 — A referência do raio é a posição em que fiquei online (P2)
Ao ficar online, a posição do momento é gravada em memória como referência e não muda até ele ficar offline,
mesmo que ele se desloque. Offline, nada é solicitado ao relay sobre `20001`. Online de novo, a referência é a
posição daquele momento.

**Teste independente**: ficar online numa posição, simular deslocamento de dezenas de km, e verificar que o
critério continua sendo a posição original; ficar offline e online de novo e verificar a nova referência.

1. **Dado** o motorista online, **quando** a posição dele muda, **então** a referência e as células inscritas não
   mudam.
2. **Dado** o motorista offline, **então** ele não recebe nem notificação de solicitações (como hoje) e a
   inscrição de `20001` não existe.
3. **Dado** que ele fica offline e online de novo em outro lugar, **então** a referência passa a ser a nova
   posição.
4. **Dado** GPS indisponível ou sem permissão ao tentar ficar online, **então** ele permanece offline com o aviso
   já existente (FR-008 da feature 004) e não recebe solicitação alguma.

## Casos de borda

- **GPS indisponível ou sem permissão ao ficar online**: a regra existente impede ficar online sem posição válida;
  o motorista continua offline, vê o aviso de sempre e não recebe nada (nem inscrição de `20001`).
- **Raio inválido**: vazio, não numérico, ≤ 0, abaixo do mínimo ou acima do máximo → recusado no formulário, que
  não salva. Um valor persistido inválido (corrompido) é tratado como ausente e vale o padrão.
- **Motorista se afasta da referência**: a referência não muda; o motorista que quer recentralizar fica offline e
  online de novo. Isso é o comportamento esperado, não um defeito.
- **Solicitações antigas, sem tag `g`**: ignoradas.
- **Origem perto da borda da célula**: coberta pelas 8 células vizinhas; nunca falha por estar do outro lado da
  linha da célula.
- **Raio maior que o coberto pelas 9 células da precisão atual**: usa-se precisão mais grossa, para que as 9 células
  sempre cubram o círculo do raio inteiro (a regra de escolha fica no plan/research).
- **Tag `g` coerente com a célula, mas origem do `content` além do raio**: descartada (o filtro exato vale sobre a
  origem lida do `content`; a tag só serve para o recorte barato).
- **Tag `g` mal formada** (vazia, caracteres fora do alfabeto de geohash, comprimento inesperado): descartada como
  inválida, sem erro.
- **`content` malformado** ou origem ausente nele: continua descartado como hoje (regra 3 de recepção).
- **Mudança do raio com o motorista online**: **não** reinscreve na hora; vale na próxima vez que ficar online (a
  referência já é fixa por sessão online; reinscrever só pelo raio criaria um segundo critério de "sessão").
- **App retomado online (feature 025), interface reaberta com o serviço vivo**: a referência não é persistida
  pela interface, então a nova referência é a primeira posição válida obtida na retomada (e o cadastro carregado).
  Até lá nenhuma solicitação é **aceita** (aberta ou notificada): as que chegam ficam estacionadas e são
  reavaliadas contra a nova referência; se não houver posição em 20 s, somem. O serviço mantém a cobertura
  anterior até a interface mandar outra.
- **Processo morto pelo sistema com o motorista online e o app fechado**: o serviço reinicia online (estado
  persistido) **sem** referência, reconecta aos relays, mas não pede nem aceita `20001` até o app ser aberto e uma
  nova referência ser definida. Limite conhecido e aceito: persistir a referência está vetado (FR-005).
- **Outros kinds** (`20003`, `20008`, `20010`, `20013`, `20014`, `20015`): a restrição geográfica vale só para
  `20001`; esses kinds continuam sendo recebidos como hoje, independentemente de posição e de raio.
- **Corrida em andamento**: a regra existente (só "Aguardando solicitação" aceita solicitações) continua; o filtro
  geográfico é mais um critério, não substitui nenhum.

## Requisitos

### Requisitos funcionais

- **FR-001**: O cadastro inicial MUST pedir o **raio de atendimento** em km, e o motorista MUST poder alterá-lo
  depois nas telas de cadastro/perfil existentes. O raio é a distância máxima, em linha reta, da posição de
  referência até a origem da corrida.
- **FR-002**: O raio MUST ser validado: número **inteiro** de km, entre o mínimo de **1 km** e o máximo de
  **100 km** (inclusive); fora disso o formulário não salva e informa o motivo e os limites. Valor persistido inválido é
  tratado como ausente.
- **FR-003**: O raio padrão MUST ser **10 km**: pré-preenchido no cadastro inicial e aplicado a motoristas já
  cadastrados sem raio, sem exigir novo cadastro.
- **FR-004**: O raio MUST ser guardado só no aparelho junto ao cadastro e MUST NOT ser publicado em nenhum evento.
- **FR-005**: Ao ficar online, o app MUST tomar a posição do momento como **referência do raio**, fixa até ele
  ficar offline. A referência MUST ficar só em memória: não é persistida nem publicada, e o status online/offline
  continua nunca persistido.
- **FR-006**: Alterar o raio com o motorista online MUST valer só a partir da próxima vez que ele ficar online, e a
  tela MUST informar isso.
- **FR-007**: Enquanto offline, o app MUST NOT manter inscrição de solicitações (`20001`). Ao ficar online, MUST
  inscrever-se em `20001` com filtro por células de geohash: a célula da referência e as 8 vizinhas; ao ficar
  offline, MUST cancelá-la.
- **FR-008**: A precisão das células da inscrição MUST ser escolhida a partir do raio, de modo que as 9 células
  cubram o círculo de raio completo em torno da referência; a regra e a tabela de limiares ficam no plan/research.
- **FR-009**: O filtro por células MUST valer só para `20001`. A inscrição dos demais kinds consumidos MUST seguir
  como hoje, sem restrição geográfica.
- **FR-010**: Na recepção, para todo `20001`, o app MUST (depois da verificação de assinatura e do marcador, e
  **antes** da deduplicação): descartar o evento sem nenhuma tag `g` bem formada que coincida com uma das células
  da inscrição (tags `g` mal formadas são ignoradas na busca; sem tag válida e coincidente, o evento é
  descartado); e, como filtro exato final, descartar o que tem origem (lida do `content`) além do raio da
  referência, pela distância de Haversine. A conferência vem antes da deduplicação para que um evento descartado
  com uma referência não seja tratado como repetido quando o relay o reentregar com outra (o motorista ficou offline
  e online em outro lugar).
- **FR-011**: Solicitação descartada pelo filtro geográfico MUST NOT aparecer na tela, gerar notificação nem
  entrar na lista de eventos recebidos; descarta-se sem erro e sem avisar a rede.
- **FR-012**: A regra geográfica MUST ser a mesma na interface e no serviço em segundo plano (FR-005 da feature
  025): a decisão de notificar usa o mesmo critério da de abrir a modal.
- **FR-013**: O contrato MUST ganhar a emenda 27 em `specs/002-nostr-relay-connection/contracts/nostr-events.md`:
  tag `g` no `20001` (geohash da origem, publicada em três precisões fixas definidas no contrato — ver
  Premissas), sem alterar o `content`, e a seção
  *Forma da inscrição* atualizada. A emenda MUST ser escrita **antes** do código e replicada, idêntica, no app do
  passageiro na mesma alteração (Princípio IV).
- **FR-014**: O `research.md` MUST registrar que o filtro por célula revela ao relay a região aproximada do
  motorista (as 9 células), e que o raio e a referência exata não saem do aparelho.
- **FR-015**: Cálculo das 9 células, escolha da precisão, recorte por célula e filtro por raio MUST ter teste
  próprio cobrindo caso aceito e rejeitado, sem rede nem relay real (Princípio II e CLAUDE.md).

### Entidades-chave

- **Raio de atendimento**: distância máxima, em km, que o motorista aceita percorrer da referência até a origem;
  atributo do cadastro, persistido só no aparelho, entre 1 e 100 km, padrão 10.
- **Posição de referência**: latitude/longitude em que o motorista ficou online; só em memória; vive de "ficar
  online" a "ficar offline".
- **Células de inscrição**: a célula da referência e as 8 vizinhas, numa precisão derivada do raio; definem o
  filtro enviado ao relay e o recorte na recepção.
- **Tag `g`**: geohash da origem da solicitação, publicado pelo passageiro no `20001`; só prefiltro, nunca
  autoridade sobre a origem (que vem do `content`).

## Critérios de sucesso

### Resultados mensuráveis

- **SC-001**: Com o motorista em Araranguá e raio de X km, 100% das solicitações com origem em São Paulo são
  descartadas sem chegar à tela, à notificação nem à lista de eventos, e 100% das de origem a menos de X km chegam.
- **SC-002**: Em teste com origens distribuídas em volta da referência (inclusive nas bordas das células e a
  poucos metros do limite do raio), nenhuma solicitação dentro do raio é perdida e nenhuma fora do raio é aceita.
- **SC-003**: Com o relay simulado entregando todos os eventos ignorando o filtro por célula, o resultado visível
  ao motorista é o mesmo de um relay que o aplica.
- **SC-004**: Uma solicitação sem tag `g` nunca é aceita, qualquer que seja a origem declarada.
- **SC-005**: Um motorista já cadastrado atualiza o app e passa a receber só solicitações num raio de 10 km sem
  tocar no cadastro.
- **SC-006**: O raio e a referência exata não aparecem em nenhum evento publicado (verificável nos eventos
  gerados em teste).
- **SC-007**: `flutter analyze` sem apontamentos e `flutter test` sem teste ignorado; os testes da feature rodam
  sem rede, relay real, GPS ou plugin de plataforma.

## Premissas

- A distância do raio é em linha reta (Haversine), não pela rota; a mesma aproximação já usada em `geo_distance`.
- **Precisão da tag `g`**: com uma única tag de 5 caracteres (~5 km), um filtro de célula mais grossa (precisão 4,
  ou 3) não casaria no relay, que compara a tag por igualdade exata de valor. Para que "raio maior ⇒ precisão
  menor" funcione, o contrato da emenda 27 define que o passageiro publica a tag `g` **em mais de uma
  precisão** (a proposta inicial: 5, 4 e 3 caracteres, cada uma como `["g", "<prefixo>"]`), derivadas do mesmo
  ponto de origem. A definição final (precisões e limiares de escolha) é do plan/research e do contrato; este é o
  único ponto em que a especificação se afasta da redação "uma tag `g`" do pedido, por consequência direta dele.
- O máximo de 100 km é cotado para que as 9 células de precisão 3 (~156 km de lado) cubram o círculo de raio
  completo; o mínimo de 1 km evita raios que o erro típico de GPS (5–15 m) e da própria origem tornariam
  imprevisíveis. Limites e padrão (10 km) são decisões desta especificação, ajustáveis no plan.
- O motorista, ao ficar offline e online de novo, aceita que o relay entregue de novo o histórico (`limit: 50`)
  da nova região; os já vistos são deduplicados por `id` como hoje.
- O app do passageiro passa a publicar a tag `g`; antes disso, qualquer solicitação sem a tag é ignorada (pedido
  explícito). Por isso as duas apps precisam ser atualizadas juntas (Princípio IV).
- O raio e a referência não têm interface de mapa nesta feature (nenhum círculo desenhado no mapa).
- Permissões Android: nenhuma nova (a localização já é usada).
- A decisão sobre nova dependência (biblioteca de geohash ou implementação própria) é do plan/research; o
  domínio continua sem importar bibliotecas de terceiros.
