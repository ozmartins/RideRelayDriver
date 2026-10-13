import 'dart:async';

import 'package:driver/domain/driver_position.dart';
import 'package:driver/domain/driver_profile.dart';
import 'package:driver/domain/nostr_event.dart';
import 'package:driver/domain/payment_method.dart';
import 'package:driver/main.dart';
import 'package:driver/services/cadastro_store.dart';
import 'package:driver/services/key_store.dart';
import 'package:driver/services/key_value_store.dart';
import 'package:driver/services/location_service.dart';
import 'package:driver/services/relay_gateway.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_cadastro_store.dart';

/// Dublês mínimos: nenhum teste deste arquivo toca plugin de plataforma,
/// SQLite real ou rede (decisão D5 da feature 002, D1 das features 003/004).
class _FakeLocationService implements LocationService {
  @override
  Future<void> ensurePermission() async {}

  @override
  Stream<DriverPosition> get positions => const Stream.empty();
}

class _FakeKeyStore implements KeyStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

class _FakeKeyValueStore implements KeyValueStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class _FakeGateway implements RelayGateway {
  final _events = StreamController<IncomingEvent>.broadcast();

  @override
  Stream<String> get connectionLost => const Stream.empty();

  @override
  Future<void> connect(String relayUrl) async {}

  @override
  Future<void> disconnect(String relayUrl) async {}

  @override
  Future<void> probe(String relayUrl) async {}

  @override
  Stream<IncomingEvent> subscribe({required List<int> kinds}) => _events.stream;

  @override
  Stream<PublishOutcome> publish(
    NostrEvent event, {
    required Map<String, dynamic> payload,
  }) => const Stream.empty();
}

const _perfilExistente = DriverProfile(
  nome: 'Fulano da Silva',
  uf: 'SC',
  cidade: 'Araranguá',
  marcaVeiculo: 'Fiat',
  modeloVeiculo: 'Palio',
  corVeiculo: 'Preto',
  placaVeiculo: 'ABC1234',
  paymentMethods: {PaymentMethod.cash},
  precoPorKm: 2.5,
  anoVeiculo: 2018,
);

Widget _app(CadastroStore cadastroStore) => CaronasDriverApp(
  keyStore: _FakeKeyStore(),
  keyValueStore: _FakeKeyValueStore(),
  gateway: _FakeGateway(),
  cadastroStore: cadastroStore,
  locationService: _FakeLocationService(),
);

