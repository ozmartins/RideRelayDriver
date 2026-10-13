import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/nostr_event.dart';
import 'event_verifier.dart';
import 'prototype_marker.dart';
import 'relay_gateway.dart';

/// Recebe eventos dos relays, descarta os inválidos e deduplica.
///
/// Ordem obrigatória (contrato de eventos, regras 1 e 2): **verificar a
/// assinatura antes de qualquer outro processamento**, depois deduplicar por
/// identificador, depois exibir. Mantém em memória apenas uma janela dos
/// eventos mais recentes, para sustentar SC-006 sob rajada.
class EventFeed {
  EventFeed({
    required Stream<IncomingEvent> incoming,
    this.verifier = const NostrEventVerifier(),
    this.maxEvents = 200,
    this.acceptedKinds = const {NostrEvent.kindRideRequest},
  }) {
    _subscription = incoming.listen(_handle);
  }

  /// Verificador de assinatura. Injetável para permitir dublê em teste.
  final EventVerifier verifier;

  /// Kinds que a aplicação exibe; os demais são ignorados sem erro.
  final Set<int> acceptedKinds;

  /// Limite da janela de eventos mantida em memória.
  final int maxEvents;

  final List<NostrEvent> _events = [];
  final Set<String> _seenIds = {};
  final StreamController<void> _changes = StreamController.broadcast();
  late final StreamSubscription<IncomingEvent> _subscription;

  /// Chave de ordenação de cada evento exibido, por id.
  final _sortKeys = <String, DateTime>{};

  int _discardedInvalid = 0;
  int _discardedDuplicate = 0;
  int _discardedUnmarked = 0;
  int _accepted = 0;

  /// Eventos aceitos, do mais recente para o mais antigo.
  List<NostrEvent> get events => List.unmodifiable(_events);

  /// Emite quando a lista muda, para a interface redesenhar.
  Stream<void> get changes => _changes.stream;

  /// Quantos eventos foram descartados por assinatura inválida ou malformação.
  int get discardedInvalidCount => _discardedInvalid;

  /// Quantas entregas duplicadas foram absorvidas (mesmo `id`).
  int get discardedDuplicateCount => _discardedDuplicate;

  /// Quantos eventos legítimos, porém alheios ao protótipo, foram descartados
  /// por não trazerem o marcador (emenda 01, regra 6 do contrato).
  int get discardedUnmarkedCount => _discardedUnmarked;

  void _handle(IncomingEvent incoming) {
    final payload = incoming.payload;

    // 1. verificação de assinatura antes de tudo (FR-009)
    if (!verifier.isValid(payload)) {
      _discardedInvalid++;
      return;
    }

    final kind = payload['kind'] as int;

    // kind desconhecido é ignorado sem erro (contrato, regra 4)
    if (!acceptedKinds.contains(kind)) return;

    // 2. marcador do protótipo (contrato, regra 6). O filtro `#t` pedido na
    // inscrição não é garantia: o relay pode ignorá-lo.
    if (!hasPrototypeMarker(payload['tags'] as List<dynamic>?)) {
      _discardedUnmarked++;
      return;
    }

    final id = payload['id'] as String;

    // 3. deduplicação por identificador (FR-010)
    if (!_seenIds.add(id)) {
      _discardedDuplicate++;
      return;
    }

    final evento = NostrEvent.fromVerifiedPayload(payload);
    final declarado = evento.createdAt;

    // Ordem de exibição: mais novo primeiro, pela data declarada — não pela
    // ordem de chegada. O relay entrega o histórico do mais novo para o mais
    // velho, e inserir cada um no topo invertia a lista.
    //
    // A data é declarada pelo autor e não é confiável (contrato, regra 5):
    // ordenar a exibição por ela é aceitável, mas um evento datado no futuro
    // não pode ficar preso no topo nem escapar da janela. Por isso a data
    // futura é limitada ao instante de chegada.
    final agora = DateTime.now();
    final chave = declarado.isAfter(agora) ? agora : declarado;
    _sortKeys[id] = chave;

    // Insere antes do primeiro evento com chave menor ou igual: em empate, o
    // recém-chegado fica na frente.
    var indice = _events.indexWhere((e) => !_sortKeys[e.id]!.isAfter(chave));
    if (indice == -1) indice = _events.length;
    _events.insert(indice, evento);

    // 4. janela limitada: a memória não cresce indefinidamente (SC-006).
    // Os ids descartados saem também do conjunto de vistos e das chaves de
    // ordenação — antes só a lista era podada, e o conjunto de vistos crescia
    // sem limite, que é justamente o vazamento que a janela deveria evitar.
    if (_events.length > maxEvents) {
      for (final descartado in _events.sublist(maxEvents)) {
        _seenIds.remove(descartado.id);
        _sortKeys.remove(descartado.id);
      }
      _events.removeRange(maxEvents, _events.length);
    }

    _accepted++;
    if (kDebugMode && _accepted % 25 == 0) {
      debugPrint(
        '[medicao] rajada: $_accepted aceitos, '
        '${_events.length} em memória, $_discardedInvalid inválidos, '
        '$_discardedDuplicate duplicados',
      );
    }

    if (!_changes.isClosed) _changes.add(null);
  }

  Future<void> dispose() async {
    await _subscription.cancel();
    await _changes.close();
  }
}
