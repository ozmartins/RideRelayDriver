import 'package:driver/domain/cadastro_progress.dart';
import 'package:driver/domain/driver_profile.dart';
import 'package:driver/domain/payment_method.dart';
import 'package:driver/screens/cadastro_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _selecionar(
  WidgetTester tester,
  int indiceDropdown,
  String texto,
) async {
  await tester.ensureVisible(
    find.byType(DropdownButtonFormField<String>).at(indiceDropdown),
  );
  await tester.pumpAndSettle();
  await tester.tap(
    find.byType(DropdownButtonFormField<String>).at(indiceDropdown),
  );
  await tester.pumpAndSettle();
  // A lista de opções é virtualizada (Scrollable): com 27 UFs, ou até
  // milhares de municípios, o item procurado pode não estar construído
  // ainda — é preciso rolar o menu aberto até ele aparecer.
  await tester.dragUntilVisible(
    find.text(texto),
    find.byType(Scrollable).last,
    const Offset(0, -60),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(texto).last);
  await tester.pumpAndSettle();
}

const _perfil = DriverProfile(
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

/// Grava o que a tela entrega em cada etapa e devolve `null` (sucesso).
class _Gravacoes {
  DriverPersonalData? pessoal;
  DriverVehicleData? veiculo;
  DriverFinancialData? financeiro;
  int chamadas = 0;

  Future<void> monta(
    WidgetTester tester, {
    CadastroProgress? initial,
    String? erro,
    bool Function()? motoristaOnline,
  }) => tester.pumpWidget(
    MaterialApp(
      home: CadastroScreen(
        initial: initial,
        motoristaOnline: motoristaOnline,
        onSavePersonal: (d) async {
          chamadas++;
          pessoal = d;
          return erro;
        },
        onSaveVehicle: (d) async {
          chamadas++;
          veiculo = d;
          return erro;
        },
        onSaveFinancial: (d) async {
          chamadas++;
          financeiro = d;
          return erro;
        },
      ),
    ),
  );
}

// Etapa 1: nome (TextField 0), UF e cidade (dropdowns 0 e 1).
Future<void> _preencherEtapa1(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField).at(0), 'Fulano da Silva');
  await _selecionar(tester, 0, 'SC — Santa Catarina');
  await _selecionar(tester, 1, 'Araranguá');
  await tester.pumpAndSettle();
}

// Etapa 2: marca 0, modelo 1, ano 2, cor 3, placa 4.
Future<void> _preencherEtapa2(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField).at(0), 'Fiat');
  await tester.enterText(find.byType(TextField).at(1), 'Palio');
  await tester.enterText(find.byType(TextField).at(2), '2018');
  await tester.enterText(find.byType(TextField).at(3), 'Preto');
  await tester.enterText(find.byType(TextField).at(4), 'ABC1234');
  await tester.pumpAndSettle();
}

