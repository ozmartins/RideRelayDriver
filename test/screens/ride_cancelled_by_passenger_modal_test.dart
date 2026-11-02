import 'package:driver/screens/ride_cancelled_by_passenger_modal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> abrir(WidgetTester tester, {VoidCallback? onClose}) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RideCancelledByPassengerModal(onClose: onClose ?? () {}),
        ),
      ),
    );
  }

  testWidgets('mostra título, mensagem e o botão OK', (tester) async {
    await abrir(tester);

    expect(find.text('Corrida cancelada'), findsOneWidget);
    expect(find.text('O passageiro cancelou a corrida.'), findsOneWidget);
    expect(find.text('OK'), findsOneWidget);
  });

  testWidgets('"OK" chama onClose', (tester) async {
    var fechou = 0;
    await abrir(tester, onClose: () => fechou++);

    await tester.tap(find.text('OK'));
    await tester.pump();

    expect(fechou, 1);
  });
}
