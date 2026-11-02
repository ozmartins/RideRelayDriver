import 'dart:async';

import 'package:driver/domain/driver_position.dart';
import 'package:driver/services/location_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Dublê em memória: nenhum teste toca sensor de localização real (decisão
/// D1, Princípio III).
class FakeLocationService implements LocationService {
  FakeLocationService({this.permissionError});

  /// Se preenchido, [ensurePermission] lança este erro.
  Object? permissionError;

  final _controller = StreamController<DriverPosition>.broadcast();

  @override
  Stream<DriverPosition> get positions => _controller.stream;

  @override
  Future<void> ensurePermission() async {
    final erro = permissionError;
    if (erro != null) throw erro;
  }

  void emitir(DriverPosition posicao) => _controller.add(posicao);

  void emitirErro(Object erro) => _controller.addError(erro);

  Future<void> fechar() => _controller.close();
}

DriverPosition posicaoDeTeste({double lat = -28.935, double lng = -49.49}) =>
    DriverPosition(latitude: lat, longitude: lng, capturedAt: DateTime.now());

void main() {
  group('LocationService — fluxo de posições (FR-003)', () {
    test('o fluxo emite as posições publicadas', () async {
      final service = FakeLocationService();
      final recebidas = <DriverPosition>[];
      final sub = service.positions.listen(recebidas.add);

      final posicao = posicaoDeTeste();
      service.emitir(posicao);
      await pumpEventQueue();

      expect(recebidas, [posicao]);
      await sub.cancel();
      await service.fechar();
    });
  });

  group('LocationService — permissão e indisponibilidade (FR-004, FR-005)', () {
    test(
      'ensurePermission() não lança quando a permissão já foi concedida',
      () async {
        final service = FakeLocationService();
        await expectLater(service.ensurePermission(), completes);
      },
    );

    test(
      'ensurePermission() lança LocationPermissionDenied quando negada',
      () async {
        final service = FakeLocationService(
          permissionError: const LocationPermissionDenied(),
        );
        await expectLater(
          service.ensurePermission(),
          throwsA(isA<LocationPermissionDenied>()),
        );
      },
    );

    test('o fluxo lança LocationUnavailable quando o sinal se perde, '
        'distinto de permissão negada', () async {
      final service = FakeLocationService();
      final erros = <Object>[];
      final sub = service.positions.listen((_) {}, onError: erros.add);

      service.emitirErro(const LocationUnavailable('sinal perdido'));
      await pumpEventQueue();

      expect(erros, hasLength(1));
      expect(erros.single, isA<LocationUnavailable>());
      expect(
        erros.single,
        isNot(isA<LocationPermissionDenied>()),
        reason:
            'indisponibilidade e permissão negada precisam ser '
            'distinguíveis para exibir a mensagem certa',
      );
      await sub.cancel();
      await service.fechar();
    });
  });
}
