# Phase 1 — Quickstart / Validação: Conexão do Motorista com Relays Nostr

Comandos executados a partir de `Prototipo/driver`. Os cenários 1–3 são automatizados; os demais exigem
emulador/aparelho com rede, porque validam comportamento contra relays reais.

## Pré-requisitos

- Ambiente da feature 001 funcionando (ver `README.md`)
- Conectividade de internet no aparelho/emulador
- Dependências instaladas: `flutter pub get`

## Cenário 1 — Gates automatizados

```bash
flutter analyze   # esperado: No issues found!
flutter test      # esperado: todos os testes passam
```

Cobrem, com dublês e sem rede (decisão D5): criação e recuperação de identidade, transições de estado dos
relays, reconexão após queda, descarte de evento com assinatura inválida e deduplicação por `id`.

## Cenário 2 — Identidade persiste (US2, SC-004)

```bash
flutter run
```

1. Anote a chave pública exibida na tela de identidade.
2. Encerre o aplicativo completamente (não apenas segundo plano) e reabra. Repita 5 vezes.

**Esperado**: a mesma chave pública nas 5 reaberturas; a chave privada nunca aparece em tela.

## Cenário 3 — Chave privada não vaza (FR-005, SC-007)

Com o app rodando:

```bash
adb logcat -d | grep -i -E "nsec|private|[0-9a-f]{64}"
```

**Esperado**: nenhuma ocorrência da chave privada. Repita a inspeção após publicar um evento.

## Cenário 4 — Conexão com a lista padrão (US1, SC-001)

Abra o aplicativo com rede disponível.

**Esperado**: cada relay aparece em `conectando` e ao menos um chega a `conectado` em até 5 segundos;
a interface permanece utilizável durante todo o processo.

## Cenário 5 — Ida e volta de um evento (US3, SC-002)

Na tela principal, publique o evento de teste.

**Esperado**: o resultado da publicação é informado **por relay** (aceito/recusado) e o próprio evento
retorna pela inscrição, aparecendo **uma única vez** na lista mesmo com vários relays conectados,
em até 5 segundos.

## Cenário 6 — Relay inalcançável não derruba os demais (US1/US3, SC-003)

Na tela de relays, adicione um endereço sintaticamente válido e inalcançável, por exemplo
`wss://relay-inexistente.invalid`.

**Esperado**: apenas esse relay fica `indisponível`, com motivo resumido; publicação e recepção seguem
funcionando pelos demais.

## Cenário 7 — Gestão e persistência da lista (US4, SC-005)

1. Adicione um relay válido → deve conectar e passar a operar.
2. Tente adicionar o mesmo endereço de novo → recusa com explicação.
3. Tente adicionar `banana` → recusa com explicação.
4. Remova um relay → conexão encerrada.
5. Feche e reabra o app → a lista alterada é restaurada.
6. Remova todos → o app explica a situação e oferece restaurar a lista padrão.

## Cenário 8 — Perda e retorno de rede (FR-014, edge cases)

```bash
adb shell svc wifi disable && adb shell svc data disable   # derruba a rede
adb shell svc wifi enable                                   # devolve a rede
```

**Esperado**: ao cair, os relays passam a `indisponível` com mensagem compreensível (sem erro técnico
cru) e o app não trava; ao voltar, a reconexão ocorre **sem intervenção manual** e nenhum evento já
exibido é duplicado.

## Cenário 9 — Rajada de eventos (SC-006)

**Atenção (emenda 01)**: inscrever-se num relay movimentado **não** produz mais rajada — a inscrição
filtra por `#t`, e o namespace do protótipo é praticamente vazio. A rajada precisa ser provocada com
eventos **marcados**:

```bash
# publique ≥ 100 eventos com a tag ["t", "tcc-ufsc-caronas"] por outro cliente,
# ou remova temporariamente o filtro `t:` de lib/services/nostr_relay_gateway.dart
# para reproduzir a condição pré-emenda
```

**Esperado**: a lista continua rolando sem congelamento perceptível; o consumo de memória não cresce
indefinidamente (janela limitada de eventos).

## Cenário 10 — Build de release com permissão de rede (FR-016, D6)

```bash
flutter build apk --release
```

