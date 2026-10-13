import 'dart:async';
import 'dart:collection';

import '../../domain/nostr_event.dart';
import '../../domain/ride_request_filter.dart';
import '../../domain/service_state.dart';
import '../event_verifier.dart';
import '../prototype_marker.dart';
import '../relay_connection.dart';
import '../relay_gateway.dart';
import '../relay_repository.dart';
import '../ride_request_notifier.dart';
import 'message_channel.dart';
import 'service_messages.dart';
import 'service_state_store.dart';

/// O que roda dentro do serviço em segundo plano (feature 025): hospeda a
/// conexão com os relays, verifica o que chega, repassa à interface e decide
/// quando uma solicitação de corrida merece notificação.
///
/// Não conhece o plugin do serviço nem a chave privada — só uma
/// [RelayConnection], um [MessageChannel] e um [RideRequestNotifier], todos
/// injetados, o que o deixa testável sem rede, sem Android e sem identidade
/// (Princípios I e II; constituição 2.14.0).
class RelayHostCore {
  RelayHostCore({
    required this.relays,
    required this.channel,
    required this.stateStore,
    required this.relayRepository,
    required this.notifier,
    required this.acceptedKinds,
    this.verifier = const NostrEventVerifier(),
    this.pendingValidity = const Duration(minutes: 5),
    this.maxSeenIds = 500,
    DateTime Function()? now,
    this.onStopRequested,
  }) : _now = now ?? DateTime.now;

  /// A conexão com os relays que este serviço hospeda.
  final RelayConnection relays;

  /// A ponta do canal que fala com a interface.
  final MessageChannel channel;

  final ServiceStateStore stateStore;
  final RelayRepository relayRepository;
  final RideRequestNotifier notifier;

  /// Kinds que o app consome; os demais são ignorados sem erro.
  final Set<int> acceptedKinds;
  final DateTime Function() _now;

  /// Verificador de assinatura (com recálculo do `id`). Injetável para teste.
  final EventVerifier verifier;

  /// Por quanto tempo uma solicitação recebida sem a interface visível continua
  /// valendo para a reentrega (FR-007).
  final Duration pendingValidity;

  /// Tamanho da janela de ids vistos, para a memória não crescer sem limite.
  final int maxSeenIds;

  /// Chamado quando a interface pede para encerrar o serviço.
  final Future<void> Function()? onStopRequested;

  ServiceState _state = const ServiceState();
  final LinkedHashSet<String> _seenIds = LinkedHashSet<String>();
  final List<_Pending> _pending = [];
  final List<StreamSubscription<Object?>> _subscriptions = [];
  final Map<int, StreamSubscription<PublishOutcome>> _publishing = {};
  bool _disposed = false;

  int _discardedInvalid = 0;
  int _discardedUnmarked = 0;
  int _discardedDuplicate = 0;

  /// Eventos descartados por assinatura inválida ou malformação.
  int get discardedInvalidCount => _discardedInvalid;

  /// Eventos legítimos, mas sem o marcador do protótipo (regra 6 do contrato).
  int get discardedUnmarkedCount => _discardedUnmarked;

  /// Entregas repetidas (mesmo `id`) absorvidas.
  int get discardedDuplicateCount => _discardedDuplicate;

  /// O estado que a interface mandou por último (ou o persistido).
  ServiceState get state => _state;

