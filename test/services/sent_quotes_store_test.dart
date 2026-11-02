import 'package:driver/services/key_value_store.dart';
import 'package:driver/services/sent_quotes_store.dart';
import 'package:flutter_test/flutter_test.dart';

class InMemoryStore implements KeyValueStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

void main() {
  late InMemoryStore store;
  late SentQuotesStore repo;

  setUp(() {
    store = InMemoryStore();
    repo = PreferencesSentQuotesStore(store);
  });

  test('id nunca registrado não está contido', () async {
    expect(await repo.contains('quote-1'), isFalse);
  });

  test('id registrado passa a estar contido', () async {
    await repo.add(
      'quote-1',
      originLat: -28.9298,
      originLon: -49.4753,
      destinationLat: -28.6721,
      destinationLon: -49.3671,
    );

    expect(await repo.contains('quote-1'), isTrue);
  });

  test(
    'registrar o mesmo id duas vezes não gera duplicidade nem erro',
    () async {
      await repo.add(
        'quote-1',
        originLat: -28.9298,
        originLon: -49.4753,
        destinationLat: -28.6721,
        destinationLon: -49.3671,
      );
      await repo.add(
        'quote-1',
        originLat: -28.9298,
        originLon: -49.4753,
        destinationLat: -28.6721,
        destinationLon: -49.3671,
      );

      expect(await repo.contains('quote-1'), isTrue);
    },
  );

  test('sobrevive a uma nova instância sobre o mesmo armazenamento (reinício '
      'entre o envio do orçamento e a chegada da aceitação — achado C1 do '
      '/speckit-analyze da feature 010)', () async {
    await repo.add(
      'quote-1',
      originLat: -28.9298,
      originLon: -49.4753,
      destinationLat: -28.6721,
      destinationLon: -49.3671,
    );

    final novaInstancia = PreferencesSentQuotesStore(store);

    expect(await novaInstancia.contains('quote-1'), isTrue);
  });

  test('armazenamento corrompido é tratado como vazio, sem travar', () async {
    store.values[PreferencesSentQuotesStore.storageKey] = 'não é json';

    expect(await repo.contains('quote-1'), isFalse);
  });

  group('originFor (feature 011)', () {
    test('devolve null para um id nunca registrado', () async {
      expect(await repo.originFor('quote-1'), isNull);
    });

    test('devolve a origem registrada por add', () async {
      await repo.add(
        'quote-1',
        originLat: -28.9298,
        originLon: -49.4753,
        destinationLat: -28.6721,
        destinationLon: -49.3671,
      );

      final origem = await repo.originFor('quote-1');

      expect(origem, (-28.9298, -49.4753));
    });

    test(
      'sobrevive a uma nova instância sobre o mesmo armazenamento',
      () async {
        await repo.add(
          'quote-1',
          originLat: -28.9298,
          originLon: -49.4753,
          destinationLat: -28.6721,
          destinationLon: -49.3671,
        );

        final novaInstancia = PreferencesSentQuotesStore(store);

        expect(await novaInstancia.originFor('quote-1'), (-28.9298, -49.4753));
      },
    );
  });

  group('destinationFor (feature 012)', () {
    test('devolve null para um id nunca registrado', () async {
      expect(await repo.destinationFor('quote-1'), isNull);
    });

    test('devolve o destino registrado por add', () async {
      await repo.add(
        'quote-1',
        originLat: -28.9298,
        originLon: -49.4753,
        destinationLat: -28.6721,
        destinationLon: -49.3671,
      );

      final destino = await repo.destinationFor('quote-1');

      expect(destino, (-28.6721, -49.3671));
    });

    test(
      'sobrevive a uma nova instância sobre o mesmo armazenamento',
      () async {
        await repo.add(
          'quote-1',
          originLat: -28.9298,
          originLon: -49.4753,
          destinationLat: -28.6721,
          destinationLon: -49.3671,
        );

        final novaInstancia = PreferencesSentQuotesStore(store);

        expect(await novaInstancia.destinationFor('quote-1'), (
          -28.6721,
          -49.3671,
        ));
      },
    );
  });
}
