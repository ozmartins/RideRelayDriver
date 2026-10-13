# Plano de implementação: 025-conexao-em-segundo-plano

**Spec**: [spec.md](spec.md) · **App**: `driver/` · **Data**: 2026-10-11 · **Plano de origem**:
`/home/oseias/.claude/plans/como-o-app-do-vectorized-feigenbaum.md`

## Resumo

Mover a conexão com os relays (`RelayService` + `NostrRelayGateway`) para o isolate de um **serviço em primeiro
plano do Android**, que vive enquanto o app está visível ou o motorista está online. A interface passa a falar com
a conexão por uma interface (`RelayConnection`), implementada por `RelayService` (testes e serviço) e por
`RemoteRelayConnection` (produção, por mensagens). O serviço aplica a mesma regra de aceitação de solicitação que
a modal hoje aplica e, com o app fora de primeiro plano, mostra uma notificação local de alta importância. Sem
FCM, sem servidor, sem mudança de contrato.

## Contexto técnico

- **Linguagem/SDK**: Dart ^3.13.3, Flutter 3.47.7, Android apenas.
- **Dependências novas** (Princípio III, detalhes em [research.md](research.md)): `flutter_foreground_task`
  11.0.3 (2026-09-07), `flutter_local_notifications` 22.3.1 (2026-09-13); `pub add --dry-run` resolve (traz
  `timezone` transitivo).
- **Armazenamento**: `KeyValueStore` (SharedPreferences) para o estado que o serviço relê (ver
  [data-model.md](data-model.md)). Sem tabela SQLite nova.
- **Testes**: `flutter_test` com dublês; nenhum teste toca rede, serviço Android ou notificação reais.
- **Alvo**: Android 13+ (`POST_NOTIFICATIONS`), tipado de serviço em primeiro plano exigido no 14+.
- **Restrições**: chave privada nunca no serviço (Princípio I); verificação de assinatura antes de tudo (II/IV);
  tipos de plugin confinados a `services/` (III); `RelayConnection` nasce com duas implementações (V).
- **Escala**: três relays padrão, tráfego de solicitações esparso; o canal entre isolates carrega no máximo a
  rota de 1000 pontos cifrada (≈ 33 KB, medida na 019) — dentro do que `SendPort` aceita sem cópia especial.

## Verificação da constituição (2.12.0)

| Princípio / restrição | Situação |
|---|---|
| I — segredo não vaza | OK por construção: o serviço não lê a chave nem decifra; só repassa `payload` já assinado. Verificação de não vazamento (inspeção do canal e de log) entra em tarefa e no quickstart. |
| II — assinatura nasce com teste | OK: a verificação no serviço reutiliza `NostrEventVerifier`; teste novo cobre inválido, duplicado e sem marcador **na fronteira do serviço**; `RideRequestFilter` testado nos casos aceita/recusa. |
| III — dependência registrada | Pendente de `research.md` (escrito neste plano). Tipos de plugin só em `services/`. |
| IV — contrato antes do código | Nenhum evento novo. Contrato interno UI↔serviço em [contracts/service-channel.md](contracts/service-channel.md). |
| V — simplicidade | `RelayConnection` tem duas implementações reais; nada de camada sem consumidor. Medições da SC-001/SC-004/SC-006 serão feitas de fato. |
| Permissões "para o futuro" | `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_SPECIAL_USE`, `POST_NOTIFICATIONS` são usadas por esta feature; `WAKE_LOCK` não é declarada (o spike provou que é desnecessário; remover a mescla do plugin). **Sem** localização em segundo plano. |
| Execução em segundo plano / notificação | **Não coberta pela constituição** → exige **emenda 2.14.0** nas duas apps (+ conferir a de `Prototipo/`), commit separado **antes** do código (gate). Texto proposto abaixo. |
| Dados fora de relay | Nada novo sai do aparelho; a notificação é local. |
| Identidade visual | Notificação do sistema; ícone/cor `roxo` do app. Sem tela nova. |

