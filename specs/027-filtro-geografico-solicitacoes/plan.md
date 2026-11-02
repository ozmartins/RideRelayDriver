# Plano de implementação: 027-filtro-geografico-solicitacoes

**Spec**: [spec.md](spec.md) · **App**: `driver/` · **Data**: 2026-10-21 · **Entrada**: pedido "filtro geográfico de solicitações de corrida"

## Resumo

O motorista passa a (1) informar um **raio de atendimento** (1–100 km, padrão 10) na etapa 1 do cadastro; (2) ao ficar
online, fixar a posição do momento como **referência** do raio, só em memória; (3) inscrever-se no `kind: 20001`
com um filtro `#g` de 9 células de geohash (a da referência e as 8 vizinhas, numa precisão derivada do raio);
(4) validar na recepção, antes de deduplicar, que o evento traz uma tag `g` numa das células e que a `origin` do
`content` está dentro do raio (Haversine). O contrato muda (emenda 27: tag `g` em três precisões no `20001`, inscrição
do motorista em dois filtros, regra de recepção 8), então a especificação do contrato vem antes do código e é
replicada no passageiro na mesma alteração. Há uma **emenda da constituição (2.18.0)** antes do código, porque o
serviço em segundo plano passa a receber a posição de referência. Sem dependência nova: geohash em casa.

## Contexto técnico

- **Linguagem/SDK**: Dart ^3.13.3, Flutter 3.47.7, Android apenas.
- **Dependências**: nenhuma nova (R1 do research). `dart_nostr` já suporta `NostrFilter.additionalFilters` para o
  `#g`; só `nostr_relay_gateway.dart` o usa.
- **Armazenamento**: `cadastro_motorista.db` v5 → v6 (coluna com `DEFAULT 10`). A cobertura não é persistida.
- **Testes**: `flutter_test` com dublês; nenhum teste toca SQLite, relay, plugin ou rede reais. Vetores de geohash
  compartilhados com o passageiro em `test/fixtures/geohash_vectors.json`, gerados por `tool/gen_geohash_vectors.dart`.
- **Alvo**: Android. Sem permissão nova (a localização já é usada pela 004).
- **Restrições**: tag `t` continua em tudo; assinatura verificada antes de tudo; conferência geográfica **antes** da
  deduplicação; `content` é dado; raio e referência nunca em evento, log, notificação nem armazenamento.
- **Escala**: ≤ 9 valores no `#g`; duas tags a mais por `20001` (~20 bytes cada).

## Verificação da constituição (2.17.0)

| Princípio / restrição | Situação |
|---|---|
| I — segredo não vaza | Sem material criptográfico novo. A posição de referência é dado pessoal, não segredo criptográfico; seu vazamento é coberto por FR-004/FR-005 e pelo cenário 9 do quickstart. |
| II — assinatura nasce com teste | Nenhuma assinatura nova. A regra "descarta mensagem" nasce com teste (CLAUDE.md): `DriverCoverage.evaluateRideRequest`, `RideRequestFilter`, `EventFeed` e `RelayHostCore`, caso aceito e recusado, sem rede. |
| III — dependência registrada | Sem dependência nova; R1 registra a escolha por geohash em casa e as alternativas. `domain/` não importa terceiros; `dart_nostr` só em `nostr_relay_gateway.dart`. |
| IV — contrato antes do código | [contracts/emenda-27-tag-g.md](contracts/emenda-27-tag-g.md) escreve a emenda antes do código; a tarefa de contrato precede toda tarefa de código e é replicada no passageiro na mesma alteração. Ordem de recepção (assinatura → marcador → geografia → deduplicação) respeita "assinatura primeiro". |
| V — simplicidade | `DriverCoverage` tem consumidores imediatos (inscrição, `EventFeed`, serviço, filtro). Nenhuma abstração sem segunda implementação: `RelayGateway`/`RelayConnection` já têm duas. Decisões não óbvias em `research.md` (R2, R3, R5). |
| Permissões | Nenhuma nova. |
| Localização (restrições de privacidade) | A posição já é lida pela 004; o uso novo (referência do raio) e seu tempo de vida (de "ficar online" a "ficar offline", só em memória) estão descritos em FR-005 e R5. |
| Dado pessoal em relay | O `#g` revela a região aproximada ao relay (R8); registrado na spec (FR-014) e no `research.md`, como a restrição exige. A `origin` em claro no `20001` já é exceção (emenda 17); a tag não acrescenta nada. |
| **Serviço em segundo plano** | **Gate**: a exceção diz que o serviço "MUST NOT acessar a localização" e que a decisão de notificar "usa apenas dados públicos do evento (kind, autor, tags) e o estado persistido pela interface". Esta feature faz o serviço **receber**, só em memória, a posição de referência e o raio, e ler a `origin` do `content` (público, em claro) para o filtro exato. ⇒ **emenda 2.18.0 da constituição** nas duas apps, em commit separado **antes** do código. Texto proposto abaixo. |
| Identidade visual | O campo novo do cadastro e o aviso de raio seguem `screens/identidade_visual.dart` (mesmo componente dos demais campos da etapa 1). |

