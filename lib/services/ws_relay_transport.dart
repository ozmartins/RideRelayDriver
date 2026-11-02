import 'dart:async';
import 'dart:io';

import 'relay_transport.dart';

/// Abre o WebSocket. Injetável para o teste controlar o handshake sem rede.
typedef WebSocketConnector = Future<WebSocket> Function(String url);

Future<WebSocket> _connectWebSocket(String url) => WebSocket.connect(url);

/// Transporte real: WebSocket do `dart:io`.
///
/// Mesmo comportamento do transporte do passageiro (`ws_relay_transport.dart`
/// dele): ping periódico, prazo de handshake e fechamento do socket que chega
/// depois do prazo. Único arquivo da aplicação que toca rede; os testes usam
/// dublês de [RelayTransport] e, aqui, um [connector] falso (decisão D5).
class WsRelayTransport implements RelayTransport {
  const WsRelayTransport({
    this.pingInterval = const Duration(seconds: 30),
    this.connector = _connectWebSocket,
  });

  /// Intervalo de ping do WebSocket.
  ///
  /// Uma conexão pode morrer sem erro nem fechamento: depois de uma troca de
  /// Wi-Fi para dados móveis o TCP fica meio aberto, e o socket não percebe por
  /// minutos. Com ping ligado, o `dart:io` fecha a conexão quando o pong não
  /// chega dentro do intervalo; o fechamento vira `onDone` em `messages`, que o
  /// gateway trata como queda de conexão.
  final Duration pingInterval;

  final WebSocketConnector connector;

  @override
  Future<RelaySocket> connect(
    String url, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    // `.timeout()` só desiste de esperar; não cancela o handshake, que continua
    // em segundo plano. Se ele terminar depois do prazo — quando o chamador já
    // tratou como falha e seguiu adiante —, ninguém mais tem referência ao
    // socket para fechá-lo. Por isso o future original é observado à parte, e
    // um socket que chega atrasado é fechado assim que aparece.
    var expirado = false;
    final conexao = connector(url);
    unawaited(
      conexao.then((socket) {
        if (expirado) unawaited(socket.close());
      }, onError: (Object _) {}),
    );

    try {
      final socket = await conexao.timeout(timeout);
      socket.pingInterval = pingInterval;
      return _WsRelaySocket(socket);
    } on TimeoutException {
      expirado = true;
      rethrow;
    }
  }
}

class _WsRelaySocket implements RelaySocket {
  _WsRelaySocket(this._socket)
    : messages = _socket
          .where((dado) => dado is String)
          .cast<String>()
          .asBroadcastStream();

  final WebSocket _socket;

  @override
  final Stream<String> messages;

  @override
  void send(String message) => _socket.add(message);

  @override
  Future<void> close() => _socket.close();
}
