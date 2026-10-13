# Feature Specification: Aplicativo Mobile Base (Motorista)

**Feature Branch**: `001-flutter-app-base`

**Created**: 2026-09-15

**Status**: Draft

**Input**: User description: "Crie um app mobile vazio usando Flutter."

## Clarifications

### Session 2026-09-15

- Q: Qual o escopo de plataformas que o app base deve suportar/validar nesta etapa? → A: Android apenas
- Q: Qual identificador de aplicativo e nome de exibição usar para o app do motorista? → A: `br.ufsc.tcc.caronas.driver`, nome de exibição "Caronas Motorista"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Executar o aplicativo base em um dispositivo (Priority: P1)

Como desenvolvedor do protótipo, quero um aplicativo mobile mínimo que compile e abra em um
dispositivo/emulador, exibindo uma tela inicial vazia identificada como o app do motorista, para que
exista uma base verificável sobre a qual as funcionalidades de caronas via Nostr serão construídas.

**Why this priority**: Sem um app que comprovadamente inicia, nenhuma funcionalidade posterior pode ser
desenvolvida ou demonstrada. É o esqueleto que viabiliza todo o restante do protótipo.

**Independent Test**: Pode ser testado integralmente instalando o aplicativo em um emulador ou aparelho
físico e verificando que ele abre sem erros, exibindo a tela inicial com o nome do aplicativo.

**Acceptance Scenarios**:

1. **Given** um emulador/dispositivo compatível conectado, **When** o aplicativo é compilado e instalado,
   **Then** ele inicia sem falhas e exibe a tela inicial vazia com o título do aplicativo.
2. **Given** o aplicativo aberto, **When** o usuário o coloca em segundo plano e retorna a ele,
   **Then** o aplicativo permanece na mesma tela, sem travar ou reiniciar.
3. **Given** o aplicativo instalado, **When** o usuário o localiza na lista de aplicativos do sistema,
   **Then** ele aparece com o nome de exibição "Caronas Motorista".

---

### User Story 2 - Reproduzir o ambiente de desenvolvimento a partir do repositório (Priority: P2)

Como avaliador ou colaborador do trabalho, quero obter o repositório e executar o aplicativo seguindo
instruções documentadas, para confirmar que o protótipo é reprodutível.

**Why this priority**: Reprodutibilidade é requisito do TCC (prova de conceito verificável por terceiros),
mas depende de a User Story 1 já existir.

**Independent Test**: Pode ser testado em uma máquina limpa, clonando o repositório e seguindo o
passo a passo documentado até o aplicativo abrir.

**Acceptance Scenarios**:

1. **Given** uma máquina com o ambiente de desenvolvimento mobile instalado, **When** o colaborador segue
   as instruções do repositório, **Then** o aplicativo é compilado e executado sem passos adicionais
   não documentados.
2. **Given** o repositório clonado, **When** a verificação automatizada de sanidade é executada,
   **Then** ela conclui com sucesso indicando que o projeto está íntegro.

---

### User Story 3 - Verificação automatizada mínima (Priority: P3)

Como desenvolvedor, quero uma verificação automatizada mínima que confirme que a tela inicial é
construída corretamente, para detectar quebras na base antes de adicionar novas funcionalidades.

**Why this priority**: Aumenta a confiança em mudanças futuras, mas não é necessária para a base existir.

**Independent Test**: Pode ser testado executando a suíte de testes do projeto e observando que o teste
da tela inicial passa.

**Acceptance Scenarios**:

1. **Given** o projeto íntegro, **When** a suíte de testes é executada, **Then** todos os testes passam.
2. **Given** a tela inicial alterada de forma incorreta, **When** a suíte de testes é executada,
   **Then** a falha é reportada.

### Edge Cases

- O que acontece quando o ambiente de desenvolvimento não possui SDK/toolchain mobile configurado?
  A verificação de sanidade deve apontar explicitamente o que falta, em vez de falhar de forma obscura.
