# Feature Specification: Mensagens cifradas entre as apps (motorista)

**Feature Branch**: `019-mensagens-cifradas`

**Created**: 2026-10-06

**Status**: Draft

**Input**: User description (pedido original, que toca as duas apps — ver Clarifications):
"Toda mensagem enviada de um app ao outro deve ser criptografada e assinada (usando-se o par de
chaves assimétricas)."

## Clarifications

### Session 2026-10-06 (decisões tomadas antes da especificação, na conversa que a originou)

- Q: O kind 20001 (Solicitação de carona) é um anúncio a qualquer motorista; o passageiro não
  conhece destinatário, logo não há chave pública para cifrar. Como tratar? → A: **exceção
  deliberada**: o 20001 continua só assinado, em claro, com a exceção justificada por escrito no
  contrato e nas constituições (posição e destino ficam públicos). Todos os demais kinds de domínio
  (20002 a 20012) passam a ser cifrados ao destinatário.
- Q: Qual padrão de cifragem? → A: NIP-44 (cifragem autenticada, com a chave privada do remetente e
  a chave pública do destinatário). NIP-04 foi descartado por depreciado.
- Q: Como dividir entre as apps? → A: duas features, uma por app, mesmo padrão das features
  012/010 e 018/019. Esta (`driver`) define o contrato (emenda nova) e cobre o que o motorista
  publica e decifra; a contrapartida do passageiro (publica 20003/20004/20008/20010 cifrados e
  decifra 20002/20005/20006/20007/20009/20011/20012) é outra feature, na mesma alteração de
  contrato (Princípio IV).
- Q: O que se cifra nos kinds de `content` hoje vazio? → A: o marcador fixo `{}` — o padrão de
  cifragem rejeita texto de entrada vazio (descoberto na fase de plano, `research.md` D2); a
  intenção original, "cifrar também os kinds sem conteúdo", se mantém.
- Q: As tags continuam em claro? → A: sim. `t` (marcador), `e` (referência) e `p` (destinatário)
  são necessárias para filtro e roteamento no relay e permanecem legíveis; a assinatura do envelope
  continua obrigatória. Só o `content` é cifrado.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Mensagens do motorista ilegíveis para terceiros (Priority: P1)

Como motorista, quero que tudo o que meu app publica para o passageiro de uma corrida (orçamento,
localização, chegada, rota, cancelamento) só possa ser lido por esse passageiro, para que ninguém
observando o relay saiba onde estou, qual o meu orçamento ou por onde passo.

**Why this priority**: é o ganho de privacidade do pedido — hoje posição em tempo real e rota
trafegam em claro, legíveis por qualquer um que assine o marcador do protótipo.

**Independent Test**: publicar cada kind (20002, 20005, 20006, 20007, 20009, 20011, 20012) com o
dublê de transporte e verificar que o `content` do evento assinado não contém nenhum dado em claro
(nem `lat`/`lon`, `total`, `points`) e que só o destinatário (chave da tag `p`) o decifra de volta ao
conteúdo original.

**Acceptance Scenarios**:

1. **Given** um orçamento pronto para envio, **When** o motorista toca "Enviar orçamento", **Then** o
   evento publicado tem `content` cifrado ao solicitante, assinatura válida e as tags `t`/`e`
   inalteradas, e nenhum campo do orçamento aparece em claro.
2. **Given** o motorista "Deslocando-se até o passageiro" ou "Em corrida", **When** o app publica
   localização, chegada, rota ou cancelamento, **Then** cada evento sai com `content` cifrado ao
   passageiro da corrida ativa (tag `p`) e assinado.
3. **Given** um terceiro com uma chave que não é a do destinatário, **When** tenta decifrar o
   `content` de qualquer desses eventos, **Then** a decifração falha.
4. **Given** uma falha ao cifrar (ex.: chave de destinatário inválida), **When** o app tentaria
   publicar, **Then** nada é publicado em claro como alternativa.

---

### User Story 2 - Mensagens do passageiro lidas só pelo motorista certo (Priority: P1)

Como motorista, quero decifrar as mensagens que o passageiro me envia (aceitação, encontro
confirmado, destino confirmado), para que o fluxo da corrida continue funcionando agora que o
conteúdo vem cifrado.

**Why this priority**: sem isso o fluxo existente quebra assim que o passageiro passar a cifrar —
o consumo precisa acompanhar o contrato.

**Independent Test**: entregar ao `EventFeed`/serviço de recepção eventos 20003, 20008 e 20010
válidos e cifrados ao motorista, e verificar que cada um produz o mesmo efeito de hoje (modal
"Orçamento aceito", transição para "Em corrida", encerramento da corrida).

**Acceptance Scenarios**:

1. **Given** uma aceitação (20003) cifrada ao motorista, **When** chega, **Then** a assinatura é
   verificada primeiro, o conteúdo é decifrado e o comportamento é idêntico ao de hoje.
