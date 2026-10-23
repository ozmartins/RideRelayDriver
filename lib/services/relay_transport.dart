/// Transporte de relay: uma conexão, mensagens de texto nos dois sentidos.
///
/// Abstrai o WebSocket para que o [RelayGateway] seja testável com dublê em
/// memória. O Princípio II da constituição proíbe que o teste de descarte de
/// mensagem dependa de relay real, e a decisão D5 da feature 002 registra que
/// nenhum teste automatizado contata relay público. Não conhece o protocolo
/// Nostr: quem monta e interpreta os frames é `relay_protocol.dart`.
abstract interface class RelayTransport {
  /// Abre a conexão com [url]. Lança se não for possível conectar dentro de
  /// [timeout] — `TimeoutException` no estouro do prazo.
  Future<RelaySocket> connect(
    String url, {
    Duration timeout = const Duration(seconds: 10),
  });
}

/// Uma conexão aberta com um relay.
abstract interface class RelaySocket {
  /// Mensagens de texto vindas do relay, em *broadcast*. Termina (`onDone`)
  /// quando o socket fecha e falha (`onError`) quando cai com erro.
  Stream<String> get messages;

  /// Envia uma mensagem de texto. Lança [StateError] se o socket já fechou.
  void send(String message);

  /// Encerra a conexão. Idempotente.
  Future<void> close();
}
