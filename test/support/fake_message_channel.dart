import 'dart:async';

import 'package:driver/services/background/message_channel.dart';
import 'package:driver/services/background/service_messages.dart';

/// Par de pontas de canal em memória: o que uma envia, a outra recebe, depois
/// de passar pelo mesmo mapa que o canal real carrega — assim os testes
/// exercitam a (de)serialização de verdade.
class FakeChannelPair {
  FakeChannelPair() {
    ui = FakeChannelEnd(this, toService: true);
    service = FakeChannelEnd(this, toService: false);
  }

  late final FakeChannelEnd ui;
  late final FakeChannelEnd service;

  /// Quando falso, as mensagens enviadas pela ponta da interface se perdem —
  /// a interface "fechada" do outro lado.
  bool uiOpen = true;
  bool serviceOpen = true;
}

class FakeChannelEnd implements MessageChannel {
  FakeChannelEnd(this._pair, {required this.toService});

  final FakeChannelPair _pair;

  /// Verdadeiro para a ponta que a interface usa (envia ao serviço).
  final bool toService;

  final StreamController<ServiceMessage> _incoming = StreamController.broadcast(
    sync: true,
  );

  /// Tudo que esta ponta enviou, na ordem.
  final List<ServiceMessage> sent = [];

  @override
  Stream<ServiceMessage> get incoming => _incoming.stream;

  @override
  void send(ServiceMessage message) {
    sent.add(message);
    final destino = toService ? _pair.service : _pair.ui;
    final aberto = toService ? _pair.serviceOpen : _pair.uiOpen;
    if (!aberto) return;
    final lida = ServiceMessage.fromMap(message.toMap());
    if (lida != null) destino._incoming.add(lida);
  }

  @override
  Future<void> close() => _incoming.close();
}
