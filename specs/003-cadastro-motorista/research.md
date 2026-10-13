# Phase 0 — Research: Cadastro do Motorista

## D1 — Biblioteca de acesso a SQLite em Flutter (atende FR-011)

**Decision**: adotar **`sqflite` versão `^2.4.4`**.

**Contexto da decisão**: SQLite foi exigido explicitamente pela descrição da feature, não é escolha
desta especificação — só a biblioteca de acesso é. Levantamento feito consultando o índice do pub.dev
(busca por pacotes de banco de dados local para Flutter) e os metadados publicados de cada pacote em
16/09/2026.

### Alternativas avaliadas

| Pacote | Versão | Última publicação | Observações |
|--------|--------|-------------------|-------------|
| **`sqflite`** | 2.4.4 | 2026-09-10 | Plugin de referência para SQLite em Flutter (tekartik). 160/160 pontos no pub.dev, 5.564 likes. API imperativa próxima de SQL puro — sem camada de ORM. |
| `drift` | 2.35.0 | 2026-09-09 | ORM completo sobre SQLite (geração de código, streams reativas, migrações tipadas). Cobre muito mais do que uma única tabela de cadastro precisa: build_runner, arquivos `.g.dart` gerados, uma camada de abstração adicional sobre o próprio SQL. |
| `sqlite3` | 3.6.0 | 2026-09-13 | Bindings FFI diretos ao SQLite, sem a camada de plugin/canal de plataforma do `sqflite`. Mais rápido, mas de nível mais baixo — sem o ciclo de vida de abertura/fechamento de banco por plataforma que o `sqflite` já resolve para Android. |

### Critérios aplicados

1. **Cobertura do caso de uso com a menor superfície** — o cadastro é uma única tabela, sem consulta
   complexa, sem relação entre tabelas e sem necessidade de stream reativa sobre o banco (a tela lê o
   cadastro uma vez na inicialização e volta a ler ao entrar na tela de edição). `sqflite` cobre isso
   com SQL direto; `drift` resolveria o mesmo problema com uma camada de geração de código
   desproporcional ao escopo (Princípio V).
2. **Manutenção ativa** — as três alternativas publicaram em setembro de 2026; nenhuma foi descartada
   por abandono.
3. **Padrão de fato para Android/Flutter** — `sqflite` é o plugin usado pela documentação oficial do
   Flutter para persistência SQL e tem, de longe, a base de adoção mais ampla (5.564 likes contra 11–12
   dos pacotes concorrentes avaliados em D2), o que reduz o risco de abandono súbito.
4. **Nenhuma dependência de teste adicional** — ao contrário de `drift` e `sqlite3`, que tipicamente
   pedem `sqflite_common_ffi` (ou equivalente) para rodar em teste de unidade sem emulador, este projeto
   já resolve esse problema de outra forma (ver D3): os testes não tocam nenhuma das três bibliotecas.

### Riscos assumidos e mitigação

- **Risco de acoplamento**: se `sqflite` se mostrar limitante — por exemplo, se uma migração de esquema
  futura precisar de controle mais fino —, a troca de biblioteca não deve contaminar a UI. **Mitigação**:
  os tipos de `sqflite` ficam confinados a `lib/services/`, atrás de uma interface própria do projeto
  (`CadastroStore`), como já acontece com `flutter_secure_storage` em `key_store.dart` e com
  `shared_preferences` em `key_value_store.dart` (Princípio III).

## D2 — Fonte da lista de UFs e municípios do IBGE (atende FR-003, FR-004)

**Decision**: **não adotar nenhum pacote de terceiros** para a lista de UFs e municípios. A lista de
UFs (fixa, 26 unidades da federação + Distrito Federal) e a lista de municípios por UF (dados do IBGE)
são embutidas no aplicativo como arquivos de dados estáticos gerados uma única vez a partir da fonte
oficial do IBGE, sem chamada de rede em tempo de execução.

**Contexto da decisão**: o `spec.md` já registra, em Assumptions, que a lista de municípios deve ser
embutida e não consultada por rede em tempo real — coerente com FR-016 da feature 002, que trata
ausência de rede como condição esperada do protótipo. Esta seção avalia se algum pacote de terceiros já
publicado atende a esse requisito antes de decidir embuti-la por conta própria.

### Alternativas avaliadas

| Pacote | Versão | Última publicação | Observações |
|--------|--------|-------------------|-------------|
| `estados_municipios` | 2.0.2 | 2023-11-02 | Descrição do próprio pacote: "todas as informações são tiradas da API do IBGE" — depende de `http` e consulta a rede em tempo de execução. **Desqualificado**: contradiz a decisão de funcionar offline. |
| `cidades_estados_ibge` | 0.1.1 | 2023-03-06 | Único candidato genuinamente offline (zero dependências além do próprio Flutter), mas declara `environment: sdk: '>=2.12.0 <3.0.0'` — **incompatível com o SDK Dart `^3.13.3`** deste projeto; `flutter pub get` rejeitaria a resolução de versão. Também não publica desde março de 2023 (~3,5 anos), versão `0.x`. **Desqualificado**: quebraria o build. |
| `brazilian_locations` | 3.4.1 | 2025-08-20 | O mais recentemente mantido dos três, mas depende de `http`, `hive`, `hive_generator`, `build_runner` e `path_provider`, e se registra como *plugin* Flutter com código nativo próprio para Android/iOS/Linux/macOS/Windows/Web. Superfície desproporcional a uma lista estática de UF/município: geração de código, cache em banco NoSQL embutido e possível busca em rede, para resolver algo que é dado fixo. **Desqualificado** por Princípio V (estrutura sem consumidor proporcional ao problema). |

