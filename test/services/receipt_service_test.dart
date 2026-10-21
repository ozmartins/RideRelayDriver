import 'dart:convert';

import 'package:driver/domain/active_ride.dart';
import 'package:driver/domain/identity.dart';
import 'package:driver/domain/nostr_event.dart';
import 'package:driver/domain/receipt.dart';
import 'package:driver/domain/reputation.dart';
import 'package:driver/services/identity_service.dart';
import 'package:driver/services/message_cipher.dart';
import 'package:driver/services/prototype_marker.dart';
import 'package:driver/services/receipt_service.dart';
import 'package:driver/services/receipt_signature.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/in_memory_receipt_store.dart';
import '../support/receipt_fixtures.dart';
import 'identity_service_test.dart' show InMemoryKeyStore;

/// Evento montado à mão, para os casos que o `IdentityService` não produziria
/// (conteúdo em claro, tags trocadas, autor diferente do avaliador). A
/// assinatura do evento já foi verificada pelo `EventFeed`, antes do serviço.
NostrEvent _evento({
  required Identity autor,
  required int kind,
  required String content,
  required List<List<String>> tags,
}) => NostrEvent(
  id: fakeGuid(DateTime.now().microsecondsSinceEpoch % 100000),
  authorPublicKey: autor.publicKey,
  createdAt: DateTime.now(),
  kind: kind,
  content: content,
  isSignatureValid: true,
  tags: tags,
);

List<List<String>> _tags(String guid, String para) => [
  prototypeMarkerTag,
  ['e', guid],
  ['p', para],
];

