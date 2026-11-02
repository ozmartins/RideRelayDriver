# Especificação: Reputação por recibos assinados (motorista)

**Feature**: `026-recibos-de-reputacao` · **App**: `driver/` · **Data**: 2026-10-20 · **Status**: Draft
**Contrato de eventos**: **muda** — emenda 25 (kinds `20014` e `20015`, campo opcional `reputacao` em `20001` e
`20002`). Contrapartida obrigatória no app do passageiro, na mesma alteração (Princípio IV).
**Entrada**: `especificacao-motorista.md` (raiz do projeto): "Reputação por recibos assinados" — a seção 1 é o
contrato comum às duas apps; a seção 2 são as mudanças específicas do motorista.

## Problema

Hoje a avaliação que o motorista dá ao passageiro (feature 013) fica só no aparelho do motorista e não chega a
ninguém; o passageiro também não tem como mostrar ao motorista que é um bom passageiro, nem o motorista ao
passageiro. Sem backend e sem guardar avaliações em relays (os eventos de corrida são efêmeros), a reputação
precisa viajar com o próprio usuário e ser **verificável** por quem a recebe.

A solução do contrato: cada corrida concluída gera um **recibo assinado** pelo avaliador, entregue ao avaliado, que
o guarda localmente e apresenta os mais recentes quando for avaliado por outra pessoa. Os recibos de cada avaliado
formam uma cadeia numerada e encadeada por hash, o que torna detectável a adulteração e a omissão no meio da
janela apresentada (não a omissão dos recibos mais recentes — ver Limites conhecidos).

## Papéis neste app

- **Avaliador** do passageiro: emite o recibo ao fim da corrida.
- **Avaliado** pelo passageiro: recebe recibos, confirma o recebimento e declara a própria reputação no orçamento.
- **Consumidor** da reputação do passageiro, que chega na solicitação de corrida.

## Cenários de usuário

### US1 — Ver a reputação do passageiro ao receber a solicitação (P1)
Ao chegar uma solicitação, o motorista vê, junto aos dados da corrida, a reputação **verificada** do passageiro
(média e quantidade de recibos que conferem) e, em texto menor, o que o passageiro **declara**. Se a reputação for
inconsistente ou houver recibos não apresentados, isso é destacado. Passageiro sem histórico é indicado como tal.

**Teste independente**: entregar ao app uma solicitação com `reputacao` válida, outra com um recibo adulterado, outra
sem o campo e outra com o campo malformado, e observar a apresentação de cada uma.

1. **Dado** uma solicitação com reputação cujos recibos todos conferem, **quando** ela aparece, **então** são
   exibidas média e contagem verificadas, e a média e contagens declaradas em texto secundário.
2. **Dado** uma reputação com recibo de assinatura inválida, **então** o recibo é descartado, não entra na média
   verificada, e o descarte é sinalizado.
3. **Dado** uma reputação cujo `head` não corresponde ao recibo mais recente apresentado, **então** ela é
   marcada como **inconsistente** de forma visível.
4. **Dado** uma lacuna de numeração entre recibos apresentados, **então** aparece "N recibos não apresentados".
5. **Dado** uma solicitação sem `reputacao`, **então** o passageiro aparece "sem histórico".
6. **Dado** uma solicitação com `reputacao` malformada, **então** a solicitação continua válida e o passageiro
   aparece como sem histórico (a reputação não invalida a corrida).

### US2 — Emitir o recibo ao concluir a corrida e garantir a entrega (P1)
Ao fechar a modal de avaliação (com nota ou pulando), o app emite um recibo assinado ao passageiro, numerado na
cadeia do passageiro, e o reenvia até receber a confirmação, mesmo que o app seja encerrado no meio.

**Teste independente**: concluir uma corrida, avaliar, matar o app antes da confirmação, reabrir e observar o
reenvio e a confirmação.

1. **Dado** uma corrida concluída e a modal fechada com nota, **quando** a reputação declarada pelo passageiro
   nesta corrida é consistente, **então** é emitido um recibo com a nota, o `seq` e o hash anterior vindos dessa
   reputação.
2. **Dado** a modal fechada sem nota ("pular"), **então** o recibo é emitido sem o campo de nota (conta como corrida,
   não como avaliação).
3. **Dado** que a reputação declarada é inconsistente, **então** nenhum recibo é emitido, o usuário é avisado em
   uma linha, e a nota local continua gravada.
