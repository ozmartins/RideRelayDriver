import 'package:driver/domain/nostr_event.dart';
import 'package:driver/services/consumed_kinds.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('driverConsumedKinds', () {
    test('contém os kinds de recibo e confirmação (emenda 25)', () {
      expect(driverConsumedKinds, contains(20014));
      expect(driverConsumedKinds, contains(20015));
      expect(NostrEvent.kindReceipt, 20014);
      expect(NostrEvent.kindReceiptAck, 20015);
    });

    test(
      'mantém os kinds anteriores e é exatamente o conjunto do contrato',
      () {
        expect(driverConsumedKinds, {
          20001,
          20003,
          20008,
          20010,
          20013,
          20014,
          20015,
        });
      },
    );
  });
}
