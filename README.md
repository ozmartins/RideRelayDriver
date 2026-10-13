# Caronas Motorista — app do motorista

Aplicativo do **motorista** do protótipo de caronas P2P sobre o protocolo Nostr, prova de conceito do TCC
*"Nostr para Mobilidade P2P: Avaliação de Viabilidade em Aplicativos de Caronas"* (UFSC — Araranguá).

O app do passageiro é um projeto **independente**, em `../passenger`. As duas aplicações não se conhecem
nem trocam pacotes diretamente: toda comunicação entre elas acontece publicando e assinando eventos em
relays Nostr. Não há backend próprio.

- Identificador do aplicativo: `br.ufsc.tcc.caronas.driver`
- Nome de exibição: **Caronas Motorista**

## Escopo atual

| Existe | Não existe ainda |
|--------|------------------|
| Identidade Nostr própria, criada uma vez e guardada no Android Keystore | Formatos de evento de caronas (oferta, solicitação, mensagem) |
| Conexão simultânea a múltiplos relays, com estado de cada um | Criptografia de conteúdo entre pares (NIP-44) |
| Publicação e recepção de eventos assinados (kinds de domínio `20001`+) | Comunicação com a app do passageiro |
| Gestão da lista de relays, persistida no aparelho | Suporte a iOS, web ou desktop |
| Verificação de assinatura e deduplicação por `id` | Histórico de eventos offline |
| Filtragem do tráfego do protótipo por marcador | Isolamento garantido pelo protocolo (não existe) |
| Cadastro do motorista (nome, UF/cidade, dados do veículo), obrigatório na primeira abertura e editável depois, persistido em SQLite | Sincronização do cadastro com qualquer evento Nostr — é dado puramente local |
| Mapa com a posição real do motorista, como tela inicial, e status online/offline | Notificação de solicitação de corrida em si — etapa futura |

### Mapa e status online/offline

A tela inicial passou a ser um mapa (mosaicos do OpenStreetMap, sem chave de provedor de terceiro)
centrado na posição real do aparelho, com um indicador dessa posição atualizado continuamente. A
mesma tela tem um controle para o motorista alternar entre online e offline: ficar online exige uma
posição válida disponível; perder a posição estando online derruba o status automaticamente. O status
nunca é lembrado entre execuções — todo início de aplicativo começa offline, por decisão deliberada de
segurança/UX, não por limitação técnica. Nem a posição nem o status são publicados em nenhum evento
Nostr nesta etapa.

### Cadastro do motorista

Na primeira abertura, antes de qualquer outra tela, o aplicativo pede nome, UF e cidade de atuação
(validadas contra as 27 unidades da federação e a lista de municípios do IBGE, embutida sem chamada de
rede) e os dados do veículo — marca, modelo, cor e placa, aceita nos dois formatos vigentes no Brasil
(antigo e Mercosul). Os dados ficam em SQLite local (`sqflite`) e podem ser corrigidos depois pela aba
"Cadastro". Não é segredo criptográfico: um cadastro corrompido é tratado como ausente, e o formulário
volta a aparecer, sem o tratamento de perda irreversível que vale para a identidade Nostr.

### Marcador do protótipo

Todo evento publicado carrega a tag `["t", "tcc-ufsc-caronas"]`, e a inscrição nos relays filtra por
ela (`#t`). Sem esse filtro, inscrever-se em `kind: 1` (que o app usava como evento de teste, já retirado) entregava o **tráfego social público da rede inteira** — medimos 125
eventos alheios em 90 segundos. Com o filtro, a lista passou a conter apenas
eventos do protótipo.

O marcador **não é mecanismo de segurança**: qualquer pessoa pode publicar com a mesma tag. Por isso a
aplicação continua verificando a assinatura de todo evento e descarta o que chega sem o marcador, mesmo
quando o relay o entrega. A regra vale **igual nas
duas apps** — motorista e passageiro precisam procurar pela mesma coisa para se enxergarem.