  /// Conecta sozinho a partir da lista persistida (não depende da interface) e
  /// avisa que está pronto.
  ///
  /// [restoreState] diz se o estado guardado vale: sim quando o sistema
  /// reiniciou o serviço sozinho (a interface não está aí para refazê-lo), não
  /// quando o app o iniciou — o motorista sempre abre offline (feature 004), e
  /// um `online` esquecido por um processo morto não pode voltar à vida.
  Future<void> start({bool restoreState = true}) async {
    if (restoreState) {
      _state = await stateStore.load();
    } else {
      _state = const ServiceState();
      await stateStore.save(_state);
    }

    _subscriptions
      ..add(channel.incoming.listen(_onMessage))
      ..add(relays.incoming.listen(_onIncoming))
      ..add(
        relays.statusChanges.listen(
          (_) => channel.send(ServiceRelaysChanged(relays.relays)),
        ),
      );

    final lista = await relayRepository.load();
    // Avisa antes de conectar: a interface pode enviar comandos já, e eles
    // esperam na fila do canal enquanto os relays conectam.
    channel.send(const ServiceReady());
    await relays.connectAll(lista);
    relays.enableAutoRetry();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final s in _subscriptions) {
      await s.cancel();
    }
    for (final s in _publishing.values) {
      await s.cancel();
    }
    _publishing.clear();
    await relays.dispose();
    await channel.close();
  }

  // ---------------------------------------------------------------- recepção

  void _onIncoming(IncomingEvent incoming) {
    final payload = incoming.payload;

    // 1. assinatura antes de qualquer outro processamento (Princípio IV)
    if (!verifier.isValid(payload)) {
      _discardedInvalid++;
      return;
    }

    // kind desconhecido é ignorado sem erro (contrato, regra 4)
    final kind = payload['kind'] as int;
    if (!acceptedKinds.contains(kind)) return;

    // 2. marcador do protótipo (contrato, regra 6)
    if (!hasPrototypeMarker(payload['tags'] as List<dynamic>?)) {
      _discardedUnmarked++;
      return;
    }

    // 3. deduplicação por id entre os relays
    final id = payload['id'] as String;
    if (!_seenIds.add(id)) {
      _discardedDuplicate++;
      return;
    }
    if (_seenIds.length > maxSeenIds) _seenIds.remove(_seenIds.first);

    channel.send(
      ServiceIncoming(relayUrl: incoming.relayUrl, payload: payload),
    );

    if (kind == NostrEvent.kindRideRequest) {
      _onRideRequest(NostrEvent.fromVerifiedPayload(payload), payload);
    }
  }

  void _onRideRequest(NostrEvent event, Map<String, dynamic> payload) {
    // Com a interface visível quem trata é a modal.
    if (_state.appInForeground) return;

    // A mesma regra que abre a modal (FR-005).
    if (!RideRequestFilter.evaluate(event, _state).accepted) return;

    _pending.add(_Pending(payload, _now()));
    unawaited(notifier.notifyRideRequest(event.id));
  }

  // ------------------------------------------------------------------ comandos

  void _onMessage(ServiceMessage message) {
    switch (message) {
      case ServiceHello(:final foreground):
        _state = _state.copyWith(appInForeground: foreground);
        if (foreground) unawaited(notifier.cancelAll());
        channel.send(
          ServiceHelloAck(
            online: _state.online,
            relays: relays.relays,
            pending: _takePending(),
          ),
        );
      case ServiceStateUpdate(:final state):
        _state = state;
        if (state.appInForeground) unawaited(notifier.cancelAll());
        unawaited(stateStore.save(state));
      case ServiceConnectAll(relays: final lista):
        unawaited(relays.connectAll(lista));
      case ServiceAddRelay(:final url):
        unawaited(relays.addRelay(url));
      case ServiceRemoveRelay(:final url):
        unawaited(relays.removeRelay(url));
      case ServiceReconnectNow():
        // Responde sempre, mudando ou não algum estado: é o que a interface
        // espera para soltar o botão "Reconectando…".
        unawaited(
          relays.reconnectNow().whenComplete(
            () => channel.send(ServiceRelaysChanged(relays.relays)),
          ),
        );
      case ServicePublish(:final reqId, :final id, :final payload):
        _publish(reqId, id, payload);
      case ServiceStop():
        unawaited(_stop());
      // Só a interface recebe estas; chegando aqui são ignoradas.
      case ServiceReady() ||
          ServiceHelloAck() ||
          ServicePublishResult() ||
          ServiceRelaysChanged() ||
          ServiceIncoming():
        break;
    }
  }

  Future<void> _stop() async {
    await onStopRequested?.call();
    await dispose();
  }

  void _publish(int reqId, String id, Map<String, dynamic> payload) {
    if (!relays.hasConnectedRelay) {
      channel.send(
        ServicePublishResult(
          reqId: reqId,
          outcomes: const [],
          done: true,
          error: 'no_relay',
        ),
      );
      return;
    }
    final Stream<PublishOutcome> outcomes;
    try {
      outcomes = relays.publish(
        NostrEvent.fromVerifiedPayload(payload),
        payload: payload,
      );
    } on Object catch (_) {
      channel.send(
        ServicePublishResult(
          reqId: reqId,
          outcomes: const [],
          done: true,
          error: 'publish_failed',
        ),
      );
      return;
    }
    _publishing[reqId] = outcomes.listen(
      (o) => channel.send(
        ServicePublishResult(reqId: reqId, outcomes: [o], done: false),
      ),
      onDone: () {
        _publishing.remove(reqId);
        channel.send(
          ServicePublishResult(reqId: reqId, outcomes: const [], done: true),
        );
      },
      onError: (Object _) {
        _publishing.remove(reqId);
        channel.send(
          ServicePublishResult(
            reqId: reqId,
            outcomes: const [],
            done: true,
            error: 'publish_failed',
          ),
        );
      },
    );
  }

  /// As solicitações ainda válidas, entregues uma única vez à interface.
  List<Map<String, dynamic>> _takePending() {
    final limite = _now().subtract(pendingValidity);
    final validas = [
      for (final p in _pending)
        if (p.receivedAt.isAfter(limite)) p.payload,
    ];
    _pending.clear();
    return validas;
  }
}

class _Pending {
  _Pending(this.payload, this.receivedAt);
  final Map<String, dynamic> payload;
  final DateTime receivedAt;
}
