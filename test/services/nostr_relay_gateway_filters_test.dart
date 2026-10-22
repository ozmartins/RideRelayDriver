import 'package:driver/domain/nostr_event.dart' as domain;
import 'package:driver/services/nostr_relay_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

/// A montagem dos filtros do `REQ` (emenda 27 do contrato) é função pura, para
/// ser testada sem relay nem rede.
void main() {
  const consumidos = [
    domain.NostrEvent.kindRideRequest,
    domain.NostrEvent.kindQuoteAccepted,
    domain.NostrEvent.kindMeetingConfirmed,
  ];
  const celulas = [
    '6fug',
    '6fue',
    '6fus',
    '6fu7',
    '6fu6',
    '6fud',
    '6fuk',
    '6fu3',
    '6fu9',
  ];

  List<Map<String, dynamic>> monta(List<int> kinds, List<String>? cells) => [
    for (final f in NostrRelayGateway.buildFilters(kinds, cells)) f.toMap(),
  ];

  test('sem células (offline): um filtro só, sem o 20001', () {
    final filtros = monta(consumidos, null);

    expect(filtros, hasLength(1));
    expect(filtros.single['kinds'], [
      domain.NostrEvent.kindQuoteAccepted,
      domain.NostrEvent.kindMeetingConfirmed,
    ]);
    expect(filtros.single['#t'], ['tcc-ufsc-caronas']);
    expect(filtros.single['limit'], 50);
    expect(filtros.single.containsKey('#g'), isFalse);
  });

  test('com células (online): o 20001 vai num filtro à parte, com #g', () {
    final filtros = monta(consumidos, celulas);

    expect(filtros, hasLength(2));
    final outros = filtros.firstWhere((f) => !f.containsKey('#g'));
    final solicitacoes = filtros.firstWhere((f) => f.containsKey('#g'));
    expect(outros['kinds'], isNot(contains(domain.NostrEvent.kindRideRequest)));
    expect(solicitacoes['kinds'], [domain.NostrEvent.kindRideRequest]);
    expect(solicitacoes['#g'], celulas);
    expect((solicitacoes['#g'] as List).length, lessThanOrEqualTo(9));
    expect(solicitacoes['#t'], ['tcc-ufsc-caronas']);
    expect(solicitacoes['limit'], 50);
  });

  test('o marcador #t está em todos os filtros', () {
    for (final filtro in monta(consumidos, celulas)) {
      expect(filtro['#t'], ['tcc-ufsc-caronas']);
    }
  });

  test('só o 20001 e sem células: nada a pedir', () {
    expect(monta(const [domain.NostrEvent.kindRideRequest], null), isEmpty);
    expect(monta(const [domain.NostrEvent.kindRideRequest], const []), isEmpty);
  });

  test('só o 20001, com células: um filtro com #g', () {
    final filtros = monta(const [domain.NostrEvent.kindRideRequest], celulas);

    expect(filtros, hasLength(1));
    expect(filtros.single['#g'], celulas);
  });

  test('sem o 20001 entre os kinds, as células não criam filtro', () {
    final filtros = monta(const [domain.NostrEvent.kindQuoteAccepted], celulas);

    expect(filtros, hasLength(1));
    expect(filtros.single.containsKey('#g'), isFalse);
  });
}