void main() {
  late Identity motorista;
  late Identity passageiro;
  late IdentityService servicoDoMotorista;
  late IdentityService servicoDoPassageiro;
  late InMemoryReceiptStore store;
  late List<SignedEvent> publicados;
  late bool relayAceita;
  Identity? identidadeAtual;
  late ReceiptService service;

  setUp(() async {
    servicoDoMotorista = IdentityService(InMemoryKeyStore());
    servicoDoPassageiro = IdentityService(InMemoryKeyStore());
    motorista = await servicoDoMotorista.loadOrCreate();
    passageiro = await servicoDoPassageiro.loadOrCreate();
    identidadeAtual = motorista;
    store = InMemoryReceiptStore();
    publicados = [];
    relayAceita = true;
    service = ReceiptService(
      store: store,
      identityService: servicoDoMotorista,
      identity: () => identidadeAtual,
      publish: (e) async {
        publicados.add(e);
        return relayAceita;
      },
    );
  });

  /// Recibo do passageiro para o motorista, assinado por ele.
  Receipt recibo({
    Identity? de,
    String? para,
    int seq = 0,
    int? nota = 5,
    String? guid,
  }) => signedReceipt(
    avaliador: de ?? passageiro,
    avaliado: para ?? motorista.publicKey,
    seq: seq,
    nota: nota,
    guid: guid ?? fakeGuid(1),
  );

  NostrEvent eventoDe(Receipt r, {Identity? autor}) =>
      (autor == null
              ? servicoDoPassageiro.signReceipt(
                  identity: passageiro,
                  receipt: r,
                )
              : IdentityService(InMemoryKeyStore())
                    .signReceipt(identity: autor, receipt: r))
          .event;

  group('ReceiptService.onReceiptEvent', () {
    test('recibo válido: grava e confirma com 20015 ao avaliador', () async {
      final r = recibo();

      await service.onReceiptEvent(eventoDe(r));

      expect(await store.receivedFor(r.guidCorrida), r);
      expect((await store.myReputation()).corridas, 1);
      expect(publicados, hasLength(1));
      final ack = publicados.single.event;
      expect(ack.kind, NostrEvent.kindReceiptAck);
      expect(ack.referencedEventId, r.guidCorrida);
      expect(ack.recipientPublicKey, passageiro.publicKey);
      final texto = MessageCipher().decryptFrom(
        passageiro,
        motorista.publicKey,
        ack.content,
      )!;
      expect(jsonDecode(texto), {'id_recibo': r.idRecibo});
    });

    test(
      'assinatura de outra chave: ignorado, nada gravado nem publicado',
      () async {
        final base = Receipt.unsigned(
          guidCorrida: fakeGuid(1),
          pubkeyAvaliador: passageiro.publicKey,
          pubkeyAvaliado: motorista.publicKey,
          nota: 5,
          criadoEm: 1760000000,
          seq: 0,
        );
        final forjado = base.withSignature(
          ReceiptSignature.sign(base, newTestIdentity()),
        );

        await service.onReceiptEvent(eventoDe(forjado));

        expect((await store.myReputation()).corridas, 0);
        expect(publicados, isEmpty);
      },
    );

    test('campo adulterado depois de assinado: ignorado', () async {
      final r = recibo(nota: 5);
      final adulterado = Receipt(
        v: r.v,
        guidCorrida: r.guidCorrida,
        pubkeyAvaliador: r.pubkeyAvaliador,
        pubkeyAvaliado: r.pubkeyAvaliado,
        nota: 1,
        criadoEm: r.criadoEm,
        seq: r.seq,
        hashAnterior: r.hashAnterior,
        idRecibo: r.idRecibo,
        assinatura: r.assinatura,
      );

      await service.onReceiptEvent(eventoDe(adulterado));

      expect((await store.myReputation()).corridas, 0);
      expect(publicados, isEmpty);
    });

    test(
      'recibo cujo avaliado não sou eu (tag p é a minha): ignorado',
      () async {
        final outro = newTestIdentity();
        final r = recibo(para: outro.publicKey);
        final evento = _evento(
          autor: passageiro,
          kind: NostrEvent.kindReceipt,
          content: MessageCipher().encryptFor(
            passageiro,
            motorista.publicKey,
            jsonEncode(r.toJson()),
          ),
          tags: _tags(r.guidCorrida, motorista.publicKey),
        );

        await service.onReceiptEvent(evento);

        expect((await store.myReputation()).corridas, 0);
        expect(publicados, isEmpty);
      },
    );

    test('avaliador diferente do autor do evento: ignorado', () async {
      final r = recibo(); // assinado pelo passageiro…
      final intruso = newTestIdentity(); // …mas entregue por outro autor
      final evento = _evento(
        autor: intruso,
        kind: NostrEvent.kindReceipt,
        content: MessageCipher().encryptFor(
          intruso,
          motorista.publicKey,
          jsonEncode(r.toJson()),
        ),
        tags: _tags(r.guidCorrida, motorista.publicKey),
      );

      await service.onReceiptEvent(evento);

      expect((await store.myReputation()).corridas, 0);
      expect(publicados, isEmpty);
    });

    test('guid_corrida diferente da tag e: ignorado', () async {
      final r = recibo();
      final evento = _evento(
        autor: passageiro,
        kind: NostrEvent.kindReceipt,
        content: MessageCipher().encryptFor(
          passageiro,
          motorista.publicKey,
          jsonEncode(r.toJson()),
        ),
        tags: _tags(fakeGuid(999), motorista.publicKey),
      );

      await service.onReceiptEvent(evento);

      expect((await store.myReputation()).corridas, 0);
      expect(publicados, isEmpty);
    });

    test('tag p que não é a própria chave: ignorado', () async {
      final r = recibo();
      final outro = newTestIdentity();
      final evento = _evento(
        autor: passageiro,
        kind: NostrEvent.kindReceipt,
        content: MessageCipher().encryptFor(
          passageiro,
          outro.publicKey,
          jsonEncode(r.toJson()),
        ),
        tags: _tags(r.guidCorrida, outro.publicKey),
      );

      await service.onReceiptEvent(evento);

      expect((await store.myReputation()).corridas, 0);
      expect(publicados, isEmpty);
    });

    test('20014 em claro é descartado', () async {
      final r = recibo();
      final evento = _evento(
        autor: passageiro,
        kind: NostrEvent.kindReceipt,
        content: jsonEncode(r.toJson()),
        tags: _tags(r.guidCorrida, motorista.publicKey),
      );

      await service.onReceiptEvent(evento);

      expect((await store.myReputation()).corridas, 0);
      expect(publicados, isEmpty);
    });

    test('conteúdo cifrado que não é um recibo: ignorado sem lançar', () async {
      final evento = _evento(
        autor: passageiro,
        kind: NostrEvent.kindReceipt,
        content: MessageCipher().encryptFor(
          passageiro,
          motorista.publicKey,
          '{"qualquer":"coisa"}',
        ),
        tags: _tags(fakeGuid(1), motorista.publicKey),
      );

      await service.onReceiptEvent(evento);

      expect((await store.myReputation()).corridas, 0);
      expect(publicados, isEmpty);
    });

    test(
      'duplicado idêntico: só reenvia a confirmação, sem regravar',
      () async {
        final r = recibo();
        await service.onReceiptEvent(eventoDe(r));
        await service.onReceiptEvent(eventoDe(r));

        expect((await store.myReputation()).corridas, 1);
        expect(store.log.where((l) => l == 'saveReceived'), hasLength(1));
        expect(publicados, hasLength(2));
        for (final p in publicados) {
          expect(p.event.kind, NostrEvent.kindReceiptAck);
        }
      },
    );

    test(
      'duplicado diferente para a mesma corrida: ignorado, sem confirmação',
      () async {
        final primeiro = recibo(nota: 5);
        final segundo = recibo(nota: 1); // mesma corrida, outro conteúdo
        await service.onReceiptEvent(eventoDe(primeiro));
        publicados.clear();

        await service.onReceiptEvent(eventoDe(segundo));

        expect(await store.receivedFor(primeiro.guidCorrida), primeiro);
        expect((await store.myReputation()).media, 5.0);
        expect(publicados, isEmpty);
      },
    );

    test('sem identidade: ignorado', () async {
      identidadeAtual = null;
      await service.onReceiptEvent(eventoDe(recibo()));
      expect(publicados, isEmpty);
    });

    test('recibo de kind errado é ignorado', () async {
      final r = recibo();
      final e = eventoDe(r);
      final errado = NostrEvent(
        id: e.id,
        authorPublicKey: e.authorPublicKey,
        createdAt: e.createdAt,
        kind: NostrEvent.kindRideCancelledByPassenger,
        content: e.content,
        isSignatureValid: true,
        tags: e.tags,
      );
      await service.onReceiptEvent(errado);
      expect((await store.myReputation()).corridas, 0);
    });

    test(
      'falha ao publicar a confirmação não desfaz o recibo gravado',
      () async {
        relayAceita = false;
        final r = recibo();

        await service.onReceiptEvent(eventoDe(r));

        expect(await store.receivedFor(r.guidCorrida), r);
      },
    );

    test('exceção ao publicar a confirmação é absorvida', () async {
      final falho = ReceiptService(
        store: store,
        identityService: servicoDoMotorista,
        identity: () => motorista,
        publish: (_) async => throw StateError('sem relay'),
      );
      final r = recibo();

      await falho.onReceiptEvent(eventoDe(r));

      expect(await store.receivedFor(r.guidCorrida), r);
    });
  });

  group('ReceiptService.onAckEvent', () {
    late Receipt emitido;

    setUp(() async {
      emitido = signedReceipt(
        avaliador: motorista,
        avaliado: passageiro.publicKey,
        seq: 0,
        nota: 4,
        guid: fakeGuid(7),
      );
      await store.saveIssued(emitido);
    });

    NostrEvent ack({
      Identity? autor,
      String? guid,
      String? idRecibo,
      String? avaliador,
    }) => IdentityService(InMemoryKeyStore())
        .signReceiptAck(
          identity: autor ?? passageiro,
          guid: guid ?? emitido.guidCorrida,
          idRecibo: idRecibo ?? emitido.idRecibo,
          avaliadorPubkey: avaliador ?? motorista.publicKey,
        )
        .event;

    test(
      'confirmação do avaliado, com o id do recibo: marca confirmado',
      () async {
        await service.onAckEvent(ack());
        expect(await store.pendingIssued(), isEmpty);
      },
    );

    test(
      'autor diferente do avaliado: ignorada, o recibo segue pendente',
      () async {
        await service.onAckEvent(ack(autor: newTestIdentity()));
        expect(await store.pendingIssued(), [emitido]);
      },
    );

    test('id_recibo que não confere: ignorada', () async {
      await service.onAckEvent(ack(idRecibo: fakeGuid(404)));
      expect(await store.pendingIssued(), [emitido]);
    });

    test('corrida (tag e) diferente da do recibo: ignorada', () async {
      await service.onAckEvent(ack(guid: fakeGuid(8)));
      expect(await store.pendingIssued(), [emitido]);
    });

    test('endereçada a outra chave (tag p): ignorada', () async {
      await service.onAckEvent(ack(avaliador: newTestIdentity().publicKey));
      expect(await store.pendingIssued(), [emitido]);
    });

    test('em claro: ignorada', () async {
      final claro = _evento(
        autor: passageiro,
        kind: NostrEvent.kindReceiptAck,
        content: jsonEncode({'id_recibo': emitido.idRecibo}),
        tags: _tags(emitido.guidCorrida, motorista.publicKey),
      );
      await service.onAckEvent(claro);
      expect(await store.pendingIssued(), [emitido]);
    });

    test('conteúdo cifrado sem id_recibo: ignorada sem lançar', () async {
      final ruim = _evento(
        autor: passageiro,
        kind: NostrEvent.kindReceiptAck,
        content: MessageCipher().encryptFor(
          passageiro,
          motorista.publicKey,
          '{"outro":1}',
        ),
        tags: _tags(emitido.guidCorrida, motorista.publicKey),
      );
      await service.onAckEvent(ruim);
      expect(await store.pendingIssued(), [emitido]);
    });

    test('sem identidade: ignorada', () async {
      identidadeAtual = null;
      await service.onAckEvent(ack());
      expect(await store.pendingIssued(), [emitido]);
    });
  });

  group('ReceiptService.issueFor (1.7)', () {
    ActiveRide corrida() => ActiveRide(
      quoteId: fakeGuid(70),
      passengerPubkey: passageiro.publicKey,
      originLat: -28.9,
      originLon: -49.4,
      destinationLat: -28.6,
      destinationLon: -49.3,
    );

    /// Reputação declarada do passageiro com [n] recibos encadeados.
    Reputation declarada(int n) {
      final cadeia = signedChain(
        avaliado: passageiro.publicKey,
        notas: List.filled(n, 4),
      );
      return Reputation(
        corridas: n,
        avaliacoes: n,
        media: 4.0,
        seqProximo: n,
        head: cadeia.last.idRecibo,
        recibos: cadeia.reversed.toList(),
      );
    }

    Receipt? reciboPublicado(SignedEvent e) {
      final texto = MessageCipher().decryptFrom(
        passageiro,
        motorista.publicKey,
        e.event.content,
      );
      return texto == null ? null : Receipt.fromJson(jsonDecode(texto));
    }

    test(
      'emite com seq e hash_anterior vindos da reputação declarada',
      () async {
        final rep = declarada(2);
        await store.saveDeclared(corrida().quoteId, passageiro.publicKey, rep);

        final resultado = await service.issueFor(corrida(), 5);

        expect(resultado, ReceiptIssue.issued);
        final emitido = (await store.pendingIssued()).single;
        expect(emitido.seq, 2);
        expect(emitido.hashAnterior, rep.head);
        expect(emitido.nota, 5);
        expect(emitido.guidCorrida, corrida().quoteId);
        expect(emitido.pubkeyAvaliador, motorista.publicKey);
        expect(emitido.pubkeyAvaliado, passageiro.publicKey);
        expect(emitido.v, 1);
        expect(ReceiptSignature.verify(emitido), isTrue);

        expect(publicados, hasLength(1));
        expect(publicados.single.event.kind, NostrEvent.kindReceipt);
        expect(
          publicados.single.event.recipientPublicKey,
          passageiro.publicKey,
        );
        expect(publicados.single.event.referencedEventId, corrida().quoteId);
        expect(reciboPublicado(publicados.single), emitido);
      },
    );

    test('sem nota (pular a avaliação): o recibo omite a nota', () async {
      await store.saveDeclared(
        corrida().quoteId,
        passageiro.publicKey,
        declarada(1),
      );

      await service.issueFor(corrida(), null);

      final emitido = (await store.pendingIssued()).single;
      expect(emitido.nota, isNull);
      expect(emitido.toJson().containsKey('nota'), isFalse);
      expect(ReceiptSignature.verify(emitido), isTrue);
    });

    test(
      'passageiro sem histórico (reputação vazia): seq 0, sem hash',
      () async {
        await store.saveDeclared(
          corrida().quoteId,
          passageiro.publicKey,
          const Reputation.empty(),
        );

        await service.issueFor(corrida(), 3);

        final emitido = (await store.pendingIssued()).single;
        expect(emitido.seq, 0);
        expect(emitido.hashAnterior, isNull);
      },
    );

    test('corrida sem registro da reputação: não emite', () async {
      final resultado = await service.issueFor(corrida(), 5);

      expect(resultado, ReceiptIssue.skipped);
      expect(await store.pendingIssued(), isEmpty);
      expect(publicados, isEmpty);
    });

    test('reputação inconsistente: não emite e não publica', () async {
      final rep = declarada(2);
      final inconsistente = Reputation(
        corridas: rep.corridas,
        avaliacoes: rep.avaliacoes,
        media: rep.media,
        seqProximo: rep.seqProximo,
        head: fakeGuid(12345), // não é o recibo de seq 1
        recibos: rep.recibos,
      );
      await store.saveDeclared(
        corrida().quoteId,
        passageiro.publicKey,
        inconsistente,
      );

      final resultado = await service.issueFor(corrida(), 5);

      expect(resultado, ReceiptIssue.inconsistent);
      expect(await store.pendingIssued(), isEmpty);
      expect(await store.issuedFor(corrida().quoteId), isNull);
      expect(publicados, isEmpty);
    });

    test('grava como pendente antes de publicar', () async {
      await store.saveDeclared(
        corrida().quoteId,
        passageiro.publicKey,
        declarada(1),
      );
      var pendentesNaPublicacao = -1;
      final conferindo = ReceiptService(
        store: store,
        identityService: servicoDoMotorista,
        identity: () => motorista,
        publish: (_) async {
          pendentesNaPublicacao = (await store.pendingIssued()).length;
          return true;
        },
      );

      await conferindo.issueFor(corrida(), 5);

      expect(pendentesNaPublicacao, 1);
    });

    test('falha ao publicar: o recibo fica pendente e nada lança', () async {
      relayAceita = false;
      await store.saveDeclared(
        corrida().quoteId,
        passageiro.publicKey,
        declarada(1),
      );
      final falho = ReceiptService(
        store: store,
        identityService: servicoDoMotorista,
        identity: () => motorista,
        publish: (_) async => throw StateError('sem relay'),
      );

      final resultado = await falho.issueFor(corrida(), 5);

      expect(resultado, ReceiptIssue.issued);
      expect(await store.pendingIssued(), hasLength(1));
    });

    test(
      'segunda chamada para a mesma corrida não emite outro recibo',
      () async {
        await store.saveDeclared(
          corrida().quoteId,
          passageiro.publicKey,
          declarada(1),
        );
        await service.issueFor(corrida(), 5);

        final resultado = await service.issueFor(corrida(), 1);

        expect(resultado, ReceiptIssue.alreadyIssued);
        expect(publicados, hasLength(1));
        expect((await store.pendingIssued()).single.nota, 5);
      },
    );

    test('sem identidade: não emite', () async {
      await store.saveDeclared(
        corrida().quoteId,
        passageiro.publicKey,
        declarada(1),
      );
      identidadeAtual = null;

      expect(await service.issueFor(corrida(), 5), ReceiptIssue.skipped);
      expect(publicados, isEmpty);
    });

    test('a chave privada não vai ao recibo, ao evento nem ao store', () async {
      await store.saveDeclared(
        corrida().quoteId,
        passageiro.publicKey,
        declarada(1),
      );
      await service.issueFor(corrida(), 5);

      final emitido = (await store.pendingIssued()).single;
      expect(
        jsonEncode(emitido.toJson()),
        isNot(contains(motorista.privateKey)),
      );
      expect(
        publicados.single.event.content,
        isNot(contains(motorista.privateKey)),
      );
      expect(
        jsonEncode(publicados.single.payload),
        isNot(contains(motorista.privateKey)),
      );
    });
  });

  group('ReceiptService.retryPending (1.7 passo 5)', () {
    Future<Receipt> emitirUm() async {
      final r = signedReceipt(
        avaliador: motorista,
        avaliado: passageiro.publicKey,
        seq: 0,
        nota: 5,
        guid: fakeGuid(80),
      );
      await store.saveIssued(r);
      return r;
    }

    test(
      'republica os pendentes como eventos novos com o mesmo recibo',
      () async {
        final r = await emitirUm();

        await service.retryPending();
        await service.retryPending();

        expect(publicados, hasLength(2));
        expect(publicados[0].event.id, isNot(publicados[1].event.id));
        for (final p in publicados) {
          expect(p.event.kind, NostrEvent.kindReceipt);
          final texto = MessageCipher().decryptFrom(
            passageiro,
            motorista.publicKey,
            p.event.content,
          )!;
          expect(Receipt.fromJson(jsonDecode(texto)), r);
        }
      },
    );

    test('para depois da confirmação (20015) correspondente', () async {
      final r = await emitirUm();
      await service.retryPending();
      expect(publicados, hasLength(1));

      final ack = IdentityService(InMemoryKeyStore())
          .signReceiptAck(
            identity: passageiro,
            guid: r.guidCorrida,
            idRecibo: r.idRecibo,
            avaliadorPubkey: motorista.publicKey,
          )
          .event;
      await service.onAckEvent(ack);
      await service.retryPending();

      expect(publicados, hasLength(1));
    });

    test('sem pendentes, ou sem identidade, não publica nada', () async {
      await service.retryPending();
      expect(publicados, isEmpty);

      await emitirUm();
      identidadeAtual = null;
      await service.retryPending();
      expect(publicados, isEmpty);
    });

    test('falha em um recibo não impede o reenvio dos outros', () async {
      await emitirUm();
      final outro = signedReceipt(
        avaliador: motorista,
        avaliado: passageiro.publicKey,
        seq: 1,
        guid: fakeGuid(81),
      );
      await store.saveIssued(outro);
      var chamadas = 0;
      final instavel = ReceiptService(
        store: store,
        identityService: servicoDoMotorista,
        identity: () => motorista,
        publish: (_) async {
          chamadas++;
          if (chamadas == 1) throw StateError('queda');
          return true;
        },
      );

      await instavel.retryPending();

      expect(chamadas, 2);
    });

    testWidgets('o temporizador reenvia a cada 60 s até a confirmação', (
      tester,
    ) async {
      final enviados = <SignedEvent>[];
      final temporizado = ReceiptService(
        store: store,
        identityService: servicoDoMotorista,
        identity: () => motorista,
        publish: (e) async {
          enviados.add(e);
          return true;
        },
      );
      final r = signedReceipt(
        avaliador: motorista,
        avaliado: passageiro.publicKey,
        seq: 0,
        guid: fakeGuid(82),
      );
      await store.saveIssued(r);

      temporizado.start();
      temporizado.start(); // idempotente: um só temporizador
      await tester.pump(const Duration(seconds: 59));
      expect(enviados, isEmpty);

      await tester.pump(const Duration(seconds: 1));
      expect(enviados, hasLength(1));

      await tester.pump(const Duration(seconds: 60));
      expect(enviados, hasLength(2));

      await store.markAcked(r.idRecibo);
      await tester.pump(const Duration(seconds: 120));
      expect(enviados, hasLength(2));

      temporizado.dispose();
    });

    testWidgets('depois do dispose o temporizador não reenvia', (tester) async {
      final enviados = <SignedEvent>[];
      final temporizado = ReceiptService(
        store: store,
        identityService: servicoDoMotorista,
        identity: () => motorista,
        publish: (e) async {
          enviados.add(e);
          return true;
        },
      );
      await store.saveIssued(
        signedReceipt(
          avaliador: motorista,
          avaliado: passageiro.publicKey,
          seq: 0,
          guid: fakeGuid(83),
        ),
      );
      temporizado.start();
      temporizado.dispose();

      await tester.pump(const Duration(minutes: 5));

      expect(enviados, isEmpty);
    });
  });
}
