import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/driver_coverage.dart';
import '../domain/nostr_event.dart';
import '../domain/relay.dart';
import 'relay_connection.dart';
import 'relay_gateway.dart';

/// Orquestra as conexões com os relays, o estado de cada um e a reconexão.
///
/// Mantém os tipos de `dart_nostr` fora do seu alcance: fala apenas com
/// [RelayGateway] e com o domínio (Princípio III).
class RelayService implements RelayConnection {
  RelayService(
    this._gateway, {
    this.connectTimeout = const Duration(seconds: 10),
    this.retryInterval = const Duration(seconds: 15),
    this.livenessInterval = const Duration(seconds: 30),
    this.livenessTimeout = const Duration(seconds: 10),
    this.subscriptionKinds = const [NostrEvent.kindRideRequest],
  }) {
    _lost = _gateway.connectionLost.listen(_handleConnectionLost);
  }

  final RelayGateway _gateway;

  /// Kinds pedidos na inscrição (REQ) real ao relay — MUST corresponder ao
  /// que a app efetivamente consome, conforme a seção "Forma da inscrição"
  /// do contrato de eventos. Antes da feature 010, este valor ficava fixo
  /// em `[1]` aqui dentro, independente de
  /// `EventFeed.acceptedKinds`: nenhum evento de domínio (`kind: 20001` em
  /// diante) chegava de um relay real, só nos testes, cujo dublê de
  /// `RelayGateway.subscribe` ignora este parâmetro — defeito encontrado
  /// durante a implementação desta feature, corrigido tornando o valor
  /// configurável e alinhado ao que `main.dart` já declarava em
  /// `EventFeed.acceptedKinds`.
  final List<int> subscriptionKinds;

  /// Tempo máximo de espera pelo handshake de um relay.
  final Duration connectTimeout;

  /// Intervalo entre retentativas automáticas dos relays indisponíveis.
  ///
  /// FR-014 exige reconexão **sem intervenção manual** quando a rede volta.
  /// Retentar periodicamente resolve isso sem dependência de monitoramento de
  /// conectividade: a própria tentativa é o teste de que a rede voltou. O botão
  /// de atualizar continua para quem não quiser esperar o próximo ciclo.
  final Duration retryInterval;

  /// Intervalo entre sondas de vivacidade dos relays conectados.
  ///
  /// Uma conexão pode morrer sem erro nem fechamento: depois de uma troca de
  /// Wi-Fi para dados móveis o TCP fica meio aberto e o socket não percebe por
  /// minutos. A biblioteca não expõe `pingInterval` do WebSocket, então a
  /// sonda é feita no nível do protocolo.
  final Duration livenessInterval;

  /// Prazo para o relay responder à sonda antes de ser dado como caído.
  final Duration livenessTimeout;

  DriverCoverage? _coverage;

  late final StreamSubscription<String> _lost;
  Timer? _retryTimer;
  Timer? _livenessTimer;
  final Set<String> _probing = {};
  bool _disposed = false;

  final List<Relay> _relays = [];
  final StreamController<IncomingEvent> _incomingEvents =
      StreamController.broadcast();
  final StreamController<void> _statusChanges = StreamController.broadcast();
  StreamSubscription<IncomingEvent>? _incoming;

  @override
  DriverCoverage? get coverage => _coverage;

  /// Guarda a cobertura e repassa as células ao gateway, que refaz a inscrição
  /// do `20001` (feature 027). Relay que conectar depois já nasce com elas.
  @override
  Future<void> applyCoverage(DriverCoverage? coverage) async {
    if (_disposed) return;
    _coverage = coverage;
    await _gateway.setRideRequestCells(coverage?.cells);
  }

  /// Estado atual de cada relay, em ordem de inclusão.
  @override
  List<Relay> get relays => List.unmodifiable(_relays);

  /// Verdadeiro se ao menos um relay está conectado (FR-003).
  @override
  bool get hasConnectedRelay =>
      _relays.any((r) => r.status == RelayStatus.connected);

  /// Eventos brutos recebidos dos relays, sem verificação nem deduplicação.
  ///
  /// Quem verifica a assinatura e deduplica é o `EventFeed`, para manter a
  /// divisão registrada no plano: este serviço cuida de conexões.
  @override
  Stream<IncomingEvent> get incoming => _incomingEvents.stream;

