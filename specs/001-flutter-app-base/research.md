# Phase 0 — Research: Aplicativo Mobile Base (Motorista)

Nenhum item do Technical Context ficou como NEEDS CLARIFICATION. As decisões abaixo consolidam o que foi
verificado no ambiente real de desenvolvimento e o que foi decidido na clarificação do spec.

## D1 — Versão do Flutter/Dart

- **Decision**: Flutter 3.47.4 (canal stable) com Dart 3.13.3, exatamente a versão já instalada em
  `/home/oseias/development/flutter`.
- **Rationale**: verificado via `flutter --version` na máquina do autor; usar a versão instalada evita
  gastar tempo de TCC com gerenciamento de toolchain. A versão fica registrada no README para
  reprodutibilidade por terceiros (SC-001).
- **Alternatives considered**: fixar via FVM (gerenciador de versões) — descartado como complexidade
  desnecessária para um protótipo com um único desenvolvedor; canal beta/master — descartado por
  instabilidade em trabalho acadêmico avaliado.

## D2 — Escopo de plataformas

- **Decision**: gerar apenas `android/` (`flutter create --platforms android`).
- **Rationale**: decidido na clarificação (Android apenas). `flutter doctor` confirma o Android toolchain
  (SDK 37.0.0) funcional e um emulador disponível (`Pixel_6_API34_1`, API 34), enquanto Chrome e o
  toolchain Linux desktop estão ausentes/quebrados no ambiente — plataformas fora de escopo não
  validáveis não devem entrar no repositório como artefatos mortos (FR-004).
- **Alternatives considered**: gerar todas as plataformas por padrão — descartado por deixar ~5 diretórios
  de build nunca compilados no repositório do TCC; incluir web para demonstração — descartado porque o
  ambiente não tem Chrome configurado e o alvo do trabalho é mobilidade em dispositivo móvel.

## D3 — Identificador e nome do aplicativo

- **Decision**: `--org br.ufsc.tcc.caronas` + nome de projeto `driver` → `applicationId`
  `br.ufsc.tcc.caronas.driver`; nome de exibição "Caronas Motorista" em `android/app/src/main/AndroidManifest.xml`.
- **Rationale**: decidido na clarificação. O `applicationId` é derivado automaticamente por
  `flutter create` a partir de `--org` + nome do projeto, sem edição manual. O par
  `br.ufsc.tcc.caronas.passenger` permanece reservado para a outra app, permitindo as duas instaladas no
  mesmo aparelho para testar a troca de eventos Nostr ponta a ponta.
- **Alternatives considered**: editar o `applicationId` manualmente depois — descartado por ser mais
  trabalhoso e propenso a ficar inconsistente com o namespace Kotlin/Gradle gerado.

## D4 — Nome do pacote Dart

- **Decision**: nome do pacote `driver` (`--project-name driver`), igual ao diretório.
- **Rationale**: o diretório já é `Prototipo/driver`; `driver` é um identificador Dart válido
  (minúsculas, sem hífen) e mantém os imports internos curtos (`package:driver/...`).
- **Alternatives considered**: `caronas_driver` — mais descritivo, mas divergiria do nome do diretório e
  do caminho já consolidado no CLAUDE.md do repositório.

## D5 — `flutter create` sobre diretório não vazio

- **Decision**: rodar `flutter create` no diretório existente `Prototipo/driver`, que já contém
  `.specify/`, `.claude/` e `specs/`.
- **Rationale**: `flutter create` em diretório existente adiciona os arquivos que faltam e não remove
  conteúdo não relacionado; manter o scaffold do spec-kit e a app no mesmo diretório é necessário porque
  as skills `speckit-*` exigem `.specify/` na raiz do projeto.
- **Risco/mitigação**: o `.gitignore` gerado pelo Flutter sobrescreve um `.gitignore` local se existir —
  hoje não existe nenhum em `driver/`, então não há perda. Após a geração, conferir com `git status` que
  nada de `.specify/` ou `specs/` foi alterado.
- **Alternatives considered**: gerar em diretório temporário e copiar — descartado por ser equivalente
  com passos extras.

## D6 — Conteúdo da tela "vazia"

- **Decision**: substituir o app de contador do template por um `MaterialApp` com `title`
  "Caronas Motorista", `AppBar` com o mesmo título e um corpo centralizado com uma mensagem de
  placeholder identificando o app do motorista. Sem `FloatingActionButton`, sem `setState`, sem contador.
- **Rationale**: "vazio" no spec significa sem lógica de negócio; deixar o contador gerado seria lógica
  de exemplo sem propósito, que o avaliador do TCC leria como código morto. O `Scaffold`/`AppBar` mínimo
  satisfaz os critérios de tela legível em tema claro/escuro (SC-004) sem inventar UI de produto.
- **Alternatives considered**: `Container` cru sem `MaterialApp` — descartado por não exibir título nem
  respeitar tema do sistema; manter o contador — descartado como boilerplate morto.

## D7 — Estratégia de teste

- **Decision**: um widget test (`test/home_screen_test.dart`) que monta o app e verifica que o título da
  tela inicial é exibido e que nenhum widget de contador do template sobreviveu; `flutter analyze` com
  `flutter_lints` como gate de análise estática.
- **Rationale**: atende FR-007 e SC-003 com o menor custo possível; o teste protege contra a regressão
  mais provável nesta base (alguém reintroduzir o boilerplate ou quebrar o build da tela). Testes de
  integração/`integration_test` não se justificam sem fluxo de usuário real.
- **Alternatives considered**: nenhum teste — rejeitado por FR-007; `integration_test` com driver no
  emulador — descartado como desproporcional para uma tela estática e por exigir emulador em CI.

## D8 — Dependências de terceiros

- **Decision**: nenhuma. Apenas `flutter`, `cupertino_icons` (se vier do template) e, em dev,
  `flutter_test` + `flutter_lints`.
- **Rationale**: FR-005 proíbe rede/persistência nesta etapa; escolher agora gerenciador de estado,
  cliente Nostr ou roteador seria decisão arquitetural sem requisito que a sustente, e o spec-kit já
  prevê features futuras onde essa escolha será fundamentada.
- **Alternatives considered**: já adicionar um gerenciador de estado (Provider/Riverpod/Bloc) e uma
  biblioteca Nostr (ex.: `dart_nostr`) — descartado: decisão prematura, e a viabilidade de cada
  biblioteca Nostr é justamente objeto de investigação do TCC.

## D9 — Verificação de ambiente

- **Decision**: o README documenta `flutter doctor` como primeiro passo e registra que apenas o grupo
  "Android toolchain" precisa estar ✓ (Chrome/Linux desktop podem falhar sem impacto).
- **Rationale**: atende o edge case de ambiente sem SDK configurado, apontando explicitamente o que falta
  em vez de falhar de forma obscura.
- **Alternatives considered**: script próprio de checagem — desnecessário, `flutter doctor` já faz isso.
