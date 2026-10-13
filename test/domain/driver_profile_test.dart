import 'package:driver/domain/driver_profile.dart';
import 'package:driver/domain/payment_method.dart';
import 'package:flutter_test/flutter_test.dart';

DriverProfile perfilValido({
  String placaVeiculo = 'ABC1234',
  Set<PaymentMethod> paymentMethods = const {PaymentMethod.cash},
  double precoPorKm = 2.5,
  int anoVeiculo = 2018,
}) => DriverProfile(
  nome: 'Fulano da Silva',
  uf: 'SC',
  cidade: 'Araranguá',
  marcaVeiculo: 'Fiat',
  modeloVeiculo: 'Palio',
  corVeiculo: 'Preto',
  placaVeiculo: placaVeiculo,
  paymentMethods: paymentMethods,
  precoPorKm: precoPorKm,
  anoVeiculo: anoVeiculo,
);

void main() {
  group('DriverProfile — acceptsPayment', () {
    test('aceita só as formas do cadastro, pelo valor do contrato', () {
      final perfil = perfilValido(
        paymentMethods: {PaymentMethod.cash, PaymentMethod.card},
      );
      expect(perfil.acceptsPayment('dinheiro'), isTrue);
      expect(perfil.acceptsPayment('cartao'), isTrue);
      expect(perfil.acceptsPayment('pix'), isFalse);
    });

    test('valor que não é do contrato nunca é aceito', () {
      final perfil = perfilValido(paymentMethods: {...PaymentMethod.values});
      expect(perfil.acceptsPayment('cash'), isFalse);
      expect(perfil.acceptsPayment(''), isFalse);
    });
  });

  group('DriverProfile — validação de placa (FR-005, D3)', () {
    test('aceita o formato antigo (3 letras + 4 dígitos)', () {
      expect(DriverProfile.isValidPlaca('ABC1234'), isTrue);
    });

    test('aceita o formato Mercosul em minúsculo', () {
      expect(DriverProfile.isValidPlaca('abc1d23'), isTrue);
    });

    test('aceita o formato Mercosul com hífen, normalizando para o mesmo '
        'valor da versão sem hífen', () {
      expect(DriverProfile.isValidPlaca('ABC-1D23'), isTrue);
      expect(
        DriverProfile.normalizePlaca('ABC-1D23'),
        DriverProfile.normalizePlaca('abc1d23'),
      );
      expect(DriverProfile.normalizePlaca('ABC-1D23'), 'ABC1D23');
    });

    test('recusa placa fora dos dois formatos (curta demais)', () {
      expect(DriverProfile.isValidPlaca('AB1234'), isFalse);
    });

    test('recusa placa com todas as posições numéricas', () {
      expect(DriverProfile.isValidPlaca('1231234'), isFalse);
    });
  });

  group('DriverProfile — campos de texto obrigatórios (FR-002, FR-006)', () {
    test('nome vazio é inválido', () {
      expect(DriverProfile.isTextoValido(''), isFalse);
    });

    test('nome só com espaços é inválido', () {
      expect(DriverProfile.isTextoValido('   '), isFalse);
    });

    test('nome com espaços nas pontas é válido e normaliza sem eles', () {
      expect(DriverProfile.isTextoValido('  Fulano  '), isTrue);
      expect(DriverProfile.normalizeTexto('  Fulano  '), 'Fulano');
    });
  });

  group('DriverProfile — validade do cadastro completo (FR-003, FR-004)', () {
    test('cadastro com todos os campos válidos é válido', () {
      expect(perfilValido().isValido, isTrue);
    });

    test('UF fora da lista fixa é inválida', () {
      expect(perfilValido().copyWith(uf: 'ZZ').isValido, isFalse);
    });

    test('cidade que não pertence à UF selecionada é inválida', () {
      // Araranguá é de SC, não de SP.
      expect(perfilValido().copyWith(uf: 'SP').isValido, isFalse);
    });

    test('placa inválida invalida o cadastro inteiro', () {
      expect(perfilValido(placaVeiculo: 'INVALIDA').isValido, isFalse);
    });
  });

  group(
    'DriverProfile — formas de pagamento (FR-002, FR-003 da feature 005)',
    () {
      test('cadastro sem nenhuma forma de pagamento é inválido', () {
        expect(perfilValido(paymentMethods: const {}).isValido, isFalse);
      });

      test('cadastro com uma forma de pagamento é válido', () {
        expect(
          perfilValido(paymentMethods: const {PaymentMethod.pix}).isValido,
          isTrue,
        );
      });

      test('cadastro com as três formas de pagamento é válido', () {
        expect(
          perfilValido(paymentMethods: PaymentMethod.values.toSet()).isValido,
          isTrue,
        );
      });
    },
  );

  group(
    'DriverProfile — preço por quilômetro (FR-001, FR-002 da feature 006)',
    () {
      test('cadastro com precoPorKm zerado é inválido', () {
        expect(perfilValido(precoPorKm: 0).isValido, isFalse);
      });

      test('cadastro com precoPorKm negativo é inválido', () {
        expect(perfilValido(precoPorKm: -1).isValido, isFalse);
      });

      test('cadastro com precoPorKm positivo é válido', () {
        expect(perfilValido(precoPorKm: 2.5).isValido, isTrue);
      });
    },
  );

  group('DriverProfile.parsePrecoPorKm (D1 de research.md)', () {
    test('aceita vírgula como separador decimal', () {
      expect(DriverProfile.parsePrecoPorKm('2,50'), 2.5);
    });

    test('aceita ponto como separador decimal', () {
      expect(DriverProfile.parsePrecoPorKm('2.50'), 2.5);
    });

    test('recusa texto vazio', () {
      expect(DriverProfile.parsePrecoPorKm(''), isNull);
    });

    test('recusa zero', () {
      expect(DriverProfile.parsePrecoPorKm('0'), isNull);
    });

    test('recusa negativo', () {
      expect(DriverProfile.parsePrecoPorKm('-1'), isNull);
    });

    test('recusa mais de duas casas decimais', () {
      expect(DriverProfile.parsePrecoPorKm('2,555'), isNull);
    });

    test('recusa texto não numérico', () {
      expect(DriverProfile.parsePrecoPorKm('abc'), isNull);
    });
  });

  group('DriverProfile — ano do veículo (FR-001, FR-002 da feature 008)', () {
    test('cadastro com ano dentro da faixa é válido', () {
      expect(perfilValido(anoVeiculo: 2018).isValido, isTrue);
    });

    test('cadastro com ano anterior a 1900 é inválido', () {
      expect(perfilValido(anoVeiculo: 1899).isValido, isFalse);
    });

    test('cadastro com ano posterior ao corrente + 1 é inválido', () {
      expect(
        perfilValido(anoVeiculo: DateTime.now().year + 2).isValido,
        isFalse,
      );
    });

    test('cadastro com ano igual ao corrente + 1 é válido (0 km)', () {
      expect(
        perfilValido(anoVeiculo: DateTime.now().year + 1).isValido,
        isTrue,
      );
    });
  });

  group('DriverProfile.parseAnoVeiculo (D1 de research.md)', () {
    test('aceita um ano de 4 dígitos dentro da faixa', () {
      expect(DriverProfile.parseAnoVeiculo('2018'), 2018);
    });

    test('recusa texto vazio', () {
      expect(DriverProfile.parseAnoVeiculo(''), isNull);
    });

    test('recusa menos de 4 dígitos', () {
      expect(DriverProfile.parseAnoVeiculo('18'), isNull);
    });

    test('recusa mais de 4 dígitos', () {
      expect(DriverProfile.parseAnoVeiculo('20199'), isNull);
    });

    test('recusa texto não numérico', () {
      expect(DriverProfile.parseAnoVeiculo('abcd'), isNull);
    });

    test('recusa ano anterior a 1900', () {
      expect(DriverProfile.parseAnoVeiculo('1899'), isNull);
    });

    test('recusa ano posterior ao corrente + 1', () {
      expect(
        DriverProfile.parseAnoVeiculo('${DateTime.now().year + 2}'),
        isNull,
      );
    });
  });

  group('DriverProfile — toMap/fromMap', () {
    test('fromMap(toMap()) devolve um cadastro igual ao original', () {
      final original = perfilValido(
        paymentMethods: const {PaymentMethod.cash, PaymentMethod.card},
      );
      expect(DriverProfile.fromMap(original.toMap()), original);
    });

    test('toMap serializa payment_methods como valores separados por '
        'vírgula', () {
      final mapa = perfilValido(
        paymentMethods: const {PaymentMethod.pix, PaymentMethod.card},
      ).toMap();
      final valores = (mapa['payment_methods'] as String).split(',');
      expect(valores, unorderedEquals(['pix', 'card']));
    });

    test('fromMap com payment_methods vazio decodifica como conjunto '
        'vazio (cadastro de uma instalação anterior à feature 005)', () {
      final mapa = perfilValido().copyWith(paymentMethods: const {}).toMap();
      expect(mapa['payment_methods'], '');

      final perfil = DriverProfile.fromMap(mapa);
      expect(perfil.paymentMethods, isEmpty);
      expect(perfil.isValido, isFalse);
    });

    test('fromMap ignora um valor desconhecido na coluna, sem lançar', () {
      final mapa = perfilValido().toMap();
      mapa['payment_methods'] = 'cash,valor-desconhecido';
      final perfil = DriverProfile.fromMap(mapa);
      expect(perfil.paymentMethods, {PaymentMethod.cash});
    });

    test('toMap serializa preco_por_km diretamente, sem conversão', () {
      final mapa = perfilValido(precoPorKm: 3.75).toMap();
      expect(mapa['preco_por_km'], 3.75);
    });

    test('fromMap com preco_por_km zerado decodifica como cadastro '
        'inválido (equivalente a uma migração das versões 1/2)', () {
      final mapa = perfilValido().toMap();
      mapa['preco_por_km'] = 0.0;
      final perfil = DriverProfile.fromMap(mapa);
      expect(perfil.precoPorKm, 0);
      expect(perfil.isValido, isFalse);
    });

    test('toMap serializa ano_veiculo diretamente, sem conversão', () {
      final mapa = perfilValido(anoVeiculo: 2020).toMap();
      expect(mapa['ano_veiculo'], 2020);
    });

    test('fromMap com ano_veiculo zerado decodifica como cadastro inválido '
        '(equivalente a uma migração das versões 1/2/3)', () {
      final mapa = perfilValido().toMap();
      mapa['ano_veiculo'] = 0;
      final perfil = DriverProfile.fromMap(mapa);
      expect(perfil.anoVeiculo, 0);
      expect(perfil.isValido, isFalse);
    });
  });

  group('DriverProfile — igualdade considera paymentMethods', () {
    test('mesmo conjunto, ordem de construção diferente, são iguais', () {
      final a = perfilValido(
        paymentMethods: const {PaymentMethod.cash, PaymentMethod.pix},
      );
      final b = perfilValido(
        paymentMethods: const {PaymentMethod.pix, PaymentMethod.cash},
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('conjuntos diferentes não são iguais', () {
      final a = perfilValido(paymentMethods: const {PaymentMethod.cash});
      final b = perfilValido(paymentMethods: const {PaymentMethod.pix});
      expect(a, isNot(b));
    });
  });
}
