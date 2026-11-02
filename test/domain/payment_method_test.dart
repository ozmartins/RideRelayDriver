import 'package:driver/domain/payment_method.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('dinheiro tem rótulo e valor de persistência corretos', () {
    expect(PaymentMethod.cash.label, 'Dinheiro');
    expect(PaymentMethod.cash.storageValue, 'cash');
  });

  test('pix tem rótulo e valor de persistência corretos', () {
    expect(PaymentMethod.pix.label, 'PIX');
    expect(PaymentMethod.pix.storageValue, 'pix');
  });

  test('cartão tem rótulo e valor de persistência corretos', () {
    expect(PaymentMethod.card.label, 'Cartão');
    expect(PaymentMethod.card.storageValue, 'card');
  });

  test('valor do contrato de cada forma de pagamento', () {
    expect(PaymentMethod.cash.wireValue, 'dinheiro');
    expect(PaymentMethod.pix.wireValue, 'pix');
    expect(PaymentMethod.card.wireValue, 'cartao');
  });

  test('fromWire reconhece os três valores e recusa qualquer outro', () {
    for (final metodo in PaymentMethod.values) {
      expect(PaymentMethod.fromWire(metodo.wireValue), metodo);
    }
    expect(PaymentMethod.fromWire('cash'), isNull);
    expect(PaymentMethod.fromWire(''), isNull);
  });
}
