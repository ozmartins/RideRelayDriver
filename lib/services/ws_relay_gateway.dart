import 'dart:async';

import '../domain/nostr_event.dart' as domain;
import 'relay_gateway.dart';
import 'relay_protocol.dart';
import 'relay_transport.dart';
import 'ws_relay_transport.dart';

/// [RelayGateway] sobre o transporte WebSocket próprio (feature 028).
///
/// Monta e interpreta os frames do protocolo (`relay_protocol.dart`) e guarda o
/// estado de cada relay: a tentativa de conexão vigente, a conexão
/// estabelecida, a sonda pendente, as publicações aguardando `OK` e as
/// inscrições abertas. Não verifica assinatura nem filtra por conteúdo: entrega
/// o payload bruto, e quem verifica é o `EventFeed` (contrato, regra 1).
///
/// Não conhece a chave privada — recebe o evento já assinado — e não registra
/// payload nem conteúdo em log (Princípio I).
class WsRelayGateway implements RelayGateway {
  WsRelayGateway({
    this.transport = const WsRelayTransport(),
    this.connectionTimeout = const Duration(seconds: 10),
    this.publishTimeout = const Duration(seconds: 10),
  });

  final RelayTransport transport;

  /// Prazo do handshake.
  final Duration connectionTimeout;

  /// Prazo da confirmação (`OK`) de uma publicação.
  final Duration publishTimeout;

  /// Tentativa de conexão vigente por url. Uma tentativa que termina depois de
  /// [disconnect] — relay removido durante o handshake — ou depois de outra
  /// tentativa começar encontra outro valor aqui e fecha a própria conexão, em
  /// vez de registrá-la órfã e continuar entregando eventos do relay removido.
  final Map<String, Object> _attempts = {};

  /// Conexão estabelecida por url.
  final Map<String, _Link> _links = {};

  final StreamController<IncomingEvent> _incoming =
      StreamController<IncomingEvent>.broadcast();
  final StreamController<String> _lost = StreamController<String>.broadcast();

  List<int> _kinds = const [domain.NostrEvent.kindRideRequest];
  List<String>? _cells;
  bool _subscribing = false;

  @override
  Stream<String> get connectionLost => _lost.stream;

  @override
  Future<void> connect(String relayUrl) async {
    await disconnect(relayUrl);
    final attempt = Object();
    _attempts[relayUrl] = attempt;

    final RelaySocket socket;
    try {
      socket = await transport.connect(relayUrl, timeout: connectionTimeout);
    } catch (error) {
      if (identical(_attempts[relayUrl], attempt)) _attempts.remove(relayUrl);
      throw StateError(_describe(error));
    }

    if (!identical(_attempts[relayUrl], attempt)) {
      await _closeQuietly(socket);
      throw StateError('conexão cancelada');
    }

    final link = _Link(socket);
    _links[relayUrl] = link;
    // Depois do handshake, erro ou fim do stream é queda de conexão.
    link.subscription = socket.messages.listen(
      (texto) => _onMessage(relayUrl, link, texto),
      onError: (Object _) => _dropped(relayUrl, link),
      onDone: () => _dropped(relayUrl, link),
    );

    if (_subscribing) _openSubscriptions(link);
  }

  @override
  Future<void> disconnect(String relayUrl) async {
    _attempts.remove(relayUrl);
    // O _Link sai do mapa antes de o socket fechar: o fechamento pedido
    // encontra outro valor em `_dropped` e não vira queda.
    final link = _links.remove(relayUrl);
    if (link == null) return;
    final erro = StateError('conexão com $relayUrl encerrada');
    link.probe?.completeError(erro);
    link.probe = null;
    for (final pendente in link.pendingOk.values) {
      pendente.completeError(erro);
    }
    link.pendingOk.clear();
    await link.subscription?.cancel();
    await _closeQuietly(link.socket);
  }

  static Future<void> _closeQuietly(RelaySocket socket) async {
    try {
      await socket.close();
    } catch (_) {
      // Desconectar é melhor-esforço: relay já caído não precisa de despedida.
    }
  }

  /// Descarta a conexão caída e avisa quem acompanha o estado dos relays.
  ///
  /// Só age se [link] ainda for a conexão registrada para [relayUrl]: o
  /// fechamento provocado por [disconnect] — ou uma queda atrasada de uma
  /// conexão já substituída — não pode derrubar a conexão atual.
  void _dropped(String relayUrl, _Link link) {
    if (!identical(_links[relayUrl], link)) return;
    unawaited(disconnect(relayUrl));
    if (!_lost.isClosed) _lost.add(relayUrl);
  }

  void _onMessage(String relayUrl, _Link link, String texto) {
    if (!identical(_links[relayUrl], link)) return;

    // Qualquer mensagem do relay prova que a conexão está viva — inclusive uma
    // que o interpretador vai descartar —, então responde a sonda pendente.
    final sonda = link.probe;
    link.probe = null;
    if (sonda != null && !sonda.isCompleted) sonda.complete();

    switch (parseRelayFrame(texto)) {
      case EventFrame(:final subscriptionId, :final payload):
        // Só inscrições abertas por este gateway: o resto não foi pedido.
        if (link.subscriptions.contains(subscriptionId) &&
            !_incoming.isClosed) {
          _incoming.add(IncomingEvent(relayUrl: relayUrl, payload: payload));
        }
      case final OkFrame ok:
        final pendente = link.pendingOk.remove(ok.eventId);
        if (pendente != null && !pendente.isCompleted) pendente.complete(ok);
      case ClosedFrame(:final subscriptionId):
        // O relay encerrou a inscrição: o socket e as outras seguem. Sem
        // reenvio automático — repetir o mesmo filtro repetiria a recusa. Ela
        // volta na próxima conexão ou troca de células.
        link.subscriptions.remove(subscriptionId);
      case NoticeFrame() || EoseFrame() || null:
        break;
    }
  }

