# Quickstart de validação: 027-filtro-geografico-solicitacoes

Os cenários 1–3 rodam sem aparelho. Os cenários 4–9 são o **roteiro de execução** num emulador Android (motorista), com
um relay local que imprime o que o app pede e uma ferramenta que publica as solicitações de teste; o app do passageiro
só entra no passo final (variante B). Os cenários que falharem MUST ser relatados, não omitidos (constituição, gates).

Situação em 2026-10-22: cenários 1–3 **executados** (3 está em `research.md`, R7); 4–9 **a executar** — o roteiro está
pronto e a tabela de resultados, no fim, em branco.

## Pré-requisitos

- `flutter pub get`; `assets/ors_api_key.txt` ou `--dart-define=ORS_API_KEY=...` (rota; sem chave cai em fallback).
- Um emulador Android (Google Play não é necessário; só se usa a localização simulada). Pacote do app:
  `br.ufsc.tcc.corridas.driver`. `adb` em `~/Android/Sdk/platform-tools`.
- Contrato com a emenda 27 e constituição 2.18.0 idênticos aos do passageiro: o contrato difere só pelo cabeçalho de
  procedência; a constituição, só pelas linhas de perspectiva já existentes. (Conferir com `diff`.)
- **Variante B (ponta a ponta)** também exige o app do passageiro já publicando a tag `g` (feature dele). Sem isso, use a
  variante A, que substitui o passageiro por `tool/publish_ride_request.dart`.

## 1. Portões automáticos

```bash
flutter analyze        # sem apontamentos
flutter test           # inteira, sem teste ignorado
```

Esperado: ambos limpos. Arquivos de teste novos ou ampliados: `geohash_test`, `driver_coverage_test`,
`geohash_contract_vectors_test`, `ride_request_filter_test`, `event_feed_test`, `driver_profile_test`,
`cadastro_store_test`, `cadastro_screen_test`, `relay_service_test`, `remote_relay_connection_test`,
`relay_host_core_test`, `service_messages_test`, `nostr_relay_gateway_filters_test`, `map_screen_test`.

## 2. Vetores compartilhados

`flutter test test/services/geohash_contract_vectors_test.dart` aqui e o equivalente no passageiro; depois
`diff test/fixtures/geohash_vectors.json ../RideRelayPassenger/test/fixtures/geohash_vectors.json` sem saída.

## 3. O relay respeita `#g`? (medição, R7 do research) — executado

```bash
dart run tool/probe_geohash_filter.dart            # relays padrão; --relay=URL para outro
```

Executado em 2026-10-22: `nos.lol`, `relay.primal.net` e `offchain.pub` respeitam o `#g` e honram o `CLOSE`. Método,
tabela e limites da medição: `research.md`, R7. Repetir só se a lista padrão de relays mudar.

---

# Roteiro dos cenários 4–9

## Preparação do ambiente (uma vez)

Use **sempre o relay local** nos cenários 4–9: o app mostra o que pede (`REQ` com `#g`) e nenhuma solicitação de teste
vai a relays públicos, onde o app de outra pessoa poderia exibi-la.

1. **Relay local** (terminal 1, fica aberto; imprime cada quadro recebido):

   ```bash
   dart run tool/relay_local.dart              # ws://0.0.0.0:7777 ; --ignora-g simula relay que ignora o filtro
   ```

2. **Emulador e app** (terminal 2):

   ```bash
   emulator -list-avds && emulator -avd <nome> &
   adb devices                                  # anote o serial, ex.: emulator-5554
   flutter run -d <serial>
   ```

3. **No app**: concluir o cadastro, se for a primeira execução (etapa 1 com o raio já em 10). Em *Mais → Relays*, remover os
   três relays padrão e acrescentar `ws://10.0.2.2:7777` (no emulador, `10.0.2.2` é o computador). O terminal 1 deve
   mostrar `[n] conectou` e, ao ficar online, um `REQ` (ver cenário 4). Ao terminar os cenários, **restaurar os padrão**
   na mesma tela.

4. **Posição do emulador** — a função abaixo (terminal 2) coloca o emulador num ponto; lembre que o `adb` pede
   **longitude antes de latitude**:

   ```bash
   pos() { adb -s <serial> emu geo fix "$2" "$1"; }    # uso: pos LAT LON
   pos -28.9298 -49.4753                                # Araranguá (referência dos cenários)
   ```

5. **Publicar uma solicitação de teste** (terminal 3; vai só ao relay local):

   ```bash
   pub() { dart run tool/publish_ride_request.dart --relay=ws://127.0.0.1:7777 "$@"; }
   pub --lat=-28.90282 --lon=-49.4753           # exemplo: origem a ~3 km ao norte de Araranguá
   ```

   Opções: `--sem-g` (só o marcador, como antes da emenda 27), `--g-de=LAT,LON` (tags `g` de outro ponto, com a origem do
   `content` onde está), `--pagamento=pix|dinheiro|cartao` (o motorista de teste precisa aceitar a forma usada).

Coordenadas usadas abaixo (cálculo, referência Araranguá −28,9298 / −49,4753; 1° de latitude = 111,195 km):