**Emenda 2.18.0 (texto proposto, na exceção do serviço em segundo plano, motorista):** "No app do motorista, a
interface pode enviar ao serviço a posição de referência do raio de atendimento e o raio (feature
`027-filtro-geografico-solicitacoes`), exclusivamente para que a decisão de notificar aplique o mesmo filtro
geográfico da interface. O serviço continua sem acessar o sensor de localização: só recebe o que a interface já
tem. Esses valores MUST ficar só em memória — MUST NOT ser gravados em `ServiceStateStore` ou em qualquer
armazenamento, publicados em evento, registrados em log nem exibidos em notificação — e MUST ser descartados quando
o motorista fica offline. Para esse filtro o serviço também lê a `origin` do `content` do `kind: 20001`, que já é
público (exceção do `20001`). O passageiro não muda. Custo aceito: sem a referência (processo morto), o serviço
reinicia sem cobertura e não recebe `20001` até a interface voltar." Passageiro: o texto espelho registra que o
serviço dele não recebe posição; sem emenda funcional, só o espelho do corpo (Governança).

## Estrutura do código

```text
lib/
├── domain/
│   ├── geohash.dart                # novo: encode, neighbors, cellWithNeighbors, isValid, dimensões, kPrecisoesDaTag
│   ├── driver_coverage.dart        # novo: DriverCoverage (around, precisionFor, matchesCells, withinRadius,
│   │                               #   evaluateRideRequest, toJson/fromJson)
│   ├── ride_request_filter.dart    # + coverage; refusals semReferencia e foraDaCobertura
│   ├── driver_profile.dart         # + raioAtendimentoKm, parseRaioKm, constantes; DriverPersonalData + raio
│   └── geo_distance.dart           # (já existe; metersBetween é reutilizada)
├── services/
│   ├── relay_gateway.dart          # + rideRequestCells em subscribe; setRideRequestCells
│   ├── nostr_relay_gateway.dart    # dois filtros; #g via additionalFilters; refaz a inscrição por relay
│   ├── relay_connection.dart       # + coverage, applyCoverage
│   ├── relay_service.dart          # guarda a cobertura e repassa as células ao gateway
│   ├── remote_relay_connection.dart# + applyCoverage → ServiceSetCoverage; reenvia ao ServiceHelloAck
│   ├── event_feed.dart             # + coverage provider; descarte geográfico antes da deduplicação
│   ├── sqflite_cadastro_store.dart # versão 6: coluna raio_atendimento_km DEFAULT 10
│   └── background/
│       ├── service_messages.dart   # + ServiceSetCoverage ('coverage')
│       └── relay_host_core.dart    # guarda a cobertura em memória; aplica à conexão; descarta antes da dedup;
│                                   #   passa coverage ao RideRequestFilter
├── screens/
│   ├── cadastro_screen.dart        # etapa 1: campo "Raio de atendimento (km)"; aviso se online
│   └── map_screen.dart             # cria/anula a cobertura (online/offline/perda de GPS/retomada); passa-a ao
│                                   #   RideRequestFilter e à conexão; reavalia as estacionadas na retomada
└── main.dart                       # EventFeed(coverage: () => _relayService.coverage)
specs/002-nostr-relay-connection/contracts/nostr-events.md   # emenda 27 (colar contracts/emenda-27-tag-g.md)
.specify/memory/constitution.md                               # emenda 2.18.0 (commit separado, antes do código)
tool/gen_geohash_vectors.dart, tool/probe_geohash_filter.dart # vetores e sonda de relay (não fazem parte do app)
test/{domain,services,services/background,screens,fixtures,support}/…   # ver quickstart e tasks
```

**Decisão de estrutura**: arquivos planos, como nas features anteriores; nenhum módulo novo. `ServiceState` e
`ServiceStateStore` **não mudam** (a cobertura é efêmera por construção); o canal ganha uma mensagem própria.
Testes existentes que fazem o motorista online receber solicitação precisam de tag `g` e cobertura: o helper de
teste da solicitação (`test/support`) passa a gerar as três tags `g` por padrão.

## Ordem de entrega (gates)

1. Emenda 2.18.0 da constituição, nas duas apps, **commit próprio** (Governança).
2. Emenda 27 no contrato das duas apps, **commit próprio**, antes do código (Princípio IV).
3. Domínio e testes (`Geohash`, `DriverCoverage`, filtro, cadastro) — puros, sem plugin.
4. Serviços (gateway, conexões, mensagem, `EventFeed`, `RelayHostCore`) e testes.
5. Telas (`MapScreen`, `CadastroScreen`) e testes.
6. Medição do relay (cenário 3 do quickstart) e registro em `research.md`.
7. `CLAUDE.md` atualizado em commit separado, depois da mudança que descreve.

## Complexity Tracking

Nenhuma violação de princípio a justificar. A emenda 2.18.0 é exigida pela constituição, não uma exceção a ela.
Dois pontos para o autor confirmar antes do código: **(a)** tag `g` em três precisões (R2) em vez de uma só;
**(b)** limite conhecido de R5 (processo morto ⇒ sem solicitações até abrir o app).
