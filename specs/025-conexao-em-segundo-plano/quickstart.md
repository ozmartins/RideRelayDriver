# Quickstart: 025-conexao-em-segundo-plano

**Pré-requisitos**: dois aparelhos/emuladores (`flutter emulators --launch Pixel_6_API34_1`), relay em comum entre
passageiro e motorista, chave ORS (`--dart-define=ORS_API_KEY=...`) no motorista. `flutter pub get`.

## Automatizado
```bash
cd Prototipo/driver && flutter analyze && flutter test
flutter test test/domain/ride_request_filter_test.dart
flutter test test/services/background/
```
Esperado: sem avisos; suíte existente (464) + novos verdes. Nenhum teste toca rede/serviço real.

## Cenários em aparelho (registrar tudo, inclusive falhas — gate 3)
1. **Spike (T001)**: serviço de teste com WebSocket real + notificação, deslizar dos recentes, confirmar vivo.
2. **US1**: motorista online → deslizar app dos recentes → passageiro solicita → notificação ≤ 10 s → tocar → modal.
3. **US1.3**: app em primeiro plano → só a modal, sem notificação.
4. **Recusas**: pagamento não aceito, offline, em corrida → nenhuma notificação.
5. **US2**: notificação fixa "Você está online"; offline + sair do app → serviço e notificação somem.
6. **US3 / SC-004**: tela apagada 10 min, trocar Wi-Fi↔dados no meio, nova solicitação ainda chega.
7. **Retomada (FR-012)**: online → fechar → reabrir: abre online; sem GPS: abre offline e serviço encerra.
8. **Permissão**: negar `POST_NOTIFICATIONS` → aviso ao ficar online, serviço não inicia.
9. **Validade**: solicitação recebida com app fechado, abrir após > 5 min → não entra na fila.
10. **Forçar parada**: serviço morre (esperado); reabrir → offline.

## Verificação de não vazamento (Princípio I)
`adb logcat | grep -i -E "nsec|privkey|secret"` durante os cenários 2–7: vazio. Inspecionar as mensagens do canal
em teste: nenhuma contém chave/semente.

## Medições (método descrito junto do número — Princípio V)
- SC-001: 10 solicitações, tempo publicação→notificação (relógio do passageiro × `when` da notificação).
- SC-006: `adb shell dumpsys batterystats` 1 h, tela apagada, online.

## Resultados (emulador `Pixel_6_API34_1`, Android 14, 2026-10-12)

Método: app de debug instalado por `adb`; o passageiro foi simulado por um script descartável (fora do repositório)
que assina um `kind: 20001` válido com o marcador do protótipo e o publica nos três relays padrão, todos respondendo
`OK true`. Removido o app dos recentes por gesto na tela de recentes (conferido em `dumpsys activity recents`:
a tarefa some, o PID e o serviço continuam). **Nada abaixo foi medido em aparelho real.**

| Cenário | Resultado |
|---|---|
| 2 — online, app removido dos recentes, solicitação `pix` | Notificação em canal `ride_requests` (`importance=4`), título "Nova solicitação de corrida", texto "Toque para ver", sem endereço nem coordenada. `when` ≈ 0,7 s depois da publicação (1 amostra). Tocar abre o app **online** (retomada) e a modal "Solicitação de corrida" aparece. |
| 3 — app em primeiro plano | Só a modal; 0 notificações. |
| 4 — recusas | Pagamento não aceito (`cartao`, cadastro com dinheiro e PIX): 0 notificações. Offline com o app fechado: 0 notificações. *Em corrida: não testado em aparelho (coberto por teste automatizado).* |
| 5 — offline e sair do app | Serviço encerra (0 `isForeground=true`) e a notificação fixa some; voltar à tela religa o serviço e a tela Mais mostra os relays. |
| 7 — retomada | Reabrir pela notificação com o serviço vivo: abre online sozinho. Depois de reinstalar (processo morto) o app abre offline e o `online` guardado é descartado (defeito achado e corrigido na sessão: o serviço novo respondia online). *Sem GPS: só por teste automatizado.* |
| 8 — permissão | Com `POST_NOTIFICATIONS` revogada, o diálogo do sistema aparece ao tocar em "ficar online" (não ao abrir o app); concedida, o serviço roda. *Negada: só por teste automatizado.* |
| 6 / SC-004 — tela apagada 10 min com queda de rede de 25 s no meio (`svc wifi/data disable`) | O serviço seguiu em primeiro plano; solicitação publicada ao fim dos 10 min gerou notificação; 1 notificação. 1 amostra. |

