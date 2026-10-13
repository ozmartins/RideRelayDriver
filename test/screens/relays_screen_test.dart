import 'dart:async';

import 'package:driver/domain/relay.dart';
import 'package:driver/screens/relays_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const damus = 'wss://relay.damus.io';

  Widget tela({
    required List<Relay> relays,
    Future<String?> Function(String)? onAdd,
    Future<void> Function(String)? onRemove,
    Future<void> Function()? onRestore,
    Future<void> Function()? onReconnect,
  }) => MaterialApp(
    home: RelaysScreen(
      relays: relays,
      onAdd: onAdd ?? (_) async => null,
      onRemove: onRemove ?? (_) async {},
      onRestoreDefaults: onRestore ?? () async {},
      onReconnect: onReconnect ?? () async {},
    ),
  );

  testWidgets('lista os relays com estado e origem', (tester) async {
    await tester.pumpWidget(
      tela(
        relays: const [
          Relay(url: damus, status: RelayStatus.connected, isDefault: true),
          Relay(url: 'wss://meu.relay.org', status: RelayStatus.unavailable),
        ],
      ),
    );

    expect(find.text(damus), findsOneWidget);
    expect(find.textContaining('conectado · lista padrão'), findsOneWidget);
    expect(find.textContaining('adicionado por você'), findsOneWidget);
  });

  testWidgets('recusa endereço inválido e mantém a lista inalterada', (
    tester,
  ) async {
    var chamadas = 0;
    await tester.pumpWidget(
      tela(
        relays: const [Relay(url: damus)],
        onAdd: (url) async {
          chamadas++;
          return 'Endereço inválido. Use wss:// ou ws:// com um domínio válido.';
        },
      ),
    );

    await tester.enterText(find.byType(TextField), 'banana');
    await tester.tap(find.text('Adicionar'));
    await tester.pump();

    expect(find.textContaining('Endereço inválido'), findsOneWidget);
    expect(find.text(damus), findsOneWidget);
    expect(chamadas, 1);
    expect(
      find.text('banana'),
      findsOneWidget,
      reason: 'o texto recusado permanece no campo para correção',
    );
  });

  testWidgets('recusa duplicado exibindo o motivo', (tester) async {
    await tester.pumpWidget(
      tela(
        relays: const [Relay(url: damus)],
        onAdd: (_) async => 'Este relay já está na lista.',
      ),
    );

    await tester.enterText(find.byType(TextField), damus);
    await tester.tap(find.text('Adicionar'));
    await tester.pump();

    expect(find.textContaining('já está na lista'), findsOneWidget);
  });

  testWidgets('limpa o campo quando a adição é aceita', (tester) async {
    await tester.pumpWidget(
      tela(
        relays: const [Relay(url: damus)],
        onAdd: (_) async => null,
      ),
    );

    await tester.enterText(find.byType(TextField), 'wss://novo.relay.org');
    await tester.tap(find.text('Adicionar'));
    await tester.pump();

    expect(find.text('wss://novo.relay.org'), findsNothing);
  });

  testWidgets('remover chama o callback com a url', (tester) async {
    String? removido;
    await tester.pumpWidget(
      tela(
        relays: const [Relay(url: damus)],
        onRemove: (url) async => removido = url,
      ),
    );

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pump();

    expect(removido, damus);
  });

  testWidgets('lista vazia explica a situação e oferece restaurar o padrão', (
    tester,
  ) async {
    var restaurou = false;
    await tester.pumpWidget(
      tela(relays: const [], onRestore: () async => restaurou = true),
    );

    expect(find.textContaining('Nenhum relay configurado'), findsOneWidget);

    await tester.tap(find.text('Restaurar lista padrão'));
    await tester.pump();

    expect(restaurou, isTrue);
  });

  group('botão Reconectar', () {
    testWidgets('chama onReconnect ao tocar', (tester) async {
      var chamadas = 0;
      await tester.pumpWidget(
        tela(
          relays: const [Relay(url: damus, status: RelayStatus.unavailable)],
          onReconnect: () async => chamadas++,
        ),
      );

      await tester.tap(find.byKey(const Key('botao-reconectar')));
      await tester.pump();

      expect(chamadas, 1);
    });

    testWidgets('fica desabilitado durante a chamada e volta depois', (
      tester,
    ) async {
      final espera = Completer<void>();
      var chamadas = 0;
      await tester.pumpWidget(
        tela(
          relays: const [Relay(url: damus, status: RelayStatus.unavailable)],
          onReconnect: () {
            chamadas++;
            return espera.future;
          },
        ),
      );

      await tester.tap(find.byKey(const Key('botao-reconectar')));
      await tester.pump();
      expect(find.text('Reconectando…'), findsOneWidget);

      // Segundo toque com a primeira rodada em curso não faz nada.
      await tester.tap(find.byKey(const Key('botao-reconectar')));
      await tester.pump();
      expect(chamadas, 1);

      espera.complete();
      await tester.pump();
      expect(find.text('Reconectar'), findsOneWidget);
    });

    testWidgets('não aparece com a lista vazia', (tester) async {
      await tester.pumpWidget(tela(relays: const []));

      expect(find.byKey(const Key('botao-reconectar')), findsNothing);
      expect(find.text('Restaurar lista padrão'), findsOneWidget);
    });
  });
}
