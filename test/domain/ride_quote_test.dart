import 'package:driver/domain/ride_quote.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('guarda requestId, pricePerKm, total e os dados do motorista', () {
    const quote = RideQuote(
      passengerPubkey: 'pubkey-do-passageiro',
      requestId: 'id-da-solicitacao',
      pricePerKm: 2.5,
      total: 18.75,
      driverName: 'Fulano da Silva',
      carBrand: 'Fiat',
      carModel: 'Palio',
      carYear: 2018,
      etaMinutes: 6,
    );

    expect(quote.requestId, 'id-da-solicitacao');
    expect(quote.pricePerKm, 2.5);
    expect(quote.total, 18.75);
    expect(quote.driverName, 'Fulano da Silva');
    expect(quote.carBrand, 'Fiat');
    expect(quote.carModel, 'Palio');
    expect(quote.carYear, 2018);
    expect(quote.etaMinutes, 6);
  });

  test('etaMinutes é opcional, nulo por padrão', () {
    const quote = RideQuote(
      passengerPubkey: 'pubkey-do-passageiro',
      requestId: 'id-da-solicitacao',
      pricePerKm: 2.5,
      total: 18.75,
      driverName: 'Fulano da Silva',
      carBrand: 'Fiat',
      carModel: 'Palio',
      carYear: 2018,
    );

    expect(quote.etaMinutes, isNull);
  });
}