void main() {
  testWidgets('a barra de navegação tem dois destinos, Mapa e Mais', (
    tester,
  ) async {
    await tester.pumpWidget(_app(FakeCadastroStore(_perfilExistente)));
    await tester.pumpAndSettle();

    final barra = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(barra.destinations, hasLength(2));
    for (final rotulo in ['Mapa', 'Mais']) {
      expect(find.text(rotulo), findsOneWidget);
    }
    for (final rotulo in ['Relays', 'Identidade', 'Cadastro', 'Eventos']) {
      expect(find.text(rotulo), findsNothing);
    }
  });

  testWidgets('"Mais" lista Cadastro, Relays e Identidade, e cada um abre '
      'com botão de voltar', (tester) async {
    await tester.pumpWidget(_app(FakeCadastroStore(_perfilExistente)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Mais'));
    await tester.pumpAndSettle();
    for (final item in ['Cadastro', 'Relays', 'Minha identidade']) {
      expect(find.text(item), findsOneWidget);
    }

    await tester.tap(find.text('Relays'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('botao-reconectar')), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Minha identidade'), findsOneWidget);

    await tester.tap(find.text('Cadastro'));
    await tester.pumpAndSettle();
    expect(find.text('Editar cadastro'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Minha identidade'), findsOneWidget);
  });

  testWidgets(
    'sem cadastro salvo, o formulário aparece antes de qualquer outra tela '
    '(US1, FR-001)',
    (tester) async {
      await tester.pumpWidget(_app(FakeCadastroStore()));
      await tester.pumpAndSettle();

      expect(find.text('Cadastro do motorista'), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    },
  );

  testWidgets('com cadastro já salvo, a tela principal aparece direto, sem o '
      'formulário (US2, SC-002)', (tester) async {
    await tester.pumpWidget(_app(FakeCadastroStore(_perfilExistente)));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Cadastro do motorista'), findsNothing);
  });

  Future<void> tocarContinuar(WidgetTester tester) async {
    await tester.ensureVisible(find.byType(FilledButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
  }

  Future<void> escolher(WidgetTester tester, int indice, String texto) async {
    await tester.tap(find.byType(DropdownButtonFormField<String>).at(indice));
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.text(texto),
      find.byType(Scrollable).last,
      const Offset(0, -60),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(texto).last);
    await tester.pumpAndSettle();
  }

  Future<void> etapa1(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField).at(0), 'Fulano da Silva');
    await escolher(tester, 0, 'SC — Santa Catarina');
    await escolher(tester, 1, 'Araranguá');
    await tocarContinuar(tester);
  }

  Future<void> etapa2(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField).at(0), 'Fiat');
    await tester.enterText(find.byType(TextField).at(1), 'Palio');
    await tester.enterText(find.byType(TextField).at(2), '2018');
    await tester.enterText(find.byType(TextField).at(3), 'Preto');
    await tester.enterText(find.byType(TextField).at(4), 'ABC1234');
    await tester.pumpAndSettle();
    await tocarContinuar(tester);
  }

  Future<void> etapa3(WidgetTester tester) async {
    await tester.ensureVisible(
      find.widgetWithText(CheckboxListTile, 'Dinheiro'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Dinheiro'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '2,50');
    await tester.pumpAndSettle();
    await tocarContinuar(tester);
  }

  testWidgets('concluir as três etapas leva à tela principal, sem reiniciar o '
      'aplicativo (US1, FR-007)', (tester) async {
    final store = FakeCadastroStore();
    await tester.pumpWidget(_app(store));
    await tester.pumpAndSettle();
    expect(find.text('Cadastro do motorista'), findsOneWidget);

    await etapa1(tester);
    expect(find.text('Dados do veículo'), findsOneWidget);
    await etapa2(tester);
    expect(find.text('Financeiro'), findsOneWidget);
    // Ainda no wizard: o cadastro só está completo após a etapa 3.
    expect(find.text('Cadastro do motorista'), findsOneWidget);
    await etapa3(tester);

    expect(store.saveCount, 3);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Cadastro do motorista'), findsNothing);
  });

  testWidgets(
    'fechar o app depois de salvar a etapa 1 reabre na etapa 2; depois de '
    'salvar a etapa 2, reabre na etapa 3',
    (tester) async {
      final store = FakeCadastroStore();
      await tester.pumpWidget(_app(store));
      await tester.pumpAndSettle();
      await etapa1(tester);

      // "Fechar o aplicativo": nova árvore, mesmo store (o "disco").
      await tester.pumpWidget(Container());
      await tester.pumpWidget(_app(store));
      await tester.pumpAndSettle();
      expect(find.text('Etapa 2 de 3'), findsOneWidget);
      expect(find.text('Dados do veículo'), findsOneWidget);

      await etapa2(tester);
      await tester.pumpWidget(Container());
      await tester.pumpWidget(_app(store));
      await tester.pumpAndSettle();
      expect(find.text('Etapa 3 de 3'), findsOneWidget);
      expect(find.text('Concluir cadastro'), findsOneWidget);

      await etapa3(tester);
      expect(find.byType(NavigationBar), findsOneWidget);
    },
  );

  testWidgets(
    'corrigir a cor do veículo pela aba Cadastro persiste, e uma nova '
    'abertura do aplicativo mostra o valor corrigido (US3, SC-005)',
    (tester) async {
      final store = FakeCadastroStore(_perfilExistente);
      await tester.pumpWidget(_app(store));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Mais'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cadastro'));
      await tester.pumpAndSettle();
      expect(find.text('Editar cadastro'), findsOneWidget);

      // Etapa 1 (já válida) → etapa 2, onde está a cor (4º TextField).
      await tocarContinuar(tester);
      await tester.enterText(find.byType(TextField).at(3), 'Branco');
      await tester.pumpAndSettle();
      await tocarContinuar(tester);

      expect(store.saveCount, 2);

      // "Reabrir o aplicativo": nova árvore de widgets, mesmo CadastroStore
      // (é ele quem representa o disco persistido entre execuções).
      await tester.pumpWidget(Container());
      await tester.pumpAndSettle();
      await tester.pumpWidget(_app(store));
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);
      await tester.tap(find.text('Mais'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cadastro'));
      await tester.pumpAndSettle();
      await tocarContinuar(tester);

      final campoCor = tester.widget<TextField>(find.byType(TextField).at(3));
      expect(campoCor.controller?.text, 'Branco');
    },
  );

  testWidgets('concluir a edição do cadastro volta à tela Mais, com a '
      'confirmação, e reabrir mostra a etapa 1', (tester) async {
    final store = FakeCadastroStore(_perfilExistente);
    await tester.pumpWidget(_app(store));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Mais'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cadastro'));
    await tester.pumpAndSettle();
    await tocarContinuar(tester);
    await tocarContinuar(tester);
    expect(find.text('Concluir cadastro'), findsOneWidget);
    await tocarContinuar(tester);

    expect(store.saveCount, 3);
    expect(find.text('Editar cadastro'), findsNothing);
    expect(find.text('Minha identidade'), findsOneWidget);
    expect(find.text('Cadastro salvo'), findsOneWidget);

    await tester.tap(find.text('Cadastro'));
    await tester.pumpAndSettle();
    expect(find.text('Etapa 1 de 3'), findsOneWidget);
  });
}