| Ponto | Lat | Lon |
|---|---|---|
| Araranguá (referência) | −28.9298 | −49.4753 |
| ~3 km ao norte | −28.90282 | −49.4753 |
| ~9,5 km ao norte | −28.84436 | −49.4753 |
| ~10,5 km ao norte | −28.83537 | −49.4753 |
| ~12 km ao norte | −28.82188 | −49.4753 |
| logo além da borda norte da célula central de precisão 4 (11,31 km) | −28.82808 | −49.4753 |
| ~15 km ao norte | −28.79490 | −49.4753 |
| ~24 km ao norte | −28.71396 | −49.4753 |
| ~26 km ao norte | −28.69598 | −49.4753 |
| ~30 km ao norte (novo ponto do cenário 7) | −28.66000 | −49.4753 |
| São Paulo | −23.5505 | −46.6333 |

A cada cenário: motorista **offline** no início (todo início é offline), a menos que o passo diga outro; trocar o estado
pelo botão da tela do mapa. "Modal" é a janela "Solicitação de corrida"; fechá-la com "Recusar corrida" antes do passo
seguinte.

## 4. Chega o que está dentro, não chega o que está fora

Raio 10 km. `pos -28.9298 -49.4753`, ficar online.

| # | Ação | Esperado |
|---|---|---|
| 4.1 | Olhar o terminal 1 ao ficar online | Um `REQ` com **dois filtros**: um com os kinds `20003,20008,20010,20013,20014,20015` (sem `20001`, sem `#g`) e outro `{"kinds":[20001],"#t":[…],"#g":[até 9 células de 4 caracteres],"limit":50}` |
| 4.2 | `pub --lat=-28.90282 --lon=-49.4753` | Modal abre; na gaveta de notificações com o app em segundo plano, aparece a notificação (repetir com o app minimizado) |
| 4.3 | `pub --lat=-23.5505 --lon=-46.6333` | **Nada**: sem modal, sem notificação. O terminal 1 mostra o `EVENT` recebido (o relay local respeita `#g`, então ele nem é entregue ao app) |
| 4.4 | Reiniciar o relay local com `--ignora-g` (o app reconecta sozinho; ficar offline e online de novo se preciso) e repetir 4.3 | Terminal 1 mostra a entrega, mas o app **continua sem modal nem notificação** (a regra 8 vale mesmo que o relay ignore o filtro) |
| 4.5 | `pub --lat=-28.90282 --lon=-49.4753 --sem-g` | Nada (solicitação sem tag `g`) |
| 4.6 | `pub --lat=-28.90282 --lon=-49.4753 --g-de=-23.5505,-46.6333` | Nada (tag fora das células) |
| 4.7 | Ficar offline e repetir 4.2 | Nada; o terminal 1 mostra o `REQ` de ficar offline **sem** o filtro do `20001` |

## 5. Raio no limite e borda de célula

Raio 10 km (padrão), online em Araranguá.

| # | Ação | Esperado |
|---|---|---|
| 5.1 | `pub` a ~9,5 km (−28.84436) | Modal |
| 5.2 | `pub` a ~10,5 km (−28.83537) | Nada (filtro exato) |
| 5.3 | Ficar offline; *Mais → Cadastro* → raio **15**; salvar; ficar online | Terminal 1: `REQ` com células de 4 caracteres |
| 5.4 | `pub` logo além da borda (−28.82808), a ~11,3 km | Modal (célula vizinha, coberta pelas 9) |
| 5.5 | Ficar offline; raio **25**; ficar online | Terminal 1: `REQ` com células de **3** caracteres |
| 5.6 | `pub` a ~24 km (−28.71396) | Modal |
| 5.7 | `pub` a ~26 km (−28.69598) | Nada |

## 6. Cadastro: raio inicial, edição, limites

| # | Ação | Esperado |
|---|---|---|
| 6.1 | Instalação limpa (`adb uninstall br.ufsc.tcc.corridas.driver`; `flutter run`); etapa 1 do cadastro | Campo "Raio de atendimento (km)" já com `10` |
| 6.2 | Apagar, `0`, `101`, `abc`, `2,5` | Botão desabilitado; texto de erro com os limites para os não vazios |
| 6.3 | `1` e `100` | Passam; salvar e reabrir em *Mais → Cadastro* mostra o valor |
| 6.4 | **Migração**: `git worktree add /tmp/driver-anterior 9d9f260` (último commit antes da feature) e `flutter run -d <serial>` lá; cadastrar; voltar a este diretório e `flutter run -d <serial>` **sem desinstalar** (mesmo pacote, os dados ficam); depois `git worktree remove /tmp/driver-anterior` | Entra direto na tela principal (sem refazer o wizard); *Mais → Cadastro* mostra raio `10` |
| 6.5 | Online com raio 10, abrir *Mais → Cadastro*, trocar para 50 e salvar | Texto "Você está online: o novo raio vale a partir da próxima vez que você ficar online" visível no campo |
| 6.6 | Ainda online: `pub` a ~12 km (−28.82188) | Nada (a cobertura em uso ainda é de 10 km) |
| 6.7 | Offline e online de novo; repetir 6.6 | Modal (raio 50) |