**Esperado**: build conclui; o manifesto final declara `android.permission.INTERNET`. Verificação:

```bash
$ANDROID_HOME/build-tools/*/aapt2 dump permissions build/app/outputs/flutter-apk/app-release.apk
```

---

## Resultados da execução de 15/09/2026

Ambiente: emulador Android `Pixel_6_API34_1` (API 34), build **debug**, Flutter 3.47.4.
Todas as medições abaixo foram **medidas**, não estimadas (Princípio V); o método está descrito
junto de cada número. Instrumentação de medição vive em `kDebugMode` e registra apenas dados
públicos (URL de relay, identificador de evento, tempos) — nunca material criptográfico.

| Cenário | Resultado |
|---------|-----------|
| 1 — `flutter analyze` / `flutter test` | ✅ `No issues found!` e **54 testes** aprovados, nenhum ignorado |
| 2 — Identidade persiste | ✅ mesma chave pública após reinícios; `IdentityService` coberto por teste de recuperação |
| 3 — Chave privada não vaza | ✅ ver abaixo |
| 4 — Conexão com a lista padrão | ✅ ver SC-001 abaixo |
| 5 — Ida e volta do evento | ✅ ver SC-002 abaixo |
| 6 — Relay inalcançável | ✅ `wss://relay.nostr.bg` ficou `indisponível` e os 3 padrão seguiram `conectado` |
| 7 — Gestão e persistência da lista | ✅ `banana` recusado com mensagem, lista intacta; relay adicionado sobreviveu a `force-stop` + reabertura |
| 8 — Perda e retorno de rede | ⚠️ **não executado** — ver pendências |
| 9 — Rajada de eventos | ✅ ver SC-006 abaixo |
| 10 — Build de release com permissão | ✅ `app-release.apk` gerado; `aapt2 dump permissions` lista **somente** `INTERNET` (mais a permissão interna de receiver do Flutter) |

### SC-001 — tempo até o primeiro relay conectado (limite: 5 s, 9 de 10 tentativas)

Método: 10 ciclos de `am force-stop` + `am start`, cronômetro iniciado em `RelayService.connectAll`
e registrado em `logcat` na primeira transição para `connected`.

`1067, 1099, 1058, 897, 1328, 1364, 935, 1235, 1380, 1256` ms
→ **10/10 dentro do limite**; mínimo 0,90 s, máximo 1,38 s, mediana ≈ 1,18 s.

### SC-002 — ida e volta do evento (limite: 5 s, 9 de 10 tentativas)

Método: 10 publicações pela interface; cronômetro iniciado na publicação e parado quando o próprio
evento reaparece no `EventFeed`, identificado pelo `id`.

`377, 286, 324, 334, 401, 340, 332, 266, 418, 315` ms
→ **10/10 dentro do limite**; mínimo 266 ms, máximo 418 ms, mediana ≈ 333 ms.

Confirmação independente: `dart run tool/verify_published.dart <pubkey>` encontrou o evento
`TCC-UFSC-teste-de-conectividade` nos **três** relays, com `assinatura_ok=true` e o mesmo `id`
(`a6468343b2b1…`) em todos — prova de que a publicação saiu do aparelho e foi aceita pela rede.

### SC-006 — responsividade sob rajada (limite: ≥ 100 eventos sem congelamento perceptível)

⚠️ **Medição pré-emenda 01**: feita em 15/09, quando a inscrição não filtrava por marcador e o tráfego
social público da rede fornecia a rajada naturalmente. O resultado continua válido como evidência de
que a aplicação aguenta o volume, mas **o método descrito abaixo não é reproduzível na versão atual** —
ver o cenário 9 para a forma correta de provocar a rajada hoje.

Método: inscrição nos 3 relays públicos por 90 s, com contagem registrada a cada 25 eventos aceitos;
`logcat` inspecionado em busca de `Choreographer: Skipped N frames` e `Davey`.

- **125 eventos aceitos** em 90 s, 84 duplicatas absorvidas, 0 inválidos.
- Um único `Skipped 87 frames` às 23:06:15,8 — **durante o startup** (carga do Flutter às 23:06:14,4),
  antes do primeiro lote da rajada (23:06:18,5). Nenhum frame perdido durante a rajada.