2. **Given** um evento com assinatura válida mas `content` que não decifra com a chave do motorista
   (cifrado a outro destinatário, adulterado ou em claro), **When** chega, **Then** é descartado
   sem erro e sem efeito algum.
3. **Given** um evento com assinatura inválida, **When** chega, **Then** é descartado antes de
   qualquer tentativa de decifrar (regra 1 de recepção inalterada).

---

### User Story 3 - Contrato e exceção do 20001 registrados (Priority: P2)

Como mantenedor do protótipo, quero que o contrato de eventos e as constituições descrevam o novo
formato cifrado, a regra de recepção e a exceção do kind 20001, para que a app do passageiro
replique o mesmo formato e a decisão de privacidade esteja justificada por escrito.

**Why this priority**: o contrato é o único acoplamento entre as apps (Princípio IV) e a
constituição exige justificativa escrita para dado pessoal que trafega sem cifra.

**Independent Test**: revisar `nostr-events.md` (emenda nova, tabela de kinds com coluna de
proteção, regra de recepção de decifração) e a justificativa do 20001; conferir que as duas
constituições (e a de `Prototipo/`, se afetada) ficam idênticas após a emenda.

**Acceptance Scenarios**:

1. **Given** o contrato, **When** lido, **Then** cada kind 20002–20012 consta como "cifrado ao
   destinatário (tag `p`)" e o 20001 como "assinado, em claro — exceção" com a justificativa.
2. **Given** as duas constituições, **When** comparadas após a emenda, **Then** os corpos são
   idênticos salvo nome/escopo/perspectiva.

---

### Edge Cases

- Mensagem sem conteúdo (20003, 20004, 20006, 20007, 20008, 20009, 20010, 20012, hoje `content`
  vazio): também é cifrada, para que presença e forma sejam uniformes e o tamanho não revele o tipo.
  O padrão de cifragem **proíbe texto de entrada vazio**, então o texto cifrado nesses kinds é o
  marcador fixo `{}` (JSON de objeto vazio); um `content` vazio em claro nesses kinds, ou cifrado de
  qualquer outro texto, passa a ser inválido.
- Evento antigo em claro (de versão anterior de uma das apps) nos kinds 20002–20012: não decifra,
  logo é descartado; não há modo de compatibilidade (protótipo, as duas apps atualizam juntas).
- Aceitação (20003) cujo orçamento o motorista não enviou: continua ignorada após decifrar.
- Tag `p` ausente ou diferente da chave do motorista: o evento não é para ele; descartado sem
  tentar decifrar.
- Rota de 1000 pontos (≈21 KB em claro): o `content` cifrado fica maior; a mensagem continua dentro
  do menor limite anunciado pelos relays padrão.
- Publicação de localização a cada 5 s: o custo de cifrar a cada mensagem não pode travar a tela
  nem atrasar o ciclo de 5 s de forma perceptível.
- Chave privada do motorista indisponível (falha de inicialização da identidade): nada é cifrado
  nem publicado, como hoje.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: O motorista MUST cifrar o `content` de todo evento de domínio que publica com
  destinatário conhecido — 20002, 20005, 20006, 20007, 20009, 20011 e 20012 — usando a chave
  privada dele e a chave pública do destinatário indicada na tag `p` (no 20002, a do autor da
  solicitação 20001 respondida).
- **FR-001a**: O `kind: 20002` MUST passar a levar a tag `["p", <chave pública do autor da solicitação
  respondida>]` (hoje só leva `["e", ...]`), por ser dela que se tira o destinatário da cifra e por ser
  por ela que o passageiro filtra o que lhe é dirigido; isso é mudança de formato do `20002`, registrada
  na emenda do contrato (FR-010) e replicada no passageiro.
- **FR-002**: O motorista MUST continuar assinando cada evento (assinatura do envelope) depois de
  cifrar; a assinatura cobre o `content` já cifrado.
- **FR-003**: As tags `t`, `e` e `p` MUST permanecer em claro e inalteradas; só o `content` é
  cifrado.
- **FR-004**: Se a cifragem falhar, o app MUST NOT publicar o evento em claro como alternativa; a
  falha é absorvida com o mesmo tratamento já dado a falha de publicação do kind em questão.
- **FR-005**: O motorista MUST decifrar o `content` dos eventos 20003, 20008 e 20010 recebidos,
  com a chave privada dele e a chave pública do autor do evento, e aplicar a mesma lógica de hoje
  ao conteúdo decifrado.
- **FR-006**: A decifração MUST ocorrer somente **depois** da verificação de assinatura e da
  conferência de que a tag `p` é a chave do motorista; evento que não passa em qualquer das duas,
  ou cujo `content` não decifra, MUST ser descartado sem erro, sem efeito e sem aparecer ao usuário.
- **FR-007**: O kind 20001 MUST permanecer assinado e em claro, por ser anúncio a destinatário
  desconhecido; o motorista continua o lendo como hoje. A exceção MUST constar do contrato e da
  seção de Restrições de Segurança e Privacidade das constituições, com justificativa.
