# Especificação: Transporte próprio sobre WebSocket para os relays (motorista)

**Feature**: `028-transporte-websocket-proprio` · **App**: `driver/` · **Data**: 2026-10-22 · **Status**: Draft
**Contrato de eventos**: **não muda** — nenhuma emenda. Nada a replicar no app do passageiro; esta feature só
alinha o motorista ao que o passageiro já faz.
**Ramo**: nenhum — o projeto trabalha direto na `master` (CLAUDE.md).
**Entrada**: "Unificar a camada de conexão com relays do app do motorista à do app do passageiro, trocando o
transporte baseado no cliente de relays do `dart_nostr` por um transporte próprio sobre WebSocket."

## Problema

Os dois apps usam a mesma biblioteca (`dart_nostr`) para chaves, assinatura e verificação, mas conectam-se aos
relays de formas diferentes. O motorista usa o cliente de relays da biblioteca (uma instância por relay,
`NostrRelayGateway`); o passageiro usa WebSocket direto, montando e interpretando ele mesmo os frames do protocolo
(`REQ`, `EVENT`, `OK`, `CLOSE`), com ping periódico, prazo de handshake e fechamento do socket que chega atrasado
(`ws_relay_transport.dart` e `relay_service.dart` do passageiro).

Essa assimetria tem dois custos:

1. **Atribuição de causa**: diante de um comportamento observado em teste ponta a ponta (mensagem que não chega,
   reconexão lenta), não dá para dizer se a causa é o protocolo ou uma das duas implementações. É uma crítica
   esperada da banca do TCC.
2. **Reconexão divergente**: o passageiro detecta conexão morta sem aviso (troca de Wi-Fi para dados móveis) por
   ping; o motorista depende do que a biblioteca faz, que não é o mesmo comportamento nem está sob controle do
   projeto.

O objetivo é que os dois apps tenham **o mesmo comportamento de conexão**, sem mudar nada que o usuário ou o
contrato de eventos enxergue.

## Cenários de usuário

### US1 — A corrida completa funciona como antes (P1)
O motorista usa o app como hoje: fica online, recebe solicitações dentro do raio, envia orçamento, troca
mensagens, finaliza a corrida e troca recibos com o passageiro. Nada na tela, nas notificações, nos filtros nem
nos eventos publicados muda; só o transporte por baixo.

**Teste independente**: com relays públicos e o app do passageiro em outro emulador, percorrer a corrida inteira
(`20001` a `20015`) e conferir que cada etapa chega ao outro lado, como na rodada anterior à troca.

1. **Dado** o motorista online e um passageiro que publica uma solicitação dentro do raio, **quando** o fluxo
   completo é percorrido, **então** todos os kinds de `20001` a `20015` são publicados e recebidos pelos dois
   lados, e a corrida termina com recibos trocados.
2. **Dado** um evento publicado pelo motorista, **quando** um relay o recusa (exige pagamento ou autenticação),
   **então** a mensagem do relay é repassada ao usuário sem interpretação, como hoje.
3. **Dado** a conexão em segundo plano (feature 025), **então** ela segue no serviço em primeiro plano, que nunca
   tem a chave privada, e entrega o mesmo que antes à tela.

### US2 — Recuperar sozinho de uma queda de conexão (P1)
A rede some sem aviso (ou o aparelho troca de Wi-Fi para dados móveis) e volta depois. O motorista não precisa
fazer nada: o app percebe a conexão morta dentro de um tempo limitado pelos parâmetros de vivacidade e retentativa (teto de ~65 s depois que a rede volta, SC-004), marca o relay como indisponível, tenta de
novo e reinscreve nos filtros, e volta a receber eventos.

**Teste independente**: no emulador, com o fluxo em andamento, desligar a rede por cerca de 25 s e religá-la.

1. **Dado** uma conexão estabelecida que morre sem erro nem fechamento, **quando** o pong do ping não chega, **então**
   o transporte fecha a conexão e emite uma única notificação de queda para aquele relay.
2. **Dado** uma queda notificada, **quando** a rede volta, **então** o app reconecta e reinscreve (incluindo o
   filtro do `20001` com `#g` se o motorista está online) sem intervenção.
3. **Dado** uma desconexão pedida pelo app (relay removido, motorista encerra), **então** nenhuma queda é
   notificada.

### US3 — Provar o comportamento sem rede (P2)
Quem audita o projeto (orientadora, banca) consegue reproduzir, sem rede nem relay real, cada comportamento do
transporte do motorista contra um dublê de socket, e ver que o motorista e o passageiro se comportam igual nos
mesmos casos.

**Teste independente**: rodar `flutter test` sem rede e observar os testes do transporte novo passarem, um por
caso do protocolo.

1. **Dado** um dublê de socket injetado, **quando** o handshake conclui, falha ou estoura o prazo, **então** o
   resultado é, respectivamente, conexão registrada, erro e erro sem socket órfão.