O formato dos eventos — único acoplamento com a app do passageiro — precisa ser idêntico nas duas aplicações.

## Estrutura do código

```text
lib/
├── main.dart          # entrypoint, composição das dependências e navegação
├── domain/            # Identity, Relay, NostrEvent, DriverProfile, UF, Municipio,
│                      # DriverPosition, AvailabilityStatus — tipos próprios, sem dart_nostr,
│                      # sqflite, geolocator nem flutter_map
├── services/          # identidade, relays, feed de eventos, verificação, persistência,
│                      # localização (location_service.dart, geolocator_location_service.dart)
└── screens/           # eventos, relays, identidade, cadastro, mapa (tela inicial)

test/                  # espelha lib/: test/domain/, test/services/ e test/screens/, dublês em cada arquivo
android/               # projeto Android (applicationId br.ufsc.tcc.caronas.driver)
```

Tipos de bibliotecas de terceiros ficam **confinados a `services/`**: `domain/` e `screens/` nunca
importam `dart_nostr`. Isso é o que permite trocar de
biblioteca Nostr sem reescrever a interface.

## Dependências

| Pacote | Para quê |
|--------|----------|
| `dart_nostr` | protocolo Nostr: chaves, assinatura, relays |
| `flutter_secure_storage` | chave privada no Android Keystore |
| `shared_preferences` | lista de relays (dado público) |
| `sqflite` | cadastro do motorista em SQLite |
| `path` | montar o caminho do arquivo SQLite |
| `geolocator` | permissão e leitura contínua de posição |
| `flutter_map` + `latlong2` | mapa com mosaicos do OpenStreetMap, sem chave de provedor |

Para o mapa, `google_maps_flutter` e `mapbox_maps_flutter` foram rejeitados por exigirem credencial de um provedor externo; para a lista de UFs/municípios do IBGE, optou-se por não adicionar pacote de terceiros.

## Pré-requisitos

- **Flutter 3.47.4** (canal stable) com **Dart 3.13.3**
- Android SDK + um emulador (AVD) ou aparelho com depuração USB habilitada
- Java 17 (JDK usado pelo Gradle)

Verifique o ambiente antes de qualquer coisa:

```bash
flutter doctor
```

Só o grupo **`[✓] Android toolchain`** (além de `[✓] Flutter`) precisa estar aprovado. Falhas em
`Chrome — develop for the web` e `Linux toolchain` são **esperadas e irrelevantes** aqui: web e desktop
estão fora de escopo. Se o Android toolchain falhar, o próprio `flutter doctor` indica o que instalar.

## Comandos

Todos executados a partir deste diretório (`Prototipo/driver`).

```bash
flutter pub get                 # instala as dependências
flutter run                     # executa no dispositivo/emulador conectado
flutter analyze                 # análise estática (deve terminar com "No issues found!")
flutter test                    # roda a suíte de testes
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
flutter emulators --launch <id-do-avd>     # inicia um AVD (ex.: Pixel_6_API34_1)
flutter devices                            # confirma o dispositivo conectado
```

## Nota sobre permissões

O aplicativo declara `android.permission.INTERNET` (normal, concedida na instalação, sem diálogo) e,
também `ACCESS_FINE_LOCATION`/`ACCESS_COARSE_LOCATION` (perigosas, com diálogo ao
usuário) — pedidas só ao abrir a tela de mapa, nunca antecipadamente, e só em primeiro plano: não há
acesso à localização em segundo plano. Verificação no APK de release:

```bash
flutter build apk --release
$ANDROID_HOME/build-tools/*/aapt2 dump permissions build/app/outputs/flutter-apk/app-release.apk
```

## Identidade e perda de dados

A chave privada é gerada na primeira execução e guardada cifrada no Android Keystore. Ela **nunca** é
exibida em tela, registrada em log ou enviada a um relay.

⚠️ **Desinstalar o aplicativo apaga a chave privada de forma irreversível**: a identidade é perdida e uma
nova será criada na próxima instalação. Não há backup nem exportação nesta etapa.