// Etapa 3: formas de pagamento (checkboxes) e preço (TextField 0).
Future<void> _preencherEtapa3(WidgetTester tester) async {
  await tester.ensureVisible(find.widgetWithText(CheckboxListTile, 'Dinheiro'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(CheckboxListTile, 'Dinheiro'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).at(0), '2,50');
  await tester.pumpAndSettle();
}

bool _botaoHabilitado(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byType(FilledButton)).onPressed != null;

Future<void> _tocarBotao(WidgetTester tester) async {
  await tester.ensureVisible(find.byType(FilledButton));
  await tester.pumpAndSettle();
  await tester.tap(find.byType(FilledButton), warnIfMissed: false);
  await tester.pumpAndSettle();
}

void main() {
  group('CadastroScreen — wizard em três etapas', () {
    testWidgets('abre na etapa 1, com o botão "Salvar e continuar"', (
      tester,
    ) async {
      await _Gravacoes().monta(tester);

      expect(find.text('Dados do motorista'), findsOneWidget);
      expect(find.text('Etapa 1 de 3'), findsOneWidget);
      expect(find.text('Salvar e continuar'), findsOneWidget);
      expect(find.text('Concluir cadastro'), findsNothing);
    });

    testWidgets('percorre as três etapas, gravando cada uma ao avançar', (
      tester,
    ) async {
      final g = _Gravacoes();
      await g.monta(tester);

      await _preencherEtapa1(tester);
      await _tocarBotao(tester);
      expect(g.pessoal, isNotNull);
      expect(g.pessoal!.nome, 'Fulano da Silva');
      expect(g.pessoal!.uf, 'SC');
      expect(g.pessoal!.cidade, 'Araranguá');
      expect(g.veiculo, isNull);
      expect(find.text('Dados do veículo'), findsOneWidget);
      expect(find.text('Salvar e continuar'), findsOneWidget);

      await _preencherEtapa2(tester);
      await _tocarBotao(tester);
      expect(g.veiculo!.placa, 'ABC1234');
      expect(g.veiculo!.ano, 2018);
      expect(g.financeiro, isNull);
      expect(find.text('Financeiro'), findsOneWidget);
      expect(find.text('Concluir cadastro'), findsOneWidget);
      expect(find.text('Salvar e continuar'), findsNothing);

      await _preencherEtapa3(tester);
      await _tocarBotao(tester);
      expect(g.financeiro!.paymentMethods, {PaymentMethod.cash});
      expect(g.financeiro!.precoPorKm, 2.5);
      expect(g.chamadas, 3);
    });

    testWidgets('etapa 1 inválida: botão desabilitado e nada é gravado', (
      tester,
    ) async {
      final g = _Gravacoes();
      await g.monta(tester);

      await _preencherEtapa1(tester);
      expect(_botaoHabilitado(tester), isTrue);
      await tester.enterText(find.byType(TextField).at(0), '');
      await tester.pumpAndSettle();

      expect(_botaoHabilitado(tester), isFalse);
      await _tocarBotao(tester);
      expect(g.chamadas, 0);
    });

    testWidgets('trocar a UF limpa a cidade selecionada (FR-009)', (
      tester,
    ) async {
      await _Gravacoes().monta(tester);

      await _preencherEtapa1(tester);
      expect(_botaoHabilitado(tester), isTrue);
      await _selecionar(tester, 0, 'RS — Rio Grande do Sul');

      expect(_botaoHabilitado(tester), isFalse);
    });

    testWidgets('etapa 2 com placa inválida não avança nem grava', (
      tester,
    ) async {
      final g = _Gravacoes();
      await g.monta(
        tester,
        initial: CadastroProgress(
          personal: CadastroProgress.fromProfile(_perfil).personal,
        ),
      );
      await _preencherEtapa2(tester);
      await tester.enterText(find.byType(TextField).at(4), 'INVALIDA');
      await tester.pumpAndSettle();

      expect(_botaoHabilitado(tester), isFalse);
      await _tocarBotao(tester);
      expect(g.chamadas, 0);
    });

    testWidgets('etapa 2 com ano fora da faixa desabilita o botão', (
      tester,
    ) async {
      await _Gravacoes().monta(
        tester,
        initial: CadastroProgress(
          personal: CadastroProgress.fromProfile(_perfil).personal,
        ),
      );
      await _preencherEtapa2(tester);

      for (final invalido in [
        '',
        '18',
        'abcd',
        '1899',
        '${DateTime.now().year + 2}',
      ]) {
        await tester.enterText(find.byType(TextField).at(2), invalido);
        await tester.pumpAndSettle();
        expect(
          _botaoHabilitado(tester),
          isFalse,
          reason: '"$invalido" deveria desabilitar o botão',
        );
      }
    });

    testWidgets('etapa 3 sem forma de pagamento desabilita o botão', (
      tester,
    ) async {
      final g = _Gravacoes();
      final base = CadastroProgress.fromProfile(_perfil);
      await g.monta(
        tester,
        initial: CadastroProgress(
          personal: base.personal,
          vehicle: base.vehicle,
        ),
      );
      await tester.enterText(find.byType(TextField).at(0), '2,50');
      await tester.pumpAndSettle();

      expect(_botaoHabilitado(tester), isFalse);
      expect(
        find.text('Marque ao menos uma forma de pagamento'),
        findsOneWidget,
      );
      await tester.ensureVisible(
        find.widgetWithText(CheckboxListTile, 'Dinheiro'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Dinheiro'));
      await tester.ensureVisible(find.widgetWithText(CheckboxListTile, 'PIX'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CheckboxListTile, 'PIX'));
      await tester.pumpAndSettle();
      expect(_botaoHabilitado(tester), isTrue);
      await _tocarBotao(tester);

      expect(g.financeiro!.paymentMethods, {
        PaymentMethod.cash,
        PaymentMethod.pix,
      });
    });

    testWidgets('preço vazio, zero, negativo ou com três casas desabilita', (
      tester,
    ) async {
      final base = CadastroProgress.fromProfile(_perfil);
      await _Gravacoes().monta(
        tester,
        initial: CadastroProgress(
          personal: base.personal,
          vehicle: base.vehicle,
        ),
      );
      await tester.ensureVisible(
        find.widgetWithText(CheckboxListTile, 'Dinheiro'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Dinheiro'));
      await tester.pumpAndSettle();
      expect(find.textContaining('alterá-lo em cada corrida'), findsOneWidget);

      for (final invalido in ['', '0', '-1', '2,555']) {
        await tester.enterText(find.byType(TextField).at(0), invalido);
        await tester.pumpAndSettle();
        expect(
          _botaoHabilitado(tester),
          isFalse,
          reason: '"$invalido" deveria desabilitar o botão',
        );
      }
    });

    testWidgets('erro de gravação é exibido e a etapa não avança', (
      tester,
    ) async {
      final g = _Gravacoes();
      await g.monta(tester, erro: 'Não foi possível salvar o cadastro: x');

      await _preencherEtapa1(tester);
      await _tocarBotao(tester);

      expect(find.textContaining('Não foi possível salvar'), findsOneWidget);
      expect(find.text('Dados do motorista'), findsOneWidget);
    });

    testWidgets('"Voltar" reexibe a etapa anterior com os dados preenchidos', (
      tester,
    ) async {
      await _Gravacoes().monta(tester);
      await _preencherEtapa1(tester);
      await _tocarBotao(tester);

      await tester.tap(find.text('Voltar'));
      await tester.pumpAndSettle();

      expect(find.text('Dados do motorista'), findsOneWidget);
      expect(find.text('Fulano da Silva'), findsOneWidget);
    });
  });

  group('CadastroScreen — identidade visual na etapa 2', () {
    testWidgets(
      'dois segmentos de progresso em destaque e campos preenchidos',
      (tester) async {
        final base = CadastroProgress.fromProfile(_perfil);
        await _Gravacoes().monta(
          tester,
          initial: CadastroProgress(personal: base.personal),
        );

        final destaque = find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).color == const Color(0xFFC8F169),
        );
        expect(destaque, findsNWidgets(2));
        final campos = tester
            .widgetList<InputDecorator>(find.byType(InputDecorator))
            .toList();
        expect(campos, hasLength(5));
        for (final c in campos) {
          expect(c.decoration.filled, isTrue);
          expect(
            c.decoration.floatingLabelBehavior,
            FloatingLabelBehavior.always,
          );
        }
      },
    );
  });

  group('CadastroScreen — identidade visual na etapa 3', () {
    testWidgets('três segmentos em destaque e campo de preço preenchido', (
      tester,
    ) async {
      final base = CadastroProgress.fromProfile(_perfil);
      await _Gravacoes().monta(
        tester,
        initial: CadastroProgress(
          personal: base.personal,
          vehicle: base.vehicle,
        ),
      );

      final destaque = find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).color == const Color(0xFFC8F169),
      );
      expect(destaque, findsNWidgets(3));
      final campo = tester.widget<InputDecorator>(find.byType(InputDecorator));
      expect(campo.decoration.filled, isTrue);
      expect(
        campo.decoration.floatingLabelBehavior,
        FloatingLabelBehavior.always,
      );
      expect(find.text('Concluir cadastro'), findsOneWidget);
    });
  });

  group('CadastroScreen — retomada depois de fechar o app', () {
    testWidgets('com a etapa 1 salva, abre na etapa 2', (tester) async {
      final base = CadastroProgress.fromProfile(_perfil);
      await _Gravacoes().monta(
        tester,
        initial: CadastroProgress(personal: base.personal),
      );

      expect(find.text('Dados do veículo'), findsOneWidget);
      expect(find.text('Etapa 2 de 3'), findsOneWidget);
      expect(find.text('Salvar e continuar'), findsOneWidget);
    });

    testWidgets('com as etapas 1 e 2 salvas, abre na etapa 3', (tester) async {
      final base = CadastroProgress.fromProfile(_perfil);
      await _Gravacoes().monta(
        tester,
        initial: CadastroProgress(
          personal: base.personal,
          vehicle: base.vehicle,
        ),
      );

      expect(find.text('Financeiro'), findsOneWidget);
      expect(find.text('Etapa 3 de 3'), findsOneWidget);
      expect(find.text('Concluir cadastro'), findsOneWidget);
    });
  });

  group('CadastroScreen — edição de um cadastro completo', () {
    testWidgets(
      'abre na etapa 1 pré-preenchida, e a etapa 2 grava a alteração',
      (tester) async {
        final g = _Gravacoes();
        await g.monta(tester, initial: CadastroProgress.fromProfile(_perfil));

        expect(find.text('Editar cadastro'), findsOneWidget);
        expect(find.text('Dados do motorista'), findsOneWidget);
        expect(find.text('Fulano da Silva'), findsOneWidget);
        expect(_botaoHabilitado(tester), isTrue);

        await _tocarBotao(tester);
        await tester.enterText(find.byType(TextField).at(3), 'Branco');
        await tester.pumpAndSettle();
        await _tocarBotao(tester);

        expect(g.veiculo!.cor, 'Branco');
      },
    );

    testWidgets('pré-preenche preço e formas de pagamento na etapa 3', (
      tester,
    ) async {
      final base = CadastroProgress.fromProfile(_perfil);
      await _Gravacoes().monta(
        tester,
        initial: CadastroProgress(
          personal: base.personal,
          vehicle: base.vehicle,
          financial: base.financial,
        ),
      );
      await _tocarBotao(tester);
      await _tocarBotao(tester);

      expect(find.text('2,50'), findsOneWidget);
      final dinheiro = tester.widget<CheckboxListTile>(
        find.widgetWithText(CheckboxListTile, 'Dinheiro'),
      );
      expect(dinheiro.value, isTrue);
    });

    testWidgets('concluir na edição confirma e volta à etapa 1', (
      tester,
    ) async {
      final g = _Gravacoes();
      await g.monta(tester, initial: CadastroProgress.fromProfile(_perfil));
      await _tocarBotao(tester);
      await _tocarBotao(tester);
      await tester.enterText(find.byType(TextField).at(0), '3,00');
      await tester.pumpAndSettle();
      await _tocarBotao(tester);

      expect(g.financeiro!.precoPorKm, 3.0);
      expect(find.text('Cadastro salvo'), findsOneWidget);
      expect(find.text('Dados do motorista'), findsOneWidget);
    });
  });
  group('CadastroScreen — raio de atendimento (feature 027, US2)', () {
    const rotulo = 'Raio de atendimento (km)';
    const erroDoRaio = 'Informe um número inteiro de 1 a 100 km';
    // Etapa 1: nome (TextField 0) e raio (TextField 1).
    Finder campoRaio() => find.byType(TextField).at(1);

    testWidgets('a etapa 1 mostra o campo, já preenchido com 10', (
      tester,
    ) async {
      await _Gravacoes().monta(tester);

      expect(find.text(rotulo), findsOneWidget);
      expect(
        tester.widget<TextField>(campoRaio()).controller!.text,
        '$kRaioPadraoKm',
      );
    });

    testWidgets(
      'vazio, 0, 101, texto e decimal impedem avançar, com a mensagem dos limites',
      (tester) async {
        final g = _Gravacoes();
        await g.monta(tester);
        await _preencherEtapa1(tester);
        expect(_botaoHabilitado(tester), isTrue);

        for (final texto in ['', '0', '101', 'abc', '2,5', '-3']) {
          await tester.enterText(campoRaio(), texto);
          await tester.pumpAndSettle();

          expect(_botaoHabilitado(tester), isFalse, reason: "'$texto'");
          expect(
            find.text(erroDoRaio),
            texto.isEmpty ? findsNothing : findsOneWidget,
            reason: "'$texto'",
          );
        }
        expect(g.chamadas, 0);
      },
    );

    for (final valor in [1, 100]) {
      testWidgets('$valor passa, e o valor vai em DriverPersonalData', (
        tester,
      ) async {
        final g = _Gravacoes();
        await g.monta(tester);
        await _preencherEtapa1(tester);

        await tester.enterText(campoRaio(), '$valor');
        await tester.pumpAndSettle();
        expect(_botaoHabilitado(tester), isTrue);
        await _tocarBotao(tester);

        expect(g.pessoal!.raioAtendimentoKm, valor);
      });
    }

    testWidgets('o raio com espaços nas pontas é aceito', (tester) async {
      final g = _Gravacoes();
      await g.monta(tester);
      await _preencherEtapa1(tester);

      await tester.enterText(campoRaio(), ' 15 ');
      await tester.pumpAndSettle();
      await _tocarBotao(tester);

      expect(g.pessoal!.raioAtendimentoKm, 15);
    });

    testWidgets('editando, o campo traz o raio salvo', (tester) async {
      await _Gravacoes().monta(
        tester,
        initial: CadastroProgress.fromProfile(
          _perfil.copyWith(raioAtendimentoKm: 25),
        ),
      );

      expect(tester.widget<TextField>(campoRaio()).controller!.text, '25');
    });

    testWidgets('editar o nome não zera o raio salvo', (tester) async {
      final g = _Gravacoes();
      await g.monta(
        tester,
        initial: CadastroProgress.fromProfile(
          _perfil.copyWith(raioAtendimentoKm: 25),
        ),
      );

      await tester.enterText(find.byType(TextField).at(0), 'Outro Nome');
      await tester.pumpAndSettle();
      await _tocarBotao(tester);

      expect(g.pessoal!.raioAtendimentoKm, 25);
    });

    testWidgets('com o motorista online, avisa que o novo raio vale depois', (
      tester,
    ) async {
      await _Gravacoes().monta(tester, motoristaOnline: () => true);

      expect(
        find.textContaining('próxima vez que você ficar online'),
        findsOneWidget,
      );
    });

    // O texto de ajuda de um campo é limitado a duas linhas pela identidade
    // visual (`helperMaxLines`), e o aviso, longo, saía cortado ("…"). O teste
    // fixa o desenho que o evita: o aviso é um texto à parte, sem limite de
    // linhas, e não parte do helperText. (Não se mede a largura de tela aqui: a
    // fonte dos testes é a Ahem, larga demais, e estouraria o que é real.)
    testWidgets('o aviso é um texto à parte, sem limite de linhas', (
      tester,
    ) async {
      await _Gravacoes().monta(tester, motoristaOnline: () => true);

      final aviso = find.textContaining('próxima vez que você ficar online');
      expect(aviso, findsOneWidget);
      expect(tester.widget<Text>(aviso).maxLines, isNull);
      expect(tester.widget<Text>(aviso).data, endsWith('ficar online.'));
      expect(
        tester.renderObject<RenderParagraph>(aviso).didExceedMaxLines,
        isFalse,
      );
      final ajuda = tester
          .widget<TextField>(campoRaio())
          .decoration!
          .helperText!;
      expect(ajuda, isNot(contains('próxima vez')));
      expect(ajuda, contains('De 1 a 100 km.'));
    });

    testWidgets('a ajuda fixa do campo continua visível com o aviso', (
      tester,
    ) async {
      await _Gravacoes().monta(tester, motoristaOnline: () => true);

      expect(find.textContaining('De 1 a 100 km.'), findsOneWidget);
    });

    testWidgets('offline (ou sem a informação), não há aviso', (tester) async {
      await _Gravacoes().monta(tester);
      expect(
        find.textContaining('próxima vez que você ficar online'),
        findsNothing,
      );

      await _Gravacoes().monta(tester, motoristaOnline: () => false);
      expect(
        find.textContaining('próxima vez que você ficar online'),
        findsNothing,
      );
    });
  });
}
