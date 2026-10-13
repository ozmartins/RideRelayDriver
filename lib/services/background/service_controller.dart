import 'dart:async';

import '../../domain/service_state.dart';
import '../remote_relay_connection.dart';
import 'background_service.dart';
import 'service_messages.dart';

/// Decide quando o serviço em segundo plano roda e o que ele sabe do app
/// (feature 025, FR-001, FR-009, FR-011, FR-012).
///
/// O serviço roda enquanto o app está em primeiro plano **ou** o motorista está
/// online — e, estando online com o app fechado, só se o aparelho deixa
/// mostrar notificação: sem ela não haveria como avisar, e manter a conexão
/// seria só gasto de bateria.
class ServiceController {
  ServiceController({
    required this.service,
    required this.connection,
    this.resumeTimeout = const Duration(seconds: 5),
  }) {
    _attachedSubscription = connection.attached.listen((_) {
      // O serviço (re)apareceu: devolve a ele o que a interface decidiu.
      if (!_resumeDecided.isCompleted) {
        _resumeDecided.complete(connection.serviceOnline);
      }
      _sendState();
    });
  }

  final BackgroundService service;
  final RemoteRelayConnection connection;
  late final StreamSubscription<void> _attachedSubscription;
  final Completer<bool> _resumeDecided = Completer<bool>();

  ServiceState _state = const ServiceState(appInForeground: true);
  bool _foreground = true;

  /// Só depois da primeira informação da tela o controlador manda estado: antes
  /// disso o padrão (offline) apagaria o que o serviço guardou (FR-012).
  bool _reported = false;
  bool _canNotify = true;
  bool _disposed = false;

  static const String textOnline = 'Você está online';
  static const String textConnected = 'Conectado aos relays';

  /// A regra de FR-001: em primeiro plano, ou online e capaz de avisar.
  static bool shouldRun({
    required bool foreground,
    required bool online,
    required bool canNotify,
  }) => foreground || (online && canNotify);

  /// O que o serviço guardava sobre o motorista estar online, lido na primeira
  /// resposta dele (FR-012). Completa com `false` se o serviço não responder em
  /// [resumeTimeout].
  Future<bool> get resumeOnline => _resumeDecided.future;

  /// Quanto esperar a primeira resposta do serviço antes de desistir de
  /// retomar o estado online.
  final Duration resumeTimeout;

  /// Inicia o serviço (se não estiver rodando) e se apresenta a ele.
  Future<void> start() async {
    _canNotify = await service.hasNotificationPermission();
    await service.start(text: _text);
    connection.attach(foreground: _foreground);
    unawaited(
      Future<void>.delayed(resumeTimeout).then((_) {
        if (!_resumeDecided.isCompleted) _resumeDecided.complete(false);
      }),
    );
  }

  /// A tela informa o estado de que o serviço depende. Chamada à vontade: só
  /// age se algo mudou.
  void update(ServiceState state) {
    if (_disposed) return;
    final novo = state.copyWith(appInForeground: _foreground);
    if (_reported && novo == _state) return;
    _reported = true;
    _state = novo;
    _sendState();
    unawaited(service.updateText(_text));
    _reconsider();
  }

  /// O app foi para segundo plano ou voltou à tela.
  Future<void> onForeground(bool foreground) async {
    if (_disposed || foreground == _foreground) return;
    _foreground = foreground;
    _state = _state.copyWith(appInForeground: foreground);
    if (foreground) {
      _canNotify = await service.hasNotificationPermission();
      if (!await service.isRunning) await service.start(text: _text);
      connection.attach(foreground: true);
      return;
    }
    // Avisa o serviço de que não há mais interface visível, para ele passar a
    // notificar, e só então decide se continua.
    connection.attach(foreground: false);
    _sendState();
    _reconsider();
  }

  /// Pede a permissão de notificação (Android 13+) se ainda não foi dada.
  /// Devolve se o app pode notificar.
  Future<bool> ensureNotificationPermission() async {
    var concedida = await service.hasNotificationPermission();
    if (!concedida) concedida = await service.requestNotificationPermission();
    _canNotify = concedida;
    _reconsider();
    return concedida;
  }

  /// Encerra o serviço a pedido (a interface está sendo destruída).
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _attachedSubscription.cancel();
  }

  String get _text => _state.online ? textOnline : textConnected;

  void _sendState() {
    if (!_reported || _disposed) return;
    connection.sendToService(ServiceStateUpdate(_state));
  }

  void _reconsider() {
    if (_disposed) return;
    final deve = shouldRun(
      foreground: _foreground,
      online: _state.online,
      canNotify: _canNotify,
    );
    if (!deve) {
      connection.detach();
      unawaited(service.stop());
    }
  }
}