- Como o aplicativo se comporta em telas muito pequenas ou com fonte do sistema ampliada?
  A tela inicial não deve apresentar sobreposição ou conteúdo cortado.
- Como o aplicativo se comporta sem conectividade de rede? Deve iniciar normalmente, pois a base não
  depende de rede.
- O que acontece ao alternar entre tema claro e escuro do sistema? A tela inicial deve permanecer legível.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: O projeto MUST conter um aplicativo mobile executável, residente em `Prototipo/driver`,
  correspondente ao aplicativo do motorista.
- **FR-002**: O aplicativo MUST iniciar em uma única tela inicial, sem funcionalidades de negócio,
  exibindo apenas a identificação do aplicativo.
- **FR-003**: O aplicativo MUST ser identificado no sistema operacional pelo nome de exibição
  "Caronas Motorista" e pelo identificador de aplicativo `br.ufsc.tcc.caronas.driver`.
- **FR-004**: O aplicativo MUST executar em dispositivos Android. Android é a única plataforma no
  escopo desta etapa: iOS, web e desktop estão explicitamente fora de escopo e nenhum artefato de
  projeto para essas plataformas deve ser mantido no repositório.
- **FR-005**: O aplicativo MUST NOT solicitar permissões do sistema, acessar rede ou persistir dados
  nesta etapa.
- **FR-006**: O repositório MUST documentar os comandos para instalar dependências, executar o
  aplicativo e rodar a verificação automatizada.
- **FR-007**: O projeto MUST incluir ao menos uma verificação automatizada que valide a construção da
  tela inicial.
- **FR-008**: O repositório MUST ignorar artefatos gerados de build, mantendo versionado apenas o código
  e a configuração do projeto.
- **FR-009**: A estrutura do projeto MUST permitir que o aplicativo do passageiro seja criado de forma
  independente em `Prototipo/passenger`, sem acoplamento entre os dois aplicativos.

### Key Entities

Não aplicável nesta etapa: o aplicativo base não modela nem persiste dados de domínio.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Um desenvolvedor com o ambiente mobile já configurado consegue executar o aplicativo em um
  emulador em menos de 10 minutos a partir do clone do repositório, seguindo apenas a documentação.
- **SC-002**: O aplicativo abre e exibe a tela inicial em até 5 segundos após o lançamento, em 100% das
  tentativas em um dispositivo/emulador de referência.
- **SC-003**: A verificação automatizada do projeto conclui com 100% de sucesso e sem avisos de
  configuração pendente.
- **SC-004**: A tela inicial é exibida sem conteúdo cortado nos temas claro e escuro e em ao menos duas
  resoluções de tela Android distintas.
- **SC-005**: Nenhuma permissão do sistema é solicitada ao usuário durante a primeira execução.

## Assumptions

- O aplicativo é construído com Flutter/Dart, conforme solicitado explicitamente pelo usuário, e este é
  o único requisito tecnológico imposto nesta etapa.
- O aplicativo do passageiro usará o identificador irmão `br.ufsc.tcc.caronas.passenger`, mantendo o
  namespace `br.ufsc.tcc.caronas`; sua criação está fora do escopo desta feature.
- O alvo é exclusivamente Android (emulador ou aparelho físico), decidido na clarificação: não há
  hardware Apple disponível no contexto do trabalho e web/desktop não agregam à prova de conceito.
  Um eventual suporte a iOS seria adicionado como feature própria no futuro.
- "Vazio" significa uma única tela sem lógica de negócio, e não a ausência de estrutura de projeto,
  documentação ou teste de sanidade.
- Não há backend próprio nem integração com relays Nostr nesta etapa; a comunicação via Nostr será
  especificada em features posteriores.
- Identidade visual (ícone e tema definitivos) fica fora de escopo nesta etapa, usando os padrões do
  framework.
- O ambiente de desenvolvimento é Linux, coerente com a máquina utilizada no trabalho.
