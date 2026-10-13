import 'package:driver/screens/cancel_ride_modal.dart';
import 'package:driver/screens/identidade_visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> abrir(
    WidgetTester tester, {
    VoidCallback? onConfirm,
    VoidCallback? onBack,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CancelRideModal(
            onConfirm: onConfirm ?? () {},
            onBack: onBack ?? () {},
          ),
        ),
      ),
    );
  }

  testWidgets('mostra título, mensagem e as duas ações', (tester) async {
    await abrir(tester);

    expect(find.text('Cancelar corrida?'), findsOneWidget);
    expect(find.textContaining('passageiro será avisado'), findsOneWidget);
    expect(find.text('Voltar'), findsOneWidget);
    expect(find.text('Cancelar corrida'), findsOneWidget);
  });

  testWidgets('o botão "Cancelar corrida" é roxo com texto branco '
      '(feature 022, FR-003)', (tester) async {
    await abrir(tester);

    final botao = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Cancelar corrida'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(botao.style!.backgroundColor!.resolve({}), IdentidadeVisual.roxo);
    expect(botao.style!.foregroundColor!.resolve({}), Colors.white);
  });

  testWidgets('"Cancelar corrida" chama só onConfirm', (tester) async {
    var confirmou = 0;
    var voltou = 0;
    await abrir(tester, onConfirm: () => confirmou++, onBack: () => voltou++);

    await tester.tap(find.text('Cancelar corrida'));
    await tester.pump();

    expect(confirmou, 1);
    expect(voltou, 0);
  });

  testWidgets('"Voltar" chama só onBack', (tester) async {
    var confirmou = 0;
    var voltou = 0;
    await abrir(tester, onConfirm: () => confirmou++, onBack: () => voltou++);

    await tester.tap(find.text('Voltar'));
    await tester.pump();

    expect(voltou, 1);
    expect(confirmou, 0);
  });
}
