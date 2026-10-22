import 'dart:async';

import 'package:dart_nostr/dart_nostr.dart' as nostr;
import 'package:driver/domain/driver_coverage.dart';
import 'package:driver/domain/geohash.dart';
import 'package:driver/domain/nostr_event.dart' as domain;
import 'package:driver/services/event_feed.dart';
import 'package:driver/services/prototype_marker.dart';
import 'package:driver/services/relay_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

/// Gera um evento **realmente assinado**, para que a verificação sob teste seja
/// a criptográfica de verdade, não um dublê que sempre aprova (Princípio II).
Map<String, dynamic> signedPayload({
  String content = 'evento de teste',
  int kind = domain.NostrEvent.kindRideRequest,
  nostr.NostrKeyPairs? keyPairs,
  List<List<String>>? tags,
  DateTime? createdAt,
}) {
  final keys = keyPairs ?? nostr.Nostr.instance.services.keys.generateKeyPair();
  final event = nostr.NostrEvent.fromPartialData(
    kind: kind,
    content: content,
    keyPairs: keys,
    tags: tags ?? [prototypeMarkerTag],
    createdAt: createdAt ?? DateTime.utc(2026, 9, 15, 12),
  );
  return {
    'id': event.id,
    'pubkey': event.pubkey,
    'created_at': event.createdAt!.millisecondsSinceEpoch ~/ 1000,
    'kind': event.kind,
    'tags': event.tags,
    'content': event.content,
    'sig': event.sig,
  };
}

