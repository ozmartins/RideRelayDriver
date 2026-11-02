import 'package:driver/services/background/background_service.dart';
import 'package:driver/services/background/message_channel.dart';

class FakeBackgroundService implements BackgroundService {
  FakeBackgroundService(this.channel);

  @override
  final MessageChannel channel;

  bool running = false;
  bool permission = true;

  /// Resposta de `requestNotificationPermission`.
  bool grantsWhenAsked = true;

  final List<String> started = [];
  final List<String> texts = [];
  int stops = 0;
  int permissionRequests = 0;

  @override
  Future<bool> get isRunning async => running;

  @override
  Future<void> start({required String text}) async {
    if (running) return;
    running = true;
    started.add(text);
  }

  @override
  Future<void> updateText(String text) async {
    if (running) texts.add(text);
  }

  @override
  Future<void> stop() async {
    if (!running) return;
    running = false;
    stops++;
  }

  @override
  Future<bool> hasNotificationPermission() async => permission;

  @override
  Future<bool> requestNotificationPermission() async {
    permissionRequests++;
    permission = grantsWhenAsked;
    return permission;
  }
}
