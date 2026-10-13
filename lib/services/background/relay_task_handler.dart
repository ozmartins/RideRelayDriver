import 'dart:async';
import 'dart:ui';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../consumed_kinds.dart';
import '../key_value_store.dart';
import '../local_ride_request_notifier.dart';
import '../nostr_relay_gateway.dart';
import '../relay_repository.dart';
import '../relay_service.dart';
import 'foreground_task_channels.dart';
import 'relay_host_core.dart';
import 'service_state_store.dart';

/// Ponto de entrada do isolate do serviço em segundo plano (feature 025).
/// Precisa ser uma função de nível superior e ficar visível ao AOT.
@pragma('vm:entry-point')
void relayServiceCallback() {
  FlutterForegroundTask.setTaskHandler(RelayTaskHandler());
}

/// O `TaskHandler` que monta o [RelayHostCore] com as dependências reais.
/// Fina de propósito: a lógica está no núcleo, testado sem o plugin.
class RelayTaskHandler extends TaskHandler {
  final ServiceSideChannel _channel = ServiceSideChannel();
  NostrRelayGateway? _gateway;
  RelayHostCore? _core;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // Plugins com implementação em Dart (shared_preferences) precisam ser
    // registrados no isolate do serviço.
    DartPluginRegistrant.ensureInitialized();

    final gateway = NostrRelayGateway();
    _gateway = gateway;
    final store = FreshPreferencesStore();
    _core = RelayHostCore(
      relays: RelayService(
        gateway,
        subscriptionKinds: driverConsumedKinds.toList(),
      ),
      channel: _channel,
      stateStore: ServiceStateStore(store),
      relayRepository: RelayRepository(store),
      notifier: LocalRideRequestNotifier(),
      acceptedKinds: driverConsumedKinds,
      onStopRequested: () async {
        await FlutterForegroundTask.stopService();
      },
    );
    // Iniciado pelo app: o estado guardado de uma execução anterior não vale.
    // Reiniciado pelo sistema (sem a interface): vale, é tudo que há.
    await _core!.start(restoreState: starter != TaskStarter.developer);
  }

  @override
  void onReceiveData(Object data) => _channel.deliver(data);

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    await _core?.dispose();
    await _gateway?.dispose();
  }
}
