import 'dart:async';

import '../domain/driver_coverage.dart';
import '../domain/nostr_event.dart';
import '../domain/relay.dart';
import 'background/message_channel.dart';
import 'background/service_messages.dart';
import 'relay_connection.dart';
import 'relay_gateway.dart';

/// A [RelayConnection] vista pela interface quando a conexão vive no serviço em
/// segundo plano (feature 025): cada operação vira uma mensagem para o serviço,
/// e o estado dos relays e os eventos recebidos voltam por mensagens.
///
/// Os comandos enviados antes de o serviço responder ao `hello` esperam numa
/// fila e saem, na ordem, quando ele responde. O serviço pode estar ainda
/// subindo (a mensagem se perde se ninguém a recebe), então o `hello` é
/// repetido até a resposta.
class RemoteRelayConnection implements RelayConnection {
  RemoteRelayConnection(
    this._channel, {
    this.helloRetry = const Duration(milliseconds: 500),
    this.reconnectTimeout = const Duration(seconds: 15),
    this.maxHelloAttempts = 20,
  }) {
    _subscription = _channel.incoming.listen(_onMessage);
  }

  final MessageChannel _channel;

  /// Intervalo entre repetições do `hello` enquanto o serviço não responde.
  final Duration helloRetry;

  /// Quantas vezes o `hello` é enviado antes de desistir até o próximo
  /// [attach] — um serviço que não sobe não pode manter a interface mandando
  /// mensagem para ninguém para sempre.
  final int maxHelloAttempts;

  /// Prazo para o serviço responder a um "reconectar agora".
  final Duration reconnectTimeout;

  late final StreamSubscription<ServiceMessage> _subscription;
  final StreamController<IncomingEvent> _incoming =
      StreamController<IncomingEvent>.broadcast();
  final StreamController<void> _statusChanges =
      StreamController<void>.broadcast();
  final StreamController<void> _attachedEvents =
      StreamController<void>.broadcast();

  List<Relay> _relays = const [];
  DriverCoverage? _coverage;
  bool _attached = false;
  bool _disposed = false;
  bool _foreground = true;
  Timer? _helloTimer;
  final List<void Function()> _queue = [];
  final Map<int, StreamController<PublishOutcome>> _publishing = {};
  int _nextRequest = 0;

  /// Emite cada vez que o serviço responde ao `hello` — na primeira ligação e
  /// quando ele reinicia. Quem guarda estado a reenviar (o controlador do
  /// serviço) o reenvia aqui.
  Stream<void> get attached => _attachedEvents.stream;

  /// Verdadeiro depois de o serviço responder ao `hello`.
  bool get isAttached => _attached;

  /// O que o serviço dizia, no último `helloAck`, sobre o motorista estar
  /// online — o estado que ele guardou antes de a interface fechar (FR-012).
  bool get serviceOnline => _serviceOnline;
  bool _serviceOnline = false;

  @override
  DriverCoverage? get coverage => _coverage;

  /// Manda a cobertura ao serviço, que é quem assina o `20001` nos relays. Na
  /// fila, vale a cobertura de quando a mensagem sai, não a de quando foi
  /// pedida.
  @override
  Future<void> applyCoverage(DriverCoverage? coverage) async {
    if (_disposed) return;
    _coverage = coverage;
    _whenAttached(() => _channel.send(ServiceSetCoverage(_coverage)));
  }

  @override
  List<Relay> get relays => List.unmodifiable(_relays);

  @override
  bool get hasConnectedRelay =>
      _relays.any((r) => r.status == RelayStatus.connected);

  @override
  Stream<IncomingEvent> get incoming => _incoming.stream;

  @override
  Stream<void> get statusChanges => _statusChanges.stream;

  /// Apresenta-se ao serviço. Repete o `hello` até a resposta; chamar de novo
  /// (app voltando ao primeiro plano) refaz o handshake e entrega ao app as
  /// solicitações que o serviço guardou.
  void attach({required bool foreground}) {
    if (_disposed) return;
    _foreground = foreground;
    _attached = false;
    _helloTimer?.cancel();
    _sendHello();
    var tentativas = 1;
    _helloTimer = Timer.periodic(helloRetry, (timer) {
      if (++tentativas > maxHelloAttempts) {
        timer.cancel();
        _helloTimer = null;
        return;
      }
      _sendHello();
    });
  }

  /// Para de procurar o serviço: ele foi encerrado de propósito.
  void detach() {
    _helloTimer?.cancel();
    _helloTimer = null;
    _attached = false;
    _queue.clear();
  }

  void _sendHello() => _channel.send(ServiceHello(foreground: _foreground));