- **FR-008**: Os kinds 20003, 20004, 20006, 20007, 20008, 20009, 20010 e 20012 (hoje com `content`
  vazio) MUST também trafegar com `content` cifrado, cujo texto de entrada é o marcador fixo `{}`
  (o padrão proíbe entrada vazia); o motorista MUST rejeitar, nesses kinds, `content` em claro ou
  que decifre para qualquer outro texto.
- **FR-009**: Nenhum segredo (chave privada, chave de conversa derivada) MUST ser registrado em
  log, exibido ou persistido; os valores decifrados MUST seguir sendo tratados como dados, nunca
  como instrução (regra 3 de recepção).
- **FR-010**: O contrato `nostr-events.md` MUST ganhar uma emenda descrevendo: o formato cifrado
  do `content`, quais kinds são cifrados, a exceção do 20001, a ordem de recepção (assinatura →
  destinatário → decifração) e o descarte silencioso. A emenda MUST ser replicada na cópia do
  passageiro na mesma alteração.
- **FR-011**: O comportamento observável do fluxo de corrida (modais, estados, rota no mapa,
  localização a cada 5 s, cancelamento) MUST permanecer idêntico ao de antes desta feature.
- **FR-012**: A mensagem publicada MUST continuar dentro do menor limite de tamanho anunciado pelos
  relays padrão, inclusive o `20011` com 1000 pontos; se não couber, o limite de pontos é revisto.
- **FR-013**: Código de cifragem, decifração e assinatura MUST nascer com teste automatizado
  (Princípio II): ida e volta, destinatário errado, adulteração, `content` em claro e conteúdo
  vazio.

### Key Entities

- **Evento cifrado**: evento de domínio cujo `content` é o texto cifrado ao destinatário; tags
  `t`/`e`/`p` em claro; assinado pelo autor.
- **Destinatário**: chave pública na tag `p`; única que decifra.
- **Exceção do kind 20001**: único kind de domínio publicado sem cifragem, por não ter destinatário.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Em 100 % dos eventos 20002–20012 publicados pelo motorista, nenhum dado do conteúdo
  (coordenadas, valores, pontos de rota, nomes) é legível sem a chave do destinatário.
- **SC-002**: Em 100 % dos casos de teste de recepção inválida (assinatura inválida, destinatário
  errado, conteúdo em claro, conteúdo adulterado), o evento é descartado sem alterar estado nem
  mostrar erro ao usuário.
- **SC-003**: O fluxo de corrida completo (aceitação → deslocamento → encontro → destino) funciona
  como antes, com a suíte de testes existente passando após os ajustes de cifragem.
- **SC-004**: A localização continua publicada a cada 5 s, com atraso adicional pela cifragem
  imperceptível ao usuário: menos de 100 ms por mensagem, **inclusive a primeira de cada par** (a mais
  cara), medido no emulador `Pixel_6_API34_1` e, se disponível, num aparelho físico.
- **SC-005**: A maior mensagem do protótipo (rota de 1000 pontos) segue abaixo do menor limite
  anunciado pelos relays padrão, medida de fato após a cifragem.
- **SC-006**: Contrato e constituições ficam consistentes entre as duas apps (diff dos corpos
  idêntico) e a exceção do 20001 consta por escrito em ambos.

## Assumptions

- Pré-requisito do passageiro: a feature irmã dele (publicar 20003/20004/20008/20010 cifrados e
  decifrar o restante) entra na mesma alteração de contrato; testes ponta a ponta exigem as duas.
- Não há compatibilidade com versões anteriores: as duas apps são do mesmo protótipo e
  atualizam juntas; evento em claro nos kinds 20002–20012 é inválido.
- A biblioteca de Nostr já adotada não oferece esse padrão de cifragem e o único pacote que o traz não
  é compatível com ela; a decisão (implementar o padrão no app, promovendo dois pacotes já transitivos
  a dependências diretas, sem pacote Nostr novo) está registrada no `research.md` D1 (Princípio III).
- A mudança quebra o formato de kinds já em uso nos dois sentidos: o motorista só fica completo
  quando a feature irmã do passageiro também estiver — as duas MUST ser concluídas em seguida, na
  mesma alteração de contrato (Princípio IV).
- A emenda de constituição (exceção do 20001 e eventual dependência) é commitada separadamente do
  código, nas duas apps juntas e na de `Prototipo/` se aplicável.
- Metadados continuam visíveis a quem observa o relay: autor, destinatário (tag `p`), referência
  (tag `e`), kind, momento e tamanho. Esconder isso (ex.: envelopes embrulhados) está fora de
  escopo.
- Fora de escopo: cifrar a avaliação (nunca sai do aparelho), cifrar o kind 1 de teste, mensagens
  de chat entre pares (kind futuro), rotação de chaves e criptografia em repouso do SQLite.
