# Corridas Motorista — app do motorista

Aplicativo do **motorista** do protótipo de corridas P2P sobre o protocolo Nostr, prova de conceito do TCC
*"Nostr para Mobilidade P2P: Avaliação de Viabilidade em Aplicativos de Corridas"* (UFSC — Araranguá).

O app do passageiro é um projeto **independente**, em `../passenger`. As duas aplicações não se conhecem
nem trocam pacotes diretamente: toda comunicação entre elas acontece publicando e assinando eventos em
relays Nostr. Não há backend próprio.

- Identificador do aplicativo: `br.ufsc.tcc.corridas.driver`
- Nome de exibição: **Corridas Motorista**
- Alvo único: Android (iOS, web e desktop estão fora de escopo)

## O que o app faz

O fluxo completo de uma corrida, do ponto de vista do motorista:

1. **Identidade e cadastro** — chave Nostr própria no Android Keystore; cadastro em etapas (nome, UF/cidade,
   veículo com ano, formas de pagamento, preço por km, raio de atendimento) em SQLite local.
2. **Mapa e status** — tela inicial com a posição real; o motorista alterna entre online e offline.
3. **Receber solicitações** — só online, filtradas por região (geohash + raio de atendimento). O app mostra
   o endereço legível e a rota da solicitação, e o motorista envia um orçamento.
4. **Corrida** — orçamento aceito, início da corrida, rota publicada ao passageiro, aviso de chegada
   (inclusive periódico), confirmação de encontro e de destino, cancelamento por qualquer das partes.
5. **Mensagens cifradas** — o conteúdo trocado com o passageiro usa NIP-44 (implementação própria).
6. **Avaliação e reputação** — ao fim, nota ao passageiro e recibo assinado (reenviado até a confirmação);
   o motorista declara no orçamento a reputação dos últimos 5 recibos que recebeu.
7. **Conexão em segundo plano** — a conexão com os relays vive num serviço em primeiro plano do Android, com
   notificação local de nova solicitação, mesmo com o app fechado.

Abas: **Mapa** e **Mais** (Cadastro, Relays, Minha identidade).

O estado real e detalhado de cada funcionalidade está em `specs/` (001 a 029) e na constituição
(`.specify/memory/constitution.md`). `CLAUDE.md` resume a arquitetura e as regras de domínio.

### Regras que vale conhecer

- **Marcador do protótipo**: todo evento publicado leva a tag `["t", "tcc-ufsc-caronas"]`, a inscrição filtra
  por `#t`, e eventos sem o marcador são descartados mesmo que o relay os entregue. Não é mecanismo de
  segurança: qualquer pessoa pode publicar com a mesma tag, por isso a assinatura de todo evento é verificada
  antes de qualquer outra coisa. A regra vale **igual nas duas apps**.
- **Contrato de eventos** (`specs/002-nostr-relay-connection/contracts/nostr-events.md`): único acoplamento
  com a app do passageiro; precisa ser idêntico nas duas aplicações, assim como a lista padrão de relays.
- **Status e posição de referência nunca são persistidos**: todo início de aplicativo começa offline, por
  decisão deliberada de segurança/UX. Posição e status não são publicados em evento algum.
- **Cadastro** é dado puramente local (não vira evento Nostr); cadastro corrompido é tratado como ausente e o
  formulário volta a aparecer.

## Estrutura do código

```text
lib/
├── main.dart          # entrypoint, composição das dependências (injeção explícita) e navegação
├── domain/            # tipos próprios (Identity, Relay, NostrEvent, DriverProfile, ActiveRide,
│                      # RideQuote, Receipt, DriverCoverage…), sem dart_nostr, sqflite, geolocator
│                      # nem flutter_map
├── services/          # único lugar com bibliotecas de terceiros: identidade, relays (transporte
│   │                  # WebSocket próprio), feed de eventos, cifra NIP-44, recibos, persistência,
│   │                  # localização, rota, geocodificação reversa
│   └── background/    # serviço em primeiro plano que hospeda a conexão com os relays
└── screens/           # mapa, cadastro, relays, identidade, modais de corrida, identidade visual

test/                  # espelha lib/ (domain, services, screens, support, fixtures)
tool/                  # sondas, geradores de vetores de teste e apoio a teste manual; não fazem parte do app
specs/                 # especificações spec-kit, uma pasta por feature
android/               # projeto Android
```

