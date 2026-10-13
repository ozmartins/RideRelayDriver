import 'package:driver/services/default_relays.dart';
import 'package:driver/services/key_value_store.dart';
import 'package:driver/services/relay_repository.dart';
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
  late RelayRepository repo;

  setUp(() {
    store = InMemoryStore();
    repo = RelayRepository(store);
  });

  test('na primeira execução devolve a lista padrão', () async {
    final relays = await repo.load();

    expect(relays.map((r) => r.url), defaultRelayUrls);
    expect(relays.every((r) => r.isDefault), isTrue);
  });

  test('persiste e restaura a lista alterada (FR-012/SC-005)', () async {
    final inicial = await repo.load();
    final comNovo = await repo.add('wss://relay.exemplo.org', inicial);

    final recarregada = await RelayRepository(store).load();

    expect(recarregada.map((r) => r.url), comNovo.map((r) => r.url));
    expect(recarregada.map((r) => r.url), contains('wss://relay.exemplo.org'));
  });

  test('rejeita endereço inválido sem alterar a lista', () async {
    final inicial = await repo.load();

    for (final invalido in [
      'banana',
      'http://relay.exemplo.org',
      'wss://',
      '',
    ]) {
      await expectLater(
        repo.add(invalido, inicial),
        throwsA(isA<InvalidRelayUrl>()),
        reason: '$invalido deveria ser recusado',
      );
    }

    expect((await repo.load()).length, inicial.length);
  });

  test('aceita relay local sem domínio com ponto', () async {
    final inicial = await repo.load();

    final atualizada = await repo.add('ws://localhost:7777', inicial);

    expect(
      atualizada.any((r) => r.url == 'ws://localhost:7777'),
      isTrue,
      reason: 'um relay local de teste é um endereço válido',
    );
  });

  test('rejeita duplicado, inclusive com barra final e maiúsculas', () async {
    final inicial = await repo.load();

    await expectLater(
      repo.add(defaultRelayUrls.first, inicial),
      throwsA(isA<DuplicateRelayUrl>()),
    );
    await expectLater(
      repo.add('${defaultRelayUrls.first}/', inicial),
      throwsA(isA<DuplicateRelayUrl>()),
    );
    await expectLater(
      repo.add(defaultRelayUrls.first.toUpperCase(), inicial),
      throwsA(isA<DuplicateRelayUrl>()),
    );
  });

  test('remove relay da lista e persiste', () async {
    final inicial = await repo.load();
    final removido = inicial.first.url;

    final restante = await repo.remove(removido, inicial);

    expect(restante.map((r) => r.url), isNot(contains(removido)));
    expect(
      (await RelayRepository(store).load()).map((r) => r.url),
      isNot(contains(removido)),
    );
  });

  test('restaura a lista padrão quando esvaziada (FR-013)', () async {
    var relays = await repo.load();
    for (final relay in [...relays]) {
      relays = await repo.remove(relay.url, relays);
    }
    expect(relays, isEmpty);

    final restaurada = await repo.restoreDefaults();

    expect(restaurada.map((r) => r.url), defaultRelayUrls);
    expect(
      (await RelayRepository(store).load()).length,
      defaultRelayUrls.length,
    );
  });

  test(
    'lista persistida corrompida volta ao padrão em vez de ficar sem relays',
    () async {
      store.values[RelayRepository.storageKey] = 'isto não é json';

      final relays = await repo.load();

      expect(relays.map((r) => r.url), defaultRelayUrls);
    },
  );
}
