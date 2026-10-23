import 'dart:async';
import 'dart:convert';

import 'package:driver/domain/nostr_event.dart' as domain;
import 'package:driver/services/event_feed.dart';
import 'package:driver/services/relay_gateway.dart';
import 'package:driver/services/relay_protocol.dart';
import 'package:driver/services/ws_relay_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_relay_transport.dart';
import '../support/signed_payload.dart';

/// `WsRelayGateway` contra um transporte dublê (feature 028): nenhum socket,
/// nenhuma rede, nenhum relay real (Princípio II).
void main() {
  const a = 'wss://a.test';
  const b = 'wss://b.test';
  const kinds = [
    domain.NostrEvent.kindRideRequest,
    domain.NostrEvent.kindQuoteAccepted,
  ];
  const celulas = ['6fug', '6fue'];
  const outrasCelulas = ['6fus', '6fu7'];

  late FakeRelayTransport transport;
  late WsRelayGateway gateway;

  setUp(() {
    transport = FakeRelayTransport();
    gateway = WsRelayGateway(
      transport: transport,
      connectionTimeout: const Duration(milliseconds: 50),
      publishTimeout: const Duration(milliseconds: 50),
    );
  });

  tearDown(() => gateway.dispose());

  Future<void> pump() => Future<void>.delayed(Duration.zero);

  /// O que o app enviou ao socket, decodificado.
  List<List<dynamic>> enviados(FakeRelaySocket socket) => [
    for (final texto in socket.sent) jsonDecode(texto) as List<dynamic>,
  ];

  List<List<dynamic>> reqs(FakeRelaySocket socket, [String? id]) => [
    for (final f in enviados(socket))
      if (f[0] == 'REQ' && (id == null || f[1] == id)) f,
  ];

  domain.NostrEvent evento(String id) => domain.NostrEvent(
    id: id,
    authorPublicKey: 'a' * 64,
    createdAt: DateTime.utc(2026, 10, 22),
    kind: 20002,
    content: 'oi',
    isSignatureValid: true,
  );

  Map<String, dynamic> payloadDe(String id) => {
    'id': id,
    'pubkey': 'a' * 64,
    'created_at': 1790000000,
    'kind': 20002,
    'tags': [
      ['t', 'tcc-ufsc-caronas'],
    ],
    'content': 'oi',
    'sig': 'c' * 128,
  };

  Future<List<PublishOutcome>> publica(String id) =>
      gateway.publish(evento(id), payload: payloadDe(id)).toList();

  group('conexão', () {
    test('connect registra o relay e abre o socket', () async {
      await gateway.connect(a);

      expect(transport.socketsFor(a), hasLength(1));
      expect(transport.lastSocket(a).closed, isFalse);
      final sonda = gateway.probe(a);
      transport.lastSocket(a).push(jsonEncode(['EOSE', 'vivacidade']));
      await expectLater(sonda, completes);
    });

    test('falha do handshake lança e não registra nada', () async {
      transport.failOn(a, 'recusado');

      await expectLater(gateway.connect(a), throwsA(isA<StateError>()));

      await expectLater(gateway.probe(a), throwsA(isA<StateError>()));
      expect(await publica('1' * 64), isEmpty);
    });

    test(
      'handshake com prazo estourado lança e fecha o socket tardio',
      () async {
        final gate = transport.hold(a);

        await expectLater(gateway.connect(a), throwsA(isA<StateError>()));
        gate.complete();
        await pump();

        expect(transport.lastSocket(a).closed, isTrue);
        await expectLater(gateway.probe(a), throwsA(isA<StateError>()));
      },
    );

    test('disconnect fecha o socket', () async {
      await gateway.connect(a);

      await gateway.disconnect(a);

      expect(transport.lastSocket(a).closed, isTrue);
    });
  });

  group('inscrição', () {
    test('subscribe antes de connect: ao conectar saem os dois REQ', () async {
      gateway.subscribe(kinds: kinds, rideRequestCells: celulas);
      await gateway.connect(a);

      final socket = transport.lastSocket(a);
      final geral = reqs(socket, 'tcc-geral').single;
      final solicitacoes = reqs(socket, 'tcc-solicitacoes').single;
      expect(geral[2], {
        'kinds': [domain.NostrEvent.kindQuoteAccepted],
        '#t': ['tcc-ufsc-caronas'],
        'limit': 50,
      });
      expect(solicitacoes[2], {
        'kinds': [domain.NostrEvent.kindRideRequest],
        '#t': ['tcc-ufsc-caronas'],
        '#g': celulas,
        'limit': 50,
      });
    });

    test('nenhum filtro leva since', () async {
      gateway.subscribe(kinds: kinds, rideRequestCells: celulas);
      await gateway.connect(a);

      for (final req in reqs(transport.lastSocket(a))) {
        expect((req[2] as Map).containsKey('since'), isFalse);
      }
    });

    test('sem células (offline): só a inscrição geral', () async {
      gateway.subscribe(kinds: kinds);
      await gateway.connect(a);

      final socket = transport.lastSocket(a);
      expect(reqs(socket), hasLength(1));
      expect(reqs(socket).single[1], 'tcc-geral');
    });

    test('só o 20001 e sem células: nada é enviado', () async {
      gateway.subscribe(kinds: const [domain.NostrEvent.kindRideRequest]);
      await gateway.connect(a);

      expect(transport.lastSocket(a).sent, isEmpty);
    });

    test('subscribe depois de conectar envia aos relays conectados', () async {
      await gateway.connect(a);
      await gateway.connect(b);

      gateway.subscribe(kinds: kinds, rideRequestCells: celulas);

      expect(reqs(transport.lastSocket(a)), hasLength(2));
      expect(reqs(transport.lastSocket(b)), hasLength(2));
    });

    test('subscribe repetido não duplica o REQ de relay já inscrito', () async {
      gateway.subscribe(kinds: kinds, rideRequestCells: celulas);
      await gateway.connect(a);

      gateway.subscribe(kinds: kinds, rideRequestCells: celulas);

      expect(reqs(transport.lastSocket(a)), hasLength(2));
    });

    test('cada reconexão reinscreve', () async {
      gateway.subscribe(kinds: kinds, rideRequestCells: celulas);
      await gateway.connect(a);
      await gateway.connect(a);

      expect(transport.socketsFor(a), hasLength(2));
      expect(reqs(transport.socketsFor(a).last), hasLength(2));
    });

    test('EVENT de qualquer das duas inscrições vira IncomingEvent', () async {
      final recebidos = <IncomingEvent>[];
      gateway
          .subscribe(kinds: kinds, rideRequestCells: celulas)
          .listen(recebidos.add);
      await gateway.connect(a);
      final socket = transport.lastSocket(a);

      socket.push(jsonEncode(['EVENT', 'tcc-geral', payloadDe('1' * 64)]));
      socket.push(
        jsonEncode(['EVENT', 'tcc-solicitacoes', payloadDe('2' * 64)]),
      );
      await pump();

      expect(recebidos.map((e) => e.relayUrl), [a, a]);
      expect(recebidos.map((e) => e.payload['id']), ['1' * 64, '2' * 64]);
    });
  });

  group('troca de células do 20001', () {
    test('refaz só a inscrição do 20001: CLOSE e REQ novo', () async {
      gateway.subscribe(kinds: kinds, rideRequestCells: celulas);
      await gateway.connect(a);
      final socket = transport.lastSocket(a);
      socket.sent.clear();

      await gateway.setRideRequestCells(outrasCelulas);

      final frames = enviados(socket);
      expect(frames, hasLength(2));
      expect(frames[0], ['CLOSE', 'tcc-solicitacoes']);
      expect(frames[1][0], 'REQ');
      expect(frames[1][1], 'tcc-solicitacoes');
      expect((frames[1][2] as Map)['#g'], outrasCelulas);
      expect(socket.sent.join(), isNot(contains('tcc-geral')));
    });

    test('mesmas células: nada é enviado', () async {
      gateway.subscribe(kinds: kinds, rideRequestCells: celulas);
      await gateway.connect(a);
      final socket = transport.lastSocket(a);
      socket.sent.clear();

      await gateway.setRideRequestCells(celulas.reversed.toList());

      expect(socket.sent, isEmpty);
    });

    test('null (ficou offline): só o CLOSE', () async {
      gateway.subscribe(kinds: kinds, rideRequestCells: celulas);
      await gateway.connect(a);
      final socket = transport.lastSocket(a);
      socket.sent.clear();

      await gateway.setRideRequestCells(null);

      expect(enviados(socket), [
        ['CLOSE', 'tcc-solicitacoes'],
      ]);
    });

    test('de null para células (ficou online): só o REQ', () async {
      gateway.subscribe(kinds: kinds);
      await gateway.connect(a);
      final socket = transport.lastSocket(a);
      socket.sent.clear();

      await gateway.setRideRequestCells(celulas);

      final frames = enviados(socket);
      expect(frames, hasLength(1));
      expect(frames.single[0], 'REQ');
      expect(frames.single[1], 'tcc-solicitacoes');
    });

    test('relay que conecta depois recebe as células vigentes', () async {
      gateway.subscribe(kinds: kinds, rideRequestCells: celulas);
      await gateway.connect(a);
      await gateway.setRideRequestCells(outrasCelulas);

      await gateway.connect(b);

      final solicitacoes = reqs(transport.lastSocket(b), 'tcc-solicitacoes');
      expect((solicitacoes.single[2] as Map)['#g'], outrasCelulas);
    });

    test('antes de assinar, só guarda as células (nada é enviado)', () async {
      await gateway.connect(a);

      await gateway.setRideRequestCells(celulas);

      expect(transport.lastSocket(a).sent, isEmpty);
    });
  });

  group('publicação', () {
    test('envia o payload assinado, intacto, num frame EVENT', () async {
      await gateway.connect(a);
      final socket = transport.lastSocket(a);
      final id = '3' * 64;

      final futuro = publica(id);
      await pump();
      socket.push(jsonEncode(['OK', id, true, '']));
      await futuro;

      expect(socket.sent.single, jsonEncode(['EVENT', payloadDe(id)]));
    });

    test('OK aceito', () async {
      await gateway.connect(a);
      final id = '4' * 64;

      final futuro = publica(id);
      await pump();
      transport.lastSocket(a).push(jsonEncode(['OK', id, true, '']));
      final resultado = (await futuro).single;

      expect(resultado.relayUrl, a);
      expect(resultado.accepted, isTrue);
      expect(resultado.message, isNull);
    });

    test('OK recusado traz a mensagem do relay', () async {
      await gateway.connect(a);
      final id = '5' * 64;

      final futuro = publica(id);
      await pump();
      transport
          .lastSocket(a)
          .push(jsonEncode(['OK', id, false, 'payment-required: pague']));
      final resultado = (await futuro).single;

      expect(resultado.accepted, isFalse);
      expect(resultado.message, 'payment-required: pague');
    });

    test('OK recusado sem mensagem: mensagem nula', () async {
      await gateway.connect(a);
      final id = '6' * 64;

      final futuro = publica(id);
      await pump();
      transport.lastSocket(a).push(jsonEncode(['OK', id, false, '']));

      expect((await futuro).single.message, isNull);
    });

    test('um resultado por relay, e o stream fecha ao fim', () async {
      await gateway.connect(a);
      await gateway.connect(b);
      final id = '7' * 64;

      final futuro = publica(id);
      await pump();
      transport.lastSocket(a).push(jsonEncode(['OK', id, true, '']));
      transport.lastSocket(b).push(jsonEncode(['OK', id, false, 'blocked']));
      final resultados = await futuro;

      expect(
        {for (final r in resultados) r.relayUrl: r.accepted},
        {a: true, b: false},
      );
    });

    test('relay que não responde: recusado por prazo', () async {
      await gateway.connect(a);

      final resultado = (await publica('8' * 64)).single;

      expect(resultado.accepted, isFalse);
      expect(resultado.message, 'sem resposta do relay');
    });

    test('socket que lança no envio: recusado com o motivo', () async {
      await gateway.connect(a);
      transport.lastSocket(a).sendError = StateError('socket morto');

      final resultado = (await publica('9' * 64)).single;

      expect(resultado.accepted, isFalse);
      expect(resultado.message, 'socket morto');
    });

    test('OK de outro id é ignorado e a publicação segue pendente', () async {
      await gateway.connect(a);
      final id = 'a' * 64;

      final futuro = publica(id);
      await pump();
      transport.lastSocket(a).push(jsonEncode(['OK', 'b' * 64, true, '']));
      final resultado = (await futuro).single;

      expect(resultado.accepted, isFalse);
      expect(resultado.message, 'sem resposta do relay');
    });

    test('nenhum relay conectado: o stream fecha vazio', () async {
      expect(await publica('c' * 64), isEmpty);
    });
  });

  group('queda de conexão', () {
    test(
      'fim do socket estabelecido emite connectionLost uma única vez',
      () async {
        final perdidas = <String>[];
        gateway.connectionLost.listen(perdidas.add);
        await gateway.connect(a);

        await transport.lastSocket(a).closeFromRelay();
        await pump();
        await pump();

        expect(perdidas, [a]);
      },
    );

    test(
      'erro do socket estabelecido emite connectionLost uma única vez',
      () async {
        final perdidas = <String>[];
        gateway.connectionLost.listen(perdidas.add);
        await gateway.connect(a);

        await transport.lastSocket(a).failFromRelay();
        await pump();
        await pump();

        expect(perdidas, [a]);
      },
    );

    test(
      'depois da queda o relay não aceita mais sonda nem publicação',
      () async {
        await gateway.connect(a);

        await transport.lastSocket(a).closeFromRelay();
        await pump();

        await expectLater(gateway.probe(a), throwsA(isA<StateError>()));
        expect(await publica('d' * 64), isEmpty);
      },
    );

    test('desconexão pedida não emite connectionLost', () async {
      final perdidas = <String>[];
      gateway.connectionLost.listen(perdidas.add);
      await gateway.connect(a);

      await gateway.disconnect(a);
      await pump();
      await pump();

      expect(perdidas, isEmpty);
    });

    test(
      'falha de handshake e prazo estourado não emitem connectionLost',
      () async {
        final perdidas = <String>[];
        gateway.connectionLost.listen(perdidas.add);
        transport.failOn(a);
        await expectLater(gateway.connect(a), throwsA(isA<StateError>()));
        transport.clearFailure(a);
        transport.hold(a);
        await expectLater(gateway.connect(a), throwsA(isA<StateError>()));
        await pump();

        expect(perdidas, isEmpty);
      },
    );

    test(
      'queda atrasada de socket substituído não derruba a conexão vigente',
      () async {
        final perdidas = <String>[];
        gateway.connectionLost.listen(perdidas.add);
        await gateway.connect(a);
        final antigo = transport.lastSocket(a);
        await gateway.connect(a);
        await pump();

        await antigo.closeFromRelay();
        await pump();
        await pump();

        expect(perdidas, isEmpty);
        final sonda = gateway.probe(a);
        transport.lastSocket(a).push(jsonEncode(['EOSE', 'vivacidade']));
        await expectLater(sonda, completes);
        expect(transport.lastSocket(a).closed, isFalse);
      },
    );

    test('reconectar depois da queda reinscreve', () async {
      gateway.subscribe(kinds: kinds, rideRequestCells: celulas);
      await gateway.connect(a);
      await transport.lastSocket(a).closeFromRelay();
      await pump();
      await pump();

      await gateway.connect(a);

      expect(reqs(transport.lastSocket(a)), hasLength(2));
    });
  });

  group('guarda de tentativa de conexão', () {
    test(
      'disconnect durante o handshake: o socket que chega é fechado',
      () async {
        final gate = transport.hold(a);
        final tentativa = gateway.connect(a);
        final falha = expectLater(
          tentativa,
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              'conexão cancelada',
            ),
          ),
        );
        await pump();

        await gateway.disconnect(a);
        gate.complete();
        await falha;

        expect(transport.lastSocket(a).closed, isTrue);
        await expectLater(gateway.probe(a), throwsA(isA<StateError>()));
      },
    );

    test(
      'nova connect durante o handshake: a antiga fecha o próprio socket',
      () async {
        final gate = transport.hold(a);
        final primeira = gateway.connect(a);
        final falha = expectLater(primeira, throwsA(isA<StateError>()));
        await pump();

        final segunda = gateway.connect(a);
        gate.complete();
        await falha;
        await segunda;

        final sockets = transport.socketsFor(a);
        // A primeira tentativa encontra a vigência trocada e fecha o próprio
        // socket; a segunda fica registrada. A ordem de criação não importa.
        expect(sockets, hasLength(2));
        expect(sockets.where((x) => x.closed), hasLength(1));
        final aberto = sockets.firstWhere((x) => !x.closed);
        final sonda = gateway.probe(a);
        aberto.push(jsonEncode(['EOSE', 'vivacidade']));
        await expectLater(sonda, completes);
      },
    );
  });

  group('sonda de vivacidade', () {
    test('envia REQ por um id inexistente e CLOSE em seguida', () async {
      await gateway.connect(a);
      final socket = transport.lastSocket(a);

      unawaited(gateway.probe(a).then((_) {}, onError: (Object _) {}));

      final frames = enviados(socket);
      expect(frames[0][0], 'REQ');
      expect(frames[0][1], 'vivacidade');
      expect(frames[0][2], {
        'ids': ['0' * 64],
        'limit': 1,
      });
      expect(frames[1], ['CLOSE', 'vivacidade']);
    });

    for (final mensagem in {
      'EOSE': jsonEncode(['EOSE', 'vivacidade']),
      'NOTICE': jsonEncode(['NOTICE', 'olá']),
      'texto que nem é JSON': 'lixo',
    }.entries) {
      test(
        'completa com qualquer mensagem do relay (${mensagem.key})',
        () async {
          await gateway.connect(a);
          final sonda = gateway.probe(a);

          transport.lastSocket(a).push(mensagem.value);

          await expectLater(sonda, completes);
        },
      );
    }

    test('sem conexão falha na hora', () async {
      await expectLater(gateway.probe(a), throwsA(isA<StateError>()));
    });

    test('sem resposta não completa (o prazo é do chamador)', () async {
      await gateway.connect(a);
      var completou = false;
      unawaited(
        gateway.probe(a).then((_) => completou = true, onError: (Object _) {}),
      );

      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(completou, isFalse);
    });

    test('disconnect com sonda pendente a completa com erro', () async {
      await gateway.connect(a);
      final sonda = gateway.probe(a);
      final falha = expectLater(sonda, throwsA(isA<StateError>()));

      await gateway.disconnect(a);

      await falha;
    });

    test('duas sondas simultâneas completam juntas', () async {
      await gateway.connect(a);
      final primeira = gateway.probe(a);
      final segunda = gateway.probe(a);

      transport.lastSocket(a).push(jsonEncode(['EOSE', 'vivacidade']));

      await expectLater(Future.wait([primeira, segunda]), completes);
    });
  });

  group('frames hostis não derrubam a conexão', () {
    late FakeRelaySocket socket;
    late List<IncomingEvent> recebidos;
    late List<String> perdidas;

    setUp(() async {
      recebidos = [];
      perdidas = [];
      gateway.connectionLost.listen(perdidas.add);
      gateway
          .subscribe(kinds: kinds, rideRequestCells: celulas)
          .listen(recebidos.add);
      await gateway.connect(a);
      socket = transport.lastSocket(a);
    });

    String eventoValido(String id) =>
        jsonEncode(['EVENT', 'tcc-geral', payloadDe(id)]);

    final hostis = <String, String Function()>{
      'EVENT malformado (sem objeto)': () => '["EVENT","tcc-geral"]',
      'EVENT truncado': () => '["EVENT","tcc-geral",{"id":"abc',
      'texto acima do limite': () =>
          '["EVENT","tcc-geral",{"content":"${'x' * kMaxRelayMessageChars}"}]',
      'EVENT de inscrição desconhecida': () =>
          jsonEncode(['EVENT', 'outra', payloadDe('1' * 64)]),
      'tipo desconhecido': () => '["AUTH","desafio"]',
      'lixo não JSON': () => 'lixo',
      'lista vazia': () => '[]',
    };

    for (final entry in hostis.entries) {
      test(entry.key, () async {
        socket.push(entry.value());
        await pump();
        socket.push(eventoValido('2' * 64));
        await pump();

        expect(recebidos.map((e) => e.payload['id']), ['2' * 64]);
        expect(perdidas, isEmpty);
        expect(socket.closed, isFalse);
      });
    }

    test(
      'OK false com tag mal formada: recusa com a mensagem, conexão viva',
      () async {
        final id = 'e' * 64;
        final futuro = publica(id);
        await pump();
        socket.push(jsonEncode(['OK', id, false, 'invalid: bad tag']));
        final resultado = (await futuro).single;

        expect(resultado.accepted, isFalse);
        expect(resultado.message, 'invalid: bad tag');
        expect(perdidas, isEmpty);
        expect(socket.closed, isFalse);
        socket.push(eventoValido('3' * 64));
        await pump();
        expect(recebidos, hasLength(1));
      },
    );

    test(
      'CLOSED da inscrição do 20001: nada cai e nada é reenviado sozinho',
      () async {
        socket.sent.clear();

        socket.push(
          jsonEncode(['CLOSED', 'tcc-solicitacoes', 'invalid: bad tag']),
        );
        await pump();

        expect(socket.sent, isEmpty);
        expect(perdidas, isEmpty);
        expect(socket.closed, isFalse);
        socket.push(eventoValido('4' * 64));
        await pump();
        expect(recebidos, hasLength(1));
      },
    );

    test(
      'depois de CLOSED, a próxima troca de células reabre o 20001',
      () async {
        socket.push(jsonEncode(['CLOSED', 'tcc-solicitacoes', 'x']));
        await pump();
        socket.sent.clear();

        await gateway.setRideRequestCells(outrasCelulas);

        final frames = enviados(socket);
        expect(frames, hasLength(1));
        expect(frames.single[0], 'REQ');
        expect(frames.single[1], 'tcc-solicitacoes');
      },
    );

    test('NOTICE é ignorado', () async {
      socket.push(jsonEncode(['NOTICE', 'rate limited']));
      await pump();

      expect(recebidos, isEmpty);
      expect(perdidas, isEmpty);
    });

    test('OK de id desconhecido ou repetido é ignorado', () async {
      socket.push(jsonEncode(['OK', 'f' * 64, true, '']));
      socket.push(jsonEncode(['OK', 'f' * 64, true, '']));
      await pump();

      expect(perdidas, isEmpty);
      expect(socket.closed, isFalse);
    });
  });

  group('a verificação continua a jusante (FR-013)', () {
    test(
      'assinatura adulterada chega bruta e o EventFeed a descarta',
      () async {
        final incoming = gateway.subscribe(
          kinds: const [domain.NostrEvent.kindRideRequest],
          rideRequestCells: celulas,
        );
        final feed = EventFeed(incoming: incoming);
        addTearDown(feed.dispose);
        await gateway.connect(a);
        final socket = transport.lastSocket(a);

        final valido = signedPayload();
        final adulterado = signedPayload()..['sig'] = 'f' * 128;
        socket.push(jsonEncode(['EVENT', 'tcc-solicitacoes', adulterado]));
        socket.push(jsonEncode(['EVENT', 'tcc-solicitacoes', valido]));
        await pumpEventQueue();

        expect(feed.discardedInvalidCount, 1);
        expect(feed.events.map((e) => e.id), [valido['id']]);
      },
    );
  });
}