  /// Emite sempre que o estado de algum relay muda, para a interface redesenhar.
  @override
  Stream<void> get statusChanges => _statusChanges.stream;

  /// Cronômetro da rodada de conexão atual, usado só para medição em debug.
  final Stopwatch _connectClock = Stopwatch();
  bool _firstConnectedReported = false;

  /// Conecta a todos os relays da lista, de forma independente (FR-001).
  @override
  Future<void> connectAll(List<Relay> relays) async {
    _connectClock
      ..reset()
      ..start();
    _firstConnectedReported = false;
    _relays
      ..clear()
      ..addAll(
        relays.map(
          (r) => r.copyWith(status: RelayStatus.connecting, clearError: true),
        ),
      );
    _notify();
    _listenToIncoming();

    await Future.wait(_relays.map((relay) => _connect(relay.url)));
  }

  /// Nova tentativa para todos os relays indisponíveis (FR-014).
  ///
  /// Só os `unavailable`: um relay em `connecting` já tem tentativa em curso, e
  /// abrir outra por cima deixaria duas conexões disputando o mesmo relay.
  Future<void> reconnectUnavailable() async {
    final pendentes = _relays
        .where((r) => r.status == RelayStatus.unavailable)
        .map((r) => r.url)
        .toList();
    if (pendentes.isEmpty) return;

    for (final url in pendentes) {
      _update(url, status: RelayStatus.connecting, clearError: true);
    }
    _notify();

    await Future.wait(pendentes.map(_connect));
  }

  /// Reconexão a pedido do usuário (botão "Reconectar").
  ///
  /// Antes de retentar os indisponíveis, sonda os conectados na hora: uma
  /// conexão meio aberta continuaria exibida como "conectada" até o próximo
  /// ciclo de vivacidade, e o botão pareceria não fazer nada. Quem não
  /// responde à sonda vira indisponível e entra na mesma rodada.
  @override
  Future<void> reconnectNow() async {
    if (_disposed) return;
    final conectados = _relays
        .where((r) => r.status == RelayStatus.connected)
        .map((r) => r.url)
        .toList();
    await Future.wait(
      conectados.map(
        // Sonda já pendente corre contra o próprio prazo; não empilha outra.
        (url) => _probing.add(url) ? _probe(url) : Future<void>.value(),
      ),
    );
    if (_disposed) return;
    await reconnectUnavailable();
  }

  /// Acrescenta um relay à lista e tenta conectar (FR-011, US4 cenário 1).
  @override
  Future<void> addRelay(String url) async {
    final relay = Relay(url: url.trim(), status: RelayStatus.connecting);
    if (_relays.contains(relay)) return;
    _relays.add(relay);
    _notify();
    await _connect(relay.url);
  }

  /// Remove um relay da lista e encerra sua conexão (FR-011, US4 cenário 3).
  @override
  Future<void> removeRelay(String url) async {
    _relays.removeWhere((r) => r == Relay(url: url));
    _notify();
    await _gateway.disconnect(url);
  }

  /// Publica um evento assinado, reportando o resultado por relay (FR-007).
  @override
  Stream<PublishOutcome> publish(
    NostrEvent event, {
    required Map<String, dynamic> payload,
  }) {
    if (!hasConnectedRelay) throw NoConnectedRelay();
    return _gateway.publish(event, payload: payload);
  }

  /// Liga a manutenção automática das conexões exigida por FR-014: retentativa
  /// dos indisponíveis e sonda de vivacidade dos conectados. Idempotente.
  ///
  /// Separado de [connectAll] para que os testes de unidade que não tratam de
  /// reconexão não precisem conviver com um relógio rodando.
  @override
  void enableAutoRetry() {
    if (_disposed) return;
    _retryTimer ??= Timer.periodic(retryInterval, (_) {
      if (_relays.any((r) => r.status == RelayStatus.unavailable)) {
        reconnectUnavailable();
      }
    });
    _livenessTimer ??= Timer.periodic(livenessInterval, (_) => _probeAll());
  }

  void _probeAll() {
    final conectados = _relays
        .where((r) => r.status == RelayStatus.connected)
        .map((r) => r.url);
    for (final url in conectados) {
      // Sonda pendente ainda corre contra o próprio prazo; não empilha outra.
      if (_probing.add(url)) unawaited(_probe(url));
    }
  }

