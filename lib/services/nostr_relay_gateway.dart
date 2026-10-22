import 'dart:async';
import 'dart:convert';

import 'package:dart_nostr/dart_nostr.dart' as nostr;

import '../domain/nostr_event.dart' as domain;
import 'prototype_marker.dart';
import 'relay_gateway.dart';

/// Transporte real sobre `dart_nostr`.
///
/// Mantém **uma instância `Nostr` por relay**: a API da biblioteca gerencia um
/// pool interno com callbacks globais, e isolar por relay é o que permite tratar
/// conexão, falha e reconexão de forma independente, como FR-003 exige.
///
/// Único arquivo da aplicação, junto de `identity_service.dart` e
/// `event_verifier.dart`, que conhece tipos de `dart_nostr` (Princípio III).
class NostrRelayGateway implements RelayGateway {
  NostrRelayGateway({this.connectionTimeout = const Duration(seconds: 10)});

  /// Tempo máximo de espera pelo handshake e pela confirmação de publicação.
  final Duration connectionTimeout;
  final Map<String, nostr.Nostr> _instances = {};
  final Map<String, StreamSubscription<nostr.NostrEvent>> _subscriptions = {};

  /// A inscrição aberta em cada relay, para poder fechá-la (`CLOSE`) ao trocar
  /// as células do `20001`.
  final Map<String, nostr.NostrEventsStream> _streams = {};

  /// Sondas de vivacidade aguardando qualquer mensagem do relay.
  final Map<String, Completer<void>> _probes = {};
  final StreamController<IncomingEvent> _incoming =
      StreamController<IncomingEvent>.broadcast();
  final StreamController<String> _lost = StreamController<String>.broadcast();

  @override
  Stream<String> get connectionLost => _lost.stream;

  /// Tentativa de conexão vigente por url. Uma tentativa que termina depois de
  /// [disconnect] — relay removido durante o handshake — ou depois de outra
  /// tentativa começar encontra outro valor aqui e fecha a própria conexão, em
  /// vez de registrá-la órfã e continuar entregando eventos do relay removido.
  final Map<String, Object> _attempts = {};

  List<int> _kinds = const [domain.NostrEvent.kindRideRequest];
  List<String>? _cells;
  bool _subscribing = false;

  @override
  Future<void> connect(String relayUrl) async {
    await disconnect(relayUrl);
    final attempt = Object();
    _attempts[relayUrl] = attempt;

    final instance = nostr.Nostr();
    Object? connectionError;
    var established = false;

    // Depois do handshake, erro ou fechamento do socket é queda de conexão.
    // A biblioteca chama os dois callbacks numa mesma queda; só a primeira
    // chamada, com a instância ainda registrada, é repassada.
    void onDrop() {
      if (established) _dropped(relayUrl, instance);
    }

    // `onRelayListening` da biblioteca dispara quando **dados** chegam do
    // relay, não quando o socket conecta — esperar por ele daria timeout em
    // relay saudável mas silencioso. Quem sinaliza o resultado do handshake é
    // o retorno de `init` (com `ignoreConnectionException: false`, ele falha
    // em vez de engolir o erro) somado ao callback de erro.
    await instance.services.relays.init(
      relaysUrl: [relayUrl],
      connectionTimeout: connectionTimeout,
      // Sem retry da biblioteca: a política de reconexão é do RelayService,
      // que é quem conhece o estado exibido ao usuário (FR-014).
      retryOnError: false,
      retryOnClose: false,
      ignoreConnectionException: false,
      lazyListeningToRelays: false,
      // Dispara a cada mensagem recebida: qualquer dado prova que a conexão
      // está viva e responde a sonda pendente.
      onRelayListening: (url, data, socket) {
        if (identical(_instances[relayUrl], instance)) {
          _probes.remove(relayUrl)?.complete();
        }
      },
      onRelayConnectionError: (url, error, socket) {
        if (established) return onDrop();
        connectionError ??= error ?? 'conexão encerrada pelo relay';
      },
      onRelayConnectionDone: (url, socket) {
        if (established) return onDrop();
        connectionError ??= 'conexão encerrada pelo relay';
      },
    );

    if (!identical(_attempts[relayUrl], attempt)) {
      await _closeQuietly(instance);
      throw StateError('conexão cancelada');
    }

    if (connectionError != null) {
      _attempts.remove(relayUrl);
      throw StateError(_describe(connectionError));
    }

    established = true;
    _instances[relayUrl] = instance;

    if (_subscribing) _startSubscription(relayUrl, instance);
  }

