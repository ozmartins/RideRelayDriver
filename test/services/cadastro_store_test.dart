import 'package:driver/domain/cadastro_progress.dart';
import 'package:driver/domain/driver_profile.dart';
import 'package:driver/domain/payment_method.dart';
import 'package:driver/services/cadastro_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_cadastro_store.dart';

DriverProfile perfilValido() => const DriverProfile(
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

void main() {
  group('CadastroStore — ausência e persistência (FR-001, FR-007)', () {
    test('load() devolve null quando nada foi salvo', () async {
      final store = FakeCadastroStore();

      expect(await store.load(), isNull);
    });

    test('as três etapas salvas resultam no cadastro completo', () async {
      final store = FakeCadastroStore();
      final progresso = CadastroProgress.fromProfile(perfilValido());

      await store.savePersonal(progresso.personal!);
      await store.saveVehicle(progresso.vehicle!);
      await store.saveFinancial(progresso.financial!);

      expect(await store.load(), perfilValido());
      expect(store.saveCount, 3);
    });

    test(
      'salvar de novo uma etapa substitui a anterior, sem acumular',
      () async {
        final store = FakeCadastroStore(perfilValido());
        final atualizado = CadastroProgress.fromProfile(
          perfilValido().copyWith(corVeiculo: 'Branco'),
        ).vehicle!;

        await store.saveVehicle(atualizado);

        expect((await store.load())!.corVeiculo, 'Branco');
      },
    );
  });

  group('CadastroStore — progresso por etapa', () {
    test('sem nada salvo, a próxima etapa é a 1 (índice 0)', () async {
      final progresso = await FakeCadastroStore().loadProgress();

      expect(progresso.nextStep, 0);
      expect(progresso.toProfile(), isNull);
    });

    test('depois da etapa 1, retoma na etapa 2 (índice 1)', () async {
      final store = FakeCadastroStore();
      final completo = CadastroProgress.fromProfile(perfilValido());
      await store.savePersonal(completo.personal!);

      final progresso = await store.loadProgress();

      expect(progresso.nextStep, 1);
      expect(await store.load(), isNull);
    });

    test('depois da etapa 2, retoma na etapa 3 (índice 2)', () async {
      final store = FakeCadastroStore();
      final completo = CadastroProgress.fromProfile(perfilValido());
      await store.savePersonal(completo.personal!);
      await store.saveVehicle(completo.vehicle!);

      expect((await store.loadProgress()).nextStep, 2);
      expect(await store.load(), isNull);
    });

    test('com as três etapas, o cadastro está completo', () async {
      final progresso = await FakeCadastroStore(perfilValido()).loadProgress();

      expect(progresso.nextStep, isNull);
      expect(progresso.isComplete, isTrue);
    });
  });

  group('CadastroStore — cadastro corrompido (FR-010, Princípio II por '
      'analogia)', () {
    test('UF fora da lista fixa é reportada como corrompida', () async {
      final store = FakeCadastroStore();
      store.debugSetRaw(
        CadastroProgress.fromProfile(perfilValido().copyWith(uf: 'ZZ')),
      );

      expect(store.loadProgress(), throwsA(isA<CorruptedDriverProfile>()));
    });

    test(
      'combinação UF/cidade inconsistente é reportada como corrompida',
      () async {
        final store = FakeCadastroStore();
        // Araranguá é de SC, não de SP.
        store.debugSetRaw(
          CadastroProgress.fromProfile(perfilValido().copyWith(uf: 'SP')),
        );

        expect(store.loadProgress(), throwsA(isA<CorruptedDriverProfile>()));
      },
    );

    test('cadastro válido não é reportado como corrompido', () async {
      final store = FakeCadastroStore();
      store.debugSetRaw(CadastroProgress.fromProfile(perfilValido()));

      await expectLater(
        store.loadProgress(),
        completion(predicate<CadastroProgress>((p) => p.isComplete)),
      );
    });

    test('cadastro sem nenhuma forma de pagamento é reportado como corrompido '
        '(equivalente a uma migração da versão 1 da feature 003, D2 de '
        'specs/005-formas-pagamento/research.md)', () async {
      final store = FakeCadastroStore();
      store.debugSetRaw(
        CadastroProgress.fromProfile(
          perfilValido().copyWith(paymentMethods: const {}),
        ),
      );

      expect(store.loadProgress(), throwsA(isA<CorruptedDriverProfile>()));
    });

    test('cadastro com precoPorKm zerado é reportado como corrompido '
        '(equivalente a uma migração das versões 1/2, D2 de '
        'specs/006-preco-por-km/research.md)', () async {
      final store = FakeCadastroStore();
      store.debugSetRaw(
        CadastroProgress.fromProfile(perfilValido().copyWith(precoPorKm: 0)),
      );

      expect(store.loadProgress(), throwsA(isA<CorruptedDriverProfile>()));
    });

    test('cadastro com anoVeiculo zerado é reportado como corrompido '
        '(equivalente a uma migração das versões 1/2/3, D2 de '
        'specs/008-ano-do-veiculo/research.md)', () async {
      final store = FakeCadastroStore();
      store.debugSetRaw(
        CadastroProgress.fromProfile(perfilValido().copyWith(anoVeiculo: 0)),
      );

      expect(store.loadProgress(), throwsA(isA<CorruptedDriverProfile>()));
    });
  });
}
