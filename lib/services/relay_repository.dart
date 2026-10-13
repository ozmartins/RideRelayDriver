import 'dart:convert';

import '../domain/relay.dart';
import 'default_relays.dart';
import 'key_value_store.dart';

/// Endereço de relay recusado na validação (FR-011).
class InvalidRelayUrl implements Exception {
  InvalidRelayUrl(this.url);
  final String url;

  @override
  String toString() => 'Endereço de relay inválido: $url';
}

/// Endereço já presente na lista (FR-011).
class DuplicateRelayUrl implements Exception {
  DuplicateRelayUrl(this.url);
  final String url;

  @override
  String toString() => 'Relay já está na lista: $url';
}

/// Persiste e valida a lista de relays do motorista.
///
/// A lista é gravada como **um único valor JSON**, de modo que a escrita seja
/// atômica do ponto de vista da aplicação (decisão D9).
class RelayRepository {
  RelayRepository(this._store);

  final KeyValueStore _store;

  static const String storageKey = 'relay_urls';

  /// Carrega a lista persistida; na primeira execução devolve a lista padrão.
  Future<List<Relay>> load() async {
    final raw = await _store.read(storageKey);
    if (raw == null) return defaultRelays();

    try {
      final decoded = (jsonDecode(raw) as List<dynamic>).cast<String>();
      return decoded.map(_toRelay).toList();
    } catch (_) {
      // Lista corrompida não deixa o app sem relays: volta ao padrão.
      return defaultRelays();
    }
  }

  /// A lista padrão embutida, usada na primeira execução e na restauração.
  List<Relay> defaultRelays() =>
      defaultRelayUrls.map((url) => Relay(url: url, isDefault: true)).toList();

  /// Grava a lista informada.
  Future<void> save(List<Relay> relays) async {
    final urls = relays.map((r) => r.url).toList();
    await _store.write(storageKey, jsonEncode(urls));
  }

  /// Acrescenta um relay, validando formato e duplicidade (FR-011).
  ///
  /// Lança [InvalidRelayUrl] ou [DuplicateRelayUrl] sem alterar a lista.
  Future<List<Relay>> add(String url, List<Relay> current) async {
    if (!Relay.isValidUrl(url)) throw InvalidRelayUrl(url);

    final novo = Relay(url: url.trim());
    if (current.contains(novo)) throw DuplicateRelayUrl(url);

    final atualizada = [...current, novo];
    await save(atualizada);
    return atualizada;
  }

  /// Remove um relay da lista (FR-011).
  Future<List<Relay>> remove(String url, List<Relay> current) async {
    final atualizada = current.where((r) => r != Relay(url: url)).toList();
    await save(atualizada);
    return atualizada;
  }

  /// Restaura a lista padrão, usado quando o motorista esvazia a lista (FR-013).
  Future<List<Relay>> restoreDefaults() async {
    final padrao = defaultRelays();
    await save(padrao);
    return padrao;
  }

  Relay _toRelay(String url) =>
      Relay(url: url, isDefault: defaultRelayUrls.contains(url));
}
