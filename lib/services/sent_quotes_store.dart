import 'dart:convert';

import 'key_value_store.dart';

/// Persiste os orçamentos (`kind: 20002`) publicados com sucesso pelo
/// motorista, e a origem e o destino da solicitação que cada um respondeu —
/// necessário para FR-011 da feature 010 (ignorar aceitação que não
/// corresponde a nenhum orçamento efetivamente enviado) e, desde a feature
/// 011, para saber a que ponto comparar a posição do motorista na checagem
/// de chegada à origem (D1 de `specs/011-notificar-chegada/research.md`) —
/// e, desde a feature 012, à chegada ao destino (D1/D2 de
/// `specs/012-confirmar-encontro-destino/research.md`). Todos sobrevivem a
/// um reinício do app entre o envio do orçamento e a chegada da aceitação
/// (D6 de `specs/010-iniciar-corrida/research.md`, achado CRITICAL do
/// `/speckit-analyze` daquela feature).
///
/// Escopo deliberadamente simples (Princípio V): nenhuma poda de entradas
/// antigas — o protótipo não roda por tempo suficiente, entre sessões de
/// avaliação, para que o crescimento da lista seja um problema real.
abstract class SentQuotesStore {
  /// Registra que o orçamento com este `id` foi publicado com sucesso,
  /// junto da origem e do destino (`RideRequestReceived.origin`/
  /// `.destination`) da solicitação respondida.
  Future<void> add(
    String quoteId, {
    required double originLat,
    required double originLon,
    required double destinationLat,
    required double destinationLon,
  });

  /// Verdadeiro se este `id` já foi registrado por [add].
  Future<bool> contains(String quoteId);

  /// Origem registrada para este `id` por [add], ou `null` se ele nunca foi
  /// registrado (mesmo caso em que [contains] devolveria falso).
  Future<(double lat, double lon)?> originFor(String quoteId);

  /// Destino registrado para este `id` por [add], ou `null` nas mesmas
  /// condições de [originFor].
  Future<(double lat, double lon)?> destinationFor(String quoteId);
}

/// Implementação real sobre `KeyValueStore`, mesmo mecanismo de
/// `RideStateStore` — um mapa de `id` para `[originLat, originLon,
/// destinationLat, destinationLon]` serializado em JSON.
class PreferencesSentQuotesStore implements SentQuotesStore {
  PreferencesSentQuotesStore(this._store);

  final KeyValueStore _store;

  static const String storageKey = 'driver_sent_quote_ids';

  @override
  Future<void> add(
    String quoteId, {
    required double originLat,
    required double originLon,
    required double destinationLat,
    required double destinationLon,
  }) async {
    final atual = await _load();
    atual[quoteId] = [originLat, originLon, destinationLat, destinationLon];
    await _store.write(storageKey, jsonEncode(atual));
  }

  @override
  Future<bool> contains(String quoteId) async =>
      (await _load()).containsKey(quoteId);

  @override
  Future<(double lat, double lon)?> originFor(String quoteId) async {
    final registro = (await _load())[quoteId];
    if (registro == null) return null;
    return (registro[0], registro[1]);
  }

  @override
  Future<(double lat, double lon)?> destinationFor(String quoteId) async {
    final registro = (await _load())[quoteId];
    if (registro == null) return null;
    return (registro[2], registro[3]);
  }

  Future<Map<String, List<double>>> _load() async {
    final raw = await _store.read(storageKey);
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map(
        (id, registro) => MapEntry(
          id,
          (registro as List<dynamic>)
              .map((v) => (v as num).toDouble())
              .toList(),
        ),
      );
    } catch (_) {
      // Dado corrompido não trava o app: trata como se nada tivesse sido
      // enviado ainda, mesma postura de `RelayRepository`/`RideStateStore`.
      return {};
    }
  }
}