### Critérios aplicados

1. **Funcionar sem rede é inegociável aqui** — eliminou `estados_municipios` de imediato.
2. **Compatibilidade com o SDK do projeto** — eliminou `cidades_estados_ibge`, que quebraria a
   resolução de dependências antes mesmo de chegar a rodar.
3. **Simplicidade proporcional (Princípio V)** — o dado em questão é uma lista estática de ~5.570
   municípios agrupados por UF, que não muda durante a vida do protótipo. Nenhuma das bibliotecas
   restantes (`brazilian_locations`) resolve isso com menos superfície do que um arquivo de dados
   próprio; pelo contrário, adiciona geração de código e um banco NoSQL embutido para o mesmo fim.
4. **Rastreabilidade acadêmica** — um arquivo de dados gerado por este projeto, com a fonte e a data da
   consulta ao IBGE documentadas, é mais fácil de auditar na monografia do que a versão interna de dados
   de um pacote de terceiros não versionado para esse fim.

### Como a lista é obtida

- Fonte oficial: [API de Localidades do IBGE](https://servicodados.ibge.gov.br/api/docs/localidades),
  endpoint de municípios por UF (`/api/v1/localidades/estados/{UF}/municipios`), consultada uma única
  vez durante a fase de implementação desta feature.
- O resultado (nome e código IBGE de cada município, agrupado por UF) é salvo como arquivo de dados no
  próprio repositório (`lib/services/ibge_municipios.dart` ou asset equivalente — detalhado em
  `data-model.md`), com a data da consulta registrada em comentário no arquivo.
- Se o IBGE alterar sua divisão municipal no futuro (criação/extinção de município), a lista **não** se
  atualiza sozinha — é uma limitação aceita do protótipo, documentada aqui, e não do escopo desta
  feature corrigir.

### Riscos assumidos e mitigação

- **Risco de defasagem**: a lista embutida fica desatualizada se o IBGE alterar a divisão municipal.
  **Mitigação**: mudanças de divisão municipal são raras e não afetam a viabilidade do protótipo — o
  objetivo é validar o fluxo de cadastro, não manter um cadastro nacional sempre atualizado.
- **Risco de tamanho do binário**: ~5.570 municípios como texto simples (nome + UF) somam poucas
  centenas de KB — desprezível frente ao tamanho já ocupado pelo motor Flutter/Dart no APK.

## D3 — Formato de validação da placa (atende FR-005)

**Decision**: aceitar os dois formatos de placa vigentes no Brasil, normalizados para caixa alta e sem
separador antes da validação:

- Formato antigo: 3 letras seguidas de 4 dígitos (`LLLNNNN`).
- Formato Mercosul: 3 letras, 1 dígito, 1 letra, 2 dígitos (`LLLNLN N`, ou seja, `LLL` + `N` + `L` + `NN`).

Como as duas formas têm exatamente 7 caracteres e diferem apenas no 5º caractere (dígito no formato
antigo, letra no Mercosul), a validação usa uma única expressão regular:
`^[A-Z]{3}[0-9][A-Z0-9][0-9]{2}$`.

**Contexto da decisão**: o Brasil concluiu a transição para o padrão Mercosul, mas veículos emplacados
antes da transição continuam circulando com o formato antigo — um motorista real pode ter qualquer um
dos dois. Recusar o formato antigo excluiria veículos genuinamente válidos; aceitar só o Mercosul sem o
antigo não corresponde à frota real em circulação.

**Riscos assumidos e mitigação**: nenhuma dependência de terceiros é necessária — a validação é uma
expressão regular avaliada em `lib/domain/`, sem custo de manutenção externo.

## Resumo das decisões

| # | Decisão | Tipo |
|---|---------|------|
| D1 | `sqflite ^2.4.4` para acesso a SQLite | Dependência de terceiros adicionada |
| D2 | Lista de UFs e municípios do IBGE embutida como dado estático do projeto, sem pacote de terceiros e sem chamada de rede | Decisão de **não** adicionar dependência |
| D3 | Validação de placa aceita os formatos antigo e Mercosul, por expressão regular própria | Decisão de domínio, sem dependência |
| D4 | `path ^1.9.1` para montar o caminho do arquivo SQLite | Dependência de terceiros adicionada |

## D4 — Pacote `path` para montar o caminho do banco (atende FR-011)

**Decision**: adotar **`path` versão `^1.9.1`** (mantido pela própria equipe do Dart/Google,
`dart.dev/tools/pub/environment-variables`), para montar de forma portável o caminho do arquivo
SQLite (`path.join(await getDatabasesPath(), 'cadastro_motorista.db')`).

**Contexto da decisão**: `sqflite` já traz `path` como dependência transitiva (`>=1.8.0 <3.0.0`), mas
`openDatabase` exige um caminho de arquivo montado por quem chama — `path` é o utilitário padrão para
isso, evitando concatenação manual de string sensível ao separador de diretório da plataforma.

**Alternativas avaliadas**: nenhuma outra foi considerada — `path` é o pacote de referência do próprio
time do Dart para essa tarefa, sem substituto genuinamente concorrente no ecossistema; concatenar a
string manualmente seria estritamente pior (não portável) sem nenhum ganho de simplicidade.

**Riscos assumidos e mitigação**: nenhum — é uma função utilitária pura, sem estado e sem
superfície de API a que a aplicação fique acoplada.