  @override
  Future<void> disconnect(String relayUrl) async {
    _attempts.remove(relayUrl);
    _probes
        .remove(relayUrl)
        ?.completeError(StateError('conexão com $relayUrl encerrada'));
    _streams.remove(relayUrl);
    await _subscriptions.remove(relayUrl)?.cancel();
    final instance = _instances.remove(relayUrl);
    if (instance == null) return;
    await _closeQuietly(instance);
  }

  static Future<void> _closeQuietly(nostr.Nostr instance) async {
    try {
      await instance.services.relays.disconnectFromRelays();
    } catch (_) {
      // Desconectar é melhor-esforço: relay já caído não precisa de despedida.
    }
  }

  @override
  Future<void> probe(String relayUrl) {
    final socket = _instances[relayUrl]
        ?.services
        .relays
        .relaysWebSocketsRegistry[relayUrl];
    if (socket == null) {
      return Future.error(StateError('sem conexão com $relayUrl'));
    }
    final pendente = _probes.putIfAbsent(relayUrl, Completer<void>.new);
    // Consulta por um id inexistente: o relay responde EOSE sem entregar nada
    // e sem depender de kind nem de marcador. O CLOSE logo em seguida libera
    // a inscrição do lado do relay.
    socket.sink
      ..add(
        jsonEncode([
          'REQ',
          _probeSubscriptionId,
          {
            'ids': [_nonexistentId],
            'limit': 1,
          },
        ]),
      )
      ..add(jsonEncode(['CLOSE', _probeSubscriptionId]));
    return pendente.future;
  }

  static const _probeSubscriptionId = 'vivacidade';
  static const _nonexistentId =
      '0000000000000000000000000000000000000000000000000000000000000000';

  /// Descarta a conexão caída e avisa quem acompanha o estado dos relays.
  ///
  /// Só age se [instance] ainda for a conexão registrada para [relayUrl]: o
  /// fechamento provocado por [disconnect] — ou uma queda atrasada de uma
  /// conexão já substituída — não pode derrubar a conexão atual.
  void _dropped(String relayUrl, nostr.Nostr instance) {
    if (!identical(_instances[relayUrl], instance)) return;
    unawaited(disconnect(relayUrl));
    if (!_lost.isClosed) _lost.add(relayUrl);
  }

  @override
  Stream<IncomingEvent> subscribe({
    required List<int> kinds,
    List<String>? rideRequestCells,
  }) {
    _kinds = kinds;
    _cells = rideRequestCells;
    _subscribing = true;
    _instances.forEach(_startSubscription);
    return _incoming.stream;
  }

  @override
  Future<void> setRideRequestCells(List<String>? cells) async {
    if (_sameCells(_cells, cells)) return;
    _cells = cells;
    if (!_subscribing) return;
    // Refaz a inscrição de cada relay conectado: fecha a anterior (`CLOSE`) e
    // abre outra com as células novas. Eventos repetidos que o relay devolver
    // na nova inscrição são deduplicados por `id` adiante.
    for (final entry in _instances.entries.toList()) {
      await _stopSubscription(entry.key);
      _startSubscription(entry.key, entry.value);
    }
  }

  static bool _sameCells(List<String>? a, List<String>? b) {
    if (a == null || b == null) return a == b;
    return a.length == b.length && a.toSet().containsAll(b);
  }

  Future<void> _stopSubscription(String relayUrl) async {
    _streams.remove(relayUrl)?.close();
    await _subscriptions.remove(relayUrl)?.cancel();
  }

