import 'dart:async';

import 'package:driver/services/relay_transport.dart';

/// Transporte dublê: nenhum teste toca a rede (decisão D5).
///
/// Por padrão cada `connect` completa na hora com um [FakeRelaySocket] novo.
/// [failOn] faz o handshake de uma url falhar; [hold] o deixa pendente até o
/// teste liberar. Imita o transporte real: estourado o prazo, `connect` lança
/// `TimeoutException` e o socket que chegar depois é fechado.
class FakeRelayTransport implements RelayTransport {
  final List<FakeRelaySocket> sockets = [];
  final List<String> connectCalls = [];
  final Map<String, Object> _failures = {};
  final Map<String, Completer<void>> _gates = {};

  /// Sockets criados para [url], do mais antigo ao mais novo.
  List<FakeRelaySocket> socketsFor(String url) => [
    for (final s in sockets)
      if (s.url == url) s,
  ];

  /// O último socket criado para [url].
  FakeRelaySocket lastSocket(String url) => socketsFor(url).last;

  void failOn(String url, [Object error = 'falha de conexão']) =>
      _failures[url] = error;

  void clearFailure(String url) => _failures.remove(url);

  /// O próximo `connect` a [url] espera o completer devolvido.
  Completer<void> hold(String url) => _gates[url] = Completer<void>();

  @override
  Future<RelaySocket> connect(
    String url, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    connectCalls.add(url);
    final gate = _gates.remove(url);
    final tentativa = () async {
      if (gate != null) await gate.future;
      final erro = _failures[url];
      if (erro != null) throw erro;
      final socket = FakeRelaySocket(url);
      sockets.add(socket);
      return socket;
    }();

    var expirado = false;
    unawaited(
      tentativa.then((socket) {
        if (expirado) unawaited(socket.close());
      }, onError: (Object _) {}),
    );
    try {
      return await tentativa.timeout(timeout);
    } on TimeoutException {
      expirado = true;
      rethrow;
    }
  }
}

class FakeRelaySocket implements RelaySocket {
  FakeRelaySocket(this.url);

  final String url;
  final StreamController<String> _controller =
      StreamController<String>.broadcast();

  /// Tudo que o app enviou, em ordem.
  final List<String> sent = [];
  bool closed = false;

  /// Se não nulo, `send` lança este erro (socket morto).
  Object? sendError;

  @override
  Stream<String> get messages => _controller.stream;

  @override
  void send(String message) {
    if (closed) throw StateError('socket fechado');
    final erro = sendError;
    if (erro != null) throw erro;
    sent.add(message);
  }

  @override
  Future<void> close() async {
    if (closed) return;
    closed = true;
    await _controller.close();
  }

  /// O relay manda [texto] ao app.
  void push(String texto) {
    if (!_controller.isClosed) _controller.add(texto);
  }

  /// O relay fecha o socket.
  Future<void> closeFromRelay() => close();

  /// O socket cai com erro.
  Future<void> failFromRelay([Object erro = 'conexão perdida']) async {
    if (!_controller.isClosed) _controller.addError(erro);
    await close();
  }
}
