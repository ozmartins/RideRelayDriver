import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:driver/domain/nostr_event.dart' as domain;
import 'package:driver/services/event_feed.dart';
import 'package:driver/services/flow_log.dart';
import 'package:driver/services/flow_log_file.dart';
import 'package:driver/services/relay_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/memory_flow_log.dart';
import 'event_feed_test.dart' show signedPayload;

void main() {
  final id = 'a' * 64;

  group('FlowLine', () {
    test('aceita só os campos do contrato, na forma esperada', () {
      final l = FlowLine.build(
        t: 5,
        papel: 'motorista',
        exec: 'e1',
        iso: 'ui',
        comp: 'relay',
        op: 'evento.publicou',
        res: 'ok',
        kind: 20001,
        id: id,
        relay: 'wss://relay.damus.io',
        guid: id,
        motivo: 'raio',
        ext: 'ors',
        n: 3,
      );
      expect(l['id'], id);
      expect(l['relay'], 'wss://relay.damus.io');
      expect(l['ext'], 'ors');
      expect(l['kind'], 20001);
    });

    test(
      'omite valores plantados fora do formato (chave, texto, URL com segredo)',
      () {
        const chavePrivada =
            'nsec1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq';
        final l = FlowLine.build(
          t: 5,
          papel: 'motorista',
          exec: 'e1',
          iso: 'ui',
          comp: 'relay',
          op: 'evento.publicou',
          res: 'ok',
          id: 'Rua das Flores, 123',
          relay: 'wss://user:senha@relay.exemplo.com/?key=SEGREDO',
          guid: chavePrivada,
          motivo: '-27.59,-48.54 raio 12',
          ext: 'chave-ors-123',
        );
        final texto = jsonEncode(l);
        for (final proibido in [
          chavePrivada,
          'Rua das Flores',
          'senha',
          'SEGREDO',
          '-27.59',
          'chave-ors',
        ]) {
          expect(texto, isNot(contains(proibido)));
        }
        expect(l.containsKey('id'), isFalse);
        expect(l.containsKey('relay'), isFalse);
        expect(l.containsKey('motivo'), isFalse);
      },
    );

    test('nome inválido de op vira "invalido" sem vazar o valor', () {
      final l = FlowLine.build(
        t: 1,
        papel: 'motorista',
        exec: 'e',
        iso: 'ui',
        comp: 'x',
        op: 'conteúdo secreto',
        res: 'ok',
      );
      expect(l['op'], 'invalido');
    });
  });

  group('EventFeed com log', () {
    test('registra recebido e descartes sem jamais gravar o content', () async {
      final incoming = StreamController<IncomingEvent>.broadcast();
      final log = MemoryFlowLog();
      final feed = EventFeed(
        incoming: incoming.stream,
        acceptedKinds: const {domain.NostrEvent.kindRideRequest},
        log: log,
      );
      addTearDown(() async {
        await feed.dispose();
        await incoming.close();
      });

      const segredo = 'SEGREDO-NO-CONTENT-Rua-X';
      final bom = signedPayload(
        content: segredo,
        tags: [
          ['t', 'tcc-ufsc-caronas'],
        ],
      );
      final adulterado = {...signedPayload(content: segredo), 'content': 'x'};
      final semMarcador = signedPayload(content: segredo, tags: []);

      void emit(Map<String, dynamic> p) => incoming.add(
        IncomingEvent(relayUrl: 'wss://relay.damus.io', payload: p),
      );
      emit(bom);
      emit(bom);
      emit(adulterado);
      emit(semMarcador);
      await Future<void>.delayed(Duration.zero);

      expect(log.ops, [
        'evento.recebeu',
        'evento.descartou',
        'evento.descartou',
        'evento.descartou',
      ]);
      expect(
        [for (final l in log.linhas) l['motivo']],
        [null, 'duplicado', 'assinatura', 'marcador'],
      );
      expect(log.linhas.first['id'], bom['id']);
      expect(log.linhas.first['relay'], 'wss://relay.damus.io');
      expect(log.texto, isNot(contains(segredo)));
    });
  });

  group('FileFlowLog', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('flowlog'));
    tearDown(() => dir.deleteSync(recursive: true));

    test(
      'grava JSON Lines, inclusive o que veio antes de o diretório abrir',
      () async {
        final log = FileFlowLog(
          papel: 'motorista',
          iso: 'servico',
          exec: 'e1',
          diretorio: () async => dir.path,
          now: () => DateTime.utc(2026, 11, 3),
        );
        log.registrar(comp: 'app', op: 'app.inicio');
        await log.gravado;
        log.registrar(comp: 'relay', op: 'relay.conectou', res: FlowLog.ok);

        final linhas = File('${dir.path}/fluxo-servico.jsonl')
            .readAsLinesSync();
        expect(linhas, hasLength(2));
        final primeira = jsonDecode(linhas.first) as Map<String, dynamic>;
        expect(primeira['op'], 'app.inicio');
        expect(primeira['exec'], 'e1');
        expect(primeira['iso'], 'servico');
        expect(primeira['t'], DateTime.utc(2026, 11, 3).millisecondsSinceEpoch);
      },
    );

    test('rotaciona ao passar do teto e registra a rotação', () async {
      final log = FileFlowLog(
        papel: 'motorista',
        iso: 'ui',
        diretorio: () async => dir.path,
        maxBytes: 300,
      );
      await log.gravado;
      for (var i = 0; i < 20; i++) {
        log.registrar(comp: 'relay', op: 'relay.conectou');
      }
      expect(File('${dir.path}/fluxo-ui.jsonl.1').existsSync(), isTrue);
      final atual = File('${dir.path}/fluxo-ui.jsonl').readAsLinesSync();
      expect(
        atual.any((l) => (jsonDecode(l) as Map)['op'] == 'log.rotacao'),
        isTrue,
      );
    });

    test('falha de diretório não lança nem afeta o chamador', () async {
      final log = FileFlowLog(
        papel: 'motorista',
        iso: 'ui',
        diretorio: () async => throw StateError('sem disco'),
      );
      log.registrar(comp: 'app', op: 'app.inicio');
      await log.gravado;
      log.registrar(comp: 'app', op: 'app.inicio');
    });
  });
}
