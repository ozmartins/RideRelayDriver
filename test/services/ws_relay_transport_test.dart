import 'dart:async';
import 'dart:io';

import 'package:driver/services/ws_relay_transport.dart';
import 'package:flutter_test/flutter_test.dart';

/// `WebSocket` falso: só o que o transporte usa. Nenhuma conexão real.
class _FakeWebSocket extends Stream<dynamic> implements WebSocket {
  final StreamController<dynamic> controller =
      StreamController<dynamic>.broadcast();
  final List<dynamic> added = [];
  bool closed = false;

  @override
  Duration? pingInterval;

  @override
  StreamSubscription<dynamic> listen(
    void Function(dynamic event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => controller.stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  void add(dynamic data) => added.add(data);

  @override
  Future<dynamic> close([int? code, String? reason]) async {
    closed = true;
    await controller.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'handshake com sucesso: devolve o socket e liga o ping de 30 s',
    () async {
      final ws = _FakeWebSocket();
      final transporte = WsRelayTransport(connector: (_) async => ws);

      final socket = await transporte.connect('wss://a.test');

      expect(ws.pingInterval, const Duration(seconds: 30));
      expect(ws.closed, isFalse);
      await socket.close();
      expect(ws.closed, isTrue);
    },
  );

  test('o intervalo de ping é configurável', () async {
    final ws = _FakeWebSocket();
    final transporte = WsRelayTransport(
      pingInterval: const Duration(seconds: 5),
      connector: (_) async => ws,
    );

    await transporte.connect('wss://a.test');

    expect(ws.pingInterval, const Duration(seconds: 5));
  });

  test('falha do handshake propaga o erro do conector', () async {
    final transporte = WsRelayTransport(
      connector: (_) =>
          Future<WebSocket>.error(const SocketException('Failed host lookup')),
    );

    await expectLater(
      transporte.connect('wss://a.test'),
      throwsA(isA<SocketException>()),
    );
  });

  test('handshake que passa do prazo lança TimeoutException', () async {
    final transporte = WsRelayTransport(
      connector: (_) => Completer<WebSocket>().future,
    );

    await expectLater(
      transporte.connect(
        'wss://a.test',
        timeout: const Duration(milliseconds: 20),
      ),
      throwsA(isA<TimeoutException>()),
    );
  });

  test('socket que chega depois do prazo é fechado', () async {
    final pendente = Completer<WebSocket>();
    final transporte = WsRelayTransport(connector: (_) => pendente.future);

    await expectLater(
      transporte.connect(
        'wss://a.test',
        timeout: const Duration(milliseconds: 20),
      ),
      throwsA(isA<TimeoutException>()),
    );
    final tardio = _FakeWebSocket();
    pendente.complete(tardio);
    await Future<void>.delayed(Duration.zero);

    expect(tardio.closed, isTrue);
  });

  test('socket que chega dentro do prazo não é fechado', () async {
    final pendente = Completer<WebSocket>();
    final transporte = WsRelayTransport(connector: (_) => pendente.future);
    final ws = _FakeWebSocket();

    final futuro = transporte.connect('wss://a.test');
    pendente.complete(ws);
    await futuro;
    await Future<void>.delayed(Duration.zero);

    expect(ws.closed, isFalse);
  });

  test('messages entrega só frames de texto', () async {
    final ws = _FakeWebSocket();
    final socket = await WsRelayTransport(connector: (_) async => ws)
        .connect('wss://a.test');
    final recebidas = <String>[];
    socket.messages.listen(recebidas.add);

    ws.controller
      ..add('um')
      ..add(<int>[1, 2, 3])
      ..add('dois');
    await Future<void>.delayed(Duration.zero);

    expect(recebidas, ['um', 'dois']);
  });

  test('send chega ao socket e o fim do socket termina messages', () async {
    final ws = _FakeWebSocket();
    final socket = await WsRelayTransport(connector: (_) async => ws)
        .connect('wss://a.test');
    final terminou = Completer<void>();
    socket.messages.listen((_) {}, onDone: terminou.complete);

    socket.send('oi');
    await ws.controller.close();
    await terminou.future.timeout(const Duration(seconds: 1));

    expect(ws.added, ['oi']);
  });
}