  /// Os filtros do `REQ` (emenda 27 do contrato): os kinds consumidos, exceto o
  /// `20001`, num filtro sempre presente; o `20001` num filtro à parte, com o
  /// `#g` das [cells], só quando há células (motorista online). Todos com o
  /// marcador `#t` e `limit: 50`. Vazio se não há nada a pedir.
  static List<nostr.NostrFilter> buildFilters(
    List<int> kinds,
    List<String>? cells,
  ) {
    final outros = [
      for (final k in kinds)
        if (k != domain.NostrEvent.kindRideRequest) k,
    ];
    final querSolicitacoes = kinds.contains(domain.NostrEvent.kindRideRequest);
    return [
      if (outros.isNotEmpty)
        // Filtro `#t` do contrato (emenda 01): sem ele, a inscrição traz o
        // tráfego público da rede inteira nos kinds pedidos. `limit: 50`
        // (emenda 02) bota um teto no histórico; sem `since`, que o passageiro
        // não pode replicar sem ficar cada vez mais velho a cada reconexão.
        nostr.NostrFilter(kinds: outros, t: const [prototypeMarker], limit: 50),
      if (querSolicitacoes && cells != null && cells.isNotEmpty)
        nostr.NostrFilter(
          kinds: const [domain.NostrEvent.kindRideRequest],
          t: const [prototypeMarker],
          additionalFilters: {'#g': cells},
          limit: 50,
        ),
    ];
  }

  @override
  Stream<PublishOutcome> publish(
    domain.NostrEvent event, {
    required Map<String, dynamic> payload,
  }) {
    final nostrEvent = nostr.NostrEvent(
      id: payload['id'] as String,
      kind: payload['kind'] as int,
      content: payload['content'] as String,
      sig: payload['sig'] as String,
      pubkey: payload['pubkey'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (payload['created_at'] as int) * 1000,
      ),
      tags: (payload['tags'] as List<dynamic>? ?? const [])
          .map((t) => (t as List<dynamic>).map((e) => e.toString()).toList())
          .toList(),
    );

    final controller = StreamController<PublishOutcome>();
    final pendentes = _instances.entries
        .map(
          (entry) => _publishTo(
            entry.key,
            entry.value,
            nostrEvent,
          ).then(controller.add),
        )
        .toList();

    Future.wait(pendentes).whenComplete(controller.close);
    return controller.stream;
  }

  Future<PublishOutcome> _publishTo(
    String relayUrl,
    nostr.Nostr instance,
    nostr.NostrEvent event,
  ) async {
    try {
      final ok = await instance.services.relays.sendEventToRelaysAsync(
        event,
        timeout: connectionTimeout,
      );
      return PublishOutcome(
        relayUrl: relayUrl,
        accepted: ok.isEventAccepted ?? false,
        message: ok.message?.isNotEmpty == true ? ok.message : null,
      );
    } catch (error) {
      return PublishOutcome(
        relayUrl: relayUrl,
        accepted: false,
        message: _describe(error),
      );
    }
  }

  void _startSubscription(String relayUrl, nostr.Nostr instance) {
    if (_subscriptions.containsKey(relayUrl)) return;

    final filtros = buildFilters(_kinds, _cells);
    if (filtros.isEmpty) return;
    final request = nostr.NostrRequest(filters: filtros);

    final stream = instance.services.relays.startEventsSubscription(
      request: request,
      relays: [relayUrl],
    );
    _streams[relayUrl] = stream;

    _subscriptions[relayUrl] = stream.stream.listen(
      (event) {
        if (_incoming.isClosed) return;
        _incoming.add(
          IncomingEvent(relayUrl: relayUrl, payload: _toPayload(event)),
        );
      },
      onError: (_) {
        // Erro na inscrição não derruba a aplicação: o estado do relay é
        // atualizado pelo RelayService na próxima tentativa.
      },
    );
  }

  static Map<String, dynamic> _toPayload(nostr.NostrEvent event) => {
    'id': event.id,
    'pubkey': event.pubkey,
    'created_at':
        (event.createdAt ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000,
    'kind': event.kind,
    'tags': event.tags ?? const <List<String>>[],
    'content': event.content,
    'sig': event.sig,
  };

  static String _describe(Object? error) {
    if (error == null) return 'falha desconhecida';
    final texto = error is StateError ? error.message : error.toString();
    return texto.length > 80 ? '${texto.substring(0, 77)}…' : texto;
  }

  Future<void> dispose() async {
    for (final url in _instances.keys.toList()) {
      await disconnect(url);
    }
    await _incoming.close();
    await _lost.close();
  }
}
