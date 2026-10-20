# Phase 0 — Research: Conexão do Motorista com Relays Nostr

## D1 — Biblioteca Nostr para Dart/Flutter (atende FR-017 e SC-008)

**Decision**: adotar **`dart_nostr` versão `^10.0.1`** (instalada em 15/09/2026).

**Contexto da decisão**: a instalação foi determinada pelo autor antes desta especificação; este
documento registra a fundamentação, as alternativas efetivamente disponíveis e os critérios aplicados,
como exige FR-017. O levantamento foi feito consultando o índice do pub.dev (busca por "nostr") e os
metadados publicados de cada pacote em 15/09/2026.

### Alternativas avaliadas

| Pacote | Versão | Última publicação | Observações |
|--------|--------|-------------------|-------------|
| **`dart_nostr`** | 10.0.1 | 2026-04-23 | API de alto nível orientada a clientes ("develop scalable Dart/Flutter Nostr clients"); cobre chaves, assinatura, eventos e gestão de relays em um único pacote. Dependências: `bip340`, `bip39`, `bip32_bip44`, `bech32`, `crypto`, `pointycastle`, `web_socket_channel`. |
| `nostr` | 2.0.0 | 2026-05-22 | Biblioteca pura em Dart, **transport-agnostic**: cobre 35+ NIPs, incluindo NIP-44 e gift wrap, mas **não gerencia as conexões WebSocket** — o cliente precisa implementar a camada de transporte e a política de reconexão. |
| `ndk` (Nostr Development Kit) | 0.9.3 | 2026-09-04 | O mais ativamente mantido (publicado há dias) e o mais completo: cache, estratégias de relay, outbox model. Em contrapartida, é o de maior superfície conceitual e exige SDK Dart ≥ 3.6.0. Versão ainda **0.x**, com API sujeita a quebras. |
| `nostr_tools` | 1.0.9 | 2023-08-27 | **Sem publicação há cerca de 3 anos**. Descartado por risco de abandono e de incompatibilidade com Dart 3.13. |

### Critérios aplicados

1. **Cobertura do caso de uso com a menor superfície** — a feature precisa de chaves, assinatura,
   verificação, conexão a múltiplos relays e inscrição para receber eventos. `dart_nostr` entrega esse conjunto
   completo; `nostr` deixaria a camada de transporte e a reconexão (FR-014) por conta do protótipo.
2. **Manutenção ativa** — publicações em 2026 eliminam `nostr_tools`.
3. **Estabilidade de API** — `dart_nostr` está em versão maior estável (10.x); `ndk` ainda é 0.x, e
   quebras de API durante a redação de um TCC custam caro.
4. **Custo de aprendizado proporcional ao escopo** — o trabalho investiga a **viabilidade do protocolo**,
   não o desempenho de um cliente avançado. Recursos do `ndk` (cache, outbox model) não são exercidos
   pelos requisitos desta feature e adicionariam conceitos a explicar na monografia sem retorno.
5. **Verificação prática antes de assumir** — a biblioteca foi exercitada no projeto antes de ser aceita:
   `Nostr.instance.services.keys.generateKeyPair()` gerou um par de chaves hexadecimais de 64 caracteres
   em teste executado localmente, e `flutter analyze`/`flutter test` seguiram limpos após a instalação.

### Riscos assumidos e mitigação

- **Risco de acoplamento**: se `dart_nostr` se mostrar limitante (ex.: NIP-44 para mensagens privadas
  entre motorista e passageiro), a troca de biblioteca não deve contaminar a UI. **Mitigação**: os tipos
  da biblioteca ficam confinados a `lib/services/`; `lib/domain/` usa tipos próprios, e as telas nunca
  importam `dart_nostr` diretamente.
