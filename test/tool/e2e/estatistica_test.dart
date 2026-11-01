import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import '../../../tool/e2e/src/estatistica.dart';

void main() {
  group('Clopper-Pearson', () {
    test(
      '0 falhas em 60: limite superior bilateral de 95% = 1 - 0,025^(1/60)',
      () {
        final ic = clopperPearson(0, 60);
        final esperado = 1 - math.pow(0.025, 1 / 60);
        expect(ic.inferior, 0);
        expect(ic.superior, closeTo(esperado, 1e-9));
        expect(ic.superior * 100, closeTo(5.96, 0.01));
      },
    );

    test('n falhas em n: limite superior é 1 e o inferior é 0,025^(1/n)', () {
      final ic = clopperPearson(30, 30);
      expect(ic.superior, 1);
      expect(ic.inferior, closeTo(math.pow(0.025, 1 / 30), 1e-9));
    });

    test('coincide com os valores do scipy (segunda via independente)', () {
      final arquivo = File('test/fixtures/e2e_clopper_pearson_vectors.json');
      final json =
          jsonDecode(arquivo.readAsStringSync()) as Map<String, dynamic>;
      final casos = json['casos'] as List<dynamic>;
      expect(casos, isNotEmpty);
      for (final c in casos.cast<Map<String, dynamic>>()) {
        final ic = clopperPearson(c['x'] as int, c['n'] as int);
        expect(
          ic.inferior,
          closeTo((c['inferior'] as num).toDouble(), 1e-9),
          reason: 'inferior x=${c['x']} n=${c['n']}',
        );
        expect(
          ic.superior,
          closeTo((c['superior'] as num).toDouble(), 1e-9),
          reason: 'superior x=${c['x']} n=${c['n']}',
        );
      }
    });

    test('rejeita entradas inválidas', () {
      expect(() => clopperPearson(1, 0), throwsArgumentError);
      expect(() => clopperPearson(5, 4), throwsArgumentError);
      expect(() => clopperPearson(-1, 4), throwsArgumentError);
    });
  });

  group('posto mais próximo', () {
    test('posição ⌈p·N⌉ com N ímpar e par', () {
      expect(postoMaisProximo([5, 1, 3, 2, 4], 50), 3);
      expect(postoMaisProximo([4, 1, 3, 2], 50), 2);
      expect(postoMaisProximo([for (var i = 1; i <= 20; i++) i], 95), 19);
      expect(postoMaisProximo([for (var i = 1; i <= 100; i++) i], 95), 95);
    });

    test('um elemento é a mediana e o P95', () {
      expect(mediana([7]), 7);
      expect(postoMaisProximo([7], 95), 7);
    });

    test('sem amostras devolve null, nunca zero', () {
      expect(mediana([]), isNull);
      expect(postoMaisProximo([], 95), isNull);
    });

    test('mediana é o percentil 50 pelo mesmo método (sem interpolação)', () {
      expect(mediana([10, 20, 30, 40]), 20);
    });
  });
}
