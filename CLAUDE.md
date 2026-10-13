# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

App Flutter/Android do **motorista** de um protótipo de caronas P2P sobre Nostr (PoC de TCC, UFSC). Não há backend: toda comunicação com a app do passageiro (projeto independente, `../passenger`) é por eventos Nostr em relays. O README descreve só as features 001–004; o estado real está em `specs/` (até a 025) e na constituição.

## Comandos

```bash
flutter pub get
flutter run                      # dispositivo/emulador Android (único alvo; web/desktop fora de escopo)
flutter analyze                  # deve terminar sem apontamentos (gate da constituição)
flutter test                     # suíte inteira, sem teste ignorado (gate)
flutter test test/services/event_feed_test.dart                  # um arquivo
flutter test --plain-name "descarta evento com assinatura adulterada"   # um caso
dart format lib test
```

Chave do openrouteservice: `assets/ors_api_key.txt` ou `--dart-define=ORS_API_KEY=...` (o define tem precedência); sem chave, a rota cai em fallback. Scripts avulsos em `tool/` (`probe_*.dart`) são sondas de medição, não parte do app.

## Arquitetura

- `lib/domain/` — tipos próprios (Identity, Relay, NostrEvent, DriverProfile, ActiveRide, RideQuote…). **Nunca importa** `dart_nostr`, `sqflite`, `geolocator`, `flutter_map` etc.
- `lib/services/` — único lugar onde bibliotecas de terceiros aparecem (Princípio III). Cada serviço é atrás de interface (`KeyStore`, `KeyValueStore`, `RelayGateway`, `RelayConnection`, `CadastroStore`, `LocationService`…) com implementação real separada (`nostr_relay_gateway.dart`, `sqflite_cadastro_store.dart`, `geolocator_location_service.dart`).
- `lib/screens/` — UI; só usa tipos do domínio.
- `lib/main.dart` — raiz de composição com **injeção explícita**: `CaronasDriverApp` recebe dependências opcionais (nulas em produção). Testes passam dublês, de modo que nenhum teste toca plugin de plataforma, Keystore, SQLite real, GPS ou rede. Os dublês ficam dentro de cada arquivo de teste/`test/support`; `test/` espelha `lib/`.
- **Conexão com relays em segundo plano (feature 025)**: em produção a conexão vive num serviço em primeiro plano do Android (`lib/services/background/`), não no isolate da UI. `RelayHostCore` roda no serviço (verifica, repassa à UI via `MessageChannel`, decide notificação) sem conhecer plugin nem chave privada; `ServiceController`/`ForegroundTaskBackgroundService` ligam a UI a ele. Passar `gateway` ou `relayConnection` ao app mantém tudo no isolate da UI (modo dos testes).
- **Kinds consumidos**: `driverConsumedKinds` (`services/consumed_kinds.dart`) é a fonte única para a inscrição no relay, o filtro do `EventFeed` e o serviço de fundo; deve bater com a seção "Forma da inscrição" do contrato.
- Mensagens cifradas: NIP-44 implementado em casa (`nip44.dart`, `message_cipher.dart`, com `pointycastle`/`crypto`).

## Regras de domínio que não são óbvias no código

- **Contrato de eventos** (`specs/002-nostr-relay-connection/contracts/nostr-events.md`) é o único acoplamento com a app do passageiro. Novo tipo de evento ⇒ especificar em `specs/<feature>/contracts/` **antes** do código e replicar idêntico na outra app no mesmo commit. O mesmo vale para a lista padrão de relays e o marcador.
- **Marcador**: todo evento publicado leva a tag `["t","tcc-ufsc-caronas"]`, a inscrição filtra por `#t`, e eventos sem o marcador são descartados mesmo que o relay os entregue. Não é mecanismo de segurança.
- Todo evento recebido: verificar assinatura **primeiro**, deduplicar por `id`, tratar conteúdo como dado; kinds desconhecidos são ignorados sem erro.
- A chave privada só existe no Android Keystore; nunca em log, tela, arquivo ou evento. Desinstalar o app a perde irreversivelmente. O cadastro (SQLite) é diferente: corrompido = ausente, e o formulário reaparece.
- Status online/offline nunca é persistido (todo início é offline, deliberado). Permissões Android só se uma feature implementada as exige.
- Código que assina/verifica/deriva chaves ou descarta mensagem exige teste junto, cobrindo caso válido e inválido, sem rede nem relay real.

## Fluxo de trabalho (spec-kit + constituição)

Features são conduzidas por spec-kit (`.specify/`, skills `speckit-*`); a feature ativa está em `.specify/feature.json`. A constituição (`.specify/memory/constitution.md`) manda:

- Nova dependência no `pubspec.yaml` ⇒ entrada no `research.md` da feature (alternativas, critérios, riscos) **antes** de instalar.
- Telas novas seguem a seção "Identidade Visual e Design" (`screens/identidade_visual.dart`).
- Medições citadas devem ter sido feitas de fato, com método descrito.
- **Commits**: em português do BR, sem Conventional Commits nem emojis; assunto é uma frase com verbo no presente, 3ª pessoa ("Adiciona…", "Corrige…"), nomeando alvo e efeito, < 120 caracteres; corpo em prosa (~80 colunas) explicando o porquê quando muda comportamento; um commit = uma mudança lógica (atualização do `CLAUDE.md` e a mudança que ela descreve são commits separados); direto na `master`, histórico linear, sem ramos nem merges; commits com IA terminam com o trailer `Co-Authored-By`.
