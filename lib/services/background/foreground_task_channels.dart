import 'dart:async';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'message_channel.dart';
import 'service_messages.dart';

/// A ponta da **interface**: envia ao isolate do serviço e recebe dele, pelo
/// canal do `flutter_foreground_task`. Exige `initCommunicationPort()` em
/// `main()`.
class UiMessageChannel implements MessageChannel {
  UiMessageChannel() {
    FlutterForegroundTask.addTaskDataCallback(_onData);
  }

  final StreamController<ServiceMessage> _incoming =
      StreamController<ServiceMessage>.broadcast();

  void _onData(Object data) {
    final mensagem = ServiceMessage.fromMap(data);
    if (mensagem != null && !_incoming.isClosed) _incoming.add(mensagem);
  }

  @override
  Stream<ServiceMessage> get incoming => _incoming.stream;

  @override
  void send(ServiceMessage message) =>
      FlutterForegroundTask.sendDataToTask(message.toMap());

  @override
  Future<void> close() async {
    FlutterForegroundTask.removeTaskDataCallback(_onData);
    await _incoming.close();
  }
}

/// A ponta do **serviço**: o `TaskHandler` repassa o que recebe a [deliver], e
/// o que envia vai à interface — se ela estiver aberta; senão a mensagem se
/// perde, e é por isso que o serviço guarda o que importa (as solicitações
/// pendentes).
class ServiceSideChannel implements MessageChannel {
  final StreamController<ServiceMessage> _incoming =
      StreamController<ServiceMessage>.broadcast();

  /// Entrega ao núcleo uma mensagem que chegou pelo `onReceiveData`.
  void deliver(Object data) {
    final mensagem = ServiceMessage.fromMap(data);
    if (mensagem != null && !_incoming.isClosed) _incoming.add(mensagem);
  }

  @override
  Stream<ServiceMessage> get incoming => _incoming.stream;

  @override
  void send(ServiceMessage message) =>
      FlutterForegroundTask.sendDataToMain(message.toMap());

  @override
  Future<void> close() => _incoming.close();
}