- **Risco de cobertura de NIPs**: a criptografia de conteúdo (NIP-44), necessária nas features futuras de
  comunicação privada, precisa ser confirmada nesta biblioteca. **Mitigação**: verificar antes da feature
  de mensagens privadas; se ausente, `nostr` (2.0.0) é a alternativa documentada, e é compatível com
  manter `dart_nostr` só no transporte.
- **Risco acadêmico**: a escolha de uma única biblioteca não deve ser lida como conclusão do trabalho
  sobre o ecossistema. **Mitigação**: esta tabela de alternativas é insumo direto da seção de resultados
  do TCC — o estado do ecossistema Dart/Nostr (poucos pacotes, um deles abandonado, o mais completo
  ainda em 0.x) é, por si só, um achado relevante sobre a maturidade do protocolo fora do JavaScript.

**Alternatives considered**: implementar o protocolo do zero sobre `web_socket_channel` + `bip340` —
descartado: reimplementar assinatura Schnorr e serialização canônica de eventos é fonte de erro
criptográfico e consumiria o tempo do TCC sem contribuir para a pergunta de pesquisa.

## D2 — Armazenamento da chave privada

**Decision**: `flutter_secure_storage`, que no Android usa o **Keystore** do sistema.

**Rationale**: FR-005 exige armazenamento protegido; SC-007 exige que a chave não apareça em log nem em
tela. Preferências simples (`shared_preferences`) gravam em XML legível por qualquer processo com acesso
ao diretório do app em aparelhos com root — inadequado para chave privada.

**Alternatives considered**: guardar a chave em `shared_preferences` — rejeitado pelo motivo acima;
derivar a chave de uma senha do usuário a cada abertura — rejeitado por adicionar fluxo de UI e risco de
perda de identidade, fora do escopo clarificado.

## D3 — Persistência da lista de relays

**Decision**: `shared_preferences`, armazenando a lista como JSON.

**Rationale**: endereços de relays são dados públicos e não sensíveis; o volume é pequeno e o acesso é
raro. Um banco de dados seria estrutura sem consumidor.

**Alternatives considered**: mesmo armazenamento seguro da chave — rejeitado por misturar dados de
sensibilidade distinta e pagar custo de Keystore sem necessidade; arquivo próprio em disco — equivalente
com mais código.

## D4 — Deduplicação de eventos entre relays

**Decision**: deduplicar pelo **identificador do evento** (hash canônico definido pelo protocolo),
mantendo em memória um conjunto dos identificadores já exibidos na sessão.

**Rationale**: atende FR-010 sem persistência. O identificador é derivado do conteúdo do evento, logo o
mesmo evento entregue por dois relays tem o mesmo identificador, e eventos distintos não colidem.

**Alternatives considered**: deduplicar por (autor + horário) — rejeitado por gerar falsos positivos em
eventos legítimos publicados no mesmo segundo.

## D5 — Estratégia de teste sem relay real

**Decision**: os serviços recebem suas dependências por injeção (armazenamento e transporte de relay), e
os testes usam dublês em memória. Nenhum teste automatizado contata relay público.

**Rationale**: testes que dependem de relay público são lentos, intermitentes e falham sem rede — e
tornariam SC-003 (relay inalcançável) impossível de reproduzir de forma determinística. A validação
contra relays reais fica no `quickstart.md`, como roteiro manual.

**Alternatives considered**: teste de integração contra relay público em CI — rejeitado pela
intermitência; subir um relay local em contêiner — desproporcional para o protótipo, e registrado como
opção caso as features seguintes exijam cenários multi-cliente.

## D6 — Permissão de rede no manifesto principal

**Decision**: declarar `android.permission.INTERNET` em
`android/app/src/main/AndroidManifest.xml`.

**Rationale**: hoje a permissão só existe nos manifestos de `debug`/`profile`, herdados do scaffold do
Flutter. Sem ela no manifesto principal, a build de release falharia ao abrir a conexão com o relay —
justamente o cenário de demonstração do trabalho. É permissão normal, concedida na instalação, sem
diálogo para o usuário.

