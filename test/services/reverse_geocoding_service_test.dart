import 'dart:convert';

import 'package:driver/services/reverse_geocoding_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';

const _ponto = LatLng(-28.9298, -49.4753);

String _corpo(Map<String, dynamic> propriedades) => jsonEncode({
  'features': [
    {'properties': propriedades},
  ],
});

http.Response _json(String corpo, [int status = 200]) =>
    http.Response.bytes(utf8.encode(corpo), status);

void main() {
  test('monta o endereço legível e envia só a coordenada', () async {
    late Uri chamada;
    late Map<String, String> cabecalhos;
    final servico = PhotonReverseGeocodingService(
      client: MockClient((req) async {
        chamada = req.url;
        cabecalhos = req.headers;
        return _json(
          _corpo({
            'street': 'Rua Central',
            'housenumber': '10',
            'district': 'Centro',
            'city': 'Araranguá',
            'state': 'Santa Catarina',
            'country': 'Brasil',
          }),
        );
      }),
    );

    final endereco = await servico.addressOf(_ponto);

    expect(endereco, 'Rua Central, 10, Centro, Araranguá, Santa Catarina');
    expect(chamada.scheme, 'https');
    expect(chamada.path, '/reverse');
    expect(chamada.queryParameters['lat'], '-28.9298');
    expect(chamada.queryParameters['lon'], '-49.4753');
    expect(cabecalhos['User-Agent'], contains('CaronasMotorista'));
    expect(
      chamada.queryParameters.keys,
      unorderedEquals(['lat', 'lon', 'lang', 'limit']),
    );
  });

  test('usa o nome do lugar quando há, sem repetir a rua', () async {
    final servico = PhotonReverseGeocodingService(
      client: MockClient(
        (_) async => _json(
          _corpo({'name': 'Praça XV', 'street': 'Rua A', 'city': 'Araranguá'}),
        ),
      ),
    );

    expect(await servico.addressOf(_ponto), 'Praça XV, Rua A, Araranguá');
  });

  test('guarda em memória: a mesma coordenada não repete a chamada', () async {
    var chamadas = 0;
    final servico = PhotonReverseGeocodingService(
      client: MockClient((_) async {
        chamadas++;
        return _json(_corpo({'street': 'Rua A', 'city': 'Araranguá'}));
      }),
    );

    await servico.addressOf(_ponto);
    await servico.addressOf(_ponto);

    expect(chamadas, 1);
  });

  for (final caso in {
    'HTTP 403': () async => _json('{}', 403),
    'JSON malformado': () async => _json('não é json'),
    'sem resultados': () async => _json('{"features": []}'),
    'sem campos de endereço': () async => _json(_corpo({'osm_id': 1})),
  }.entries) {
    test('lança ReverseGeocodingFailure: ${caso.key}', () {
      final servico = PhotonReverseGeocodingService(
        client: MockClient((_) => caso.value()),
        retryDelays: const [Duration.zero, Duration.zero],
      );

      expect(
        servico.addressOf(_ponto),
        throwsA(isA<ReverseGeocodingFailure>()),
      );
    });
  }

  test('lança ReverseGeocodingFailure em erro de rede', () {
    final servico = PhotonReverseGeocodingService(
      client: MockClient((_) => Future.error(Exception('sem rede'))),
      retryDelays: const [Duration.zero, Duration.zero],
    );

    expect(servico.addressOf(_ponto), throwsA(isA<ReverseGeocodingFailure>()));
  });

  group('retentativa', () {
    const zero = [Duration.zero, Duration.zero];

    test('HTTP 429 seguido de 200 devolve o endereço', () async {
      var chamadas = 0;
      final servico = PhotonReverseGeocodingService(
        client: MockClient((_) async {
          chamadas++;
          return chamadas == 1
              ? _json('{}', 429)
              : _json(_corpo({'street': 'Rua A', 'city': 'Criciúma'}));
        }),
        retryDelays: zero,
      );

      expect(await servico.addressOf(_ponto), 'Rua A, Criciúma');
      expect(chamadas, 2);
    });

    test('erro de rede seguido de 200 devolve o endereço', () async {
      var chamadas = 0;
      final servico = PhotonReverseGeocodingService(
        client: MockClient((_) async {
          chamadas++;
          if (chamadas == 1) throw http.ClientException('caiu');
          return _json(_corpo({'street': 'Rua A', 'city': 'Criciúma'}));
        }),
        retryDelays: zero,
      );

      expect(await servico.addressOf(_ponto), 'Rua A, Criciúma');
    });

    test('esgotadas as tentativas, lança a falha', () async {
      var chamadas = 0;
      final servico = PhotonReverseGeocodingService(
        client: MockClient((_) async {
          chamadas++;
          return _json('{}', 503);
        }),
        retryDelays: zero,
      );

      await expectLater(
        servico.addressOf(_ponto),
        throwsA(isA<ReverseGeocodingFailure>()),
      );
      expect(chamadas, 3);
    });

    test('falha definitiva (403, sem resultado) não retenta', () async {
      var chamadas = 0;
      final servico = PhotonReverseGeocodingService(
        client: MockClient((_) async {
          chamadas++;
          return _json('{"features": []}');
        }),
        retryDelays: zero,
      );

      await expectLater(
        servico.addressOf(_ponto),
        throwsA(isA<ReverseGeocodingFailure>()),
      );
      expect(chamadas, 1);
    });
  });
}