4. **Dado** um recibo emitido e ainda não confirmado, **quando** o app é reaberto, a conexão com um relay é
   restabelecida, ou passam 60 s com a interface do app ativa, **então** o recibo é reenviado, até chegar a confirmação
   correspondente.
5. **Dado** uma corrida cancelada ou não concluída, **então** nenhum recibo é emitido.
6. **Dado** uma falha ao publicar, **então** a interface não é bloqueada e o recibo permanece pendente.

### US3 — Receber recibos do passageiro e declarar a própria reputação (P1)
Quando o passageiro avalia o motorista, o app valida o recibo, o guarda de forma imutável, confirma o recebimento
e passa a refletir o novo histórico na reputação declarada nos próximos orçamentos.

**Teste independente**: entregar ao app recibos válidos, adulterados, de outro avaliado, duplicados e em claro, e
conferir o efeito sobre a reputação própria.

1. **Dado** um recibo válido endereçado a este motorista, **então** ele é gravado, uma confirmação é enviada ao
   avaliador, e contagens, média, próximo `seq` e `head` são recalculados.
2. **Dado** um recibo com assinatura inválida, adulterado, de outro avaliado ou com a tag de destinatário que não
   é a própria, **então** é ignorado e **nunca** altera a reputação própria.
3. **Dado** um recibo já guardado para a mesma corrida, **quando** idêntico, **então** só a confirmação é reenviada;
   **quando** diferente, é ignorado.
4. **Dado** um recibo que chega em claro (não cifrado), **então** é descartado.
5. **Dado** o motorista enviando um orçamento, **então** o orçamento carrega a reputação própria (últimos 5
   recibos por `seq`, mais as contagens declaradas), omitida se não há histórico.

### US4 — Guardar a reputação declarada pelo passageiro daquela corrida (P2)
Ao enviar o orçamento, o app guarda a reputação que o passageiro declarou na solicitação respondida, para que o
recibo de fim de corrida use exatamente o estado que foi verificado e aceito na negociação.

1. **Dado** o envio de um orçamento a uma solicitação com reputação, **então** essa reputação fica associada
   àquela corrida e é recuperável no fim dela, inclusive após reinício do app.

## Casos de borda

- Recibos fora de ordem de chegada são aceitos; a ordem é por `seq`. Ramos (mesmo `seq`, corridas diferentes) são
  tolerados e exibidos como tal; `seq` repetido para a mesma corrida é rejeitado.
- Linha local de recibo recebido cuja assinatura deixa de conferir (corrupção) é ignorada e não conta.
- Reputação própria muito grande: o conteúdo do orçamento respeita o limite de 65 535 bytes (janela fixa de 5).
- Motorista sem histórico: orçamento sai sem o campo; o passageiro o trata como "sem histórico".
- Avaliador igual ao avaliado, recibo com `v` diferente de 1, nota fora de 1–5, `guid_corrida` repetido na lista ou
  `seq` não decrescente: recibo descartado e contado.
- Confirmação (`20015`) de quem não é o avaliado do recibo pendente, ou com `id_recibo` que não confere: ignorada.
- Eventos novos sem assinatura válida, duplicados por `id`, sem o marcador ou com `content` ilegível: descartados
  como os demais eventos, sem erro.
- Corridas anteriores a esta feature não geram recibo retroativo.
- Recibo válido de um estranho, com corrida inventada: ignorado (emenda 26). Quem negociou com o motorista ainda pode lhe emitir recibo de corrida que não houve; isso fica registrado nos limites do contrato.
- Passageiro que declarou reputação ausente na corrida (sem histórico) recebe recibo com `seq = 0` e sem hash anterior.

## Requisitos

### Requisitos funcionais

**Contrato**
- **FR-001**: O contrato de eventos MUST receber a emenda 25: kinds `20014` (recibo) e `20015` (confirmação),
  campo opcional `reputacao` em `20001` (em claro) e `20002` (cifrado), seções de conteúdo dos novos kinds,
  atualização das regras de cifragem/recepção para "kinds `20002` a `20015`" e da "Forma da inscrição", e a seção
  "Reputação por recibos" copiada literalmente da seção 1 de `especificacao-motorista.md` — antes ou na mesma
  alteração do código, e idêntica à da app do passageiro.
- **FR-002**: O app MUST passar a consumir `20014` e `20015` (inscrição no relay, filtro do feed e serviço em
  segundo plano a partir do mesmo conjunto de kinds).