**Alternatives considered**: nenhuma; é requisito técnico do Android para qualquer acesso de rede.

## D7 — Lista padrão de relays

**Decision**: embutir uma lista inicial de 3 relays públicos, gratuitos e sem exigência de autenticação,
confirmando a disponibilidade de cada um no momento da implementação (a lista é volátil por natureza).

**Rationale**: três relays permitem observar o comportamento multi-relay exigido por FR-003/SC-003 sem
sobrecarregar a interface. A lista fica em uma constante única, facilitando a substituição quando um
relay sair do ar.

**Alternatives considered**: um único relay — não exercita o comportamento distribuído, que é o objeto do
estudo; dezenas de relays — ruído sem ganho analítico e risco de esgotar conexões no aparelho.

## D8 — Armazenamento seguro da chave privada (biblioteca)

**Decision**: `flutter_secure_storage ^11.1.1`.

**Contexto**: registrado em 15/09/2026, **antes** da instalação, conforme o Princípio III da constituição.
Levantamento feito no pub.dev na mesma data.

| Pacote | Versão | Publicação | Publisher | Likes | Observações |
|--------|--------|-----------|-----------|-------|-------------|
| **`flutter_secure_storage`** | 11.1.1 | 2026-09-11 | steenbakker.dev | 4.488 | Usa **Android Keystore** via `EncryptedSharedPreferences`; 160/160 pontos no pub; publicação há dias |
| `hive_ce` | 2.20.0 | 2026-09-12 | iodesignteam.com | 565 | Banco local com criptografia opcional — **a chave de criptografia precisaria ser guardada em outro lugar**, o que recria o problema em vez de resolvê-lo |
| `get_storage` | 2.1.1 | 2023-02-27 | — | — | **Sem publicação desde 2023** e sem criptografia; descartado |

**Rationale**: é o único candidato que delega a proteção ao **Keystore do sistema operacional**, em vez de
guardar bytes cifrados por uma chave que o próprio app teria de guardar. O Princípio I exige armazenamento
protegido do SO; os outros dois não atendem essa condição, independentemente de qualidade.

**Riscos assumidos e mitigação**: o plugin depende de implementação nativa por plataforma — restrição
irrelevante aqui, já que o alvo é só Android (feature 001). Acoplamento mitigado pelo Princípio III: o
`IdentityService` recebe o armazenamento por injeção, atrás de uma interface do projeto, de modo que os
testes usam dublê em memória e a troca de plugin não toca a UI.

**Alternatives considered**: `shared_preferences` para a chave privada — rejeitado, grava XML legível por
qualquer processo com acesso ao diretório do app em aparelho com root; implementar criptografia própria
sobre arquivo — rejeitado, é justamente o tipo de código criptográfico artesanal que o Princípio II trata
como fonte de erro silencioso.

## D9 — Persistência da lista de relays (biblioteca)

**Decision**: `shared_preferences ^2.5.5`.

**Contexto**: registrado em 15/09/2026, **antes** da instalação (Princípio III).

| Pacote | Versão | Publicação | Publisher | Likes | Observações |
|--------|--------|-----------|-----------|-------|-------------|
| **`shared_preferences`** | 2.5.5 | 2026-03-25 | **flutter.dev** | 10.568 | Mantido pelo próprio time do Flutter; 160/160 pontos; API mínima para chave-valor |
| `hive_ce` | 2.20.0 | 2026-09-12 | iodesignteam.com | 565 | Banco completo com consultas e índices — capacidade sem consumidor para uma lista de 3 a 10 endereços |
| `flutter_secure_storage` | 11.1.1 | 2026-09-11 | steenbakker.dev | 4.488 | Já estará no projeto, mas pagaria custo de Keystore para dado público |

**Rationale**: a lista de relays é **dado público e de baixo volume**. Usar o mesmo armazenamento seguro da
chave privada misturaria dados de sensibilidade distinta no mesmo lugar, o que atrapalha auditar depois o
que é segredo e o que não é. Um banco embarcado seria estrutura sem consumidor, proibida pelo Princípio V.

