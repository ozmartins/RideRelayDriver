import 'package:driver/domain/driver_coverage.dart';
import 'package:driver/domain/driver_ride_status.dart';
import 'package:driver/domain/geohash.dart';
import 'package:driver/domain/nostr_event.dart';
import 'package:driver/domain/ride_request_filter.dart';
import 'package:driver/domain/service_state.dart';
import 'package:flutter_test/flutter_test.dart';

const _contentValido =
    '{"origin":{"lat":-28.9298,"lon":-49.4753},'
    '"destination":{"lat":-28.6721,"lon":-49.3671},'
    '"payment":"pix"}';

/// As três tags `g` da origem do [_contentValido] (Araranguá), como o
/// passageiro as publica (emenda 27).
final _tagsDeAraranguaG = [
  for (final p in kPrecisoesDaTag) ['g', Geohash.encode(-28.9298, -49.4753, p)],
];

NostrEvent _evento({
  String content = _contentValido,
  String id = 'id-1',
  List<List<String>>? tags,
}) => NostrEvent(
  id: id,
  authorPublicKey: 'a' * 64,
  createdAt: DateTime.now(),
  kind: NostrEvent.kindRideRequest,
  content: content,
  tags: tags ?? _tagsDeAraranguaG,
  isSignatureValid: true,
);

/// Motorista online em Araranguá, raio de 10 km.
final _padrao = DriverCoverage.around(
  lat: -28.9298,
  lon: -49.4753,
  radiusKm: 10,
);

RideRequestDecision _avalia(
  NostrEvent evento,
  ServiceState estado, {
  DriverCoverage? coverage,
  bool semCobertura = false,
}) => RideRequestFilter.evaluate(
  evento,
  estado,
  coverage: semCobertura ? null : (coverage ?? _padrao),
);

const _online = ServiceState(online: true, acceptedPayments: {'pix', 'cartao'});

void main() {
  group('RideRequestFilter.evaluate (FR-005 da feature 025)', () {
    test('aceita: online, aguardando, content válido e pagamento aceito', () {
      final decisao = _avalia(_evento(), _online);

      expect(decisao.accepted, isTrue);
      expect(decisao.refusal, isNull);
      expect(decisao.request!.requestId, 'id-1');
      expect(decisao.request!.payment, 'pix');
    });

    test('recusa offline', () {
      final decisao = _avalia(_evento(), _online.copyWith(online: false));

      expect(decisao.accepted, isFalse);
      expect(decisao.refusal, RideRequestRefusal.offline);
      expect(decisao.request, isNull);
    });

    for (final estado in [
      DriverRideStatus.deslocandoAtePassageiro,
      DriverRideStatus.emCorrida,
    ]) {
      test('recusa com a corrida em $estado', () {
        final decisao = _avalia(
          _evento(),
          _online.copyWith(rideStatus: estado),
        );

        expect(decisao.refusal, RideRequestRefusal.emCorrida);
      });
    }

    test('recusa content malformado, sem lançar', () {
      for (final content in ['não é json', '{}', '[]', '{"origin":1}']) {
        final decisao = _avalia(_evento(content: content), _online);

        expect(decisao.refusal, RideRequestRefusal.malformada, reason: content);
      }
    });

    test('recusa forma de pagamento que o motorista não aceita', () {
      final decisao = _avalia(
        _evento(),
        _online.copyWith(acceptedPayments: const {'dinheiro'}),
      );

      expect(decisao.refusal, RideRequestRefusal.pagamentoNaoAceito);
    });

    test('recusa pagamento fora dos três valores do contrato', () {
      final decisao = _avalia(
        _evento(
          content:
              '{"origin":{"lat":-28.9298,"lon":-49.4753},'
              '"destination":{"lat":3,"lon":4},'
              '"payment":"bitcoin"}',
        ),
        _online.copyWith(acceptedPayments: const {'bitcoin', 'pix'}),
      );

      expect(decisao.refusal, RideRequestRefusal.pagamentoNaoAceito);
    });

    test('sem cadastro carregado (null) não descarta por pagamento', () {
      final decisao = _avalia(_evento(), const ServiceState(online: true));

      expect(decisao.accepted, isTrue);
    });

    test(
      'a ordem das recusas é offline, corrida, content, geografia, pagamento',
      () {
        const tudoErrado = ServiceState(
          acceptedPayments: {'dinheiro'},
          rideStatus: DriverRideStatus.emCorrida,
        );

        expect(
          _avalia(_evento(content: 'x'), tudoErrado).refusal,
          RideRequestRefusal.offline,
        );
        expect(
          _avalia(
            _evento(content: 'x'),
            tudoErrado.copyWith(online: true),
          ).refusal,
          RideRequestRefusal.emCorrida,
        );
        expect(
          _avalia(
            _evento(content: 'x'),
            tudoErrado.copyWith(
              online: true,
              rideStatus: DriverRideStatus.aguardandoSolicitacao,
            ),
          ).refusal,
          RideRequestRefusal.malformada,
        );
      },
    );
  });

  group('RideRequestFilter.evaluate — recorte geográfico (feature 027)', () {
    test('aceita origem dentro do raio com g na célula', () {
      expect(_avalia(_evento(), _online).accepted, isTrue);
    });

    test('online sem cobertura recusa por falta de referência', () {
      final decisao = _avalia(_evento(), _online, semCobertura: true);

      expect(decisao.accepted, isFalse);
      expect(decisao.refusal, RideRequestRefusal.semReferencia);
    });

    test('recusa sem tag g, mesmo com a origem dentro do raio', () {
      final decisao = _avalia(_evento(tags: const []), _online);

      expect(decisao.refusal, RideRequestRefusal.foraDaCobertura);
    });

    test('recusa g fora das células, mesmo com a origem dentro do raio', () {
      final saoPaulo = [
        for (final p in kPrecisoesDaTag)
          ['g', Geohash.encode(-23.5505, -46.6333, p)],
      ];
      final decisao = _avalia(_evento(tags: saoPaulo), _online);

      expect(decisao.refusal, RideRequestRefusal.foraDaCobertura);
    });

    test('recusa origem além do raio, mesmo com g na célula', () {
      // ~15 km ao norte: na célula de precisão 4, fora dos 10 km.
      const longe =
          '{"origin":{"lat":-28.7949,"lon":-49.4753},'
          '"destination":{"lat":-28.6721,"lon":-49.3671},"payment":"pix"}';
      final tags = [
        for (final p in kPrecisoesDaTag)
          ['g', Geohash.encode(-28.7949, -49.4753, p)],
      ];
      final decisao = _avalia(_evento(content: longe, tags: tags), _online);

      expect(decisao.refusal, RideRequestRefusal.foraDaCobertura);
    });

    test('content malformado vem antes da geografia', () {
      final decisao = _avalia(_evento(content: 'x', tags: const []), _online);

      expect(decisao.refusal, RideRequestRefusal.malformada);
    });

    test('geografia vem antes do pagamento', () {
      final decisao = _avalia(
        _evento(tags: const []),
        _online.copyWith(acceptedPayments: const {'dinheiro'}),
      );

      expect(decisao.refusal, RideRequestRefusal.foraDaCobertura);
    });

    test('offline e corrida em andamento vêm antes da referência', () {
      expect(
        _avalia(
          _evento(),
          _online.copyWith(online: false),
          semCobertura: true,
        ).refusal,
        RideRequestRefusal.offline,
      );
      expect(
        _avalia(
          _evento(),
          _online.copyWith(rideStatus: DriverRideStatus.emCorrida),
          semCobertura: true,
        ).refusal,
        RideRequestRefusal.emCorrida,
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
