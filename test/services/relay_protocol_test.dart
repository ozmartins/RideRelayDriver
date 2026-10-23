import 'dart:convert';

import 'package:driver/domain/nostr_event.dart' as domain;
import 'package:driver/services/relay_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

/// Frames do protocolo montados e interpretados no motorista (feature 028).
/// Tudo função pura: nenhum socket, nenhuma rede. O que vem do relay é entrada
/// não confiável; frame ruim vira `null`, nunca exceção.
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

  group('buildFilters (emenda 27 do contrato)', () {
    test('sem células (offline): um filtro só, sem o 20001', () {
      final filtros = buildFilters(consumidos, null);

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
      final filtros = buildFilters(consumidos, celulas);

      expect(filtros, hasLength(2));
      final outros = filtros.firstWhere((f) => !f.containsKey('#g'));
      final solicitacoes = filtros.firstWhere((f) => f.containsKey('#g'));
      expect(
        outros['kinds'],
        isNot(contains(domain.NostrEvent.kindRideRequest)),
      );
      expect(solicitacoes['kinds'], [domain.NostrEvent.kindRideRequest]);
      expect(solicitacoes['#g'], celulas);
      expect((solicitacoes['#g'] as List).length, lessThanOrEqualTo(9));
      expect(solicitacoes['#t'], ['tcc-ufsc-caronas']);
      expect(solicitacoes['limit'], 50);
    });

    test('o marcador #t e o limit estão em todos os filtros, nunca since', () {
      for (final filtro in buildFilters(consumidos, celulas)) {
        expect(filtro['#t'], ['tcc-ufsc-caronas']);
        expect(filtro['limit'], 50);
        expect(filtro.containsKey('since'), isFalse);
      }
    });

    test('só o 20001 e sem células: nada a pedir', () {
      expect(
        buildFilters(const [domain.NostrEvent.kindRideRequest], null),
        isEmpty,
      );
      expect(
        buildFilters(const [domain.NostrEvent.kindRideRequest], const []),
        isEmpty,
      );
    });

    test('só o 20001, com células: um filtro com #g', () {
      final filtros = buildFilters(const [
        domain.NostrEvent.kindRideRequest,
      ], celulas);

      expect(filtros, hasLength(1));
      expect(filtros.single['#g'], celulas);
    });

    test('sem o 20001 entre os kinds, as células não criam filtro', () {
      final filtros = buildFilters(const [
        domain.NostrEvent.kindQuoteAccepted,
      ], celulas);

      expect(filtros, hasLength(1));
      expect(filtros.single.containsKey('#g'), isFalse);
    });
  });

  group('montagem de frames', () {
    test('REQ leva o id da inscrição e um filtro após o outro', () {
      final filtros = buildFilters(consumidos, celulas);
      final frame = jsonDecode(reqFrame(generalSubscriptionId, filtros));

      expect(frame, ['REQ', 'tcc-geral', ...filtros]);
    });

    test('CLOSE leva só o id da inscrição', () {
      expect(jsonDecode(closeFrame('tcc-solicitacoes')), [
        'CLOSE',
        'tcc-solicitacoes',
      ]);
    });

    test('EVENT leva o payload assinado sem campo a mais', () {
      final payload = <String, dynamic>{
        'id': 'a' * 64,
        'pubkey': 'b' * 64,
        'created_at': 1700000000,
        'kind': 20002,
        'tags': [
          ['t', 'tcc-ufsc-caronas'],
        ],
        'content': 'x',
        'sig': 'c' * 128,
      };

      expect(jsonDecode(eventFrame(payload)), ['EVENT', payload]);
    });

    test('a sonda consulta por um id inexistente e libera a inscrição', () {
      final req = jsonDecode(probeReqFrame()) as List;

      expect(req[0], 'REQ');
      expect(req[1], 'vivacidade');
      expect(req[2], {
        'ids': ['0' * 64],
        'limit': 1,
      });
      expect(jsonDecode(closeFrame(probeSubscriptionId)), [
        'CLOSE',
        'vivacidade',
      ]);
    });
  });

  group('parseRelayFrame — frames válidos', () {
    test('EVENT com id de inscrição e objeto', () {
      final frame = parseRelayFrame(
        jsonEncode([
          'EVENT',
          'tcc-geral',
          {'id': 'abc', 'kind': 20002},
        ]),
      );

      expect(frame, isA<EventFrame>());
      frame as EventFrame;
      expect(frame.subscriptionId, 'tcc-geral');
      expect(frame.payload, {'id': 'abc', 'kind': 20002});
    });

    test('OK aceito, recusado com mensagem e recusado sem mensagem', () {
      final aceito = parseRelayFrame(jsonEncode(['OK', 'id1', true, '']));
      final recusado = parseRelayFrame(
        jsonEncode(['OK', 'id2', false, 'invalid: bad tag']),
      );
      final semMensagem = parseRelayFrame(jsonEncode(['OK', 'id3', false]));

      expect(aceito, isA<OkFrame>());
      expect((aceito as OkFrame).accepted, isTrue);
      expect(aceito.eventId, 'id1');
      expect(aceito.message, isNull);
      expect((recusado as OkFrame).accepted, isFalse);
      expect(recusado.message, 'invalid: bad tag');
      expect((semMensagem as OkFrame).message, isNull);
    });

    test('NOTICE, EOSE e CLOSED', () {
      final notice = parseRelayFrame(jsonEncode(['NOTICE', 'olá']));
      final eose = parseRelayFrame(jsonEncode(['EOSE', 'tcc-geral']));
      final closed = parseRelayFrame(
        jsonEncode(['CLOSED', 'tcc-solicitacoes', 'auth-required: x']),
      );
      final closedSemMensagem = parseRelayFrame(
        jsonEncode(['CLOSED', 'tcc-geral']),
      );

      expect((notice as NoticeFrame).message, 'olá');
      expect((eose as EoseFrame).subscriptionId, 'tcc-geral');
      expect((closed as ClosedFrame).subscriptionId, 'tcc-solicitacoes');
      expect(closed.message, 'auth-required: x');
      expect((closedSemMensagem as ClosedFrame).message, isNull);
    });
  });

  group('parseRelayFrame — frames hostis viram null, sem lançar', () {
    final hostis = <String, String>{
      'texto vazio': '',
      'não é JSON': 'isto não é json',
      'JSON truncado no meio': '["EVENT","tcc-geral",{"id":"ab',
      'raiz objeto': '{"EVENT":1}',
      'raiz número': '42',
      'raiz nula': 'null',
      'lista vazia': '[]',
      'tipo desconhecido': '["AUTH","desafio"]',
      'tipo não é texto': '[1,2,3]',
      'EVENT sem objeto': '["EVENT","tcc-geral"]',
      'EVENT com texto no lugar do objeto': '["EVENT","tcc-geral","x"]',
      'EVENT com lista no lugar do objeto': '["EVENT","tcc-geral",[]]',
      'EVENT com número no lugar do subId': '["EVENT",7,{}]',
      'OK com aceito não booleano': '["OK","id","sim","x"]',
      'OK sem aceito': '["OK","id"]',
      'OK com id numérico': '["OK",5,true,""]',
      'NOTICE sem texto': '["NOTICE"]',
      'NOTICE com número': '["NOTICE",3]',
      'EOSE sem id': '["EOSE"]',
      'CLOSED sem id': '["CLOSED"]',
    };

    for (final entry in hostis.entries) {
      test(entry.key, () {
        expect(() => parseRelayFrame(entry.value), returnsNormally);
        expect(parseRelayFrame(entry.value), isNull);
      });
    }

    String eventoComTamanho(int caracteres) {
      const moldura = '["EVENT","tcc-geral",{"content":""}]';
      final enchimento = 'x' * (caracteres - moldura.length);
      return '["EVENT","tcc-geral",{"content":"$enchimento"}]';
    }

    test('texto com exatamente o limite ainda é aceito se for válido', () {
      final texto = eventoComTamanho(kMaxRelayMessageChars);

      expect(texto.length, kMaxRelayMessageChars);
      expect(parseRelayFrame(texto), isA<EventFrame>());
    });

    test('texto com um caractere além do limite é descartado', () {
      final texto = eventoComTamanho(kMaxRelayMessageChars + 1);

      expect(texto.length, kMaxRelayMessageChars + 1);
      expect(parseRelayFrame(texto), isNull);
    });
  });
}