**Riscos assumidos e mitigação**: `shared_preferences` não é transacional — uma escrita interrompida pode
deixar a lista parcialmente gravada. Mitigação: a lista é serializada como **um único valor JSON**, de modo
que a escrita é atômica do ponto de vista da aplicação. O `RelayRepository` também recebe o armazenamento
por injeção, permitindo dublê nos testes.

**Alternatives considered**: arquivo JSON próprio em disco — equivalente funcional com mais código de I/O e
tratamento de erro; não persistir e reconstruir a lista padrão a cada abertura — rejeitado por FR-012.

## D10 — Endereços da lista padrão de relays

**Decision (revisada em 16/09/2026)**: `wss://nos.lol`, `wss://relay.primal.net` e
`wss://offchain.pub`. Lista **idêntica à da app do passageiro**, por obrigação de simetria.

### Revisão D10-R1 — verificação por publicação, e remoção do relay.damus.io

A verificação original (15/09/2026) usou apenas o documento NIP-11: os três relays de então responderam
HTTP 200 sem exigir pagamento nem autenticação. **NIP-11 prova que o relay responde HTTP, não que ele
aceita conexão WebSocket nem publicação de eventos** — e foi por essa brecha que `relay.damus.io`
entrou na lista.

Verificação refeita em 16/09/2026 publicando um evento assinado e recuperando-o por uma **conexão
separada**, que é a mecânica real da interoperabilidade entre as duas apps:

| Relay | Aceita publicação | Ida e volta entre conexões | Situação |
|---|---|---|---|
| `wss://nos.lol` | ✓ 377 ms | ✓ 1255 ms | **adotado** |
| `wss://relay.primal.net` | ✓ 224 ms | ✓ 1330 ms | **adotado** |
| `wss://offchain.pub` | ✓ 174 ms | ✓ 892 ms | **adotado** |
| `wss://nostr.mom` | ✓ 287 ms | não testado | reserva verificada |
| `wss://relay.damus.io` | **falhou 1 de 3 tentativas** | — | **removido** |

`relay.damus.io` é o relay mais difundido do ecossistema e, ainda assim, recusou a conexão em uma de
três tentativas consecutivas, tendo respondido normalmente minutos antes. Mantê-lo na lista padrão
injetaria ruído nas medições de SC-001 e SC-009 — um relay que falha um terço das vezes tornaria
ambíguo se um resultado ruim vem do protocolo ou daquele operador.

**Achado para a monografia**: a volatilidade da infraestrutura pública é resultado relevante por si só.
Dos relays sondados, um não respondeu, um exigia pagamento e o mais conhecido mostrou-se intermitente
entre duas execuções separadas por minutos. Sustentar um aplicativo de corridas sobre relays abertos de
terceiros implica conviver com isso — o que justifica FR-003 (falha de um relay não derruba os demais)
como requisito, e não como refinamento.

**Descartado antes**: `nostr.wine` declara `payment_required` — publicar exigiria conta paga, o que
quebraria FR-007 para o avaliador do TCC; `relay.nostr.band` não respondeu dentro de 8 s, e voltou a
não responder na verificação de 16/09.

**Obrigação de simetria**: esta lista MUST permanecer idêntica à de
`Prototipo/passenger/lib/shared/default_relays.dart`. É o relay em comum que torna possível o
passageiro receber o que o motorista publica; listas disjuntas fariam o experimento central falhar por
configuração, não por limitação do protocolo.

**Rationale**: três relays de operadores distintos permitem observar o comportamento multi-relay exigido
por FR-003/SC-003. A lista é volátil por natureza — relays saem do ar —, por isso fica em constante única
(`lib/services/default_relays.dart`) e o app trata `unavailable` como estado normal, não como erro fatal.