  void _onMessage(ServiceMessage message) {
    switch (message) {
      case ServiceReady():
        // Serviço (re)iniciado: o handshake anterior não vale mais.
        if (_attached || _helloTimer != null) attach(foreground: _foreground);
      case ServiceHelloAck(:final online, :final relays, :final pending):
        _helloTimer?.cancel();
        _helloTimer = null;
        _serviceOnline = online;
        _relays = relays;
        _attached = true;
        _statusChanges.add(null);
        // Reentrega pelo mesmo caminho de qualquer evento (verificação e
        // deduplicação do EventFeed valem também para ela).
        for (final payload in pending) {
          _incoming.add(
            IncomingEvent(relayUrl: _pendingSource, payload: payload),
          );
        }
        final fila = List.of(_queue);
        _queue.clear();
        for (final comando in fila) {
          comando();
        }
        // Serviço reiniciado: ele não guarda a cobertura em disco, então a
        // interface a devolve. Se a fila já a mandou, o reenvio é inócuo.
        if (_coverage != null) _channel.send(ServiceSetCoverage(_coverage));
        _attachedEvents.add(null);
      case ServiceRelaysChanged(:final relays):
        _relays = relays;
        _statusChanges.add(null);
      case ServiceIncoming(:final relayUrl, :final payload):
        _incoming.add(IncomingEvent(relayUrl: relayUrl, payload: payload));
      case ServicePublishResult():
        _onPublishResult(message);
      // Só o serviço recebe estas.
      case ServiceHello() ||
          ServiceStateUpdate() ||
          ServiceSetCoverage() ||
          ServiceConnectAll() ||
          ServiceAddRelay() ||
          ServiceRemoveRelay() ||
          ServiceReconnectNow() ||
          ServicePublish() ||
          ServiceStop():
        break;
    }
  }

  /// Origem atribuída a uma solicitação reentregue: o serviço a recebeu de um
  /// relay, mas qual deles já não importa.
  static const String _pendingSource = 'servico';

  /// Envia uma mensagem de controle ao serviço, na hora ou assim que ele
  /// responder ao `hello` — o estado do app, que o controlador do serviço
  /// manda.
  void sendToService(ServiceMessage message) =>
      _whenAttached(() => _channel.send(message));

  /// Executa [comando] agora, ou guarda até o serviço responder ao `hello`.
  void _whenAttached(void Function() comando) {
    if (_attached) {
      comando();
    } else {
      _queue.add(comando);
    }
  }

  @override
  Future<void> connectAll(List<Relay> relays) async {
    _whenAttached(() {
      // O serviço já conectou sozinho à lista persistida: reenviar a mesma
      // lista só faria derrubar e refazer conexões que estão boas.
      final iguais =
          relays.length == _relays.length &&
          relays.every((r) => _relays.contains(r));
      if (iguais) return;
      _channel.send(ServiceConnectAll(relays));
    });
  }

  @override
  Future<void> addRelay(String url) async =>
      _whenAttached(() => _channel.send(ServiceAddRelay(url)));

  @override
  Future<void> removeRelay(String url) async =>
      _whenAttached(() => _channel.send(ServiceRemoveRelay(url)));

  @override
  Future<void> reconnectNow() async {
    if (_disposed) return;
    final resposta = _statusChanges.stream.first;
    _whenAttached(() => _channel.send(const ServiceReconnectNow()));
    try {
      await resposta.timeout(reconnectTimeout);
    } on TimeoutException {
      // O serviço não respondeu a tempo; o botão volta mesmo assim.
    } on StateError {
      // Fechado durante a espera.
    }
  }

  @override
  Stream<PublishOutcome> publish(
    NostrEvent event, {
    required Map<String, dynamic> payload,
  }) {
    if (!hasConnectedRelay) throw NoConnectedRelay();
    final reqId = _nextRequest++;
    final controller = StreamController<PublishOutcome>();
    _publishing[reqId] = controller;
    _whenAttached(
      () => _channel.send(
        ServicePublish(reqId: reqId, id: event.id, payload: payload),
      ),
    );
    return controller.stream;
  }

  void _onPublishResult(ServicePublishResult resultado) {
    final controller = _publishing[resultado.reqId];
    if (controller == null || controller.isClosed) return;
    for (final outcome in resultado.outcomes) {
      controller.add(outcome);
    }
    if (!resultado.done) return;
    _publishing.remove(resultado.reqId);
    if (resultado.error == 'no_relay') {
      controller.addError(NoConnectedRelay());
    } else if (resultado.error != null) {
      controller.addError(StateError('publicação falhou: ${resultado.error}'));
    }
    unawaited(controller.close());
  }

  /// A retentativa e a sonda de vivacidade rodam no serviço.
  @override
  void enableAutoRetry() {}

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _helloTimer?.cancel();
    await _subscription.cancel();
    for (final c in _publishing.values) {
      await c.close();
    }
    _publishing.clear();
    await _incoming.close();
    await _statusChanges.close();
    await _attachedEvents.close();
  }
}