**Emenda 2.14.0 (texto proposto, em Restrições de Segurança e Privacidade):** "O app do motorista pode manter um
serviço em primeiro plano do Android, ativo enquanto o app está visível ou o motorista online, que hospeda a
conexão com os relays configurados e mostra notificações locais. O serviço MUST NOT ler nem receber a chave
privada, MUST NOT decifrar mensagens, MUST NOT acessar localização, e a notificação de solicitação MUST NOT conter
endereço, coordenada, nome ou chave pública de terceiros. Nenhum serviço de push de terceiros é permitido."
Aplica-se ao motorista; o passageiro registra a mesma seção como não utilizada (espelho de texto).

## Estrutura do código

```text
driver/lib/
├── domain/
│   ├── ride_request_filter.dart        # novo: regra pura de aceitação (FR-005) usada por UI e serviço
│   └── service_state.dart              # novo: estado que o serviço relê (online, pagamentos, corrida, foreground)
├── services/
│   ├── relay_connection.dart           # novo: interface (relays, hasConnectedRelay, incoming, statusChanges,
│   │                                   #   publish, reconnectNow, addRelay, removeRelay, connectAll)
│   ├── relay_service.dart              # implementa RelayConnection (sem mudar comportamento)
│   ├── remote_relay_connection.dart    # novo: lado da interface, fala com o serviço por mensagens
│   ├── background/
│   │   ├── service_messages.dart       # novo: (de)serialização das mensagens do canal
│   │   ├── relay_task_handler.dart     # novo: TaskHandler — hospeda RelayService, verifica, filtra, notifica
│   │   ├── service_controller.dart     # novo: ciclo de vida (quando iniciar/encerrar, textos da notificação fixa)
│   │   └── background_service.dart     # novo: start/stop/estado do serviço (única fronteira com o plugin)
│   └── ride_request_notifier.dart      # novo: flutter_local_notifications (canal de alta importância)
├── screens/map_screen.dart             # tipo do parâmetro vira RelayConnection; usa RideRequestFilter;
│                                       #   informa estado ao serviço; observa o ciclo de vida
└── main.dart                           # compõe RemoteRelayConnection em produção; dublê nos testes
driver/android/app/src/main/AndroidManifest.xml   # permissões, <service>, receptor do plugin
driver/test/{domain,services}/…         # testes novos (ver tasks)
```

**Decisão de estrutura**: sem módulo novo de pacote; a pasta `services/background/` concentra tudo que roda no
isolate do serviço para facilitar a leitura do avaliador e a revisão de vazamento (Princípio I).

## Ciclo de vida do serviço

`app abre → serviço inicia (notificação discreta)` · `online → texto "Você está online"` · `app sai de primeiro
plano & offline → serviço encerra` · `app sai & online → serviço continua` · `offline com app fechado → encerra`.
Ao reabrir com o serviço vivo: handshake de estado (FR-012) e reentrega das solicitações guardadas (≤ 5 min).

O Android 14+ só permite iniciar o serviço em primeiro plano com o app visível: o serviço sempre é iniciado pela
UI (abertura do app ou toque em "online"), nunca por receptor em segundo plano nem no boot.

## Riscos

1. O isolate do plugin sobrevive ao "deslizar dos recentes"? — **spike obrigatório** (T002) — feito, ver research.md D3, antes de qualquer
   refatoração. Se falhar: parar e voltar ao usuário.
2. Otimização de bateria de fabricantes e Doze — limitação documentada, medida no quickstart.
3. `dataSync` tem limite de 6 h/24 h no Android 15; por isso o tipo escolhido é `specialUse` (ver D3).
4. Refatoração de `MapScreen` (1716 linhas): trocar só o tipo do parâmetro e extrair a regra; sem reescrita.

## Complexity Tracking

Sem violação injustificada. A emenda 2.14.0 é pré-requisito, não exceção.
