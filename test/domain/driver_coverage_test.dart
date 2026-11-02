import 'dart:convert';
import 'dart:math' as math;

import 'package:driver/domain/driver_coverage.dart';
import 'package:driver/domain/geo_distance.dart';
import 'package:driver/domain/geohash.dart';
import 'package:flutter_test/flutter_test.dart';

// Araranguá, Boa Vista (perto do equador) e Chuí (extremo sul do país).
const _ararangua = (lat: -28.9298, lon: -49.4753);
const _boaVista = (lat: 2.8235, lon: -60.6758);
const _chui = (lat: -33.6866, lon: -53.4595);
const _saoPaulo = (lat: -23.5505, lon: -46.6333);

List<List<String>> _tags(double lat, double lon, {List<int>? precisoes}) => [
  ['t', 'tcc-ufsc-caronas'],
  for (final p in precisoes ?? kPrecisoesDaTag)
    ['g', Geohash.encode(lat, lon, p)],
];

String _content(double lat, double lon) => jsonEncode({
  'origin': {'lat': lat, 'lon': lon},
  'destination': {'lat': lat + 0.1, 'lon': lon + 0.1},
  'payment': 'pix',
});

/// Ponto a [km] da referência, ao norte (aproximação suficiente para o teste:
/// 1° de latitude = 111,195 km, mesma constante do geohash).
({double lat, double lon}) _aoNorte(
  ({double lat, double lon}) ref,
  double km,
) => (lat: ref.lat + km / 111.195, lon: ref.lon);

DriverCoverage _cobertura(({double lat, double lon}) ref, {int raio = 10}) =>
    DriverCoverage.around(lat: ref.lat, lon: ref.lon, radiusKm: raio);

