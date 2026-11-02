import 'dart:convert';

import 'package:dart_nostr/dart_nostr.dart' as nostr;
import 'package:driver/services/default_relays.dart';
import 'package:driver/services/event_verifier.dart';
import 'package:driver/services/prototype_marker.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../tool/e2e/src/observador.dart';
import '../../support/fake_relay_transport.dart';
import '../../support/signed_payload.dart';
import 'support/relogio_falso.dart';

String _eventoDe(String inscricao, Map<String, dynamic> payload) =>
    jsonEncode(['EVENT', inscricao, payload]);

void main() {
  late nostr.NostrKeyPairs motorista;
  late nostr.NostrKeyPairs passageiro;
  late Identidades ids;
  late FakeRelayTransport transporte;
  late RelogioFalso relogio;
  late List<EventoObservado> registrados;
  late Observador observador;

  setUp(() async {
    motorista = nostr.Nostr.instance.services.keys.generateKeyPair();
    passageiro = nostr.Nostr.instance.services.keys.generateKeyPair();
    ids = Identidades(
      motorista: motorista.public,
      passageiro: passageiro.public,
    );
    transporte = FakeRelayTransport();
    relogio = RelogioFalso();
    registrados = [];
    observador = Observador(
      transport: transporte,
      verifier: const NostrEventVerifier(),
      identidades: ids,
      relogio: relogio,
      aoRegistrar: registrados.add,
    );
    await observador.iniciar();
  });

  Future<void> enviar(String url, String texto) async {
    transporte.lastSocket(url).push(texto);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }

  Map<String, dynamic> evento({
    required nostr.NostrKeyPairs de,
    required String para,
    int kind = 20002,
  }) => signedPayload(
    kind: kind,
    keyPairs: de,
    content: 'SEGREDO-NAO-PODE-APARECER',
    tags: [
      prototypeMarkerTag,
      ['p', para],
    ],
  );

  test('(a) registra metadados sem o campo content', () async {
    final payload = evento(de: motorista, para: passageiro.public);
    await enviar(
      defaultRelayUrls.first,
      _eventoDe(Observador.idInscricao, payload),
    );

    expect(registrados, hasLength(1));
    final e = registrados.single;
    expect(e.kind, 20002);
    expect(e.id, payload['id']);
    expect(e.createdAt, payload['created_at']);
    expect(e.relay, defaultRelayUrls.first);
    expect(e.autor, 'motorista');
    expect(e.destinatario, 'passageiro');
    final json = jsonEncode(e.toJson());
    expect(json.contains('content'), isFalse);
    expect(json.contains('SEGREDO'), isFalse);
  });

  test('(b) assinatura adulterada é descartada e contada', () async {
    final payload = evento(de: motorista, para: passageiro.public);
    payload['content'] = 'adulterado';
    await enviar(
      defaultRelayUrls.first,
      _eventoDe(Observador.idInscricao, payload),
    );

    expect(registrados, isEmpty);
    expect(observador.invalidosPorRelay[defaultRelayUrls.first], 1);
  });

  test(
    '(c) evento de autor e destinatário fora das identidades não é gravado',
    () async {
      final terceiro = nostr.Nostr.instance.services.keys.generateKeyPair();
      final outro = nostr.Nostr.instance.services.keys.generateKeyPair();
      await enviar(
        defaultRelayUrls.first,
        _eventoDe(
          Observador.idInscricao,
          evento(de: terceiro, para: outro.public),
        ),
      );

      expect(registrados, isEmpty);
      expect(observador.ignorados, 1);
    },
  );

  test('evento sem o marcador do protótipo é descartado', () async {
    final payload = signedPayload(
      kind: 20002,
      keyPairs: motorista,
      tags: [
        ['p', passageiro.public],
      ],
    );
    await enviar(
      defaultRelayUrls.first,
      _eventoDe(Observador.idInscricao, payload),
    );
    expect(registrados, isEmpty);
  });

  test('(d) o mesmo evento nos três relays vira três linhas; repetido no mesmo relay, uma', () async {
    final payload = evento(de: motorista, para: passageiro.public);
    for (final url in defaultRelayUrls) {
      await enviar(url, _eventoDe(Observador.idInscricao, payload));
    }
    await enviar(
      defaultRelayUrls.first,
      _eventoDe(Observador.idInscricao, payload),
    );

    expect(registrados, hasLength(3));
    expect({for (final e in registrados) e.relay}, defaultRelayUrls.toSet());
  });

  test(
    '(e) o REQ tem os dois filtros, kinds 20001–20015, #t e since com margem',
    () async {
      final sent = transporte.lastSocket(defaultRelayUrls.first).sent;
      expect(sent, hasLength(1));
      final req = jsonDecode(sent.single) as List<dynamic>;
      expect(req[0], 'REQ');
      expect(req[1], Observador.idInscricao);
      final f1 = req[2] as Map<String, dynamic>;
      final f2 = req[3] as Map<String, dynamic>;
      expect(f1['authors'], [motorista.public, passageiro.public]);
      expect(f2['#p'], [motorista.public, passageiro.public]);
      for (final f in [f1, f2]) {
        expect(f['kinds'], [for (var k = 20001; k <= 20015; k++) k]);
        expect(f['#t'], [prototypeMarker]);
        final since = f['since'] as int;
        final esperado =
            relogio
                .agora()
                .subtract(const Duration(minutes: 10))
                .millisecondsSinceEpoch ~/
            1000;
        expect(since, esperado);
      }
    },
  );

  test('(f) nunca envia EVENT', () async {
    await enviar(
      defaultRelayUrls.first,
      _eventoDe(
        Observador.idInscricao,
        evento(de: motorista, para: passageiro.public),
      ),
    );
    await observador.parar();
    for (final s in transporte.sockets) {
      for (final enviado in s.sent) {
        expect((jsonDecode(enviado) as List).first, isNot('EVENT'));
      }
    }
  });

  test(
    'pronto só depois do EOSE em cada relay; queda tira o relay dos prontos',
    () async {
      expect(observador.relaysProntos, isEmpty);
      for (final url in defaultRelayUrls) {
        await enviar(url, jsonEncode(['EOSE', Observador.idInscricao]));
      }
      expect(observador.relaysProntos, defaultRelayUrls);

      await transporte.lastSocket(defaultRelayUrls.first).closeFromRelay();
      await Future<void>.delayed(Duration.zero);
      expect(observador.relaysProntos, isNot(contains(defaultRelayUrls.first)));
      expect(observador.todosCaidos, isFalse);

      await observador.garantirConexoes();
      expect(transporte.socketsFor(defaultRelayUrls.first), hasLength(2));
    },
  );

  test('todosCaidos quando nenhum relay conecta', () async {
    final t = FakeRelayTransport();
    for (final u in defaultRelayUrls) {
      t.failOn(u);
    }
    final o = Observador(
      transport: t,
      verifier: const NostrEventVerifier(),
      identidades: ids,
      relogio: relogio,
    );
    await o.iniciar();
    expect(o.todosCaidos, isTrue);
    expect(o.relaysProntos, isEmpty);
  });

  test('consultas: menor instante entre relays, janela e contagem', () async {
    final payload = evento(de: motorista, para: passageiro.public, kind: 20002);
    final antes = relogio.agora();
    relogio.avancar(const Duration(milliseconds: 300));
    await enviar(
      defaultRelayUrls[1],
      _eventoDe(Observador.idInscricao, payload),
    );
    relogio.avancar(const Duration(milliseconds: 200));
    await enviar(
      defaultRelayUrls[0],
      _eventoDe(Observador.idInscricao, payload),
    );

    final primeiro = observador.primeiroEvento(
      kind: 20002,
      autor: 'motorista',
      apos: antes,
    );
    expect(primeiro!.relay, defaultRelayUrls[1]);
    expect(
      observador.vistoEmAlgumRelay(
        kind: 20003,
        autor: 'motorista',
        apos: antes,
      ),
      isFalse,
    );
    expect(observador.naJanela(antes, relogio.agora()), hasLength(2));
    expect(observador.contagemPorRelay()[defaultRelayUrls[1]], 1);
  });
}