- Janela de memória respeitada: a lista para de crescer no limite configurado.

→ Critério atendido para a rajada. O engasgo de startup é do build **debug** e fica registrado como
observação, não como aprovação disfarçada: medir em build de release é trabalho pendente.

### SC-007 — chave privada não vaza (verificação do Princípio I)

- `logcat` completo da sessão: **0** ocorrências de `nsec`, `private key` ou `chave privada`;
  **0** sequências hexadecimais de 64 caracteres.
- Tela de identidade: exibe só a chave pública; teste de widget garante que a privada não aparece em
  nenhum widget de texto.
- Em repouso: `FlutterSecureKeyStorage:br.ufsc.tcc.corridas.driver.xml` contém **ciphertext base64**,
  não a chave hexadecimal; a chave de cifragem fica no Android Keystore.
- As preferências comuns (`br.ufsc.tcc.corridas.driver.xml`) não contêm material criptográfico.

### Pendências honestas desta execução

1. **Cenário 8 (perda e retorno de rede) não foi executado.** `adb shell svc wifi/data disable` no
   emulador derruba também a ponte com o host, o que impediria a coleta do resultado. A reconexão está
   coberta por teste automatizado (`reconecta automaticamente os indisponíveis quando a rede volta` e
   `reentrega após reconexão não duplica evento já visto`), mas **não** foi verificada em aparelho.
   Requer aparelho físico ou desligar apenas os dados móveis do emulador por outro caminho.
2. **Medições feitas em build debug.** Os números de SC-001, SC-002 e SC-006 tendem a melhorar em
   release; nenhum deles está perto do limite, então a conclusão não muda.
3. **Uma única sessão de medição.** Relays públicos variam de carga ao longo do dia; repetir em outro
   horário fortaleceria a análise do TCC.

---

## Emenda 01 — verificação de 16/09/2026

Ambiente: mesmo emulador `Pixel_6_API34_1`, build debug. A emenda acrescentou o marcador
`["t", "tcc-ufsc-caronas"]` na publicação, o filtro `#t` na inscrição e o descarte de evento sem
marcador (regra 6 do contrato).

### SC-009 — proporção de eventos do protótipo na lista (limite: ≥ 95%)

Método: aplicativo aberto por 2 minutos com os relays padrão, contando os eventos exibidos e sua
origem. A instrumentação de debug registra os descartes por marcador ausente.

| Medição | Antes da emenda (15/09) | Depois da emenda (16/09) |
|---|---|---|
| Eventos exibidos | 125 em 90 s | **3 em 120 s** |
| Do protótipo | 0 | **3 (100%)** |
| Tráfego social alheio exibido | 125 | **0** |

→ **SC-009 atendido com folga**: 100% contra o limite de 95%.

Os três eventos exibidos são: o publicado por este aplicativo (`TCC-emenda01-motorista`, autor
`2e70c9a4…cea61556`) e **dois da aplicação do passageiro** (autores `df48cfee…` e `0ff59334…`) — ou
seja, a emenda foi verificada com tráfego real das duas apps, não só com o próprio eco.

### SC-002 após a emenda

Ida e volta do evento com marcador: **526 ms** (limite 5 s). A tag entra no cálculo do identificador
canônico, portanto passa a fazer parte do que a assinatura protege — confirmado por teste automatizado.

### Efeito colateral positivo

A rajada que motivava SC-006 deixou de ser o caminho normal de inicialização. O critério continua
válido como cenário extremo, mas o comportamento cotidiano do aplicativo passou a ser o oposto: lista
enxuta, só com tráfego do protótipo.

### Achado para a monografia

O Nostr **não oferece isolamento de aplicação**. Um app de corridas sobre relays públicos compartilha o
mesmo espaço de eventos que toda a rede social, e a separação é **convenção** — uma tag combinada entre
as partes —, não garantia do protocolo. Qualquer terceiro pode publicar com a mesma tag, o que empurra
toda a confiança para a verificação de assinatura e a checagem de autoria. É diferença arquitetural
concreta em relação a um aplicativo de corridas com backend próprio, onde o isolamento é dado.