2. **Dado** um frame `EVENT` malformado ou truncado, **então** ele é descartado sem erro e a conexão continua.
3. **Dado** um `OK` aceito, um `OK` recusado com mensagem e uma publicação sem resposta, **então** o relatório por
   relay traz aceito, recusado com a mensagem do relay e recusado por prazo, respectivamente.

## Casos de borda

- Socket que termina o handshake **depois** do prazo de 10 s: é fechado assim que aparece, sem ficar órfão nem
  entregar eventos.
- Tentativa de conexão cancelada (`disconnect`) ou substituída (nova `connect` ao mesmo relay) durante o
  handshake: a tentativa antiga fecha a própria conexão e não se registra.
- Queda e `disconnect` quase simultâneos: no máximo uma notificação de queda, e nenhuma se a desconexão foi
  pedida.
- Frame do relay que não é JSON, não é lista, tem tipo desconhecido, ou `EVENT` sem objeto de evento: ignorado.
- Mensagem acima do limite de tamanho aceito: descartada sem derrubar a conexão.
- Recusa do relay por tag mal formada (`OK false` / `NOTICE` / `CLOSED` com o motivo): vira resultado de
  publicação ou é ignorada, mas não derruba a conexão nem as outras inscrições.
- `CLOSED` do relay para uma inscrição: não encerra o socket; a reinscrição acontece na próxima conexão ou troca de
  células.
- Troca de células do `20001` com um relay ainda conectando: o relay que conectar depois se inscreve já com as
  células novas.
- Motorista offline (sem células): o `20001` não é pedido; os demais kinds continuam inscritos.
- Relay que aceita o socket e nunca responde: a sonda de vivacidade falha no prazo do chamador.
- Relay duplicado na lista ou `connect` repetido à mesma url: uma só conexão vigente.

## Requisitos

### Requisitos funcionais

- **FR-001**: A conexão do motorista com cada relay MUST usar um transporte próprio sobre WebSocket do `dart:io`,
  sem o cliente de relays do `dart_nostr`. `NostrRelayGateway` MUST ser removido, não mantido em paralelo.
- **FR-002**: O transporte MUST se comportar como o do passageiro: ping periódico de 30 s para detectar conexão
  morta sem aviso, prazo de handshake de 10 s e fechamento imediato do socket que chegar depois do prazo.
- **FR-003**: A implementação nova MUST satisfazer a interface `RelayGateway` existente (`connect`, `disconnect`,
  `probe`, `connectionLost`, `subscribe`, `setRideRequestCells`, `publish`) sem exigir mudança de comportamento em
  `RelayService`, `EventFeed`, `RelayHostCore`, `RemoteRelayConnection` nem nas telas.
- **FR-004**: O motorista MUST montar e interpretar os frames `REQ`, `CLOSE`, `EVENT`, `OK`, `NOTICE`, `EOSE` e
  `CLOSED`, nos moldes do passageiro e do contrato.
- **FR-005**: Os filtros de inscrição MUST ser idênticos aos atuais: os kinds consumidos exceto `20001` num filtro
  sempre presente; o `20001` num filtro à parte, com `#g`, só com o motorista online; todos com `#t` do marcador e
  `limit: 50`; nunca `since`.
- **FR-006**: A troca de células (`setRideRequestCells`) MUST refazer a inscrição **só** do `20001` em cada relay
  conectado, sem perder a dos demais kinds, e valer para relays que conectarem depois.
- **FR-007**: A inscrição MUST ser refeita a cada conexão (re)estabelecida.
- **FR-008**: A sonda de vivacidade (`probe`) MUST completar com **qualquer** mensagem recebida do relay e falhar
  de imediato quando não há conexão registrada; o prazo é do chamador.
- **FR-009**: `connectionLost` MUST emitir a url uma única vez por queda de conexão **já estabelecida**, depois de
  o transporte descartar a conexão, e MUST NOT emitir em desconexão pedida nem em falha de handshake.
- **FR-010**: Uma tentativa de conexão cancelada ou substituída durante o handshake MUST fechar a própria conexão e
  não se registrar.
- **FR-011**: `publish` MUST reportar, por relay, aceito ou recusado, com a mensagem do relay quando houver, e
  MUST encerrar por prazo quando o relay não responde ao `EVENT`; o evento enviado é o `payload` já assinado, sem
  reassinatura.
- **FR-012**: Frames malformados, truncados, de tipo desconhecido, acima do limite de tamanho ou com tag mal
  formada recusada pelo relay MUST NOT derrubar a conexão nem lançar para fora do transporte.
- **FR-013**: A verificação do evento recebido MUST continuar a mesma: assinatura primeiro, deduplicação por `id`
  depois, conteúdo como dado, kind desconhecido ignorado. O transporte entrega o payload bruto (`IncomingEvent`) e
  não verifica nem filtra por conteúdo.
