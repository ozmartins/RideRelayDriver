import 'dart:convert';
import 'dart:io';

import 'package:dart_nostr/dart_nostr.dart' as nostr;
import 'package:driver/domain/identity.dart';
import 'package:driver/domain/relay.dart';
import 'package:driver/services/background/relay_host_core.dart';
import 'package:driver/services/background/service_state_store.dart';
import 'package:driver/services/consumed_kinds.dart';
import 'package:driver/services/identity_service.dart';
import 'package:driver/services/key_store.dart';
import 'package:driver/services/relay_gateway.dart';
import 'package:driver/services/relay_repository.dart';
import 'package:driver/services/relay_service.dart';
import 'package:driver/services/remote_relay_connection.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_message_channel.dart';
import '../../support/fake_relay_gateway.dart';
import '../../support/fake_ride_request_notifier.dart';
import '../../support/in_memory_key_value_store.dart';

/// Verificação de não vazamento do Princípio I para a feature 025: o serviço em
/// segundo plano nunca vê a chave privada, nem pelo código que ele importa nem
/// pelo que atravessa o canal.
void main() {
  group('Princípio I — o serviço em segundo plano e a chave privada', () {
    test('nenhum arquivo do serviço importa identidade, chaves ou cifra', () {
      final proibidos = RegExp(
        r'''^import\s+['"][^'"]*(identity|key_store|message_cipher|nip44|secure_storage)''',
        multiLine: true,
      );
      final arquivos = [
        ...Directory('lib/services/background').listSync().whereType<File>(),
        File('lib/services/local_ride_request_notifier.dart'),
        File('lib/services/ride_request_notifier.dart'),
      ];

      expect(arquivos, isNotEmpty);
      for (final arquivo in arquivos) {
        final fonte = arquivo.readAsStringSync();
        expect(
          proibidos.hasMatch(fonte),
          isFalse,
          reason: '${arquivo.path} importa algo que toca a chave privada',
        );
      }
    });

    test(
      'o núcleo do serviço não recebe identidade nem armazenamento de chave',
      () {
        final fonte = File('lib/services/background/relay_host_core.dart')
            .readAsStringSync();

        expect(fonte, isNot(contains('Identity')));
        expect(fonte, isNot(contains('KeyStore')));
      },
    );

    test('publicar de ponta a ponta não faz a chave privada cruzar o canal', () async {
      final keys = nostr.Nostr.instance.services.keys.generateKeyPair();
      final identidade = Identity(
        publicKey: keys.public,
        privateKey: keys.private,
      );
      final passageiro = nostr.Nostr.instance.services.keys.generateKeyPair();
      final servico = IdentityService(_MemoryKeyStore());

      final canais = FakeChannelPair();
      final gateway = FakeRelayGateway()
        ..publishOutcomes = const [
          PublishOutcome(relayUrl: 'wss://a.test', accepted: true),
        ];
      final store = InMemoryKeyValueStore();
      await RelayRepository(store).save(const [Relay(url: 'wss://a.test')]);
      final nucleo = RelayHostCore(
        relays: RelayService(gateway),
        channel: canais.service,
        stateStore: ServiceStateStore(store),
        relayRepository: RelayRepository(store),
        notifier: FakeRideRequestNotifier(),
        acceptedKinds: driverConsumedKinds,
      );
      final remota = RemoteRelayConnection(canais.ui);
      addTearDown(() async {
        await nucleo.dispose();
        await remota.dispose();
      });
      await nucleo.start();
      remota.attach(foreground: true);
      await pumpEventQueue();

      // Um aviso cifrado ao passageiro, assinado com a chave do motorista, sai
      // pela interface e atravessa o canal até o serviço publicá-lo.
      final assinado = servico.signRideNoLongerAvailable(
        identity: identidade,
        quoteId: 'a' * 64,
        passengerPubkey: passageiro.public,
      );
      await remota.publish(assinado.event, payload: assinado.payload).toList();
      await pumpEventQueue();

      expect(gateway.published, hasLength(1), reason: 'o evento foi publicado');

      final trafego = [
        ...canais.ui.sent,
        ...canais.service.sent,
      ].map((m) => jsonEncode(m.toMap())).join('\n');
      expect(trafego, isNotEmpty);
      expect(
        trafego.contains(identidade.privateKey),
        isFalse,
        reason: 'a chave privada atravessou o canal entre interface e serviço',
      );
      expect(
        gateway.published
            .map(jsonEncode)
            .join()
            .contains(identidade.privateKey),
        isFalse,
        reason: 'a chave privada foi parar no evento enviado ao relay',
      );
      // O conteúdo foi cifrado ao passageiro antes de cruzar o canal: o
      // serviço só viu texto cifrado.
      expect(assinado.payload['content'], isNot('{}'));
      expect(gateway.published.single['content'], assinado.payload['content']);
    });
  });
}

class _MemoryKeyStore implements KeyStore {
  @override
  Future<String?> read(String key) async => null;

  @override
  Future<void> write(String key, String value) async {}

  @override
  Future<void> delete(String key) async {}
}
