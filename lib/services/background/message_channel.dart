import 'service_messages.dart';

/// Uma ponta do canal de mensagens entre a interface e o serviço em segundo
/// plano. A interface fala com o serviço por uma ponta e o serviço com a
/// interface pela outra; a implementação real usa o plugin do serviço, e os
/// testes usam um par em memória.
abstract class MessageChannel {
  /// Mensagens vindas da outra ponta. Dado que não é uma [ServiceMessage]
  /// válida nunca aparece aqui.
  Stream<ServiceMessage> get incoming;

  /// Envia à outra ponta. Sem ninguém do outro lado, a mensagem se perde: o
  /// canal não guarda nada (a interface pode estar fechada).
  void send(ServiceMessage message);

  Future<void> close();
}
