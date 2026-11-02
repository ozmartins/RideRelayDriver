import 'dart:async';

import 'package:driver/domain/driver_profile.dart';
import 'package:driver/domain/payment_method.dart';
import 'package:driver/domain/ride_quote.dart';
import 'package:driver/domain/ride_request_received.dart';
import 'package:driver/screens/ride_request_modal.dart';
import 'package:driver/services/reverse_geocoding_service.dart';
import 'package:driver/domain/route_trace.dart';
import 'package:driver/services/route_distance_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

/// Dublê de geocodificação reversa (feature 015): responde por coordenada
/// via [enderecos]; sem entrada, falha. [pendente] segura a resposta.
class FakeReverseGeocodingService implements ReverseGeocodingService {
  FakeReverseGeocodingService({this.enderecos = const {}, this.pendente});

  final Map<LatLng, String> enderecos;
  final Completer<void>? pendente;

  @override
  Future<String> addressOf(LatLng point) async {
    await pendente?.future;
    final endereco = enderecos[point];
    if (endereco == null) throw const ReverseGeocodingFailure('dublê');
    return endereco;
  }
}

/// Dublê em memória: nenhum teste toca o serviço de rota real (Princípio II
/// aplicado por analogia). Cada chamada consome a próxima entrada de
/// [resultadosDistancia] — permite programar resultados diferentes para as
/// duas chamadas que a modal faz (motorista→origem e origem→destino).
/// [duracaoSegundos] é fixa para todas as chamadas bem-sucedidas — só a
/// chamada motorista→origem usa a duração (ETA). [erro] lança em toda
/// chamada; [indicesComErro] lança só nas chamadas naquelas posições
/// (0-indexado pela ordem de chegada) — usado para simular falha em só uma
/// das duas chamadas.
class FakeRouteDistanceService implements RouteDistanceService {
  FakeRouteDistanceService({
    List<double>? resultadosDistancia,
    this.erro,
    Set<int>? indicesComErro,
    this.duracaoSegundos = 360,
  }) : _resultadosDistancia = [...?resultadosDistancia],
       _indicesComErro = indicesComErro ?? const {};

  final List<double> _resultadosDistancia;
  Object? erro;
  final Set<int> _indicesComErro;
  double duracaoSegundos;
  final chamadas = <({LatLng origin, LatLng destination})>[];

  @override
  Future<RouteEstimate> estimate({
    required LatLng origin,
    required LatLng destination,
  }) async {
    final indice = chamadas.length;
    chamadas.add((origin: origin, destination: destination));
    final erroAtual = erro;
    if (erroAtual != null || _indicesComErro.contains(indice)) {
      throw erroAtual ?? Exception('falha simulada na chamada $indice');
    }
    return RouteEstimate(
      distanceMeters: _resultadosDistancia.removeAt(0),
      durationSeconds: duracaoSegundos,
    );
  }

  /// A modal não traça rota (feature 016 é da tela do mapa).
  @override
  Future<RouteTrace> trace({
    required LatLng origin,
    required LatLng destination,
  }) => throw UnimplementedError('a modal não usa trace()');
}

const _origem = LatLng(-28.9298, -49.4753);
const _destino = LatLng(-28.6721, -49.3671);
const _posicaoMotorista = LatLng(-28.9350, -49.4800);

RideRequestReceived _solicitacao() => const RideRequestReceived(
  requestId: 'id-solicitacao',
  passengerPubkey: 'pubkey-do-passageiro',
  origin: _origem,
  destination: _destino,
  payment: 'pix',
);

DriverProfile _perfilDeTeste({double precoPorKm = 2.5}) => DriverProfile(
  nome: 'Fulano da Silva',
  uf: 'SC',
  cidade: 'Araranguá',
  marcaVeiculo: 'Fiat',
  modeloVeiculo: 'Palio',
  corVeiculo: 'Preto',
  placaVeiculo: 'ABC1234',
  paymentMethods: const {PaymentMethod.cash},
  precoPorKm: precoPorKm,
  anoVeiculo: 2018,
);

