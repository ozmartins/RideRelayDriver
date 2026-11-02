import 'dart:convert';

import 'package:dart_nostr/dart_nostr.dart' as nostr;
import 'package:driver/domain/identity.dart';
import 'package:driver/domain/nostr_event.dart';
import 'package:driver/domain/ride_quote.dart';
import 'package:driver/services/identity_service.dart';
import 'package:driver/services/key_store.dart';
import 'package:driver/services/message_cipher.dart';
import 'package:driver/services/nip44.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

/// Dublê em memória: os testes de identidade rodam sem rede e sem Keystore
/// real (decisão D5).
class InMemoryKeyStore implements KeyStore {
  InMemoryKeyStore([Map<String, String>? initial]) : _values = {...?initial};

  final Map<String, String> _values;
  int writeCount = 0;

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    writeCount++;
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async => _values.remove(key);
}

/// Dublê que falha em toda operação, simulando Keystore indisponível.
class BrokenKeyStore implements KeyStore {
  @override
  Future<String?> read(String key) async =>
      throw KeyStoreUnavailable('sem Keystore');

  @override
  Future<void> write(String key, String value) async =>
      throw KeyStoreUnavailable('sem Keystore');

  @override
  Future<void> delete(String key) async =>
      throw KeyStoreUnavailable('sem Keystore');
}

/// Passageiro de teste: destinatário real, com par de chaves de verdade, já
/// que o `content` agora é cifrado a ele (emenda 17).
final Identity _passageiro = _novaIdentidade();

Identity _novaIdentidade() {
  final par = nostr.Nostr.instance.services.keys.generateKeyPair();
  return Identity(publicKey: par.public, privateKey: par.private);
}

/// Decifra o `content` de [signed] como o passageiro o faria.
String _decifrar(SignedEvent signed, Identity motorista) => MessageCipher()
    .decryptFrom(_passageiro, motorista.publicKey, signed.event.content)!;

