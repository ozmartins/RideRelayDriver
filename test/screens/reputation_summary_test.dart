import 'package:driver/domain/driver_profile.dart';
import 'package:driver/domain/payment_method.dart';
import 'package:driver/domain/receipt.dart';
import 'package:driver/domain/reputation.dart';
import 'package:driver/domain/reputation_view.dart';
import 'package:driver/domain/ride_request_received.dart';
import 'package:driver/screens/reputation_summary.dart';
import 'package:driver/screens/ride_request_modal.dart';
import 'package:driver/services/receipt_signature.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import '../support/receipt_fixtures.dart';
import 'ride_request_modal_test.dart'
    show FakeReverseGeocodingService, FakeRouteDistanceService;

Future<void> _montarResumo(WidgetTester tester, ReputationView? view) =>
    tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ReputationSummary(view: view)),
      ),
    );

ReputationView _view({
  int verifiedCount = 3,
  double? verifiedAverage = 4.67,
  DeclaredReputation declared = const DeclaredReputation(
    corridas: 12,
    avaliacoes: 9,
    media: 4.78,
  ),
  int invalidDiscarded = 0,
  int gaps = 0,
  bool inconsistent = false,
}) => ReputationView(
  verifiedCount: verifiedCount,
  verifiedAverage: verifiedAverage,
  declared: declared,
  invalidDiscarded: invalidDiscarded,
  gaps: gaps,
  inconsistent: inconsistent,
);

