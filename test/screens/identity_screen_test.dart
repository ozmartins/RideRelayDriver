import 'package:driver/domain/identity.dart';
import 'package:driver/screens/identity_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Chaves fixas de teste, sem valor real: nunca usadas em rede.
final _publicKey = 'a' * 64;
final _privateKey = 'b' * 64;

void main() {
  final identity = Identity(publicKey: _publicKey, privateKey: _privateKey);

  Future<void> pump(WidgetTester tester) =>
      tester.pumpWidget(MaterialApp(home: IdentityScreen(identity: identity)));

  testWidgets('exibe a chave pública', (tester) async {
    await pump(tester);

    expect(find.text(_publicKey), findsOneWidget);
  });

  testWidgets('não exibe a chave privada em nenhum widget de texto', (
    tester,
  ) async {
    await pump(tester);

    final textos = <String>[
      ...tester.widgetList<Text>(find.byType(Text)).map((w) => w.data ?? ''),
      ...tester
          .widgetList<SelectableText>(find.byType(SelectableText))
          .map((w) => w.data ?? ''),
    ];

    expect(
      textos.any((t) => t.contains(_privateKey)),
      isFalse,
      reason: 'a chave privada nunca deve aparecer em tela (Princípio I)',
    );
    expect(textos.any((t) => t.contains(_publicKey)), isTrue);
  });

  testWidgets('advertindo que desinstalar destrói a identidade', (
    tester,
  ) async {
    await pump(tester);

    expect(find.textContaining('irreversível'), findsOneWidget);
  });

  testWidgets('lida com identidade ainda não carregada', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: IdentityScreen(identity: null)),
    );

    expect(find.textContaining('ainda não carregada'), findsOneWidget);
  });
}
