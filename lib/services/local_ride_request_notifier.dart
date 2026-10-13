import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'ride_request_notifier.dart';

/// Notificação local de solicitação de corrida sobre
/// `flutter_local_notifications` (decisão D2 de
/// `specs/025-conexao-em-segundo-plano/research.md`). Roda no isolate do
/// serviço, sem passar por nenhum servidor de push.
///
/// Único arquivo, junto do serviço em primeiro plano, que conhece o plugin
/// (Princípio III).
class LocalRideRequestNotifier implements RideRequestNotifier {
  LocalRideRequestNotifier({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  Future<void>? _initialized;

  /// Importância alta (aviso na tela e som) — o motorista precisa notar uma
  /// corrida chegando. A notificação fixa do serviço fica em outro canal, de
  /// importância baixa.
  static const AndroidNotificationDetails _details = AndroidNotificationDetails(
    'ride_requests',
    'Solicitações de corrida',
    channelDescription: 'Avisa quando chega uma solicitação de corrida.',
    importance: Importance.high,
    priority: Priority.high,
  );

  Future<void> _ensureInitialized() => _initialized ??= _plugin.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
  );

  @override
  Future<void> notifyRideRequest(String eventId) async {
    await _ensureInitialized();
    final conteudo = RideRequestNotificationContent.forEvent(eventId);
    await _plugin.show(
      id: conteudo.id,
      title: conteudo.title,
      body: conteudo.body,
      notificationDetails: const NotificationDetails(android: _details),
    );
  }

  @override
  Future<void> cancelAll() async {
    await _ensureInitialized();
    await _plugin.cancelAll();
  }
}