void main() {
  group('ReputationSummary', () {
    testWidgets('verificada em destaque e declarada em texto menor', (
      tester,
    ) async {
      await _montarResumo(tester, _view());

      expect(
        find.text('Reputação verificada: 4,67 ★ em 3 recibos'),
        findsOneWidget,
      );
      expect(
        find.text('Declarada pelo passageiro: 12 corridas, média 4,78'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('reputacao-inconsistente')), findsNothing);
      expect(find.byKey(const Key('reputacao-lacunas')), findsNothing);
      expect(find.byKey(const Key('reputacao-descartados')), findsNothing);

      final verificada = tester.widget<Text>(
        find.byKey(const Key('reputacao-verificada')),
      );
      final declarada = tester.widget<Text>(
        find.byKey(const Key('reputacao-declarada')),
      );
      expect(
        verificada.style!.fontSize ?? 14,
        greaterThan(declarada.style!.fontSize!),
      );
    });

    testWidgets('sem reputação: "sem histórico"', (tester) async {
      await _montarResumo(tester, null);
      expect(find.byKey(const Key('reputacao-sem-historico')), findsOneWidget);
      expect(find.byKey(const Key('reputacao-verificada')), findsNothing);
    });

    testWidgets('inconsistente é destacado', (tester) async {
      await _montarResumo(tester, _view(inconsistent: true));
      expect(find.byKey(const Key('reputacao-inconsistente')), findsOneWidget);
    });

    testWidgets('lacunas: "N recibos não apresentados" (singular e plural)', (
      tester,
    ) async {
      await _montarResumo(tester, _view(gaps: 2));
      expect(find.text('2 recibos não apresentados'), findsOneWidget);
      await _montarResumo(tester, _view(gaps: 1));
      expect(find.text('1 recibo não apresentado'), findsOneWidget);
    });

    testWidgets('recibo descartado por inválido é sinalizado', (tester) async {
      await _montarResumo(
        tester,
        _view(invalidDiscarded: 1, verifiedCount: 0, verifiedAverage: null),
      );
      expect(find.text('1 recibo descartado por ser inválido'), findsOneWidget);
      expect(
        find.text('Reputação verificada: nenhum recibo válido'),
        findsOneWidget,
      );
    });

    testWidgets('sem notas verificadas e sem avaliações declaradas', (
      tester,
    ) async {
      await _montarResumo(
        tester,
        _view(
          verifiedAverage: null,
          declared: const DeclaredReputation(corridas: 1, avaliacoes: 0),
          verifiedCount: 1,
        ),
      );
      expect(
        find.text('Reputação verificada: sem notas em 1 recibo'),
        findsOneWidget,
      );
      expect(
        find.text('Declarada pelo passageiro: 1 corrida, sem avaliações'),
        findsOneWidget,
      );
    });
  });

  group('RideRequestModal — reputação do passageiro (US1)', () {
    final passageiro = newTestIdentity();

    RideRequestReceived solicitacao(Reputation? reputation) =>
        RideRequestReceived(
          requestId: 'id-solicitacao',
          passengerPubkey: passageiro.publicKey,
          origin: const LatLng(-28.9298, -49.4753),
          destination: const LatLng(-28.6721, -49.3671),
          payment: 'pix',
          reputation: reputation,
        );

    Future<void> montar(WidgetTester tester, RideRequestReceived s) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RideRequestModal(
              request: s,
              driverPosition: const LatLng(-28.9350, -49.4800),
              driverProfile: DriverProfile(
                nome: 'Fulano',
                uf: 'SC',
                cidade: 'Araranguá',
                marcaVeiculo: 'Fiat',
                modeloVeiculo: 'Palio',
                corVeiculo: 'Preto',
                placaVeiculo: 'ABC1234',
                paymentMethods: const {PaymentMethod.cash},
                precoPorKm: 2.5,
                anoVeiculo: 2018,
              ),
              routeDistanceService: FakeRouteDistanceService(
                resultadosDistancia: [1000, 2000],
              ),
              reverseGeocodingService: FakeReverseGeocodingService(),
              onSendQuote: (_) async => null,
              onReject: () {},
            ),
          ),
        ),
      );
      await tester.pump();
    }

    Reputation reputacaoDe(List<Receipt> cadeia) => Reputation(
      corridas: cadeia.length,
      avaliacoes: cadeia.where((r) => r.nota != null).length,
      media: 4.0,
      seqProximo: cadeia.length,
      head: cadeia.last.idRecibo,
      recibos: cadeia.reversed.toList(),
    );

    testWidgets('recibos que conferem: média e contagem verificadas', (
      tester,
    ) async {
      final cadeia = signedChain(avaliado: passageiro.publicKey, notas: [5, 3]);
      await montar(tester, solicitacao(reputacaoDe(cadeia)));

      expect(
        find.text('Reputação verificada: 4,00 ★ em 2 recibos'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('reputacao-inconsistente')), findsNothing);
    });

    testWidgets('recibo de assinatura inválida é descartado e sinalizado', (
      tester,
    ) async {
      final cadeia = signedChain(avaliado: passageiro.publicKey, notas: [5, 5]);
      // Assinatura de uma chave que não é a do avaliador: inválida.
      final forjado = cadeia.last.withSignature(
        ReceiptSignature.sign(cadeia.last, newTestIdentity()),
      );
      final rep = reputacaoDe([cadeia.first, forjado]);
      await montar(tester, solicitacao(rep));

      expect(find.text('1 recibo descartado por ser inválido'), findsOneWidget);
      // O head aponta para o recibo descartado: inconsistente.
      expect(find.byKey(const Key('reputacao-inconsistente')), findsOneWidget);
    });

    testWidgets('sem reputação: "sem histórico"', (tester) async {
      await montar(tester, solicitacao(null));
      expect(find.byKey(const Key('reputacao-sem-historico')), findsOneWidget);
    });

    testWidgets('lacuna entre recibos apresentados', (tester) async {
      final avaliador = newTestIdentity();
      final r1 = signedReceipt(
        avaliador: avaliador,
        avaliado: passageiro.publicKey,
        seq: 1,
        guid: fakeGuid(1),
        nota: 5,
      );
      final r4 = signedReceipt(
        avaliador: avaliador,
        avaliado: passageiro.publicKey,
        seq: 4,
        guid: fakeGuid(4),
        nota: 4,
        hashAnterior: fakeGuid(3),
      );
      final rep = Reputation(
        corridas: 5,
        avaliacoes: 5,
        media: 4.5,
        seqProximo: 5,
        head: r4.idRecibo,
        recibos: [r4, r1],
      );
      await montar(tester, solicitacao(rep));

      expect(find.text('2 recibos não apresentados'), findsOneWidget);
    });
  });
}