Registrar a versão do SQLite do emulador (`adb shell sqlite3 --version`, se existir) junto do resultado de 6.4: a migração
foi conferida antes só num SQLite de computador.

## 7. Referência fixa e ciclo online/offline

Raio 10 km. Online em Araranguá.

| # | Ação | Esperado |
|---|---|---|
| 7.1 | `pos -28.66000 -49.4753` (30 km ao norte); `pub` perto de Araranguá (−28.90282) | Modal (referência não acompanha o motorista) |
| 7.2 | `pub` perto do novo ponto (−28.66000) | Nada; o terminal 1 não mostra novo `REQ` (a inscrição não foi refeita) |
| 7.3 | Ficar offline; terminal 1 | `REQ` sem o filtro do `20001` |
| 7.4 | Ficar online no novo ponto; `pub` perto de Araranguá, depois perto do novo ponto | A primeira não chega; a segunda abre a modal (nova referência) |
| 7.5 | Desligar a localização do emulador (Configurações do emulador → Location, ou `adb shell settings put secure location_mode 0`) com o motorista online | Aviso "Você ficou offline porque a localização foi perdida."; terminal 1: `REQ` sem `#g`; `pub` não abre nada |
| 7.6 | Offline, localização ligada e sem fix ainda: tentar ficar online | Aviso "É preciso ter uma localização válida para ficar online."; nada de `#g` no terminal 1 |

## 8. Serviço em segundo plano e retomada

Raio 10 km.

| # | Ação | Esperado |
|---|---|---|
| 8.1 | Online; minimizar o app; `pub` a ~3 km | Notificação de nova solicitação (sem endereço nem coordenada no texto); tocar nela abre o app com a modal |
| 8.2 | Minimizado, `pub` em São Paulo | Nenhuma notificação |
| 8.3 | Fechar o app deslizando (online); `pub` a ~3 km; abrir o app pela notificação | Volta online na primeira posição válida; a solicitação, avaliada contra a nova referência, abre a modal |
| 8.4 | Repetir 8.3 com `pub` em São Paulo | Nenhuma modal |
| 8.5 | **Processo morto (limite conhecido, R5)**: online, app fechado; `adb shell "run-as br.ufsc.tcc.corridas.driver kill -9 $(adb shell pidof br.ufsc.tcc.corridas.driver)"` (build de depuração); esperar o serviço reiniciar; `pub` a ~3 km | **Esperado**: nenhuma notificação (o serviço reiniciou sem cobertura; terminal 1 não mostra `REQ` com `#g`). Abrir o app: volta online, referência nova, e o `REQ` com `#g` reaparece. **Relatar o que de fato ocorrer** |

## 9. Não vazamento (privacidade)

Durante os cenários 4–8, em outro terminal:

```bash
adb -s <serial> logcat -s flutter | tee /tmp/logcat-027.txt      # parar com Ctrl+C ao fim
grep -nE "28[.,]9298|49[.,]4753|-28\.935|-49\.49|raio" /tmp/logcat-027.txt     # nenhuma ocorrência esperada
```

| # | Verificação | Esperado |
|---|---|---|
| 9.1 | `grep` acima (use também as coordenadas simuladas dos cenários 5 e 7) | Nenhuma coordenada da referência nem o raio no log |
| 9.2 | Quadros do terminal 1 vindos do app (`<-`) | Só `REQ` (com `#t`, `kinds`, `#g`) e `CLOSE`; nenhum `EVENT` do app que contenha a referência, a posição ou o raio. (Publique um orçamento num cenário para ver um `EVENT` do app: `content` cifrado em base64, tags `t`, `e`, `p`.) |
| 9.3 | Gaveta de notificações | Texto genérico; sem endereço, coordenada, nome nem chave pública |
| 9.4 | `adb shell run-as br.ufsc.tcc.corridas.driver ls files shared_prefs databases` e `grep -r` por `raio` e pelas coordenadas nos arquivos do app | Só `raio_atendimento_km` no `cadastro_motorista.db`; a posição de referência não aparece em arquivo algum |

## Variante B — com o app do passageiro

Depois de a feature dele publicar a tag `g`: repetir 4.2, 4.3, 5.1–5.2 e 7.1–7.2 solicitando corridas pelo app do passageiro
(em outro emulador, com a posição dele simulada em cada ponto da tabela; mesmos relay local ou, só então, relays públicos).
Conferir, no terminal 1, que o `EVENT` do `20001` traz **três** tags `g` (5, 4 e 3 caracteres) e que o `content` não mudou.

## Tabela de resultados (preencher ao executar)

| Cenário | Data | Obtido | Passou? | Observações |
|---|---|---|---|---|
| 1 | | | | |
| 2 | | | | |
| 3 | 2026-10-22 | ver `research.md` R7 | sim | três relays padrão |
| 4 | | | | |
| 5 | | | | |
| 6 | | | | |
| 7 | | | | |
| 8 | | | | |
| 9 | | | | |
| Variante B | | | | depende da feature do passageiro |