Tipos de bibliotecas de terceiros ficam **confinados a `services/`**: `domain/` e `screens/` nunca importam
`dart_nostr`, `sqflite`, `geolocator` etc. Cada serviço fica atrás de uma interface, com implementação real
separada; os testes passam dublês e não tocam plugin de plataforma, Keystore, SQLite real, GPS nem rede.

## Dependências

| Pacote | Para quê |
|--------|----------|
| `dart_nostr` | chaves, assinatura e verificação (o transporte com relays é próprio, sobre `dart:io`) |
| `pointycastle` + `crypto` | NIP-44 (ChaCha20, secp256k1, HKDF/HMAC) |
| `flutter_secure_storage` | chave privada no Android Keystore |
| `shared_preferences` | lista de relays (dado público) |
| `sqflite` + `path` | cadastro, recibos e demais dados locais em SQLite |
| `geolocator` | permissão e leitura contínua de posição |
| `flutter_map` + `latlong2` + `vector_map_tiles` | mapa com tiles vetoriais do OpenFreeMap (sem chave) |
| `open_route_service` + `http` | rota e distância (openrouteservice) e geocodificação reversa |
| `flutter_foreground_task` | serviço em primeiro plano com a conexão com os relays |
| `flutter_local_notifications` | notificação local de nova solicitação |

Toda dependência nova exige entrada no `research.md` da feature antes de ser instalada (constituição).

## Pré-requisitos

- **Flutter 3.47** (canal stable) com **Dart ^3.13.3**
- Android SDK + um emulador (AVD) ou aparelho com depuração USB habilitada
- Java 17 (JDK usado pelo Gradle)

```bash
flutter doctor
```

Só o grupo **`[✓] Android toolchain`** (além de `[✓] Flutter`) precisa estar aprovado. Falhas em
`Chrome — develop for the web` e `Linux toolchain` são esperadas e irrelevantes aqui.

### Chave do openrouteservice

A chave do openrouteservice é **opcional**: o app compila e roda normalmente sem ela. Sem chave, a
distância e a rota da corrida usam a distância em linha reta (fallback, marcada como aproximada) em vez do traçado real pelas ruas.

Para usar a rota real, crie uma conta gratuita em <https://openrouteservice.org/dev/#/signup>, gere
um token e informe-o de uma das formas abaixo:

- copie `assets/ors_api_key.txt.example` para `assets/ors_api_key.txt` (arquivo ignorado pelo Git) e
  substitua o conteúdo pela sua chave; ou
- passe `--dart-define=ORS_API_KEY=...` ao `flutter run`/`flutter build` (o define tem precedência).

Nunca versione a chave.

## Comandos

Todos executados a partir da raiz do repositório.

```bash
flutter pub get                 # instala as dependências
flutter run                     # executa no dispositivo/emulador conectado
flutter analyze                 # análise estática (deve terminar com "No issues found!")
flutter test                    # roda a suíte de testes (sem teste ignorado)
dart format lib test            # formata o código
flutter build apk --debug       # gera o APK de depuração
```

Rodar **um único teste**:

```bash
flutter test test/services/event_feed_test.dart                 # um arquivo
flutter test --plain-name "descarta evento com assinatura adulterada"   # um caso específico
```

Emulador:

```bash
flutter emulators                          # lista os AVDs disponíveis
flutter emulators --launch <id-do-avd>     # inicia um AVD
flutter devices                            # confirma o dispositivo conectado
```

## Permissões Android

| Permissão | Para quê |
|-----------|----------|
| `INTERNET` | conexão com os relays, tiles, rota |
| `ACCESS_FINE_LOCATION` / `ACCESS_COARSE_LOCATION` | posição no mapa; pedida só ao abrir a tela de mapa |
| `FOREGROUND_SERVICE` / `FOREGROUND_SERVICE_SPECIAL_USE` | serviço em primeiro plano com a conexão com os relays |
| `POST_NOTIFICATIONS` | notificação de nova solicitação e do serviço em segundo plano |

Não há acesso à localização em segundo plano. `WAKE_LOCK` e `RECEIVE_BOOT_COMPLETED` são removidas
explicitamente do manifesto. Verificação no APK de release:

```bash
flutter build apk --release
$ANDROID_HOME/build-tools/*/aapt2 dump permissions build/app/outputs/flutter-apk/app-release.apk
```

## Identidade e perda de dados

A chave privada é gerada na primeira execução e guardada cifrada no Android Keystore. Ela **nunca** é
exibida em tela, registrada em log ou enviada a um relay.

⚠️ **Desinstalar o aplicativo apaga a chave privada de forma irreversível**: a identidade é perdida e uma
nova será criada na próxima instalação. Não há backup nem exportação.