- **FR-003**: `20014` e `20015` MUST ser cifrados ao destinatário; conteúdo em claro nesses kinds MUST ser
  descartado. O `20001` continua com `reputacao` em claro; o `20002` com `reputacao` cifrada como o resto do conteúdo.

**Recibo e assinatura**
- **FR-004**: O recibo MUST ter os campos do contrato (versão, corrida, avaliador, avaliado, nota opcional,
  criado em, `seq`, hash anterior opcional, identificador do recibo, assinatura), com forma canônica estável e
  identificador igual ao SHA-256 dessa forma; decodificação estrita rejeita campo faltante ou de tipo errado.
- **FR-005**: O recibo MUST ser assinado pelo avaliador sobre o identificador do recibo, usando a mesma API de
  assinatura da avaliação existente; a chave privada MUST NOT aparecer em hash, log ou evento.

**Verificação (função pura, sem I/O)**
- **FR-006**: Ao receber uma reputação, o app MUST verificar cada recibo conforme 1.6 (a–g): identificador
  recalculado, assinatura, avaliado igual ao autor do evento, versão e faixa da nota, `seq` estritamente
  decrescente, corrida sem repetição, avaliador diferente do avaliado. Recibo inválido é descartado e contado.
- **FR-007**: O app MUST marcar a reputação como **inconsistente** quando o `head` não for o recibo de
  `seq = seq_proximo − 1` presente na lista; MUST validar o encadeamento por `hash_anterior` entre recibos
  consecutivos presentes; MUST informar lacunas de `seq` como "N recibos não apresentados".
- **FR-008**: O resultado MUST separar **verificado** (contagem e média só dos recibos válidos) de **declarado**
  (corridas, avaliações, média informadas), nunca combinados numa só nota.

**Armazenamento**
- **FR-009**: O app MUST guardar localmente: recibos recebidos (imutáveis, um por corrida), recibos emitidos com
  marca de pendência, e a reputação do passageiro declarada em cada corrida. Banco novo, separado dos existentes.
- **FR-010**: Cada leitura de recibo recebido MUST revalidar a assinatura; linha que falhar é ignorada.
- **FR-011**: A reputação própria MUST ser calculada a partir dos recibos recebidos: nº de recibos, nº com nota,
  média, próximo `seq` = maior `seq` + 1, `head` = identificador do recibo de maior `seq`, e os 5 mais recentes por `seq`.

**Emissão e entrega (avaliador)**
- **FR-012**: Ao fechar a modal de avaliação (com ou sem nota), **depois** de gravada a nota local, o app MUST
  tentar emitir o recibo seguindo 1.7: verificar a reputação declarada na corrida; se inconsistente, não emitir e
  avisar em uma linha; senão, `seq` e hash anterior vêm dela; gravar como pendente **antes** de publicar.
- **FR-013**: O app MUST reenviar recibos pendentes ao abrir o app, a cada reconexão de relay e a cada 60 s
  enquanto a interface do app estiver ativa (o serviço em segundo plano não tem a chave e não reenvia), até chegar confirmação válida (autor = avaliado do recibo e
  identificador conferindo).
- **FR-014**: Corrida cancelada ou não concluída MUST NOT gerar recibo. Falha de publicação MUST NOT bloquear a interface.

**Recepção (avaliado)**
- **FR-015**: Ao receber `20014`, depois das regras de recepção gerais, o app MUST validar o recibo (1.6 a–d, g) com
  avaliado = própria chave, avaliador = autor do evento e corrida = tag `e`; se já existe recibo para a corrida,
  idêntico apenas reenvia a confirmação, diferente é ignorado; senão grava (imutável) e publica `20015`.
- **FR-016**: O orçamento (`20002`) MUST incluir a reputação própria, omitindo o campo se o motorista não tem recibos.

**Corrida conhecida (emenda 26)**
- **FR-023**: Ao receber um recibo, o app MUST gravá-lo só se o `guid_corrida` for de um orçamento que **este motorista enviou àquele avaliador**, conforme o registro local; recibo de corrida desconhecida, ou ligada a outro passageiro, MUST ser descartado sem erro e sem confirmação. A consulta MUST usar só o registro local, nunca dados do próprio recibo.
- **FR-024**: Uma `reputacao` com mais de 5 recibos MUST ser tratada como malformada (ausente), sem verificar nenhum recibo dela.

**Apresentação e integração**
- **FR-017**: A solicitação recebida MUST ler a `reputacao` opcional do `20001`; reputação malformada MUST virar
  "ausente" sem invalidar a solicitação.