  @override
  Future<void> probe(String relayUrl) {
    final link = _links[relayUrl];
    if (link == null) {
      return Future.error(StateError('sem conexão com $relayUrl'));
    }
    final pendente = link.probe ??= Completer<void>();
    // Consulta por um id inexistente: o relay responde EOSE sem entregar nada.
    // O CLOSE logo em seguida libera a inscrição do lado do relay.
    if (!_send(link, probeReqFrame()) ||
        !_send(link, closeFrame(probeSubscriptionId))) {
      link.probe = null;
      pendente.completeError(StateError('sem conexão com $relayUrl'));
    }
    return pendente.future;
  }

  @override
  Stream<IncomingEvent> subscribe({
    required List<int> kinds,
    List<String>? rideRequestCells,
  }) {
    _kinds = kinds;
    _cells = rideRequestCells;
    _subscribing = true;
    _links.values.toList().forEach(_openSubscriptions);
    return _incoming.stream;
  }

  @override
  Future<void> setRideRequestCells(List<String>? cells) async {
    if (_sameCells(_cells, cells)) return;
    _cells = cells;
    if (!_subscribing) return;
    // Refaz só a inscrição do 20001 em cada relay conectado: fecha a anterior
    // (`CLOSE`) e abre outra com as células novas. A dos demais kinds não é
    // tocada. Eventos repetidos que o relay devolver são deduplicados por `id`
    // adiante.
    for (final link in _links.values.toList()) {
      if (link.subscriptions.remove(rideRequestSubscriptionId)) {
        _send(link, closeFrame(rideRequestSubscriptionId));
      }
      _openSubscriptions(link);
    }
  }

  static bool _sameCells(List<String>? a, List<String>? b) {
    if (a == null || b == null) return a == b;
    return a.length == b.length && a.toSet().containsAll(b);
  }

  /// Abre, no [link], as inscrições que ainda não estão abertas, com os filtros
  /// vigentes. Chamado a cada conexão estabelecida e a cada troca de células.
  void _openSubscriptions(_Link link) {
    final filtros = buildFilters(_kinds, _cells);
    final geral = filtros.where((f) => !f.containsKey('#g'));
    final solicitacoes = filtros.where((f) => f.containsKey('#g'));
    _open(link, generalSubscriptionId, geral);
    _open(link, rideRequestSubscriptionId, solicitacoes);
  }

  void _open(
    _Link link,
    String subscriptionId,
    Iterable<Map<String, dynamic>> filtros,
  ) {
    if (filtros.isEmpty || link.subscriptions.contains(subscriptionId)) return;
    if (_send(link, reqFrame(subscriptionId, filtros.toList()))) {
      link.subscriptions.add(subscriptionId);
    }
  }

  /// Envia [texto]; falso se o socket já morreu (a queda chega por `onDone`).
  static bool _send(_Link link, String texto) {
    try {
      link.socket.send(texto);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Stream<PublishOutcome> publish(
    domain.NostrEvent event, {
    required Map<String, dynamic> payload,
  }) {
    final id = payload['id'] as String;
    final texto = eventFrame(payload);

    final controller = StreamController<PublishOutcome>();
    final pendentes = _links.entries
        .toList()
        .map(
          (entry) => _publishTo(
            entry.key,
            entry.value,
            id,
            texto,
          ).then(controller.add),
        )
        .toList();

    Future.wait(pendentes).whenComplete(controller.close);
    return controller.stream;
  }

  Future<PublishOutcome> _publishTo(
    String relayUrl,
    _Link link,
    String eventId,
    String texto,
  ) async {
    final resposta = Completer<OkFrame>();
    link.pendingOk[eventId] = resposta;
    try {
      link.socket.send(texto);
      final ok = await resposta.future.timeout(publishTimeout);
      return PublishOutcome(
        relayUrl: relayUrl,
        accepted: ok.accepted,
        message: ok.message,
      );
    } on TimeoutException {
      return PublishOutcome(
        relayUrl: relayUrl,
        accepted: false,
        message: 'sem resposta do relay',
      );
    } catch (error) {
      return PublishOutcome(
        relayUrl: relayUrl,
        accepted: false,
        message: _describe(error),
      );
    } finally {
      if (identical(link.pendingOk[eventId], resposta)) {
        link.pendingOk.remove(eventId);
      }
    }
  }

  static String _describe(Object? error) {
    if (error == null) return 'falha desconhecida';
    final texto = error is StateError ? error.message : error.toString();
    return texto.length > 80 ? '${texto.substring(0, 77)}…' : texto;
  }

  Future<void> dispose() async {
    for (final url in _links.keys.toList()) {
      await disconnect(url);
    }
    _attempts.clear();
    await _incoming.close();
    await _lost.close();
  }
}

/// Uma conexão estabelecida com um relay.
class _Link {
  _Link(this.socket);

  final RelaySocket socket;
  StreamSubscription<String>? subscription;

  /// Sonda de vivacidade aguardando qualquer mensagem do relay.
  Completer<void>? probe;

  /// Publicações aguardando o `OK`, por id do evento.
  final Map<String, Completer<OkFrame>> pendingOk = {};

  /// Inscrições abertas nesta conexão.
  final Set<String> subscriptions = {};
}
