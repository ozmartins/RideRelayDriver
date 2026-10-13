import 'package:driver/domain/availability_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AvailabilityRules.canGoOnline (FR-008)', () {
    test('permite ficar online com posição válida disponível', () {
      expect(AvailabilityRules.canGoOnline(hasValidPosition: true), isTrue);
    });

    test('impede ficar online sem posição válida disponível', () {
      expect(AvailabilityRules.canGoOnline(hasValidPosition: false), isFalse);
    });
  });
}