void main() {
  late StreamController<IncomingEvent> incoming;
  late EventFeed feed;

  setUp(() {
    incoming = StreamController<IncomingEvent>.broadcast();
  });

  tearDown(() async {
    await feed.dispose();
    await incoming.close();
  });

  EventFeed buildFeed({
    int maxEvents = 200,
    DriverCoverage? Function()? coverage,
    Set<int> acceptedKinds = const {domain.NostrEvent.kindRideRequest},
  }) {
    feed = EventFeed(
      incoming: incoming.stream,
      maxEvents: maxEvents,
      coverage: coverage,
      acceptedKinds: acceptedKinds,
    );
    return feed;
  }

  void emit(
    Map<String, dynamic> payload, {
    String relay = 'wss://relay.damus.io',
  }) {
    incoming.add(IncomingEvent(relayUrl: relay, payload: payload));
  }

  group('EventFeed — verificação de assinatura (caso válido e inválido)', () {
    test('aceita evento com assinatura válida', () async {
      final f = buildFeed();

      emit(signedPayload(content: 'olá da rede'));
      await pumpEventQueue();

      expect(f.events.length, 1);
      expect(f.events.single.content, 'olá da rede');
      expect(f.events.single.isSignatureValid, isTrue);
    });

    test('descarta evento com assinatura adulterada', () async {
      final f = buildFeed();
      final payload = signedPayload()..['sig'] = 'f' * 128;

      emit(payload);
      await pumpEventQueue();

      expect(f.events, isEmpty);
      expect(f.discardedInvalidCount, 1);
    });

    test(
      'descarta evento com conteúdo adulterado, mantendo id e sig originais',
      () async {
        final f = buildFeed();
        final payload = signedPayload(content: 'conteúdo original')
          ..['content'] = 'conteúdo trocado por um terceiro';

        emit(payload);
        await pumpEventQueue();

        expect(
          f.events,
          isEmpty,
          reason: 'o id é recalculado a partir do conteúdo e deixa de conferir',
        );
        expect(f.discardedInvalidCount, 1);
      },
    );

    test('descarta evento cujo autor diverge da assinatura', () async {
      final f = buildFeed();
      final outro = nostr.Nostr.instance.services.keys.generateKeyPair();
      final payload = signedPayload()..['pubkey'] = outro.public;

      emit(payload);
      await pumpEventQueue();

      expect(f.events, isEmpty);
      expect(f.discardedInvalidCount, 1);
    });

    test('descarta evento com campo obrigatório ausente', () async {
      final f = buildFeed();
      final payload = signedPayload()..remove('sig');

      emit(payload);
      await pumpEventQueue();

      expect(f.events, isEmpty);
      expect(f.discardedInvalidCount, 1);
    });

    test('evento malformado não sobe exceção para a interface', () async {
      final f = buildFeed();

      emit({'id': 42, 'kind': 'texto'});
      await pumpEventQueue();

      expect(f.events, isEmpty);
      expect(f.discardedInvalidCount, 1);
    });
  });

  group('EventFeed — deduplicação (FR-010)', () {
    test(
      'o mesmo evento entregue por dois relays aparece uma única vez',
      () async {
        final f = buildFeed();
        final payload = signedPayload();

        emit(payload, relay: 'wss://relay.damus.io');
        emit(payload, relay: 'wss://nos.lol');
        await pumpEventQueue();

        expect(f.events.length, 1);
        expect(f.discardedDuplicateCount, 1);
      },
    );

    test('reentrega após reconexão não duplica evento já visto', () async {
      final f = buildFeed();
      final payload = signedPayload(content: 'antes da queda');

      emit(payload);
      await pumpEventQueue();

      // a rede cai e volta; o relay reenvia o histórico da inscrição
      emit(payload);
      emit(payload, relay: 'wss://nos.lol');
      await pumpEventQueue();

      expect(
        f.events.length,
        1,
        reason: 'trocar Wi-Fi por dados móveis não pode duplicar a lista',
      );
    });

    test('eventos distintos do mesmo autor coexistem', () async {
      final f = buildFeed();
      final keys = nostr.Nostr.instance.services.keys.generateKeyPair();

      emit(signedPayload(content: 'primeiro', keyPairs: keys));
      emit(signedPayload(content: 'segundo', keyPairs: keys));
      await pumpEventQueue();

      expect(f.events.length, 2);
    });
  });

  group('EventFeed — marcador do protótipo (emenda 01, regra 6)', () {
    test('descarta evento sem o marcador, mesmo entregue pelo relay', () async {
      final f = buildFeed();

      // Nota social comum da rede: assinatura válida, kind conhecido, sem tag.
      emit(signedPayload(content: 'nota social alheia', tags: const []));
      await pumpEventQueue();

      expect(
        f.events,
        isEmpty,
        reason:
            'o filtro #t da inscrição não é garantia; o relay pode ignorá-lo',
      );
      expect(f.discardedUnmarkedCount, 1);
    });

    test('descarta evento com marcador de outro namespace', () async {
      final f = buildFeed();

      emit(
        signedPayload(
          tags: const [
            ['t', 'outro-app-qualquer'],
          ],
        ),
      );
      await pumpEventQueue();

      expect(f.events, isEmpty);
      expect(f.discardedUnmarkedCount, 1);
    });

    test('aceita evento com o marcador do protótipo', () async {
      final f = buildFeed();

      emit(signedPayload(content: 'evento do protótipo'));
      await pumpEventQueue();

      expect(f.events.single.content, 'evento do protótipo');
      expect(f.discardedUnmarkedCount, 0);
    });

    test('aceita evento que traga o marcador entre outras tags', () async {
      final f = buildFeed();

      emit(
        signedPayload(
          tags: [
            ['e', 'a' * 64],
            prototypeMarkerTag,
          ],
        ),
      );
      await pumpEventQueue();

      expect(f.events.length, 1);
    });

    test(
      'descarte por marcador não é contado como assinatura inválida',
      () async {
        final f = buildFeed();

        emit(signedPayload(tags: const []));
        await pumpEventQueue();

        expect(
          f.discardedInvalidCount,
          0,
          reason: 'o evento é legítimo, apenas não é deste protótipo',
        );
      },
    );
  });

  group('EventFeed — kinds e janela', () {
    test('kind desconhecido é ignorado sem erro', () async {
      final f = buildFeed();

      emit(signedPayload(kind: 30023, content: 'artigo longo'));
      await pumpEventQueue();

      expect(f.events, isEmpty);
      expect(
        f.discardedInvalidCount,
        0,
        reason: 'ignorar não é descartar por inválido',
      );
    });

    test('mantém apenas a janela mais recente sob rajada (SC-006)', () async {
      final f = buildFeed(maxEvents: 10);

      for (var i = 0; i < 120; i++) {
        emit(signedPayload(content: 'evento $i'));
      }
      await pumpEventQueue();

      expect(f.events.length, 10);
      expect(
        f.events.first.content,
        'evento 119',
        reason: 'o mais recente fica no topo',
      );
    });

    test('expõe os eventos como lista imodificável', () async {
      final f = buildFeed();
      emit(signedPayload());
      await pumpEventQueue();

      expect(() => f.events.add(f.events.first), throwsUnsupportedError);
    });
  });
  group('EventFeed — ordem de exibição', () {
    // Defeito encontrado na validação cross-app pela sessão que mantém as duas
    // apps: eventos eram inseridos no topo por ordem de CHEGADA. O relay
    // entrega o histórico do mais novo para o mais velho, então a lista saía
    // invertida — o mesmo defeito existia no passageiro.

    test('histórico entregue do mais novo para o mais velho é exibido com o '
        'mais novo primeiro', () async {
      final f = buildFeed();
      final base = DateTime.utc(2026, 9, 16, 12);

      for (final minutos in [0, 10, 20, 30]) {
        emit(
          signedPayload(
            content: 'há $minutos min',
            createdAt: base.subtract(Duration(minutes: minutos)),
          ),
        );
      }
      await pumpEventQueue();

      expect(f.events.map((e) => e.content), [
        'há 0 min',
        'há 10 min',
        'há 20 min',
        'há 30 min',
      ]);
    });

    test('evento com data no futuro não fica preso no topo', () async {
      final f = buildFeed();

      emit(
        signedPayload(
          content: 'datado no futuro',
          createdAt: DateTime.now().add(const Duration(days: 365)),
        ),
      );
      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      emit(
        signedPayload(content: 'legítimo e recente', createdAt: DateTime.now()),
      );
      await pumpEventQueue();

      expect(f.events.first.content, 'legítimo e recente');
    });
  });

  group('EventFeed — memória limitada de verdade (SC-006)', () {
    test('o id de um evento descartado pela janela é esquecido', () async {
      // Defeito: a janela removia eventos da lista, mas não os ids do conjunto
      // de vistos, que crescia sem limite — o vazamento que a janela existe
      // para evitar. Sonda: um id já descartado não pode mais contar como
      // duplicata, porque não deveria mais estar guardado.
      final f = buildFeed(maxEvents: 2);
      final base = DateTime.utc(2026, 9, 16, 12);

      final antigo = signedPayload(content: 'antigo', createdAt: base);
      emit(antigo);
      emit(
        signedPayload(
          content: 'meio',
          createdAt: base.add(const Duration(minutes: 1)),
        ),
      );
      emit(
        signedPayload(
          content: 'novo',
          createdAt: base.add(const Duration(minutes: 2)),
        ),
      );
      await pumpEventQueue();
      expect(f.events.map((e) => e.content), ['novo', 'meio']);

      emit(antigo);
      await pumpEventQueue();

      expect(
        f.discardedDuplicateCount,
        0,
        reason: 'o id descartado pela janela continuava guardado',
      );
    });
  });
  group('recorte geográfico do 20001 (feature 027, regra 8 do contrato)', () {
    const araranguaLat = -28.9298, araranguaLon = -49.4753;
    DriverCoverage cobertura({int raio = 10}) => DriverCoverage.around(
      lat: araranguaLat,
      lon: araranguaLon,
      radiusKm: raio,
    );

    List<List<String>> tagsG(double lat, double lon) => [
      for (final p in kPrecisoesDaTag) ['g', Geohash.encode(lat, lon, p)],
    ];

    Map<String, dynamic> solicitacao(
      double lat,
      double lon, {
      List<List<String>>? tags,
      int kind = domain.NostrEvent.kindRideRequest,
    }) => signedPayload(
      kind: kind,
      content:
          '{"origin":{"lat":$lat,"lon":$lon},'
          '"destination":{"lat":$lat,"lon":$lon},"payment":"pix"}',
      tags: tags ?? [prototypeMarkerTag, ...tagsG(lat, lon)],
    );

    test('aceita a solicitação de origem dentro do raio', () async {
      final f = buildFeed(coverage: cobertura);

      emit(solicitacao(araranguaLat + 0.03, araranguaLon)); // ~3 km
      await pumpEventQueue();

      expect(f.events, hasLength(1));
      expect(f.discardedOutOfCoverageCount, 0);
    });

    test(
      'descarta São Paulo: nem entra na lista nem conta como aceita',
      () async {
        final f = buildFeed(coverage: cobertura);

        emit(solicitacao(-23.5505, -46.6333));
        await pumpEventQueue();

        expect(f.events, isEmpty);
        expect(f.discardedOutOfCoverageCount, 1);
      },
    );

    test(
      'descarta sem tag g, g fora das células e origem além do raio',
      () async {
        final f = buildFeed(coverage: cobertura);

        // Sem g.
        emit(
          solicitacao(araranguaLat, araranguaLon, tags: [prototypeMarkerTag]),
        );
        // g de São Paulo, origem em Araranguá.
        emit(
          solicitacao(
            araranguaLat,
            araranguaLon,
            tags: [prototypeMarkerTag, ...tagsG(-23.5505, -46.6333)],
          ),
        );
        // g na célula, origem ~15 km ao norte: fora dos 10 km.
        emit(solicitacao(araranguaLat + 0.135, araranguaLon));
        await pumpEventQueue();

        expect(f.events, isEmpty);
        expect(f.discardedOutOfCoverageCount, 3);
      },
    );

    test('o descarte vem antes da deduplicação: reentregue com outra cobertura, entra', () async {
      var atual = cobertura();
      final f = buildFeed(coverage: () => atual);
      final longe = solicitacao(-23.5505, -46.6333);

      emit(longe);
      await pumpEventQueue();
      expect(f.events, isEmpty);

      // O motorista ficou offline e online em São Paulo.
      atual = DriverCoverage.around(lat: -23.5505, lon: -46.6333, radiusKm: 10);
      emit(longe);
      await pumpEventQueue();

      expect(f.events, hasLength(1));
      expect(f.discardedDuplicateCount, 0);
    });

    test(
      'assinatura inválida continua sendo descartada antes de tudo',
      () async {
        final f = buildFeed(coverage: cobertura);

        emit(solicitacao(araranguaLat, araranguaLon)..['sig'] = 'f' * 128);
        await pumpEventQueue();

        expect(f.events, isEmpty);
        expect(f.discardedInvalidCount, 1);
        expect(f.discardedOutOfCoverageCount, 0);
      },
    );

    test(
      'sem o parâmetro, ou com cobertura nula, não há recorte geográfico',
      () async {
        final f = buildFeed();
        emit(solicitacao(-23.5505, -46.6333));
        await pumpEventQueue();
        expect(f.events, hasLength(1));
        await f.dispose();

        final g = buildFeed(coverage: () => null);
        emit(solicitacao(-23.5505, -46.6333, tags: [prototypeMarkerTag]));
        await pumpEventQueue();
        expect(g.events, hasLength(1));
        expect(g.discardedOutOfCoverageCount, 0);
      },
    );

    test('outros kinds não sofrem o recorte', () async {
      final f = buildFeed(
        coverage: cobertura,
        acceptedKinds: const {domain.NostrEvent.kindQuoteAccepted},
      );

      emit(
        signedPayload(
          kind: domain.NostrEvent.kindQuoteAccepted,
          content: 'x',
          tags: [prototypeMarkerTag],
        ),
      );
      await pumpEventQueue();

      expect(f.events, hasLength(1));
      expect(f.discardedOutOfCoverageCount, 0);
    });
  });
}