void main() {
  group('IdentityService', () {
    test('cria uma identidade na primeira execução', () async {
      final store = InMemoryKeyStore();
      final service = IdentityService(store);

      final identity = await service.loadOrCreate();

      expect(Identity.isValidHexKey(identity.publicKey), isTrue);
      expect(Identity.isValidHexKey(identity.privateKey), isTrue);
      expect(
        store.writeCount,
        1,
        reason: 'a chave deve ser persistida uma vez',
      );
    });

    test('recupera a mesma identidade na segunda execução', () async {
      final store = InMemoryKeyStore();
      final primeira = await IdentityService(store).loadOrCreate();

      final segunda = await IdentityService(store).loadOrCreate();

      expect(segunda.publicKey, primeira.publicKey);
      expect(segunda.privateKey, primeira.privateKey);
      expect(
        store.writeCount,
        1,
        reason: 'não deve regravar identidade existente',
      );
    });

    test(
      'a chave pública é derivada da privada guardada, não guardada solta',
      () async {
        final store = InMemoryKeyStore();
        final identity = await IdentityService(store).loadOrCreate();

        final guardado = await store.read(IdentityService.privateKeyStorageKey);

        expect(guardado, identity.privateKey);
        expect(await store.read('publicKey'), isNull);
      },
    );

    test(
      'trata chave guardada em formato inválido como armazenamento corrompido',
      () async {
        final store = InMemoryKeyStore({
          IdentityService.privateKeyStorageKey: 'nao-e-uma-chave',
        });
        final service = IdentityService(store);

        await expectLater(
          service.loadOrCreate(),
          throwsA(isA<CorruptedIdentityStorage>()),
        );
      },
    );

    test(
      'propaga falha do armazenamento seguro em vez de gerar identidade nova',
      () async {
        final service = IdentityService(BrokenKeyStore());

        await expectLater(
          service.loadOrCreate(),
          throwsA(isA<KeyStoreUnavailable>()),
        );
      },
    );

    group('signRideQuote (feature 007, ampliado pela feature 009)', () {
      test('assina um orçamento com kind, tags e content corretos (incluindo '
          'etaMinutes), assinatura válida', () async {
        final service = IdentityService(InMemoryKeyStore());
        final identity = await service.loadOrCreate();

        final signed = service.signRideQuote(
          identity: identity,
          quote: RideQuote(
            requestId: 'id-da-solicitacao',
            passengerPubkey: _passageiro.publicKey,
            pricePerKm: 2.5,
            total: 18.75,
            driverName: 'Fulano da Silva',
            carBrand: 'Fiat',
            carModel: 'Palio',
            carYear: 2018,
            etaMinutes: 6,
          ),
        );

        expect(signed.event.kind, NostrEvent.kindRideQuote);
        expect(signed.event.isSignatureValid, isTrue);
        expect(signed.event.authorPublicKey, identity.publicKey);

        final tags = (signed.payload['tags'] as List<dynamic>)
            .map((t) => (t as List<dynamic>).map((e) => e.toString()).toList())
            .toList();
        expect(tags, anyElement(equals(['t', 'tcc-ufsc-caronas'])));
        expect(tags, anyElement(equals(['e', 'id-da-solicitacao'])));
        expect(tags, anyElement(equals(['p', _passageiro.publicKey])));

        final content = jsonDecode(_decifrar(signed, identity)) as Map;
        expect(content['pricePerKm'], 2.5);
        expect(content['total'], 18.75);
        expect(content['driverName'], 'Fulano da Silva');
        expect(content['carBrand'], 'Fiat');
        expect(content['carModel'], 'Palio');
        expect(content['carYear'], 2018);
        expect(content['etaMinutes'], 6);
      });

      test('omite a chave etaMinutes quando o RideQuote não a tem (D2 de '
          'specs/009-detalhes-do-orcamento/research.md)', () async {
        final service = IdentityService(InMemoryKeyStore());
        final identity = await service.loadOrCreate();

        final signed = service.signRideQuote(
          identity: identity,
          quote: RideQuote(
            requestId: 'id-da-solicitacao',
            passengerPubkey: _passageiro.publicKey,
            pricePerKm: 2.5,
            total: 18.75,
            driverName: 'Fulano da Silva',
            carBrand: 'Fiat',
            carModel: 'Palio',
            carYear: 2018,
          ),
        );

        final content = jsonDecode(_decifrar(signed, identity)) as Map;
        expect(content.containsKey('etaMinutes'), isFalse);
      });
    });

    group('signDriverLocation (feature 010)', () {
      test('assina uma localização com kind, tags e content corretos, '
          'assinatura válida', () async {
        final service = IdentityService(InMemoryKeyStore());
        final identity = await service.loadOrCreate();

        final signed = service.signDriverLocation(
          identity: identity,
          quoteId: 'id-do-orcamento',
          passengerPubkey: _passageiro.publicKey,
          lat: -28.9312,
          lon: -49.4889,
        );

        expect(signed.event.kind, NostrEvent.kindDriverLocation);
        expect(signed.event.isSignatureValid, isTrue);
        expect(signed.event.authorPublicKey, identity.publicKey);

        final tags = (signed.payload['tags'] as List<dynamic>)
            .map((t) => (t as List<dynamic>).map((e) => e.toString()).toList())
            .toList();
        expect(tags, anyElement(equals(['t', 'tcc-ufsc-caronas'])));
        expect(tags, anyElement(equals(['e', 'id-do-orcamento'])));
        expect(tags, anyElement(equals(['p', _passageiro.publicKey])));

        final content = jsonDecode(_decifrar(signed, identity)) as Map;
        expect(content['lat'], -28.9312);
        expect(content['lon'], -49.4889);
      });
    });

    group('signRideNoLongerAvailable (feature 010)', () {
      test('assina o aviso com kind, tags corretas e content vazio, '
          'assinatura válida', () async {
        final service = IdentityService(InMemoryKeyStore());
        final identity = await service.loadOrCreate();

        final signed = service.signRideNoLongerAvailable(
          identity: identity,
          quoteId: 'id-do-orcamento',
          passengerPubkey: _passageiro.publicKey,
        );

        expect(signed.event.kind, NostrEvent.kindRideNoLongerAvailable);
        expect(signed.event.isSignatureValid, isTrue);
        expect(signed.event.authorPublicKey, identity.publicKey);
        expect(_decifrar(signed, identity), '{}');
        expect(signed.event.content, isNot(''));

        final tags = (signed.payload['tags'] as List<dynamic>)
            .map((t) => (t as List<dynamic>).map((e) => e.toString()).toList())
            .toList();
        expect(tags, anyElement(equals(['t', 'tcc-ufsc-caronas'])));
        expect(tags, anyElement(equals(['e', 'id-do-orcamento'])));
        expect(tags, anyElement(equals(['p', _passageiro.publicKey])));
      });
    });

    group('signArrivalNotice (feature 011)', () {
      test('assina o aviso de chegada com kind, tags corretas e content '
          'vazio, assinatura válida', () async {
        final service = IdentityService(InMemoryKeyStore());
        final identity = await service.loadOrCreate();

        final signed = service.signArrivalNotice(
          identity: identity,
          quoteId: 'id-do-orcamento',
          passengerPubkey: _passageiro.publicKey,
        );

        expect(signed.event.kind, NostrEvent.kindArrivalNotice);
        expect(signed.event.isSignatureValid, isTrue);
        expect(signed.event.authorPublicKey, identity.publicKey);
        expect(_decifrar(signed, identity), '{}');
        expect(signed.event.content, isNot(''));

        final tags = (signed.payload['tags'] as List<dynamic>)
            .map((t) => (t as List<dynamic>).map((e) => e.toString()).toList())
            .toList();
        expect(tags, anyElement(equals(['t', 'tcc-ufsc-caronas'])));
        expect(tags, anyElement(equals(['e', 'id-do-orcamento'])));
        expect(tags, anyElement(equals(['p', _passageiro.publicKey])));
      });
    });

    group('signDestinationArrival (feature 012)', () {
      test('assina o aviso de chegada ao destino com kind, tags corretas e '
          'content vazio, assinatura válida', () async {
        final service = IdentityService(InMemoryKeyStore());
        final identity = await service.loadOrCreate();

        final signed = service.signDestinationArrival(
          identity: identity,
          quoteId: 'id-do-orcamento',
          passengerPubkey: _passageiro.publicKey,
        );

        expect(signed.event.kind, NostrEvent.kindDestinationArrival);
        expect(signed.event.isSignatureValid, isTrue);
        expect(signed.event.authorPublicKey, identity.publicKey);
        expect(_decifrar(signed, identity), '{}');
        expect(signed.event.content, isNot(''));

        final tags = (signed.payload['tags'] as List<dynamic>)
            .map((t) => (t as List<dynamic>).map((e) => e.toString()).toList())
            .toList();
        expect(tags, anyElement(equals(['t', 'tcc-ufsc-caronas'])));
        expect(tags, anyElement(equals(['e', 'id-do-orcamento'])));
        expect(tags, anyElement(equals(['p', _passageiro.publicKey])));
      });
    });

    group('signRideCancelled (feature 018)', () {
      test('assina o cancelamento com kind 20012, tags corretas, content vazio '
          'e assinatura válida', () async {
        final service = IdentityService(InMemoryKeyStore());
        final identity = await service.loadOrCreate();

        final signed = service.signRideCancelled(
          identity: identity,
          quoteId: 'id-do-orcamento',
          passengerPubkey: _passageiro.publicKey,
        );

        expect(signed.event.kind, NostrEvent.kindRideCancelled);
        expect(signed.event.kind, 20012);
        expect(signed.event.isSignatureValid, isTrue);
        expect(signed.event.authorPublicKey, identity.publicKey);
        expect(_decifrar(signed, identity), '{}');
        expect(signed.event.content, isNot(''));

        final tags = (signed.payload['tags'] as List<dynamic>)
            .map((t) => (t as List<dynamic>).map((e) => e.toString()).toList())
            .toList();
        expect(tags, anyElement(equals(['t', 'tcc-ufsc-caronas'])));
        expect(tags, anyElement(equals(['e', 'id-do-orcamento'])));
        expect(tags, anyElement(equals(['p', _passageiro.publicKey])));
      });
    });

    group('signRideRoute (feature 017)', () {
      test('assina a rota com kind 20011, tags corretas, pontos no content e '
          'assinatura válida', () async {
        final service = IdentityService(InMemoryKeyStore());
        final identity = await service.loadOrCreate();

        final signed = service.signRideRoute(
          identity: identity,
          quoteId: 'id-do-orcamento',
          passengerPubkey: _passageiro.publicKey,
          points: const [LatLng(-28.9, -49.4), LatLng(-28.8, -49.3)],
        );

        expect(signed.event.kind, NostrEvent.kindRideRoute);
        expect(signed.event.kind, 20011);
        expect(signed.event.isSignatureValid, isTrue);
        expect(signed.event.authorPublicKey, identity.publicKey);
        expect(jsonDecode(_decifrar(signed, identity)), {
          'points': [
            [-28.9, -49.4],
            [-28.8, -49.3],
          ],
        });

        final tags = (signed.payload['tags'] as List<dynamic>)
            .map((t) => (t as List<dynamic>).map((e) => e.toString()).toList())
            .toList();
        expect(tags, anyElement(equals(['t', 'tcc-ufsc-caronas'])));
        expect(tags, anyElement(equals(['e', 'id-do-orcamento'])));
        expect(tags, anyElement(equals(['p', _passageiro.publicKey])));
      });
    });
  });
  group('conteúdo cifrado (feature 019, emenda 17)', () {
    late Identity motorista;
    late IdentityService service;
    final terceiro = _novaIdentidade();

    setUp(() async {
      service = IdentityService(InMemoryKeyStore());
      motorista = await service.loadOrCreate();
    });

    RideQuote orcamento() => RideQuote(
      requestId: 'id-da-solicitacao',
      passengerPubkey: _passageiro.publicKey,
      pricePerKm: 2.5,
      total: 18.75,
      driverName: 'Fulano da Silva',
      carBrand: 'Fiat',
      carModel: 'Palio',
      carYear: 2018,
      etaMinutes: 6,
    );

    Map<String, SignedEvent Function()> publicados() => {
      'signRideQuote': () =>
          service.signRideQuote(identity: motorista, quote: orcamento()),
      'signDriverLocation': () => service.signDriverLocation(
        identity: motorista,
        quoteId: 'q',
        passengerPubkey: _passageiro.publicKey,
        lat: -28.9312,
        lon: -49.4889,
      ),
      'signRideNoLongerAvailable': () => service.signRideNoLongerAvailable(
        identity: motorista,
        quoteId: 'q',
        passengerPubkey: _passageiro.publicKey,
      ),
      'signArrivalNotice': () => service.signArrivalNotice(
        identity: motorista,
        quoteId: 'q',
        passengerPubkey: _passageiro.publicKey,
      ),
      'signDestinationArrival': () => service.signDestinationArrival(
        identity: motorista,
        quoteId: 'q',
        passengerPubkey: _passageiro.publicKey,
      ),
      'signRideRoute': () => service.signRideRoute(
        identity: motorista,
        quoteId: 'q',
        passengerPubkey: _passageiro.publicKey,
        points: const [
          LatLng(-28.93123, -49.48891),
          LatLng(-28.9314, -49.4887),
        ],
      ),
      'signRideCancelled': () => service.signRideCancelled(
        identity: motorista,
        quoteId: 'q',
        passengerPubkey: _passageiro.publicKey,
      ),
    };

    test('o content sai opaco: nenhum dado em claro', () {
      for (final entry in publicados().entries) {
        final content = entry.value().event.content;
        // base64 não tem `{` nem `"`: nenhum JSON em claro.
        expect(
          content,
          isNot(anyOf(contains('{'), contains('"'))),
          reason: entry.key,
        );
        expect(
          () => jsonDecode(content),
          throwsFormatException,
          reason: entry.key,
        );
        expect(
          () => base64.decode(content),
          returnsNormally,
          reason: entry.key,
        );
      }
    });

    test('só o passageiro destinatário decifra; um terceiro não', () {
      for (final entry in publicados().entries) {
        final content = entry.value().event.content;
        expect(
          MessageCipher().decryptFrom(
            _passageiro,
            motorista.publicKey,
            content,
          ),
          isNotNull,
          reason: entry.key,
        );
        expect(
          MessageCipher().decryptFrom(terceiro, motorista.publicKey, content),
          isNull,
          reason: entry.key,
        );
      }
    });

    test('a assinatura é válida sobre o content cifrado e as tags ficam em '
        'claro', () {
      for (final entry in publicados().entries) {
        final signed = entry.value();
        expect(signed.event.isSignatureValid, isTrue, reason: entry.key);
        expect(signed.payload['content'], signed.event.content);
        final tags = (signed.payload['tags'] as List<dynamic>)
            .map((t) => (t as List<dynamic>).map((e) => e.toString()).toList())
            .toList();
        expect(tags, anyElement(equals(['t', 'tcc-ufsc-caronas'])));
        expect(
          tags,
          anyElement(equals(['p', _passageiro.publicKey])),
          reason: entry.key,
        );
      }
    });

    test('destinatário malformado: nada é assinado em claro (FR-004)', () {
      expect(
        () => service.signRideCancelled(
          identity: motorista,
          quoteId: 'q',
          passengerPubkey: 'pubkey-do-passageiro',
        ),
        throwsA(isA<Nip44Exception>()),
      );
      expect(
        () => service.signRideQuote(
          identity: motorista,
          quote: RideQuote(
            requestId: 'id',
            passengerPubkey: 'pubkey-do-passageiro',
            pricePerKm: 1,
            total: 1,
            driverName: 'F',
            carBrand: 'B',
            carModel: 'M',
            carYear: 2020,
          ),
        ),
        throwsA(isA<Nip44Exception>()),
      );
    });
  });
  group('decryptContent (feature 019, emenda 17)', () {
    late Identity motorista;
    late IdentityService service;
    final cifra = MessageCipher();

    setUp(() async {
      service = IdentityService(InMemoryKeyStore());
      motorista = await service.loadOrCreate();
    });

    NostrEvent recebido({
      required String content,
      String? p,
      Identity? autor,
    }) => NostrEvent(
      id: 'id',
      authorPublicKey: (autor ?? _passageiro).publicKey,
      createdAt: DateTime(2026, 10, 6),
      kind: NostrEvent.kindMeetingConfirmed,
      content: content,
      isSignatureValid: true,
      tags: [
        ['t', 'tcc-ufsc-caronas'],
        ['e', 'q'],
        ['p', p ?? motorista.publicKey],
      ],
    );

    String cifrado(String texto, {Identity? de, Identity? para}) => cifra
        .encryptFor(de ?? _passageiro, (para ?? motorista).publicKey, texto);

    test('cifrado ao motorista, decifra para o texto original', () {
      final evento = recebido(content: cifrado('{"a":1}'));

      expect(
        service.decryptContent(identity: motorista, event: evento),
        '{"a":1}',
      );
    });

    test('kind sem dado próprio: aceita só o marcador {}', () {
      final ok = recebido(content: cifrado(''));
      final outro = recebido(content: cifrado('{"a":1}'));

      expect(
        service.decryptContent(
          identity: motorista,
          event: ok,
          emptyMarker: true,
        ),
        '{}',
      );
      expect(
        service.decryptContent(
          identity: motorista,
          event: outro,
          emptyMarker: true,
        ),
        isNull,
      );
    });

    test('tag p de outro destinatário: null, sem tentar decifrar', () {
      final outro = _novaIdentidade();
      final evento = recebido(
        content: cifrado('{}', para: outro),
        p: outro.publicKey,
      );

      expect(
        service.decryptContent(identity: motorista, event: evento),
        isNull,
      );
    });

    test('tag p é a do motorista mas o conteúdo foi cifrado a outra chave', () {
      final evento = recebido(content: cifrado('{}', para: _novaIdentidade()));

      expect(
        service.decryptContent(identity: motorista, event: evento),
        isNull,
      );
    });

    test('conteúdo em claro: null', () {
      expect(
        service.decryptContent(
          identity: motorista,
          event: recebido(content: '{}'),
        ),
        isNull,
      );
    });

    test('MAC adulterado: null', () {
      final bytes = base64.decode(cifrado('{}'))..[60] ^= 0x01;

      expect(
        service.decryptContent(
          identity: motorista,
          event: recebido(content: base64.encode(bytes)),
        ),
        isNull,
      );
    });

    test('sem tag p: null', () {
      final semP = NostrEvent(
        id: 'id',
        authorPublicKey: _passageiro.publicKey,
        createdAt: DateTime(2026, 10, 6),
        kind: NostrEvent.kindMeetingConfirmed,
        content: cifrado('{}'),
        isSignatureValid: true,
        tags: const [
          ['e', 'q'],
        ],
      );

      expect(service.decryptContent(identity: motorista, event: semP), isNull);
    });
  });
}
