# Phase 1 — Quickstart / Validação: Aplicativo Mobile Base (Motorista)

Guia para provar que a feature funciona ponta a ponta. Todos os comandos rodam a partir de
`Prototipo/driver`.

## Pré-requisitos

1. Flutter 3.47.4 (stable) com Dart 3.13.3 no `PATH`.
2. Android SDK + um emulador ou aparelho com depuração USB habilitada.
3. Verificação do ambiente:

   ```bash
   flutter doctor
   ```

   **Esperado**: o grupo `[✓] Android toolchain` e `[✓] Flutter` aprovados. Falhas em
   `Chrome — develop for the web` e `Linux toolchain` são aceitáveis: web e desktop estão fora de escopo
   (FR-004). Se o Android toolchain falhar, `flutter doctor` indica exatamente o que instalar.

## Cenário 1 — Dependências resolvem (FR-006)

```bash
flutter pub get
```

**Esperado**: conclui sem erro; nenhuma dependência de terceiros é baixada além do SDK e dos pacotes de
desenvolvimento (`flutter_test`, `flutter_lints`).

## Cenário 2 — Análise estática limpa (SC-003)

```bash
flutter analyze
```

**Esperado**: `No issues found!`.

## Cenário 3 — Teste de sanidade da tela inicial (FR-007, SC-003)

```bash
flutter test
```

**Esperado**: todos os testes passam. Para rodar apenas um teste:

```bash
flutter test test/home_screen_test.dart
flutter test --plain-name "exibe o título do aplicativo"
```

**Contraprova** (cenário de aceitação 2 da User Story 3): altere o título exibido em
`lib/main.dart` e rode `flutter test` novamente — o teste deve falhar apontando o texto ausente. Desfaça
a alteração depois.

## Cenário 4 — App abre no dispositivo (User Story 1, SC-002, SC-005)

```bash
flutter emulators --launch Pixel_6_API34_1   # ou conecte um aparelho físico
flutter devices                              # confirme que o dispositivo aparece
flutter run
```

**Esperado**:

- o app compila, instala e abre em até ~5 s após o lançamento (SC-002);
- a tela inicial exibe o título "Corridas Motorista", sem contador nem botão flutuante;
- **nenhum diálogo de permissão** é exibido (SC-005);
- colocar o app em segundo plano e retornar mantém a mesma tela (User Story 1, cenário 2);
- na gaveta de aplicativos do sistema, o app aparece como "Corridas Motorista" (User Story 1, cenário 3).

## Cenário 5 — Tema e resoluções (SC-004)

Com o app aberto, alterne o tema do sistema Android entre claro e escuro: a tela permanece legível, sem
texto cortado. Repita em um segundo emulador com resolução/densidade diferente.

## Cenário 6 — Build de release (integridade do projeto)

```bash
flutter build apk --debug
```

**Esperado**: build conclui e o APK é gerado em `build/app/outputs/flutter-apk/`.

## Cenário 7 — Higiene do repositório (FR-008)

```bash
git status --short
```

**Esperado**: nada de `build/`, `.dart_tool/` ou `.flutter-plugins*` listado como não rastreado; e nenhuma
alteração inesperada em `.specify/`, `.claude/` ou `specs/`.

## Cenário 8 — Reprodutibilidade (User Story 2, SC-001)

Em uma máquina limpa com o ambiente mobile instalado: clonar o repositório, entrar em `Prototipo/driver`
e seguir apenas o `README.md` — de `flutter pub get` até o app aberto no emulador em menos de 10 minutos,
sem nenhum passo não documentado.
