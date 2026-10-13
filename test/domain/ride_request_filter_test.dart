import 'package:driver/domain/driver_ride_status.dart';
import 'package:driver/domain/nostr_event.dart';
import 'package:driver/domain/ride_request_filter.dart';
import 'package:driver/domain/service_state.dart';
import 'package:flutter_test/flutter_test.dart';

const _contentValido =
    '{"origin":{"lat":-28.9298,"lon":-49.4753},'
    '"destination":{"lat":-28.6721,"lon":-49.3671},'
    '"payment":"pix"}';

NostrEvent _evento({String content = _contentValido, String id = 'id-1'}) =>
    NostrEvent(
      id: id,
      authorPublicKey: 'a' * 64,
      createdAt: DateTime.now(),
      kind: NostrEvent.kindRideRequest,
      content: content,
      isSignatureValid: true,
    );

const _online = ServiceState(online: true, acceptedPayments: {'pix', 'cartao'});

void main() {
  group('RideRequestFilter.evaluate (FR-005 da feature 025)', () {
    test('aceita: online, aguardando, content válido e pagamento aceito', () {
      final decisao = RideRequestFilter.evaluate(_evento(), _online);

      expect(decisao.accepted, isTrue);
      expect(decisao.refusal, isNull);
      expect(decisao.request!.requestId, 'id-1');
      expect(decisao.request!.payment, 'pix');
    });

    test('recusa offline', () {
      final decisao = RideRequestFilter.evaluate(
        _evento(),
        _online.copyWith(online: false),
      );

      expect(decisao.accepted, isFalse);
      expect(decisao.refusal, RideRequestRefusal.offline);
      expect(decisao.request, isNull);
    });

    for (final estado in [
      DriverRideStatus.deslocandoAtePassageiro,
      DriverRideStatus.emCorrida,
    ]) {
      test('recusa com a corrida em $estado', () {
        final decisao = RideRequestFilter.evaluate(
          _evento(),
          _online.copyWith(rideStatus: estado),
        );

        expect(decisao.refusal, RideRequestRefusal.emCorrida);
      });
    }

    test('recusa content malformado, sem lançar', () {
      for (final content in ['não é json', '{}', '[]', '{"origin":1}']) {
        final decisao = RideRequestFilter.evaluate(
          _evento(content: content),
          _online,
        );

        expect(decisao.refusal, RideRequestRefusal.malformada, reason: content);
      }
    });

    test('recusa forma de pagamento que o motorista não aceita', () {
      final decisao = RideRequestFilter.evaluate(
        _evento(),
        _online.copyWith(acceptedPayments: const {'dinheiro'}),
      );

      expect(decisao.refusal, RideRequestRefusal.pagamentoNaoAceito);
    });

    test('recusa pagamento fora dos três valores do contrato', () {
      final decisao = RideRequestFilter.evaluate(
        _evento(
          content:
              '{"origin":{"lat":1,"lon":2},"destination":{"lat":3,"lon":4},'
              '"payment":"bitcoin"}',
        ),
        _online.copyWith(acceptedPayments: const {'bitcoin', 'pix'}),
      );

      expect(decisao.refusal, RideRequestRefusal.pagamentoNaoAceito);
    });

    test('sem cadastro carregado (null) não descarta por pagamento', () {
      final decisao = RideRequestFilter.evaluate(
        _evento(),
        const ServiceState(online: true),
      );

      expect(decisao.accepted, isTrue);
    });

    test('a ordem das recusas é offline, corrida, content, pagamento', () {
      const tudoErrado = ServiceState(
        acceptedPayments: {'dinheiro'},
        rideStatus: DriverRideStatus.emCorrida,
      );

      expect(
        RideRequestFilter.evaluate(_evento(content: 'x'), tudoErrado).refusal,
        RideRequestRefusal.offline,
      );
      expect(
        RideRequestFilter.evaluate(
          _evento(content: 'x'),
          tudoErrado.copyWith(online: true),
        ).refusal,
        RideRequestRefusal.emCorrida,
      );
      expect(
        RideRequestFilter.evaluate(
          _evento(content: 'x'),
          tudoErrado.copyWith(
            online: true,
            rideStatus: DriverRideStatus.aguardandoSolicitacao,
          ),
        ).refusal,
        RideRequestRefusal.malformada,
      );
    });
  });

  group('RideRequestFilter.acceptsPayment', () {
    test('sem cadastro (null) aceita qualquer valor', () {
      expect(RideRequestFilter.acceptsPayment(null, 'pix'), isTrue);
      expect(RideRequestFilter.acceptsPayment(null, 'bitcoin'), isTrue);
    });

    test('exige valor do contrato e presença no conjunto', () {
      expect(RideRequestFilter.acceptsPayment({'pix'}, 'pix'), isTrue);
      expect(RideRequestFilter.acceptsPayment({'pix'}, 'cartao'), isFalse);
      expect(RideRequestFilter.acceptsPayment({'bitcoin'}, 'bitcoin'), isFalse);
      expect(RideRequestFilter.acceptsPayment(<String>{}, 'pix'), isFalse);
    });
  });
}