Future<void> _montar(
  WidgetTester tester, {
  required RouteDistanceService routeDistanceService,
  ReverseGeocodingService? reverseGeocodingService,
  DriverProfile? driverProfile,
  Future<String?> Function(RideQuote)? onSendQuote,
  VoidCallback? onReject,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: RideRequestModal(
          request: _solicitacao(),
          driverPosition: _posicaoMotorista,
          driverProfile: driverProfile ?? _perfilDeTeste(),
          routeDistanceService: routeDistanceService,
          reverseGeocodingService:
              reverseGeocodingService ?? FakeReverseGeocodingService(),
          onSendQuote: onSendQuote ?? (_) async => null,
          onReject: onReject ?? () {},
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('RideRequestModal — dados e distâncias (US1)', () {
    testWidgets(
      'exibe origem, destino, as duas distâncias e o total calculado com o '
      'preço padrão',
      (tester) async {
        final servico = FakeRouteDistanceService(
          resultadosDistancia: [1200, 15300],
        );
        await _montar(tester, routeDistanceService: servico);
        await tester.pump();

        expect(servico.chamadas, hasLength(2));
        expect(servico.chamadas.first, (
          origin: _posicaoMotorista,
          destination: _origem,
        ));
        expect(servico.chamadas.last, (origin: _origem, destination: _destino));

        expect(find.text('1.2 km'), findsOneWidget);
        expect(find.text('15.3 km'), findsOneWidget);
        // total = 2.5 * 15.3 = 38.25
        expect(find.text('R\$ 38.25'), findsOneWidget);
      },
    );

    testWidgets(
      'editar o preço recalcula o total imediatamente, sem nova chamada de '
      'rota',
      (tester) async {
        final servico = FakeRouteDistanceService(
          resultadosDistancia: [1200, 10000],
        );
        await _montar(tester, routeDistanceService: servico);
        await tester.pump();
        expect(find.text('R\$ 25.00'), findsOneWidget);

        await tester.enterText(
          find.widgetWithText(
            TextField,
            'Preço por quilômetro (só para esta corrida)',
          ),
          '3,00',
        );
        await tester.pump();

        expect(find.text('R\$ 30.00'), findsOneWidget);
        expect(
          servico.chamadas,
          hasLength(2),
          reason: 'nenhuma chamada nova ao editar o preço',
        );
      },
    );

    testWidgets(
      'falha em uma das distâncias indica "não calculada", sem exceção, e '
      'mantém a modal utilizável',
      (tester) async {
        final servico = FakeRouteDistanceService(erro: Exception('sem rede'));
        await _montar(tester, routeDistanceService: servico);
        await tester.pump();

        expect(find.text('não calculada'), findsNWidgets(2));
        expect(find.text('0'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'editar o preço não altera nada fora da modal (FR-007 — não persiste '
      'no cadastro, verificado pela ausência de qualquer callback de '
      'persistência)',
      (tester) async {
        final servico = FakeRouteDistanceService(
          resultadosDistancia: [1000, 10000],
        );
        var onSendQuoteChamado = false;
        var onRejectChamado = false;
        await _montar(
          tester,
          routeDistanceService: servico,
          onSendQuote: (_) async {
            onSendQuoteChamado = true;
            return null;
          },
          onReject: () => onRejectChamado = true,
        );
        await tester.pump();

        await tester.enterText(
          find.widgetWithText(
            TextField,
            'Preço por quilômetro (só para esta corrida)',
          ),
          '9,90',
        );
        await tester.pump();

        expect(
          onSendQuoteChamado,
          isFalse,
          reason:
              'editar o preço não deve, por si só, enviar nem persistir nada',
        );
        expect(onRejectChamado, isFalse);
      },
    );
  });

  group('RideRequestModal — enviar orçamento (US2)', () {
    testWidgets('preço válido chama onSendQuote com o RideQuote correto', (
      tester,
    ) async {
      final servico = FakeRouteDistanceService(
        resultadosDistancia: [1000, 10000],
      );
      RideQuote? recebido;
      await _montar(
        tester,
        routeDistanceService: servico,
        onSendQuote: (quote) async {
          recebido = quote;
          return null;
        },
      );
      await tester.pump();

      await tester.tap(find.widgetWithText(FilledButton, 'Enviar orçamento'));
      await tester.pump();

      expect(recebido, isNotNull);
      expect(recebido!.requestId, 'id-solicitacao');
      expect(recebido!.pricePerKm, 2.5);
      expect(recebido!.total, 25.0);
      expect(recebido!.driverName, 'Fulano da Silva');
      expect(recebido!.carBrand, 'Fiat');
      expect(recebido!.carModel, 'Palio');
      expect(recebido!.carYear, 2018);
      // duracaoSegundos padrão do dublê é 360s = 6min, para a chamada
      // motorista→origem (feature 009, D1 de research.md).
      expect(recebido!.etaMinutes, 6);
    });

    testWidgets(
      'quando só a distância motorista→origem falha, o RideQuote enviado '
      'não tem etaMinutes (FR-003 de '
      'specs/009-detalhes-do-orcamento/spec.md)',
      (tester) async {
        // Chamada 0 é motorista→origem (falha); chamada 1 é origem→destino
        // (bem-sucedida, com 10000 m) — a modal continua utilizável e o
        // total é calculável mesmo sem a distância até a origem.
        final servico = FakeRouteDistanceService(
          resultadosDistancia: [10000],
          indicesComErro: {0},
        );
        RideQuote? recebido;
        await _montar(
          tester,
          routeDistanceService: servico,
          onSendQuote: (quote) async {
            recebido = quote;
            return null;
          },
        );
        await tester.pump();

        await tester.tap(find.widgetWithText(FilledButton, 'Enviar orçamento'));
        await tester.pump();

        expect(recebido, isNotNull);
        expect(recebido!.etaMinutes, isNull);
      },
    );

    testWidgets(
      'preço vazio, zero, negativo ou mal formatado desabilita "Enviar '
      'orçamento"',
      (tester) async {
        final servico = FakeRouteDistanceService(
          resultadosDistancia: [
            1000,
            10000,
            1000,
            10000,
            1000,
            10000,
            1000,
            10000,
          ],
        );
        await _montar(tester, routeDistanceService: servico);
        await tester.pump();

        for (final invalido in ['', '0', '-1', '2,555']) {
          await tester.enterText(
            find.widgetWithText(
              TextField,
              'Preço por quilômetro (só para esta corrida)',
            ),
            invalido,
          );
          await tester.pump();

          final botao = tester.widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Enviar orçamento'),
          );
          expect(
            botao.onPressed,
            isNull,
            reason: '"$invalido" deveria desabilitar o envio',
          );
        }
      },
    );

    testWidgets(
      'sem relay conectado, onSendQuote devolve mensagem e a modal continua '
      'aberta com o preço preservado',
      (tester) async {
        final servico = FakeRouteDistanceService(
          resultadosDistancia: [1000, 10000],
        );
        await _montar(
          tester,
          routeDistanceService: servico,
          onSendQuote: (_) async => 'Nenhum relay conectado.',
        );
        await tester.pump();

        await tester.tap(find.widgetWithText(FilledButton, 'Enviar orçamento'));
        await tester.pump();

        expect(find.text('Nenhum relay conectado.'), findsOneWidget);
        expect(
          find.widgetWithText(
            TextField,
            'Preço por quilômetro (só para esta corrida)',
          ),
          findsOneWidget,
        );
      },
    );
  });

  group('RideRequestModal — recusar corrida (US3)', () {
    testWidgets(
      'tocar em "Recusar corrida" chama onReject e não chama onSendQuote',
      (tester) async {
        final servico = FakeRouteDistanceService(
          resultadosDistancia: [1000, 10000],
        );
        var recusado = false;
        var enviado = false;
        await _montar(
          tester,
          routeDistanceService: servico,
          onReject: () => recusado = true,
          onSendQuote: (_) async {
            enviado = true;
            return null;
          },
        );
        await tester.pump();

        await tester.tap(find.widgetWithText(TextButton, 'Recusar corrida'));
        await tester.pump();

        expect(recusado, isTrue);
        expect(enviado, isFalse);
      },
    );
  });

  group('endereço legível (feature 015)', () {
    testWidgets('mostra o endereço de origem e de destino', (tester) async {
      await _montar(
        tester,
        routeDistanceService: FakeRouteDistanceService(
          resultadosDistancia: [500, 8000],
        ),
        reverseGeocodingService: FakeReverseGeocodingService(
          enderecos: {
            _origem: 'Rua Central, 10, Araranguá',
            _destino: 'Avenida Beira Mar, Balneário Arroio do Silva',
          },
        ),
      );
      await tester.pump();

      expect(find.text('Rua Central, 10, Araranguá'), findsOneWidget);
      expect(
        find.text('Avenida Beira Mar, Balneário Arroio do Silva'),
        findsOneWidget,
      );
      expect(find.textContaining('-28.9298'), findsNothing);
    });

    testWidgets('indica a busca enquanto o endereço não chega', (tester) async {
      await _montar(
        tester,
        routeDistanceService: FakeRouteDistanceService(
          resultadosDistancia: [500, 8000],
        ),
        reverseGeocodingService: FakeReverseGeocodingService(
          pendente: Completer<void>(),
        ),
      );

      expect(find.text('buscando endereço…'), findsNWidgets(2));
    });

    testWidgets('volta a mostrar latitude e longitude se a busca falhar', (
      tester,
    ) async {
      await _montar(
        tester,
        routeDistanceService: FakeRouteDistanceService(
          resultadosDistancia: [500, 8000],
        ),
      );
      await tester.pump();

      expect(find.text('-28.9298, -49.4753'), findsOneWidget);
      expect(find.text('-28.6721, -49.3671'), findsOneWidget);
    });
  });
}
