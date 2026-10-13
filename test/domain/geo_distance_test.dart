import 'package:driver/domain/geo_distance.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('metersBetween', () {
    test('mesmo ponto tem distância zero', () {
      expect(metersBetween(-28.9298, -49.4753, -28.9298, -49.4753), 0);
    });

    test('dois pontos ~1 grau de latitude de distância ficam perto de '
        '111 km (aproximação esférica padrão)', () {
      final distancia = metersBetween(0, 0, 1, 0);

      expect(distancia, closeTo(111195, 500));
    });

    test('distância conhecida entre dois pontos de Araranguá (~57 m)', () {
      // Coordenadas escolhidas para dar uma distância pequena, da ordem do
      // limiar de 50 m usado por FR-008.
      final distancia = metersBetween(-28.9298, -49.4753, -28.9303, -49.4753);

      expect(distancia, closeTo(55.6, 2));
    });
  });
}