void main() {
  group('precisionFor', () {
    test('Araranguá: raio pequeno ⇒ 5, médio ⇒ 4, grande ⇒ 3', () {
      int p(int r) => DriverCoverage.precisionFor(r, _ararangua.lat);
      expect(p(1), 5);
      expect(p(4), 5);
      expect(p(5), 4);
      expect(p(10), 4);
      expect(p(19), 4);
      expect(p(20), 3);
      expect(p(100), 3);
    });

    test('em qualquer latitude do país a precisão escolhida cobre o raio', () {
      for (final lat in [_boaVista.lat, _ararangua.lat, _chui.lat, 0.0]) {
        for (var r = 1; r <= 100; r++) {
          final p = DriverCoverage.precisionFor(r, lat);
          expect(kPrecisoesDaTag, contains(p));
          double cobre(int q) {
            final longe = (lat.abs() + r / 111.195).clamp(0.0, 89.0);
            final h = Geohash.cellHeightKm(q);
            final w = Geohash.cellWidthKm(q, longe);
            return h < w ? h : w;
          }

          expect(cobre(p), greaterThanOrEqualTo(r), reason: 'lat $lat r $r');
          // E nenhuma precisão maior também cobriria.
          for (final maior in kPrecisoesDaTag.where((q) => q > p)) {
            expect(cobre(maior), lessThan(r), reason: 'lat $lat r $r p $maior');
          }
        }
      }
    });

    test('latitude alta, onde nem a precisão 3 cobre, ainda devolve 3', () {
      expect(DriverCoverage.precisionFor(100, 55), 3);
    });
  });

  group('around', () {
    test(
      'calcula precisão e células: até 9, sem repetição, com a da referência',
      () {
        final c = _cobertura(_ararangua, raio: 10);
        expect(c.precision, 4);
        expect(c.cells.length, lessThanOrEqualTo(9));
        expect(c.cells.toSet(), hasLength(c.cells.length));
        expect(c.cells.every((x) => x.length == c.precision), isTrue);
        expect(
          c.cells,
          contains(Geohash.encode(_ararangua.lat, _ararangua.lon, c.precision)),
        );
      },
    );

    test('raio fora de 1–100 lança ArgumentError', () {
      expect(() => _cobertura(_ararangua, raio: 0), throwsArgumentError);
      expect(() => _cobertura(_ararangua, raio: 101), throwsArgumentError);
    });

    test('latitude ou longitude fora da faixa lançam ArgumentError', () {
      expect(
        () => DriverCoverage.around(lat: 91, lon: 0, radiusKm: 10),
        throwsArgumentError,
      );
    });

    test('igualdade por valor', () {
      expect(_cobertura(_ararangua), _cobertura(_ararangua));
      expect(_cobertura(_ararangua), isNot(_cobertura(_ararangua, raio: 11)));
      expect(_cobertura(_ararangua), isNot(_cobertura(_saoPaulo)));
    });
  });

  group('withinRadius', () {
    test('é inclusivo no limite e falso poucos metros além', () {
      final c = _cobertura(_ararangua, raio: 10);
      final alvo = _aoNorte(_ararangua, 10);
      final metros = metersBetween(
        _ararangua.lat,
        _ararangua.lon,
        alvo.lat,
        alvo.lon,
      );
      // Raio exatamente igual à distância calculada: dentro.
      expect(metros, closeTo(10000, 60));
      final dentro = _aoNorte(_ararangua, 9.9);
      final fora = _aoNorte(_ararangua, 10.1);
      expect(c.withinRadius(dentro.lat, dentro.lon), isTrue);
      expect(c.withinRadius(fora.lat, fora.lon), isFalse);
      expect(c.withinRadius(_ararangua.lat, _ararangua.lon), isTrue);
    });

    test('São Paulo está fora de qualquer raio de Araranguá', () {
      final c = _cobertura(_ararangua, raio: 100);
      expect(c.withinRadius(_saoPaulo.lat, _saoPaulo.lon), isFalse);
    });
  });

  group('matchesCells', () {
    final c = _cobertura(_ararangua, raio: 10);

    test('aceita tag g de uma das células', () {
      expect(c.matchesCells(_tags(_ararangua.lat, _ararangua.lon)), isTrue);
    });

    test(
      'recusa sem g, g fora das células, g mal formada e só outra precisão',
      () {
        expect(
          c.matchesCells([
            ['t', 'tcc-ufsc-caronas'],
          ]),
          isFalse,
        );
        expect(c.matchesCells(_tags(_saoPaulo.lat, _saoPaulo.lon)), isFalse);
        expect(
          c.matchesCells([
            ['g', 'ZZZZ'],
            ['g', ''],
            ['g'],
          ]),
          isFalse,
        );
        // A cobertura é de precisão 4; só a tag de 5 caracteres não casa.
        expect(
          c.matchesCells(
            _tags(_ararangua.lat, _ararangua.lon, precisoes: const [5]),
          ),
          isFalse,
        );
      },
    );

    test('ignora tag mal formada e ainda casa com outra válida', () {
      final tags = [
        ['g', 'ZZZZ'],
        ['g', Geohash.encode(_ararangua.lat, _ararangua.lon, 4)],
      ];
      expect(c.matchesCells(tags), isTrue);
    });
  });

  group('evaluateRideRequest', () {
    final c = _cobertura(_ararangua, raio: 10);

    CoverageDecision avalia(
      double lat,
      double lon, {
      List<List<String>>? tags,
    }) => c.evaluateRideRequest(
      tags: tags ?? _tags(lat, lon),
      content: _content(lat, lon),
    );

    test('aceita origem dentro do raio, com g na célula', () {
      final o = _aoNorte(_ararangua, 3);
      expect(avalia(o.lat, o.lon).accepted, isTrue);
    });

    test('aceita origem dentro do raio a poucos metros da borda da célula', () {
      // Raio 15 km, precisão 4: a borda norte da célula central fica a
      // ~11 km da referência, dentro do raio.
      final c15 = _cobertura(_ararangua, raio: 15);
      expect(c15.precision, 4);
      final borda = Geohash.bounds(
        Geohash.encode(_ararangua.lat, _ararangua.lon, c15.precision),
      );
      final o = (lat: borda.maxLat + 0.00005, lon: _ararangua.lon);
      final dist = metersBetween(_ararangua.lat, _ararangua.lon, o.lat, o.lon);
      expect(dist, lessThan(15000), reason: 'pré-condição do teste');
      final d = c15.evaluateRideRequest(
        tags: _tags(o.lat, o.lon),
        content: _content(o.lat, o.lon),
      );
      expect(d.accepted, isTrue);
    });

    test('recusa sem tag g', () {
      final o = _aoNorte(_ararangua, 3);
      final d = avalia(
        o.lat,
        o.lon,
        tags: [
          ['t', 'tcc-ufsc-caronas'],
        ],
      );
      expect(d.accepted, isFalse);
      expect(d.refusal, CoverageRefusal.semTagG);
    });

    test('recusa g fora das células, mesmo com a origem dentro do raio', () {
      final o = _aoNorte(_ararangua, 3);
      final d = avalia(o.lat, o.lon, tags: _tags(_saoPaulo.lat, _saoPaulo.lon));
      expect(d.refusal, CoverageRefusal.foraDasCelulas);
    });

    test('recusa origem ilegível: não JSON, sem origin, origin malformada', () {
      final tags = _tags(_ararangua.lat, _ararangua.lon);
      for (final content in [
        'isto não é json',
        '{}',
        '[]',
        '{"origin": 3}',
        '{"origin": {"lat": "x", "lon": 1}}',
        '{"origin": {"lat": 95, "lon": 1}}',
      ]) {
        final d = c.evaluateRideRequest(tags: tags, content: content);
        expect(d.refusal, CoverageRefusal.origemIlegivel, reason: content);
      }
    });

    test('recusa além do raio, mesmo com g na célula', () {
      // Cobertura de raio 10 em precisão 4: células de ~19×34 km, então uma
      // origem a 15 km ao norte ainda está nas 9 células mas fora do raio.
      final o = _aoNorte(_ararangua, 15);
      final d = avalia(o.lat, o.lon);
      expect(d.refusal, CoverageRefusal.alemDoRaio);
    });

    test('recusa São Paulo', () {
      final d = avalia(_saoPaulo.lat, _saoPaulo.lon);
      expect(d.accepted, isFalse);
    });

    test('varredura: dentro do raio é aceito, fora é recusado, em todas as direções', () {
      for (final raio in [1, 4, 5, 10, 19, 20, 50, 100]) {
        for (final ref in [_ararangua, _boaVista, _chui]) {
          final cob = _cobertura(ref, raio: raio);
          for (var graus = 0; graus < 360; graus += 15) {
            for (final fator in [0.5, 0.97, 1.03, 1.5]) {
              final km = raio * fator;
              final rad = graus * math.pi / 180;
              final lat = ref.lat + km * _cos(rad) / 111.195;
              final lon =
                  ref.lon +
                  km * _sin(rad) / (111.195 * _cos(ref.lat * math.pi / 180));
              final metros = metersBetween(ref.lat, ref.lon, lat, lon);
              final esperadoDentro = metros <= raio * 1000;
              final d = cob.evaluateRideRequest(
                tags: _tags(lat, lon),
                content: _content(lat, lon),
              );
              expect(
                d.accepted,
                esperadoDentro,
                reason:
                    'raio $raio ref $ref graus $graus fator $fator '
                    '(${metros.toStringAsFixed(0)} m): $d',
              );
            }
          }
        }
      }
    });
  });

  group('toJson / fromJson', () {
    test('ida e volta recalcula precisão e células', () {
      final c = _cobertura(_ararangua, raio: 25);
      final volta = DriverCoverage.fromJson(jsonDecode(jsonEncode(c.toJson())));
      expect(volta, c);
      expect(volta.precision, c.precision);
      expect(volta.cells, c.cells);
    });

    test('só leva lat, lon e raio_km', () {
      expect(_cobertura(_ararangua).toJson().keys.toSet(), {
        'lat',
        'lon',
        'raio_km',
      });
    });

    test(
      'lança FormatException para campo faltando, tipo errado e raio fora',
      () {
        for (final json in <Object?>[
          null,
          'x',
          <String, Object?>{},
          {'lat': -28.9, 'lon': -49.4},
          {'lat': 'a', 'lon': -49.4, 'raio_km': 10},
          {'lat': -28.9, 'lon': -49.4, 'raio_km': 10.5},
          {'lat': -28.9, 'lon': -49.4, 'raio_km': 0},
          {'lat': -28.9, 'lon': -49.4, 'raio_km': 101},
          {'lat': 95, 'lon': -49.4, 'raio_km': 10},
        ]) {
          expect(
            () => DriverCoverage.fromJson(json),
            throwsFormatException,
            reason: '$json',
          );
        }
      },
    );
  });
}

double _cos(double r) => math.cos(r);
double _sin(double r) => math.sin(r);