- **FR-018**: Ao enviar o orçamento, o app MUST guardar a reputação do passageiro daquela solicitação associada à corrida.
- **FR-019**: A apresentação da solicitação MUST mostrar a reputação verificada do passageiro (média, nº verificado),
  a declarada em texto menor, e destacar "inconsistente" e "N recibos não apresentados", seguindo a identidade
  visual do projeto.
- **FR-020**: A nota local da avaliação (feature 013/014) MUST permanecer como está; nenhum dado antigo vira recibo.

**Qualidade**
- **FR-021**: Nenhuma chave privada ou conteúdo decifrado em log; código que assina, verifica ou descarta
  mensagem MUST ter teste (caso válido e inválido) sem rede, SQLite ou relay reais.
- **FR-022**: Um recibo gerado por este app MUST ser aceito pelo verificador do passageiro: um conjunto de vetores
  compartilhado, idêntico nos dois repositórios, MUST ser exercitado por teste em cada app.

### Entidades-chave

- **Recibo**: prova assinada por um avaliador de que uma corrida ocorreu, com nota opcional, posição na cadeia do
  avaliado e elo para o recibo anterior.
- **Reputação**: resumo apresentado por um usuário — contagens e média declaradas, próximo `seq`, `head`, e os
  recibos mais recentes (janela de 5).
- **Visão da reputação**: resultado da verificação — contagem e média verificadas, declarado, descartados,
  lacunas, indicador de inconsistência.
- **Recibo emitido**: recibo que este motorista gerou, com marca de pendente até a confirmação.
- **Reputação declarada da corrida**: reputação do passageiro como veio na solicitação respondida.

## Limites conhecidos (a documentar no contrato, não esconder)

- O avaliado controla o que apresenta: pode omitir recibos ruins **recentes** criando cadeia sem eles; a cadeia
  mais o `head` conferido pelo avaliador só reduz isso.
- Quem recria a identidade zera o histórico (Sybil); perder o app ou a chave perde a reputação.
- Corridas, avaliações e média declaradas não são verificáveis além da janela de 5.
- O `20001` é público: os recibos nele expõem chaves públicas das contrapartes e as notas dadas. **Justificativa**:
  o motorista precisa avaliar o solicitante antes de existir destinatário conhecido e, sem backend, a reputação só
  pode viajar com o próprio usuário; custo aceito no protótipo (alternativa futura: resumo no `20001` e recibos após
  o orçamento).

## Fora de escopo

Backend; armazenamento de recibos em relays; qualquer NIP além de NIP-01/NIP-44; migração de dados antigos; mudar
o marcador de protótipo.

## Critérios de sucesso

- **SC-001**: Duas apps (reais ou emuladores) trocam solicitação e orçamento com reputação, recibo e confirmação, e
  ambas exibem a reputação verificada da contraparte.
- **SC-002**: Com o app encerrado entre a emissão e a confirmação, ao reabrir o recibo pendente é reenviado e
  confirmado sem ação do usuário, em até 60 s com um relay conectado.
- **SC-003**: Em 100% dos casos de teste com recibo adulterado, de assinatura inválida, de outro avaliado ou em
  claro, a reputação própria permanece inalterada.
- **SC-004**: Em 100% dos casos de teste de reputação inconsistente, nenhum recibo é emitido e o usuário vê o aviso.
- **SC-005**: A solicitação com reputação malformada continua apresentada em 100% dos casos de teste.
- **SC-006**: `flutter analyze` sem apontamentos e `flutter test` sem falhas nem testes ignorados; nenhuma chave ou
  texto decifrado em log.

## Premissas

- A pasta `specs/026-avaliacao-enviada-ao-passageiro` citada em `especificacao-motorista.md` não existe neste
  repositório; a feature usa o próximo número sequencial, `026-recibos-de-reputacao`.
- O app do passageiro implementa a contrapartida (emissão como avaliador do motorista, recepção, `reputacao` no
  `20001`) em projeto próprio, com o mesmo texto de contrato.
- A janela de recibos apresentados é fixa em 5 e a reputação própria só usa recibos recebidos de outros.
- A emenda 25 do contrato é a próxima (a última existente é a 24).
- Reaproveitam-se a assinatura, o armazenamento e o temporizador de publicações periódicas já existentes
  (features 013, 014, 021, 025); o serviço em segundo plano (025) passa a conhecer os novos kinds.
- Detalhes de implementação (arquivos, esquemas de tabela, métodos) estão em `especificacao-motorista.md`, seção 2,
  e serão decididos no plano.