- **FR-014**: `dart_nostr` MUST permanecer no `pubspec.yaml` apenas para chaves, assinatura e verificação: depois da
  troca, só `identity_service.dart`, `event_verifier.dart`, `ride_rating_signature.dart` e `receipt_signature.dart`
  o importam. Nenhuma dependência nova.
- **FR-015**: Tipos de transporte (`dart:io`, `WebSocket`) MUST ficar confinados a `lib/services`; `lib/domain` não
  os importa (Princípio III). O serviço em segundo plano (feature 025) continua sem acesso à chave privada.
- **FR-016**: Os testes do transporte MUST rodar sem rede e sem relay real, com dublê de socket injetado, e MUST
  existir junto do código (Princípio II).
- **FR-017**: A documentação que descreve `dart_nostr` como transporte (`CLAUDE.md`, comentário de
  `relay_gateway.dart`, constituição se citar) MUST ser atualizada, em commit separado, ao final.

### Entidades

- **Transporte de relay**: abre uma conexão WebSocket com prazo, expõe mensagens de texto recebidas e aceita envio;
  fecha. Não conhece o protocolo Nostr.
- **Conexão de relay (por url)**: o socket vigente, a tentativa de conexão que a originou, a sonda pendente e a
  inscrição aberta. Uma por url.
- **Inscrição**: conjunto de filtros enviados em `REQ` e identificador da inscrição; refeita a cada conexão e a
  cada troca de células.
- **Resultado de publicação**: `PublishOutcome` por relay (já existente).

## Critérios de sucesso

- **SC-001**: `flutter analyze` termina sem apontamentos e `flutter test` passa integralmente, sem teste ignorado.
- **SC-002**: Cada comportamento listado em FR-002 a FR-012 tem ao menos um teste automatizado sem rede, cobrindo
  caso válido e inválido: handshake com sucesso, falha e prazo; socket tardio fechado; `EVENT` malformado ou
  truncado descartado; `OK` aceito e recusado com mensagem; publicação sem resposta; queda estabelecida emite uma
  única vez; desconexão pedida não emite; sonda responde com qualquer mensagem e falha sem conexão; troca de
  células refaz só o `20001` e vale para relay tardio; limite de tamanho e tag recusada não derrubam a conexão.
- **SC-003**: Em emulador, com relays públicos e o app do passageiro, o fluxo completo de uma corrida (`20001` a
  `20015`) é concluído sem falha atribuível à troca, e o `quickstart.md` registra método e resultado reais.
- **SC-004**: Em emulador, com a rede desligada por cerca de 25 s durante o fluxo, o app volta a receber eventos
  depois que a rede retorna, sem intervenção do usuário, em até ~65 s após a volta da rede. O teto é **derivado** dos
  parâmetros existentes, não medido: queda ainda não percebida (sonda a cada 30 s + prazo de 10 s = 40 s) mais
  retentativa a cada 15 s e handshake de até 10 s (25 s). O `quickstart.md` registra o método e o tempo observado;
  passar do teto é achado a investigar, não reprovação automática.
- **SC-005**: Nenhum arquivo em `lib/` fora de `identity_service.dart`, `event_verifier.dart`,
  `ride_rating_signature.dart` e `receipt_signature.dart` importa `dart_nostr` após a troca, verificável por
  `grep -rn "import.*dart_nostr" lib` (a busca só por "dart_nostr" pega comentários).
- **SC-006**: Nenhuma medição (latência, tempo de conexão) é citada no TCC sem ter sido refeita com o método
  descrito; números da rodada anterior não são reaproveitados.

## Fora de escopo

Qualquer mudança no app do passageiro; mudança de contrato de eventos; troca da lista de relays; funcionalidade
nova; autenticação NIP-42 e pagamento de relay (a mensagem de recusa continua apenas repassada ao usuário).

## Premissas

- O transporte do passageiro é a referência de comportamento (`../RideRelayPassenger`, `ws_relay_transport.dart` e
  `relay_service.dart`); divergência encontrada ali é registrada, não corrigida nesta feature.
- A política de reconexão (retentativas, estado exibido ao usuário) continua em `RelayService`; o transporte só
  sinaliza queda e falha de conexão.
- O limite de tamanho de mensagem é um valor razoável escolhido no plano e documentado em `research.md`; relays
  públicos costumam limitar eventos a dezenas de KiB.
- A mensagem de erro de conexão exibida ao usuário mantém o texto resumido atual (até 80 caracteres), sem erro
  técnico cru.
- Nenhuma permissão Android nova: o WebSocket já é coberto pela permissão de internet existente.
- O pacote `dart_nostr` continua sendo usado fora do transporte; remover a dependência por inteiro não é objetivo.