  Future<void> _probe(String url) async {
    try {
      await _gateway.probe(url).timeout(livenessTimeout);
    } catch (_) {
      if (!_disposed) await _handleUnresponsive(url);
    } finally {
      _probing.remove(url);
    }
  }

  Future<void> _handleUnresponsive(String url) async {
    final index = _relays.indexWhere((r) => r == Relay(url: url));
    if (index == -1 || _relays[index].status != RelayStatus.connected) return;
    _update(
      url,
      status: RelayStatus.unavailable,
      error: 'sem resposta do relay',
    );
    _notify();
    await _gateway.disconnect(url);
  }

  /// Idempotente: chamar duas vezes não é erro.
  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _retryTimer?.cancel();
    _retryTimer = null;
    _livenessTimer?.cancel();
    _livenessTimer = null;
    await _lost.cancel();
    await _incoming?.cancel();
    await _incomingEvents.close();
    await _statusChanges.close();
  }

  Future<void> _connect(String url) async {
    try {
      await _gateway.connect(url).timeout(connectTimeout);
      _update(url, status: RelayStatus.connected, clearError: true);
      if (kDebugMode && !_firstConnectedReported) {
        _firstConnectedReported = true;
        debugPrint(
          '[medicao] primeiro relay conectado em '
          '${_connectClock.elapsedMilliseconds}ms ($url)',
        );
      }
    } on TimeoutException {
      _update(
        url,
        status: RelayStatus.unavailable,
        error: 'sem resposta dentro do tempo limite',
      );
    } catch (error) {
      _update(
        url,
        status: RelayStatus.unavailable,
        error: describeFailure(error),
      );
    }
    _notify();
  }

  /// A conexão de um relay caiu depois de estabelecida. Relay que já saiu da
  /// lista é ignorado; os demais voltam pelo ciclo de retentativas.
  void _handleConnectionLost(String url) {
    final index = _relays.indexWhere((r) => r == Relay(url: url));
    if (index == -1) return;
    if (_relays[index].status != RelayStatus.connected) return;
    _update(
      url,
      status: RelayStatus.unavailable,
      error: 'conexão encerrada pelo relay',
    );
    _notify();
  }

  void _listenToIncoming() {
    _incoming?.cancel();
    _incoming = _gateway
        .subscribe(kinds: subscriptionKinds, rideRequestCells: _coverage?.cells)
        .listen(_handleIncoming);
  }

  void _handleIncoming(IncomingEvent incoming) {
    if (!_incomingEvents.isClosed) _incomingEvents.add(incoming);
  }

  void _update(
    String url, {
    RelayStatus? status,
    String? error,
    bool clearError = false,
  }) {
    final index = _relays.indexWhere((r) => r == Relay(url: url));
    if (index == -1) return;
    _relays[index] = _relays[index].copyWith(
      status: status,
      lastError: error,
      clearError: clearError,
    );
  }

  void _notify() {
    if (!_statusChanges.isClosed) _statusChanges.add(null);
  }

  /// Traduz a falha técnica em mensagem compreensível (FR-015).
  ///
  /// Exibir `WebSocketChannelException: SocketException: Failed host lookup`
  /// para o motorista não o ajuda a decidir nada. O texto original continua
  /// disponível no log de depuração, não na interface.
  static String describeFailure(Object error) {
    final bruto = (error is StateError ? error.message : error.toString())
        .toLowerCase();

    if (bruto.contains('failed host lookup') ||
        bruto.contains('nodename nor servname') ||
        bruto.contains('no address associated')) {
      return 'endereço não encontrado';
    }
    if (bruto.contains('connection refused')) {
      return 'conexão recusada pelo relay';
    }
    if (bruto.contains('timed out') || bruto.contains('timeout')) {
      return 'sem resposta dentro do tempo limite';
    }
    if (bruto.contains('certificate') || bruto.contains('handshake')) {
      return 'falha na conexão segura';
    }
    if (bruto.contains('network is unreachable') ||
        bruto.contains('no route to host')) {
      return 'sem acesso à rede';
    }
    if (bruto.contains('connection closed') || bruto.contains('encerrada')) {
      return 'conexão encerrada pelo relay';
    }
    return 'não foi possível conectar';
  }
}
