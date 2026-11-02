import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'message_channel.dart';
import 'relay_task_handler.dart';

/// Controle do serviço em primeiro plano, visto pela interface. A única
/// fronteira dela com o plugin `flutter_foreground_task` (Princípio III); os
/// testes usam um dublê.
abstract class BackgroundService {
  /// A ponta do canal que a interface usa para falar com o serviço.
  MessageChannel get channel;

  Future<bool> get isRunning;

  /// Inicia o serviço, com [text] na notificação fixa. Não faz nada se já
  /// estiver rodando.
  Future<void> start({required String text});

  /// Troca o texto da notificação fixa.
  Future<void> updateText(String text);

  Future<void> stop();

  /// Verdadeiro se o aparelho deixa o app mostrar notificações (Android 13+
  /// pede a permissão em tempo de execução).
  Future<bool> hasNotificationPermission();

  /// Pede a permissão de notificação. Devolve se foi concedida.
  Future<bool> requestNotificationPermission();
}

/// Implementação real sobre `flutter_foreground_task`, com o tipo de serviço
/// `specialUse` (D3 de `research.md`).
class ForegroundTaskBackgroundService implements BackgroundService {
  /// Prepara o canal entre a interface e o serviço. MUST ser chamado em
  /// `main()`, antes de `runApp`.
  static void initCommunicationPort() =>
      FlutterForegroundTask.initCommunicationPort();

  ForegroundTaskBackgroundService({required this.channel}) {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'driver_service',
        channelName: 'Conexão com os relays',
        channelDescription:
            'Mostra que o app mantém a conexão para receber corridas.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        // Nunca no boot do aparelho nem ao atualizar o app (constituição
        // 2.14.0): o serviço só nasce da interface, com o app visível.
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: false,
        allowWifiLock: false,
      ),
    );
  }

  @override
  final MessageChannel channel;

  static const String _title = 'Corridas Motorista';

  @override
  Future<bool> get isRunning => FlutterForegroundTask.isRunningService;

  @override
  Future<void> start({required String text}) async {
    if (!Platform.isAndroid || await isRunning) return;
    await FlutterForegroundTask.startService(
      serviceId: 2514,
      serviceTypes: [ForegroundServiceTypes.specialUse],
      notificationTitle: _title,
      notificationText: text,
      callback: relayServiceCallback,
    );
  }

  @override
  Future<void> updateText(String text) async {
    if (!await isRunning) return;
    await FlutterForegroundTask.updateService(
      notificationTitle: _title,
      notificationText: text,
    );
  }

  @override
  Future<void> stop() async {
    if (await isRunning) await FlutterForegroundTask.stopService();
  }

  @override
  Future<bool> hasNotificationPermission() async =>
      await FlutterForegroundTask.checkNotificationPermission() ==
      NotificationPermission.granted;

  @override
  Future<bool> requestNotificationPermission() async =>
      await FlutterForegroundTask.requestNotificationPermission() ==
      NotificationPermission.granted;
}