Achados corrigidos durante a verificação (cada um em commit próprio): (1) o `online` de uma execução anterior
sobrevivia à morte do processo; (2) a solicitação reentregue chegava ao mapa antes de o app saber se o motorista
estava online e era recusada por "offline", então a modal nunca abria depois do toque na notificação.

**Pendente em aparelho real:** cenário 9 (solicitação com mais de 5 min), recusa em corrida, permissão negada,
retomada sem GPS, cenário 10 (Forçar parada), SC-001 com 10 amostras, SC-006 (bateria) e comportamento em
fabricantes com economia de bateria agressiva.

### Medições e verificações complementares (emulador, 2026-10-12)

**Cenário 10 — Forçar parada** (`am force-stop`): o serviço desaparece (0 `isForeground=true`, sem PID) e, ao reabrir, o
app abre offline e o serviço sobe de novo.

**SC-001 — latência publicação → notificação** (10 amostras, app removido dos recentes, motorista online). Método: um
script envia o mesmo evento aos três relays já conectados e registra o instante do envio (relógio do computador);
a latência é o `when` da notificação (relógio do aparelho, definido por `flutter_local_notifications` ao mostrá-la)
menos o instante do envio, corrigido pela diferença de relógio entre computador e aparelho (medida por `adb` no início,
284 ms; incerteza estimada em ± 50 ms por causa do `adb`). A rede do emulador tem RTT de 270 a 460 ms até os relays.

| Amostra | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 |
|---|---|---|---|---|---|---|---|---|---|---|
| Latência (ms) | 503 | 283 | 203 | 294 | 279 | 268 | 259 | 336 | 282 | 293 |

Mediana 283 ms, média 300 ms, máximo 503 ms, bem abaixo dos 10 s do critério. É **emulador com rede do computador**: não
representa dados móveis nem aparelho real, e a amostra não cobre relay lento ou reconexão no meio.

**Princípio I — não vazamento** (T030): (a) teste automatizado `no_secret_leak_test.dart`: nenhum arquivo do serviço
importa identidade, armazenamento de chave nem cifra; o núcleo não recebe `Identity` nem `KeyStore`; e uma publicação de
ponta a ponta (assinada e cifrada pela interface, publicada pelo serviço) não faz a chave privada aparecer em nenhuma
mensagem do canal nem no evento entregue ao relay — o teste falha se um `import` proibido for acrescentado (conferido
na hora). (b) `logcat` durante as 10 amostras, com o app fora dos recentes: 0 linhas do app e 0 ocorrências de
`nsec`, `privkey`, `private key`, `secret`, `seed`, `mnemonic` ou do valor cifrado da chave guardada no Keystore.
O `logcat` do app aberto não foi inspecionado nesta rodada.

**SC-006 — bateria por hora online com a tela apagada: NÃO MEDIDO.** O modelo de bateria do emulador não representa o
consumo de um aparelho; um número daqui seria estimativa apresentada como medição (Princípio V). Método a aplicar em
aparelho real: `adb shell dumpsys batterystats --reset`, 1 h online com tela apagada e a conexão ativa, depois
`dumpsys batterystats` e a parcela do pacote `br.ufsc.tcc.corridas.driver`; repetir offline para comparar.
