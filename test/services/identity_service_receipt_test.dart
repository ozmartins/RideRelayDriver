import 'dart:convert';

import 'package:driver/domain/identity.dart';
import 'package:driver/domain/nostr_event.dart';
import 'package:driver/domain/receipt.dart';
import 'package:driver/domain/reputation.dart';
import 'package:driver/domain/ride_quote.dart';
import 'package:driver/services/identity_service.dart';
import 'package:driver/services/message_cipher.dart';
import 'package:driver/services/receipt_signature.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/receipt_fixtures.dart';
import 'identity_service_test.dart' show InMemoryKeyStore;

List<List<String>> _tags(SignedEvent s) => (s.payload['tags'] as List<dynamic>)
    .map((t) => (t as List<dynamic>).map((e) => e.toString()).toList())
    .toList();

String? _decifrarComo(Identity receptor, SignedEvent s) => MessageCipher()
    .decryptFrom(receptor, s.event.authorPublicKey, s.event.content);

void main() {
  group('signReceipt / signReceiptAck (emenda 25)', () {
    test('20014: kind, tags e content cifrado só ao avaliado', () async {
      final service = IdentityService(InMemoryKeyStore());
      final motorista = await service.loadOrCreate();
      final passageiro = newTestIdentity();
      final base = Receipt.unsigned(
        guidCorrida: fakeGuid(1),
        pubkeyAvaliador: motorista.publicKey,
        pubkeyAvaliado: passageiro.publicKey,
        nota: 5,
        criadoEm: 1760000000,
        seq: 0,
      );
      final recibo = base.withSignature(ReceiptSignature.sign(base, motorista));

      final signed = service.signReceipt(identity: motorista, receipt: recibo);

      expect(signed.event.kind, NostrEvent.kindReceipt);
      expect(signed.event.isSignatureValid, isTrue);
      expect(signed.event.authorPublicKey, motorista.publicKey);
      expect(_tags(signed), anyElement(equals(['t', 'tcc-ufsc-caronas'])));
      expect(_tags(signed), anyElement(equals(['e', fakeGuid(1)])));
      expect(_tags(signed), anyElement(equals(['p', passageiro.publicKey])));

      // Cifrado: nada legível em claro, e só o avaliado decifra.
      expect(signed.event.content, isNot(contains('guid_corrida')));
      expect(signed.event.content, isNot(contains(recibo.idRecibo)));
      final texto = _decifrarComo(passageiro, signed)!;
      expect(Receipt.fromJson(jsonDecode(texto)), recibo);
      expect(_decifrarComo(newTestIdentity(), signed), isNull);
    });

    test('20015: content {"id_recibo": …} cifrado ao avaliador', () async {
      final service = IdentityService(InMemoryKeyStore());
      final avaliado = await service.loadOrCreate();
      final avaliador = newTestIdentity();

      final signed = service.signReceiptAck(
        identity: avaliado,
        guid: fakeGuid(1),
        idRecibo: 'ab' * 32,
        avaliadorPubkey: avaliador.publicKey,
      );

      expect(signed.event.kind, NostrEvent.kindReceiptAck);
      expect(signed.event.isSignatureValid, isTrue);
      expect(_tags(signed), anyElement(equals(['e', fakeGuid(1)])));
      expect(_tags(signed), anyElement(equals(['p', avaliador.publicKey])));
      expect(signed.event.content, isNot(contains('id_recibo')));
      expect(jsonDecode(_decifrarComo(avaliador, signed)!), {
        'id_recibo': 'ab' * 32,
      });
      expect(_decifrarComo(newTestIdentity(), signed), isNull);
    });
  });

  group('signRideQuote com reputacao (emenda 25)', () {
    RideQuote quote(Identity passageiro, {Reputation? reputation}) => RideQuote(
      requestId: 'req',
      passengerPubkey: passageiro.publicKey,
      pricePerKm: 2.5,
      total: 10,
      driverName: 'Fulano',
      carBrand: 'Fiat',
      carModel: 'Palio',
      carYear: 2018,
      reputation: reputation,
    );

    test('inclui reputacao quando passada', () async {
      final service = IdentityService(InMemoryKeyStore());
      final motorista = await service.loadOrCreate();
      final passageiro = newTestIdentity();
      final cadeia = signedChain(avaliado: motorista.publicKey, notas: [5, 3]);
      final rep = Reputation(
        corridas: 2,
        avaliacoes: 2,
        media: 4.0,
        seqProximo: 2,
        head: cadeia.last.idRecibo,
        recibos: cadeia.reversed.toList(),
      );

      final signed = service.signRideQuote(
        identity: motorista,
        quote: quote(passageiro, reputation: rep),
      );

      final content = jsonDecode(
        _decifrarComo(passageiro, signed)!,
      ) as Map<String, dynamic>;
      expect(Reputation.fromJson(content['reputacao']), rep);
    });

    test('omite a chave reputacao quando nula, nunca null', () async {
      final service = IdentityService(InMemoryKeyStore());
      final motorista = await service.loadOrCreate();
      final passageiro = newTestIdentity();

      final signed = service.signRideQuote(
        identity: motorista,
        quote: quote(passageiro),
      );

      final content = jsonDecode(
        _decifrarComo(passageiro, signed)!,
      ) as Map<String, dynamic>;
      expect(content.containsKey('reputacao'), isFalse);
    });
  });
}
