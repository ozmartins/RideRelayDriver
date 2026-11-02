import 'dart:async';
import 'dart:convert';

import 'package:dart_nostr/dart_nostr.dart' as nostr;
import 'package:driver/domain/active_ride.dart';
import 'package:driver/domain/driver_position.dart';
import 'package:driver/domain/driver_profile.dart';
import 'package:driver/domain/driver_ride_status.dart';
import 'package:driver/domain/geohash.dart';
import 'package:driver/domain/identity.dart';
import 'package:driver/domain/nostr_event.dart';
import 'package:driver/domain/payment_method.dart';
import 'package:driver/domain/receipt.dart';
import 'package:driver/domain/relay.dart';
import 'package:driver/domain/reputation.dart';
import 'package:driver/domain/ride_rating.dart';
import 'package:driver/screens/identidade_visual.dart';
import 'package:driver/screens/map_screen.dart';
import 'package:driver/domain/service_state.dart';
import 'package:driver/services/background/service_controller.dart';
import 'package:driver/services/background/service_messages.dart';
import 'package:driver/services/event_feed.dart';
import 'package:driver/services/remote_relay_connection.dart';
import 'package:driver/services/identity_service.dart';
import 'package:driver/services/message_cipher.dart';
import 'package:driver/services/key_store.dart';
import 'package:driver/services/location_service.dart';
import 'package:driver/services/prototype_marker.dart';
import 'package:driver/services/cadastro_store.dart';
import 'package:driver/services/receipt_service.dart';
import 'package:driver/services/relay_gateway.dart';
import 'package:driver/services/relay_service.dart';
import 'package:driver/services/ride_rating_store.dart';
import 'package:driver/services/ride_state_store.dart';
import 'package:driver/services/reverse_geocoding_service.dart';
import 'package:driver/services/route_distance_service.dart';
import 'package:driver/services/sent_quotes_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import '../support/signed_payload.dart';
import '../support/fake_background_service.dart';
import '../support/fake_cadastro_store.dart';
import '../support/in_memory_receipt_store.dart';
import '../support/receipt_fixtures.dart';
import '../support/fake_message_channel.dart';
import '../support/fake_route_distance_service.dart';

/// Dublê em memória: nenhum teste deste arquivo toca sensor real nem rede
/// para mosaicos de mapa (decisão D1/D2 da feature 004, Princípio III).
class FakeLocationService implements LocationService {
  FakeLocationService({this.permissionError});

  Object? permissionError;

  final _controller = StreamController<DriverPosition>.broadcast();

  @override
  Stream<DriverPosition> get positions => _controller.stream;

  @override
  Future<void> ensurePermission() async {
    final erro = permissionError;
    if (erro != null) throw erro;
  }

  void emitir(DriverPosition posicao) => _controller.add(posicao);

  void emitirErro(Object erro) => _controller.addError(erro);
}

DriverPosition posicaoDeTeste() => DriverPosition(
  latitude: -28.935,
  longitude: -49.49,
  capturedAt: DateTime.now(),
);

/// Dublê de transporte de relay (feature 007) — nenhum teste toca rede real.
class FakeGateway implements RelayGateway {
  final _events = StreamController<IncomingEvent>.broadcast();
  final publicados = <NostrEvent>[];

  /// Verdadeiro por padrão: cada relay conectado aceita a publicação
  /// (mesmo padrão de sucesso já usado nos outros dublês deste app).
  var aceitarPublicacoes = true;

  final _lost = StreamController<String>.broadcast();

  /// Tentativas de conexão por url (a inicial conta como a primeira).
  final tentativas = <String, int>{};

  @override
  Stream<String> get connectionLost => _lost.stream;

  /// Simula a conexão com [relayUrl] caindo depois de estabelecida.
  void derrubar(String relayUrl) => _lost.add(relayUrl);

  @override
  Future<void> connect(String relayUrl) async {
    tentativas.update(relayUrl, (n) => n + 1, ifAbsent: () => 1);
  }

  @override
  Future<void> disconnect(String relayUrl) async {}

  @override
  Future<void> probe(String relayUrl) async {}

  @override
  Stream<IncomingEvent> subscribe({
    required List<int> kinds,
    List<String>? rideRequestCells,
  }) => _events.stream;

  /// Cada chamada de [setRideRequestCells], em ordem (feature 027).
  final celulasPedidas = <List<String>?>[];

  @override
  Future<void> setRideRequestCells(List<String>? cells) async =>
      celulasPedidas.add(cells);

  @override
  Stream<PublishOutcome> publish(
    NostrEvent event, {
    required Map<String, dynamic> payload,
  }) {
    publicados.add(event);
    return Stream.value(
      PublishOutcome(relayUrl: 'wss://a.test', accepted: aceitarPublicacoes),
    );
  }

  void emitir(IncomingEvent evento) => _events.add(evento);
}

/// Dublê em memória de `RideStateStore` (feature 010) — permite pré-carregar
/// um estado, simulando um reinício do app com corrida já em andamento.
class InMemoryRideStateStore implements RideStateStore {
  InMemoryRideStateStore({
    this.status = DriverRideStatus.aguardandoSolicitacao,
    this.active,
  });

  DriverRideStatus status;
  ActiveRide? active;
  int saveCount = 0;

  @override
  Future<(DriverRideStatus, ActiveRide?)> load() async => (status, active);

  @override
  Future<void> save(DriverRideStatus status, ActiveRide? active) async {
    saveCount++;
    this.status = status;
    this.active = active;
  }
}

/// Dublê em memória de `RideRatingStore` (feature 013) — nenhum teste toca
/// SQLite real.
class InMemoryRideRatingStore implements RideRatingStore {
  final salvos = <RideRating>[];

  @override
  Future<void> save(RideRating rating, Identity identity) async =>
      salvos.add(rating);

  @override
  Future<RideRating?> forRide(String rideId, Identity identity) async {
    for (final rating in salvos.reversed) {
      if (rating.rideId == rideId) return rating;
    }
    return null;
  }
}

/// `RideRatingStore` que só termina de gravar quando [liberar] completa — para
/// provar que o recibo espera a nota local ser gravada.
class _RatingLento extends InMemoryRideRatingStore {
  _RatingLento(this.liberar);

  final Future<void> liberar;

  @override
  Future<void> save(RideRating rating, Identity identity) async {
    await liberar;
    await super.save(rating, identity);
  }
}

/// Origem padrão usada pelos dublês desta suíte quando o teste não precisa
/// controlar a distância até ela — mesma coordenada default de
/// [solicitacaoAssinada].
const _origemPadrao = (-28.9298, -49.4753);

/// Origem padrão usada pelos dublês desta suíte quando o teste não precisa
/// controlar a distância até ele — mesma coordenada default de
/// [solicitacaoAssinada].
const _destinoPadrao = (-28.6721, -49.3671);

/// Dublê em memória de `SentQuotesStore` (feature 010, ampliado pela
/// feature 011 com a origem, e pela feature 012 com o destino de cada
/// orçamento) — `initial`/`initialDestinations` simulam orçamentos já
/// enviados antes do reinício do app (achado C1 do `/speckit-analyze` da
/// feature 010).
class InMemorySentQuotesStore implements SentQuotesStore {
  InMemorySentQuotesStore({
    Map<String, (double, double)>? initial,
    Map<String, (double, double)>? initialDestinations,
  }) : _origins = {...?initial},
       _destinations = {...?initialDestinations};

  final Map<String, (double, double)> _origins;
  final Map<String, (double, double)> _destinations;

  @override
  Future<void> add(
    String quoteId, {
    required double originLat,
    required double originLon,
    required double destinationLat,
    required double destinationLon,
  }) async {
    _origins[quoteId] = (originLat, originLon);
    _destinations[quoteId] = (destinationLat, destinationLon);
  }

  @override
  Future<bool> contains(String quoteId) async => _origins.containsKey(quoteId);

  @override
  Future<(double lat, double lon)?> originFor(String quoteId) async =>
      _origins[quoteId];

  @override
  Future<(double lat, double lon)?> destinationFor(String quoteId) async =>
      _destinations[quoteId];
}

/// Dublê de geocodificação reversa (feature 015): sempre falha, o que faz a
/// modal manter latitude e longitude — nenhum teste toca a Photon real.
class FakeReverseGeocodingService implements ReverseGeocodingService {
  @override
  Future<String> addressOf(LatLng point) =>
      Future.error(const ReverseGeocodingFailure('dublê'));
}

Identity identidadeDeTeste() {
  final par = nostr.Nostr.instance.services.keys.generateKeyPair();
  return Identity(publicKey: par.public, privateKey: par.private);
}

/// Motorista de teste: identidade padrão do `MapScreen` montado pelos testes
/// e destinatário padrão dos eventos que o passageiro "publica" (emenda 17: o
/// `content` chega cifrado a ele).
final Identity motoristaDeTeste = identidadeDeTeste();

/// Passageiro de teste com par de chaves de verdade: o `content` publicado
/// pelo motorista é cifrado a ele (emenda 17), então a chave precisa ser válida.
final Identity passageiroDeTeste = identidadeDeTeste();

/// Decifra o `content` de um evento publicado pelo motorista, como o
/// passageiro de teste o faria.
String? decifradoPeloPassageiro(NostrEvent evento) => MessageCipher()
    .decryptFrom(passageiroDeTeste, evento.authorPublicKey, evento.content);

DriverProfile perfilComPreco(double precoPorKm) => DriverProfile(
  nome: 'Fulano da Silva',
  uf: 'SC',
  cidade: 'Araranguá',
  marcaVeiculo: 'Fiat',
  modeloVeiculo: 'Palio',
  corVeiculo: 'Preto',
  placaVeiculo: 'ABC1234',
  paymentMethods: {...PaymentMethod.values},
  precoPorKm: precoPorKm,
  anoVeiculo: 2018,
);

/// Monta um payload de `kind: 20001` já assinado — a mesma solicitação de
/// corrida que o passageiro publicaria (emenda 04 do contrato).
Map<String, dynamic> solicitacaoAssinada({
  double originLat = -28.9298,
  double originLon = -49.4753,
  double destLat = -28.6721,
  double destLon = -49.3671,
  String payment = 'pix',
  Identity? autor,
  Object? reputacao,
  List<List<String>>? tags,
}) {
  final keys = autor == null
      ? nostr.Nostr.instance.services.keys.generateKeyPair()
      : nostr.NostrKeyPairs(private: autor.privateKey);
  final event = nostr.NostrEvent.fromPartialData(
    kind: NostrEvent.kindRideRequest,
    content: reputacao == null
        ? '{"origin":{"lat":$originLat,"lon":$originLon},'
              '"destination":{"lat":$destLat,"lon":$destLon},'
              '"payment":"$payment"}'
        : jsonEncode({
            'origin': {'lat': originLat, 'lon': originLon},
            'destination': {'lat': destLat, 'lon': destLon},
            'payment': payment,
            'reputacao': reputacao,
          }),
    keyPairs: keys,
    tags: tags ?? tagsDeSolicitacao(lat: originLat, lon: originLon),
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

/// Monta um payload de `kind: 20003` já assinado — a mesma aceitação de
/// orçamento que o passageiro publicaria (emenda 07 do contrato), sob uma
/// identidade própria de passageiro (o `pubkey` do evento, lido por
/// `QuoteAccepted.passengerPubkey`).
({Map<String, dynamic> payload, String passengerPubkey}) aceitacaoAssinada({
  required String quoteId,
  String? motoristaPubkey,
  String? cifrarPara,
  String? conteudoBruto,
  String conteudo = '',
}) {
  final keys = nostr.Nostr.instance.services.keys.generateKeyPair();
  final destinatario = motoristaPubkey ?? motoristaDeTeste.publicKey;
  final event = nostr.NostrEvent.fromPartialData(
    kind: NostrEvent.kindQuoteAccepted,
    content:
        conteudoBruto ??
        _cifrarComoPassageiro(keys, cifrarPara ?? destinatario, conteudo),
    keyPairs: keys,
    tags: [
      prototypeMarkerTag,
      ['e', quoteId],
      ['p', destinatario],
    ],
  );
  return (
    payload: {
      'id': event.id,
      'pubkey': event.pubkey,
      'created_at': event.createdAt!.millisecondsSinceEpoch ~/ 1000,
      'kind': event.kind,
      'tags': event.tags,
      'content': event.content,
      'sig': event.sig,
    },
    passengerPubkey: event.pubkey,
  );
}

/// Cifra [conteudo] (vazio vira `{}`) como o passageiro de par [keys] o faria
/// para [destinatario] (emenda 17).
String _cifrarComoPassageiro(
  nostr.NostrKeyPairs keys,
  String destinatario,
  String conteudo,
) => MessageCipher().encryptFor(
  Identity(publicKey: keys.public, privateKey: keys.private),
  destinatario,
  conteudo,
);

/// Monta um payload já assinado de um dos dois eventos que o passageiro
/// publica na feature 012 (confirmação de encontro, `kind: 20008`, ou
/// confirmação de destino, `kind: 20010`) — mesmo formato de tags
/// (`["e", quoteId]` + `["p", destinatário]`) dos demais kinds efêmeros do
/// contrato.
Map<String, dynamic> confirmacaoAssinada({
  required int kind,
  required String quoteId,
  String? motoristaPubkey,
  String? cifrarPara,
  String? conteudoBruto,
  String conteudo = '',
}) {
  final keys = nostr.Nostr.instance.services.keys.generateKeyPair();
  final destinatario = motoristaPubkey ?? motoristaDeTeste.publicKey;
  final event = nostr.NostrEvent.fromPartialData(
    kind: kind,
    content:
        conteudoBruto ??
        _cifrarComoPassageiro(keys, cifrarPara ?? destinatario, conteudo),
    keyPairs: keys,
    tags: [
      prototypeMarkerTag,
      ['e', quoteId],
      ['p', destinatario],
    ],
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

/// Monta um payload de `kind: 20014` (emenda 25) como o passageiro o publicaria:
/// o recibo completo cifrado ao motorista (ou em claro, com [emClaro]), tags
/// `["e", guid]` e `["p", motorista]`.
Map<String, dynamic> reciboAssinado({
  required Receipt recibo,
  Identity? autor,
  bool emClaro = false,
}) {
  final quem = autor ?? passageiroDeTeste;
  final keys = nostr.NostrKeyPairs(private: quem.privateKey);
  final texto = jsonEncode(recibo.toJson());
  final event = nostr.NostrEvent.fromPartialData(
    kind: NostrEvent.kindReceipt,
    content: emClaro
        ? texto
        : _cifrarComoPassageiro(keys, motoristaDeTeste.publicKey, texto),
    keyPairs: keys,
    tags: [
      prototypeMarkerTag,
      ['e', recibo.guidCorrida],
      ['p', motoristaDeTeste.publicKey],
    ],
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

/// Idem para `kind: 20015`: `{"id_recibo": …}` do avaliado ao avaliador (o
/// motorista), assinado por [autor] (o passageiro por padrão).
Map<String, dynamic> confirmacaoDeReciboAssinada({
  required String guid,
  required String idRecibo,
  Identity? autor,
}) {
  final quem = autor ?? passageiroDeTeste;
  final keys = nostr.NostrKeyPairs(private: quem.privateKey);
  final event = nostr.NostrEvent.fromPartialData(
    kind: NostrEvent.kindReceiptAck,
    content: _cifrarComoPassageiro(
      keys,
      motoristaDeTeste.publicKey,
      jsonEncode({'id_recibo': idRecibo}),
    ),
    keyPairs: keys,
    tags: [
      prototypeMarkerTag,
      ['e', guid],
      ['p', motoristaDeTeste.publicKey],
    ],
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

/// Monta um payload já assinado de `kind: 20013` (emenda 19), como o passageiro
/// o publicaria: tags `["e", quoteId]` e `["p", motorista]`, `content` cifrado
/// ao motorista com o texto `{}`. [autor] é quem assina (o passageiro da
/// corrida por padrão).
Map<String, dynamic> cancelamentoDoPassageiro({
  required String quoteId,
  Identity? autor,
  String? motoristaPubkey,
  String? conteudoBruto,
  String conteudo = '',
}) {
  final quem = autor ?? passageiroDeTeste;
  final keys = nostr.NostrKeyPairs(private: quem.privateKey);
  final destinatario = motoristaPubkey ?? motoristaDeTeste.publicKey;
  final event = nostr.NostrEvent.fromPartialData(
    kind: NostrEvent.kindRideCancelledByPassenger,
    content:
        conteudoBruto ?? _cifrarComoPassageiro(keys, destinatario, conteudo),
    keyPairs: keys,
    tags: [
      prototypeMarkerTag,
      ['e', quoteId],
      ['p', destinatario],
    ],
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
  /// Monta `MapScreen` com os dublês da suíte. `relayGateway` e
  /// `cadastroStore` podem ser sobrescritos quando o cenário precisa
  /// controlar publicação/preço padrão.
  Future<
    ({
      FakeGateway gateway,
      RelayService relayService,
      EventFeed eventFeed,
      InMemoryRideStateStore rideStateStore,
      InMemorySentQuotesStore sentQuotesStore,
      InMemoryRideRatingStore rideRatingStore,
      InMemoryReceiptStore receiptStore,
    })
  >
  montar(
    WidgetTester tester, {
    LocationService? locationService,
    CadastroStore? cadastroStore,
    RouteDistanceService? routeDistanceService,
    Identity? identity,
    InMemoryRideStateStore? rideStateStore,
    InMemorySentQuotesStore? sentQuotesStore,
    InMemoryRideRatingStore? rideRatingStore,
    InMemoryReceiptStore? receiptStore,
    ValueListenable<DriverProfile?>? perfilAoVivo,
    ServiceController? serviceController,
  }) async {
    final gateway = FakeGateway();
    final relayService = RelayService(gateway);
    await relayService.connectAll(const [Relay(url: 'wss://a.test')]);
    final eventFeed = EventFeed(
      incoming: relayService.incoming,
      coverage: () => relayService.coverage,
      acceptedKinds: const {
        NostrEvent.kindRideRequest,
        NostrEvent.kindQuoteAccepted,
        NostrEvent.kindMeetingConfirmed,
        NostrEvent.kindDestinationConfirmed,
        NostrEvent.kindRideCancelledByPassenger,
        NostrEvent.kindReceipt,
        NostrEvent.kindReceiptAck,
      },
    );
    final rideState = rideStateStore ?? InMemoryRideStateStore();
    final sentQuotes = sentQuotesStore ?? InMemorySentQuotesStore();
    final rideRatings = rideRatingStore ?? InMemoryRideRatingStore();
    final receipts = receiptStore ?? InMemoryReceiptStore();
    final identityService = IdentityService(_MemoryKeyStore());
    final receiptService = ReceiptService(
      store: receipts,
      identityService: identityService,
      identity: () => identity ?? motoristaDeTeste,
      publish: (signed) async {
        final resultados = await relayService
            .publish(signed.event, payload: signed.payload)
            .toList();
        return resultados.any((r) => r.accepted);
      },
    );

    Widget mapa(DriverProfile? perfil) => MapScreen(
      driverProfile: perfil,
      locationService: locationService ?? FakeLocationService(),
      eventFeed: eventFeed,
      cadastroStore: cadastroStore ?? FakeCadastroStore(perfilComPreco(2.5)),
      routeDistanceService: routeDistanceService ?? FakeRouteDistanceService(),
      reverseGeocodingService: FakeReverseGeocodingService(),
      identity: identity ?? motoristaDeTeste,
      identityService: identityService,
      relayService: relayService,
      serviceController: serviceController,
      rideStateStore: rideState,
      sentQuotesStore: sentQuotes,
      rideRatingStore: rideRatings,
      receiptStore: receipts,
      receiptService: receiptService,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: perfilAoVivo == null
            ? mapa(null)
            : ValueListenableBuilder<DriverProfile?>(
                valueListenable: perfilAoVivo,
                builder: (_, perfil, _) => mapa(perfil),
              ),
      ),
    );
    await tester.pump();
    return (
      gateway: gateway,
      relayService: relayService,
      eventFeed: eventFeed,
      rideStateStore: rideState,
      sentQuotesStore: sentQuotes,
      rideRatingStore: rideRatings,
      receiptStore: receipts,
    );
  }

  group('MapScreen — serviço em segundo plano (feature 025)', () {
    late FakeChannelPair canais;
    late FakeBackgroundService servico;
    late RemoteRelayConnection conexao;
    late ServiceController controlador;

    /// Criado dentro de cada teste, e não num `setUp`: os `StreamController`
    /// precisam nascer na zona de tempo falso do `testWidgets`, senão seus
    /// eventos só andam com o relógio real e nunca com `tester.pump`.
    void preparar() {
      canais = FakeChannelPair();
      servico = FakeBackgroundService(canais.ui);
      conexao = RemoteRelayConnection(canais.ui);
      controlador = ServiceController(
        service: servico,
        connection: conexao,
        resumeTimeout: const Duration(seconds: 1),
      );
    }

    tearDown(() async {
      await controlador.dispose();
      await conexao.dispose();
    });

    /// `montar` com o controlador do serviço, criado já na zona do teste.
    Future<FakeGateway> montarComServico(
      WidgetTester tester, {
      LocationService? locationService,
      CadastroStore? cadastroStore,
      InMemoryRideStateStore? rideStateStore,
      ValueListenable<DriverProfile?>? perfilAoVivo,
      bool permissaoDeNotificacao = true,
      bool concedeAoPedir = true,
    }) async {
      preparar();
      servico.permission = permissaoDeNotificacao;
      servico.grantsWhenAsked = concedeAoPedir;
      final m = await montar(
        tester,
        locationService: locationService,
        cadastroStore: cadastroStore,
        rideStateStore: rideStateStore,
        perfilAoVivo: perfilAoVivo,
        serviceController: controlador,
      );
      return m.gateway;
    }

    List<ServiceState> estadosEnviados() => [
      for (final m in canais.ui.sent.whereType<ServiceStateUpdate>()) m.state,
    ];

    void servicoResponde({required bool online}) => canais.service.send(
      ServiceHelloAck(online: online, relays: const [], pending: const []),
    );

    /// Liga o controlador como `main.dart` faz e deixa passar o prazo curto de
    /// espera pela resposta do serviço.
    Future<void> ligar(WidgetTester tester, {required bool online}) async {
      await controlador.start();
      servicoResponde(online: online);
      // Primeiro deixa a resposta chegar à tela; só depois o prazo de espera do
      // controlador corre (e não deixa timer pendente ao fim do teste).
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
    }

    testWidgets('informa o estado ao serviço ao ficar online', (tester) async {
      final location = FakeLocationService();
      await montarComServico(tester, locationService: location);
      await ligar(tester, online: false);
      expect(estadosEnviados().last.online, isFalse);

      location.emitir(posicaoDeTeste());
      await tester.pump();
      await tester.tap(find.byType(Switch));
      await tester.pump();

      final estado = estadosEnviados().last;
      expect(estado.online, isTrue);
      expect(estado.rideStatus, DriverRideStatus.aguardandoSolicitacao);
      expect(estado.appInForeground, isTrue);
    });

    testWidgets('as formas de pagamento do cadastro chegam ao serviço', (
      tester,
    ) async {
      final soDinheiro = perfilComPreco(2.5)
          .copyWith(paymentMethods: {PaymentMethod.cash});
      await montarComServico(
        tester,
        cadastroStore: FakeCadastroStore(soDinheiro),
      );
      await ligar(tester, online: false);
      await tester.pump();

      expect(estadosEnviados().last.acceptedPayments, {'dinheiro'});
    });

    testWidgets('mudar o cadastro atualiza o serviço sem reiniciar', (
      tester,
    ) async {
      final perfil = ValueNotifier<DriverProfile?>(
        perfilComPreco(2.5).copyWith(paymentMethods: {PaymentMethod.cash}),
      );
      await montarComServico(
        tester,
        cadastroStore: FakeCadastroStore(perfil.value),
        perfilAoVivo: perfil,
      );
      await ligar(tester, online: false);
      expect(estadosEnviados().last.acceptedPayments, {'dinheiro'});

      perfil.value = perfilComPreco(2.5)
          .copyWith(paymentMethods: {PaymentMethod.pix});
      await tester.pump();

      expect(estadosEnviados().last.acceptedPayments, {'pix'});
    });

    testWidgets('a corrida em andamento restaurada chega ao serviço', (
      tester,
    ) async {
      final estado = InMemoryRideStateStore();
      await estado.save(
        DriverRideStatus.deslocandoAtePassageiro,
        const ActiveRide(
          quoteId: 'q1',
          passengerPubkey: 'p1',
          originLat: -28.9,
          originLon: -49.4,
          destinationLat: -28.6,
          destinationLon: -49.3,
        ),
      );
      await montarComServico(tester, rideStateStore: estado);
      await ligar(tester, online: false);
      await tester.pump();

      expect(
        estadosEnviados().last.rideStatus,
        DriverRideStatus.deslocandoAtePassageiro,
      );
    });

    testWidgets('pede a permissão de notificação só ao ficar online', (
      tester,
    ) async {
      final location = FakeLocationService();
      await montarComServico(
        tester,
        locationService: location,
        permissaoDeNotificacao: false,
      );
      await ligar(tester, online: false);
      expect(servico.permissionRequests, 0);

      location.emitir(posicaoDeTeste());
      await tester.pump();
      await tester.tap(find.byType(Switch));
      await tester.pump();
      await tester.pump();

      expect(servico.permissionRequests, 1);
    });

    testWidgets('permissão negada: o motorista é avisado', (tester) async {
      final location = FakeLocationService();
      await montarComServico(
        tester,
        locationService: location,
        permissaoDeNotificacao: false,
        concedeAoPedir: false,
      );
      await ligar(tester, online: false);

      location.emitir(posicaoDeTeste());
      await tester.pump();
      await tester.tap(find.byType(Switch));
      await tester.pump();
      await tester.pump();

      expect(
        find.textContaining('só será avisado de corridas'),
        findsOneWidget,
      );
    });

    testWidgets('permissão concedida: nenhum aviso', (tester) async {
      final location = FakeLocationService();
      await montarComServico(tester, locationService: location);
      await ligar(tester, online: false);

      location.emitir(posicaoDeTeste());
      await tester.pump();
      await tester.tap(find.byType(Switch));
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('só será avisado de corridas'), findsNothing);
    });

    testWidgets('serviço estava online e há posição: retoma online sozinho', (
      tester,
    ) async {
      final location = FakeLocationService();
      await montarComServico(tester, locationService: location);
      location.emitir(posicaoDeTeste());
      await tester.pump();

      await ligar(tester, online: true);
      await tester.pump();

      expect(find.text('Você está online'), findsOneWidget);
    });

    testWidgets('serviço estava online, posição chega depois: retoma online', (
      tester,
    ) async {
      final location = FakeLocationService();
      await montarComServico(tester, locationService: location);
      await ligar(tester, online: true);
      await tester.pump();

      expect(find.text('Você está offline'), findsOneWidget);
      // Enquanto espera a posição, o serviço já o vê como online: não perde
      // uma solicitação nesse intervalo.
      expect(estadosEnviados().last.online, isTrue);

      location.emitir(posicaoDeTeste());
      await tester.pump();
      await tester.pump();

      expect(find.text('Você está online'), findsOneWidget);
    });

    testWidgets('serviço estava offline: continua offline', (tester) async {
      final location = FakeLocationService();
      await montarComServico(tester, locationService: location);
      location.emitir(posicaoDeTeste());
      await tester.pump();

      await ligar(tester, online: false);
      await tester.pump();

      expect(find.text('Você está offline'), findsOneWidget);
      expect(estadosEnviados().last.online, isFalse);
    });

    testWidgets('sem posição a tempo, desiste e informa o serviço', (
      tester,
    ) async {
      await montarComServico(tester);
      await ligar(tester, online: true);
      await tester.pump();
      expect(estadosEnviados().last.online, isTrue);

      await tester.pump(const Duration(seconds: 21));

      expect(find.text('Você está offline'), findsOneWidget);
      expect(estadosEnviados().last.online, isFalse);
    });

    group('solicitação reentregue pelo serviço durante a retomada', () {
      Future<void> chegaSolicitacao(
        WidgetTester tester,
        FakeGateway gateway,
      ) async {
        gateway.emitir(
          IncomingEvent(
            relayUrl: 'wss://a.test',
            payload: solicitacaoAssinada(),
          ),
        );
        await tester.pump();
        await tester.pump();
      }

      testWidgets(
        'chega antes de o serviço responder: abre a modal quando a retomada termina online',
        (tester) async {
          final location = FakeLocationService();
          final gateway = await montarComServico(
            tester,
            locationService: location,
          );
          await controlador.start();

          await chegaSolicitacao(tester, gateway);
          expect(find.text('Solicitação de corrida'), findsNothing);

          servicoResponde(online: true);
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));
          expect(find.text('Solicitação de corrida'), findsNothing);

          location.emitir(posicaoDeTeste());
          await tester.pump();
          await tester.pump();

          expect(find.text('Você está online'), findsOneWidget);
          expect(find.text('Solicitação de corrida'), findsOneWidget);
        },
      );

      testWidgets('o serviço estava offline: a solicitação é descartada', (
        tester,
      ) async {
        final location = FakeLocationService();
        final gateway = await montarComServico(
          tester,
          locationService: location,
        );
        await controlador.start();
        await chegaSolicitacao(tester, gateway);

        servicoResponde(online: false);
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
        location.emitir(posicaoDeTeste());
        await tester.pump();
        await tester.pump();

        expect(find.text('Solicitação de corrida'), findsNothing);
        expect(find.text('Você está offline'), findsOneWidget);
      });

      testWidgets('sem posição a tempo a solicitação é descartada', (
        tester,
      ) async {
        final location = FakeLocationService();
        final gateway = await montarComServico(
          tester,
          locationService: location,
        );
        await controlador.start();
        await chegaSolicitacao(tester, gateway);
        servicoResponde(online: true);
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));

        await tester.pump(const Duration(seconds: 21));
        location.emitir(posicaoDeTeste());
        await tester.pump();
        await tester.pump();

        expect(find.text('Solicitação de corrida'), findsNothing);
        expect(find.text('Você está offline'), findsOneWidget);
      });

      testWidgets('já online e com tudo pronto, abre direto', (tester) async {
        final location = FakeLocationService();
        final gateway = await montarComServico(
          tester,
          locationService: location,
        );
        location.emitir(posicaoDeTeste());
        await tester.pump();
        await ligar(tester, online: true);
        await tester.pump();
        expect(find.text('Você está online'), findsOneWidget);

        await chegaSolicitacao(tester, gateway);

        expect(find.text('Solicitação de corrida'), findsOneWidget);
      });

      testWidgets(
        'chegou antes da posição e fica fora da nova referência: é descartada',
        (tester) async {
          final location = FakeLocationService();
          final gateway = await montarComServico(
            tester,
            locationService: location,
          );
          await controlador.start();
          gateway.emitir(
            IncomingEvent(
              relayUrl: 'wss://a.test',
              // Passou pelo serviço com a referência antiga; a nova é Araranguá.
              payload: solicitacaoAssinada(
                originLat: -23.5505,
                originLon: -46.6333,
              ),
            ),
          );
          await tester.pump();
          await tester.pump();
          servicoResponde(online: true);
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));

          location.emitir(posicaoDeTeste());
          await tester.pump();
          await tester.pump();

          expect(find.text('Você está online'), findsOneWidget);
          expect(find.text('Solicitação de corrida'), findsNothing);
        },
      );

      testWidgets(
        'retomada online cria a cobertura na primeira posição e a entrega à conexão',
        (tester) async {
          final location = FakeLocationService();
          final gateway = await montarComServico(
            tester,
            locationService: location,
          );
          await controlador.start();
          servicoResponde(online: true);
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));
          expect(gateway.celulasPedidas, isEmpty);

          location.emitir(posicaoDeTeste());
          await tester.pump();
          await tester.pump();

          expect(gateway.celulasPedidas, hasLength(1));
          expect(gateway.celulasPedidas.single, isNotEmpty);
        },
      );
    });

    testWidgets('localização perdida durante a retomada: fica offline', (
      tester,
    ) async {
      final location = FakeLocationService();
      await montarComServico(tester, locationService: location);
      await ligar(tester, online: true);
      await tester.pump();

      location.emitirErro(const LocationUnavailable(null));
      await tester.pump();
      await tester.pump();

      expect(find.text('Você está offline'), findsOneWidget);
      expect(estadosEnviados().last.online, isFalse);
    });
  });

  group('MapScreen — forma de pagamento aceita', () {
    final soDinheiro = perfilComPreco(2.5)
        .copyWith(paymentMethods: {PaymentMethod.cash});

    Future<void> ficarOnline(
      WidgetTester tester,
      FakeLocationService service,
    ) async {
      service.emitir(posicaoDeTeste());
      await tester.pump();
      await tester.tap(find.byType(Switch));
      await tester.pump();
    }

    Future<void> receber(
      WidgetTester tester,
      FakeGateway gateway,
      String payment,
    ) async {
      gateway.emitir(
        IncomingEvent(
          relayUrl: 'wss://a.test',
          payload: solicitacaoAssinada(payment: payment),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    testWidgets('pagamento fora da lista aceita é ignorado, sem modal', (
      tester,
    ) async {
      final service = FakeLocationService();
      final m = await montar(
        tester,
        locationService: service,
        cadastroStore: FakeCadastroStore(soDinheiro),
      );
      await ficarOnline(tester, service);

      await receber(tester, m.gateway, 'pix');
      expect(find.text('Solicitação de corrida'), findsNothing);

      await receber(tester, m.gateway, 'valor-desconhecido');
      expect(find.text('Solicitação de corrida'), findsNothing);
    });

    testWidgets('pagamento da lista aceita abre a modal', (tester) async {
      final service = FakeLocationService();
      final m = await montar(
        tester,
        locationService: service,
        cadastroStore: FakeCadastroStore(soDinheiro),
      );
      await ficarOnline(tester, service);

      await receber(tester, m.gateway, 'dinheiro');

      expect(find.text('Solicitação de corrida'), findsOneWidget);
    });

    testWidgets('uma recusada não atrapalha a próxima aceita', (tester) async {
      final service = FakeLocationService();
      final m = await montar(
        tester,
        locationService: service,
        cadastroStore: FakeCadastroStore(soDinheiro),
      );
      await ficarOnline(tester, service);

      await receber(tester, m.gateway, 'cartao');
      await receber(tester, m.gateway, 'dinheiro');

      expect(find.text('Solicitação de corrida'), findsOneWidget);
    });

    testWidgets('o cadastro editado vale sem reiniciar o app', (tester) async {
      final service = FakeLocationService();
      final perfil = ValueNotifier<DriverProfile?>(soDinheiro);
      final m = await montar(
        tester,
        locationService: service,
        cadastroStore: FakeCadastroStore(soDinheiro),
        perfilAoVivo: perfil,
      );
      await ficarOnline(tester, service);

      await receber(tester, m.gateway, 'pix');
      expect(find.text('Solicitação de corrida'), findsNothing);

      perfil.value = soDinheiro.copyWith(
        paymentMethods: {PaymentMethod.cash, PaymentMethod.pix},
      );
      await tester.pump();
      await receber(tester, m.gateway, 'pix');

      expect(find.text('Solicitação de corrida'), findsOneWidget);
    });
  });

  group('MapScreen — faixa sem conexão com os relays', () {
    testWidgets('some com relay conectado e aparece quando todos caem', (
      tester,
    ) async {
      final m = await montar(tester);
      expect(find.text('Sem conexão com os relays.'), findsNothing);

      m.gateway.derrubar('wss://a.test');
      await tester.pump();

      expect(find.text('Sem conexão com os relays.'), findsOneWidget);
      expect(find.byKey(const Key('botao-reconectar-mapa')), findsOneWidget);
    });

    testWidgets('Reconectar volta a conectar e a faixa some', (tester) async {
      final m = await montar(tester);
      m.gateway.derrubar('wss://a.test');
      await tester.pump();
      expect(find.text('Sem conexão com os relays.'), findsOneWidget);

      await tester.tap(find.byKey(const Key('botao-reconectar-mapa')));
      await tester.pump();
      await tester.pump();

      expect(m.relayService.hasConnectedRelay, isTrue);
      expect(m.gateway.tentativas['wss://a.test'], 2);
      expect(find.text('Sem conexão com os relays.'), findsNothing);
    });
  });

  group('MapScreen — posição e indisponibilidade (US1)', () {
    testWidgets('exibe o indicador de posição quando uma posição chega', (
      tester,
    ) async {
      final service = FakeLocationService();
      await montar(tester, locationService: service);

      expect(find.byIcon(Icons.directions_car), findsNothing);

      service.emitir(posicaoDeTeste());
      await tester.pump();

      expect(find.byIcon(Icons.directions_car), findsOneWidget);
    });

    testWidgets(
      'exibe mensagem compreensível quando a permissão é negada, sem travar',
      (tester) async {
        final service = FakeLocationService(
          permissionError: const LocationPermissionDenied(),
        );
        await montar(tester, locationService: service);
        await tester.pump();

        expect(
          find.textContaining('permitir o acesso à localização'),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.directions_car), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('exibe mensagem diferente quando a permissão foi negada '
        'permanentemente', (tester) async {
      final service = FakeLocationService(
        permissionError: const LocationPermissionDenied(permanently: true),
      );
      await montar(tester, locationService: service);
      await tester.pump();

      expect(find.textContaining('configurações do aparelho'), findsOneWidget);
    });

    testWidgets('exibe mensagem compreensível quando a localização se torna '
        'indisponível, sem travar', (tester) async {
      final service = FakeLocationService();
      await montar(tester, locationService: service);

      service.emitirErro(const LocationUnavailable('sinal perdido'));
      await tester.pump();

      expect(
        find.textContaining('Não foi possível obter sua localização'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('MapScreen — status online/offline (US2)', () {
    testWidgets(
      'o estado inicial é sempre offline, com qualquer dublê (FR-010, '
      'SC-005)',
      (tester) async {
        await montar(tester);

        expect(find.text('Você está offline'), findsOneWidget);
        expect(find.text('Você está online'), findsNothing);
      },
    );

    testWidgets(
      'tentar ficar online sem posição válida é recusado (FR-008, SC-004)',
      (tester) async {
        await montar(tester);

        await tester.tap(find.byType(Switch));
        await tester.pump();

        expect(find.text('Você está offline'), findsOneWidget);
        expect(
          find.textContaining('preciso ter uma localização válida'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'com posição válida, alterna para online e de volta a offline',
      (tester) async {
        final service = FakeLocationService();
        await montar(tester, locationService: service);
        service.emitir(posicaoDeTeste());
        await tester.pump();

        await tester.tap(find.byType(Switch));
        await tester.pump();
        expect(find.text('Você está online'), findsOneWidget);

        await tester.tap(find.byType(Switch));
        await tester.pump();
        expect(find.text('Você está offline'), findsOneWidget);
      },
    );

    testWidgets('perder a posição estando online força offline automaticamente '
        '(FR-009, SC-006)', (tester) async {
      final service = FakeLocationService();
      await montar(tester, locationService: service);
      service.emitir(posicaoDeTeste());
      await tester.pump();
      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(find.text('Você está online'), findsOneWidget);

      service.emitirErro(const LocationUnavailable('sinal perdido'));
      await tester.pump();

      expect(find.text('Você está offline'), findsOneWidget);
      expect(
        find.textContaining('ficou offline porque a localização'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'dois toques em sequência rápida resultam em um único estado final '
      'consistente (edge case de toques repetidos)',
      (tester) async {
        final service = FakeLocationService();
        await montar(tester, locationService: service);
        service.emitir(posicaoDeTeste());
        await tester.pump();

        // Dois toques sem `pump()` entre eles — nenhum estado intermediário
        // deve escapar visível.
        await tester.tap(find.byType(Switch));
        await tester.tap(find.byType(Switch));
        await tester.pump();

        expect(find.text('Você está offline'), findsOneWidget);
        expect(find.text('Você está online'), findsNothing);
      },
    );
  });

  group('MapScreen — modal de solicitação de corrida (US1/US2/US3 da feature '
      '007)', () {
    testWidgets(
      'solicitação recebida com o motorista online abre a modal (FR-001)',
      (tester) async {
        final service = FakeLocationService();
        final ambiente = await montar(tester, locationService: service);
        service.emitir(posicaoDeTeste());
        await tester.pump();
        await tester.tap(find.byType(Switch));
        await tester.pump();

        ambiente.gateway.emitir(
          IncomingEvent(
            relayUrl: 'wss://a.test',
            payload: solicitacaoAssinada(),
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(find.text('Solicitação de corrida'), findsOneWidget);
      },
    );

    testWidgets('solicitação recebida com o motorista offline não abre modal '
        '(FR-002)', (tester) async {
      final service = FakeLocationService();
      final ambiente = await montar(tester, locationService: service);
      service.emitir(posicaoDeTeste());
      await tester.pump();
      // Nunca toca o Switch: permanece offline.

      ambiente.gateway.emitir(
        IncomingEvent(relayUrl: 'wss://a.test', payload: solicitacaoAssinada()),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Solicitação de corrida'), findsNothing);
    });

    testWidgets(
      'duas solicitações em sequência: só uma modal por vez (FR-015)',
      (tester) async {
        final service = FakeLocationService();
        final ambiente = await montar(
          tester,
          locationService: service,
          routeDistanceService: FakeRouteDistanceService(
            resultados: [1000, 1000, 1000, 1000],
          ),
        );
        service.emitir(posicaoDeTeste());
        await tester.pump();
        await tester.tap(find.byType(Switch));
        await tester.pump();

        ambiente.gateway.emitir(
          IncomingEvent(
            relayUrl: 'wss://a.test',
            payload: solicitacaoAssinada(originLat: -28.90),
          ),
        );
        await tester.pump();
        ambiente.gateway.emitir(
          IncomingEvent(
            relayUrl: 'wss://a.test',
            payload: solicitacaoAssinada(originLat: -28.91),
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(find.text('Solicitação de corrida'), findsOneWidget);

        await tester.tap(find.widgetWithText(TextButton, 'Recusar corrida'));
        await tester.pumpAndSettle();

        expect(
          find.text('Solicitação de corrida'),
          findsOneWidget,
          reason:
              'a segunda solicitação deve abrir imediatamente após a primeira',
        );
      },
    );

    testWidgets('enviar orçamento publica o evento kind 20002 com a tag "e" '
        'correta', (tester) async {
      final service = FakeLocationService();
      final ambiente = await montar(
        tester,
        locationService: service,
        routeDistanceService: FakeRouteDistanceService(
          resultados: [1000, 10000],
        ),
      );
      service.emitir(posicaoDeTeste());
      await tester.pump();
      await tester.tap(find.byType(Switch));
      await tester.pump();

      final payload = solicitacaoAssinada();
      ambiente.gateway.emitir(
        IncomingEvent(relayUrl: 'wss://a.test', payload: payload),
      );
      await tester.pump();
      await tester.pump();

      await tester.tap(find.widgetWithText(FilledButton, 'Enviar orçamento'));
      await tester.pumpAndSettle();

      expect(ambiente.gateway.publicados, hasLength(1));
      final publicado = ambiente.gateway.publicados.single;
      expect(publicado.kind, NostrEvent.kindRideQuote);
      expect(find.text('Solicitação de corrida'), findsNothing);
    });

    testWidgets(
      'enviar orçamento registra o id em SentQuotesStore, sem alterar o '
      'estado do motorista (FR-006, FR-011 — pré-requisito para a US1 da '
      'feature 010 reconhecer a aceitação depois)',
      (tester) async {
        final service = FakeLocationService();
        final ambiente = await montar(
          tester,
          locationService: service,
          routeDistanceService: FakeRouteDistanceService(
            resultados: [1000, 10000],
          ),
        );
        service.emitir(posicaoDeTeste());
        await tester.pump();
        await tester.tap(find.byType(Switch));
        await tester.pump();

        ambiente.gateway.emitir(
          IncomingEvent(
            relayUrl: 'wss://a.test',
            payload: solicitacaoAssinada(),
          ),
        );
        await tester.pump();
        await tester.pump();

        await tester.tap(find.widgetWithText(FilledButton, 'Enviar orçamento'));
        await tester.pumpAndSettle();

        final publicado = ambiente.gateway.publicados.single;
        expect(await ambiente.sentQuotesStore.contains(publicado.id), isTrue);
        expect(
          ambiente.rideStateStore.saveCount,
          0,
          reason:
              'enviar orçamento nunca chama RideStateStore.save — o envio '
              'não muda o estado do motorista',
        );
      },
    );
  });

  group('MapScreen — modal de aceitação de orçamento e início da corrida '
      '(US1 da feature 010)', () {
    testWidgets(
      'aceitação referenciando um orçamento já enviado abre a modal (FR-001)',
      (tester) async {
        final sentQuotes = InMemorySentQuotesStore(
          initial: {'quote-1': _origemPadrao},
        );
        final ambiente = await montar(tester, sentQuotesStore: sentQuotes);

        final aceitacao = aceitacaoAssinada(quoteId: 'quote-1');
        ambiente.gateway.emitir(
          IncomingEvent(relayUrl: 'wss://a.test', payload: aceitacao.payload),
        );
        await tester.pump();
        await tester.pump();
        await tester.pump();

        expect(find.text('Orçamento aceito'), findsOneWidget);
        expect(find.text('Iniciar corrida'), findsOneWidget);
      },
    );

    testWidgets(
      'tocar "Iniciar corrida" persiste o novo estado e fecha a modal '
      '(FR-002, FR-003)',
      (tester) async {
        final sentQuotes = InMemorySentQuotesStore(
          initial: {'quote-1': _origemPadrao},
          initialDestinations: {'quote-1': _destinoPadrao},
        );
        final ambiente = await montar(tester, sentQuotesStore: sentQuotes);

        final aceitacao = aceitacaoAssinada(quoteId: 'quote-1');
        ambiente.gateway.emitir(
          IncomingEvent(relayUrl: 'wss://a.test', payload: aceitacao.payload),
        );
        await tester.pump();
        await tester.pump();
        await tester.pump();

        await tester.tap(find.widgetWithText(FilledButton, 'Iniciar corrida'));
        await tester.pumpAndSettle();

        expect(find.text('Orçamento aceito'), findsNothing);
        expect(ambiente.rideStateStore.saveCount, 1);
        final (status, active) = await ambiente.rideStateStore.load();
        expect(status, DriverRideStatus.deslocandoAtePassageiro);
        expect(
          active,
          ActiveRide(
            quoteId: 'quote-1',
            passengerPubkey: aceitacao.passengerPubkey,
            originLat: _origemPadrao.$1,
            originLon: _origemPadrao.$2,
            destinationLat: _destinoPadrao.$1,
            destinationLon: _destinoPadrao.$2,
          ),
        );
      },
    );

    testWidgets('estado restaurado ao reabrir não exibe modal nem pede nova '
        'confirmação (FR-003, FR-009)', (tester) async {
      final rideState = InMemoryRideStateStore(
        status: DriverRideStatus.deslocandoAtePassageiro,
        active: ActiveRide(
          quoteId: 'quote-1',
          passengerPubkey: passageiroDeTeste.publicKey,
          originLat: -28.9298,
          originLon: -49.4753,
          destinationLat: -28.6721,
          destinationLon: -49.3671,
        ),
      );
      await montar(tester, rideStateStore: rideState);

      expect(find.text('Orçamento aceito'), findsNothing);
      expect(find.text('Iniciar corrida'), findsNothing);
    });

    testWidgets(
      'aceitação referenciando um quoteId nunca enviado por este motorista '
      'é ignorada (FR-011, achado C1 do /speckit-analyze)',
      (tester) async {
        final ambiente = await montar(tester); // SentQuotesStore vazio

        final aceitacao = aceitacaoAssinada(quoteId: 'quote-desconhecido');
        ambiente.gateway.emitir(
          IncomingEvent(relayUrl: 'wss://a.test', payload: aceitacao.payload),
        );
        await tester.pump();
        await tester.pump();
        await tester.pump();

        expect(find.text('Orçamento aceito'), findsNothing);
      },
    );

    testWidgets('aceitação referenciando um quoteId registrado antes da '
        'reconstrução do widget ainda abre a modal (janela de reinício, '
        'achado C1 do /speckit-analyze)', (tester) async {
      // SentQuotesStore pré-carregado simula um orçamento enviado antes
      // de um reinício do app — sem isto, a aceitação legítima seria
      // descartada como se fosse desconhecida.
      final sentQuotes = InMemorySentQuotesStore(
        initial: {'quote-1': _origemPadrao},
      );
      final ambiente = await montar(tester, sentQuotesStore: sentQuotes);

      final aceitacao = aceitacaoAssinada(quoteId: 'quote-1');
      ambiente.gateway.emitir(
        IncomingEvent(relayUrl: 'wss://a.test', payload: aceitacao.payload),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(find.text('Orçamento aceito'), findsOneWidget);
    });
  });

  group('MapScreen — bloqueio de novas solicitações fora de "Aguardando" '
      '(US2 da feature 010)', () {
    testWidgets('solicitação de corrida não abre modal quando o motorista está '
        'Deslocando-se (FR-004)', (tester) async {
      final rideState = InMemoryRideStateStore(
        status: DriverRideStatus.deslocandoAtePassageiro,
        active: ActiveRide(
          quoteId: 'quote-1',
          passengerPubkey: passageiroDeTeste.publicKey,
          originLat: -28.9298,
          originLon: -49.4753,
          destinationLat: -28.6721,
          destinationLon: -49.3671,
        ),
      );
      final service = FakeLocationService();
      final ambiente = await montar(
        tester,
        locationService: service,
        rideStateStore: rideState,
      );
      service.emitir(posicaoDeTeste());
      await tester.pump();
      await tester.tap(find.byType(Switch));
      await tester.pump();

      ambiente.gateway.emitir(
        IncomingEvent(relayUrl: 'wss://a.test', payload: solicitacaoAssinada()),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Solicitação de corrida'), findsNothing);
    });

    testWidgets(
      'solicitações enfileiradas antes da transição são descartadas ao '
      'iniciar a corrida (FR-005)',
      (tester) async {
        final service = FakeLocationService();
        final sentQuotes = InMemorySentQuotesStore(
          initial: {'quote-1': _origemPadrao},
        );
        final ambiente = await montar(
          tester,
          locationService: service,
          sentQuotesStore: sentQuotes,
        );
        service.emitir(posicaoDeTeste());
        await tester.pump();
        await tester.tap(find.byType(Switch));
        await tester.pump();

        final aceitacao = aceitacaoAssinada(quoteId: 'quote-1');
        ambiente.gateway.emitir(
          IncomingEvent(relayUrl: 'wss://a.test', payload: aceitacao.payload),
        );
        await tester.pump();
        await tester.pump();
        await tester.pump();
        expect(find.text('Orçamento aceito'), findsOneWidget);

        // Chega enquanto a modal de aceitação está aberta: fica na fila,
        // atrás dela.
        ambiente.gateway.emitir(
          IncomingEvent(
            relayUrl: 'wss://a.test',
            payload: solicitacaoAssinada(),
          ),
        );
        await tester.pump();
        await tester.pump();
        expect(
          find.text('Solicitação de corrida'),
          findsNothing,
          reason: 'ainda atrás da modal de aceitação, que segue aberta',
        );

        await tester.tap(find.widgetWithText(FilledButton, 'Iniciar corrida'));
        await tester.pumpAndSettle();

        expect(
          find.text('Solicitação de corrida'),
          findsNothing,
          reason: 'descartada pela transição — não deveria aparecer depois',
        );
      },
    );
  });

  group('MapScreen — publicação de localização durante o deslocamento (US3 da '
      'feature 010)', () {
    testWidgets('publica kind 20005 na primeira posição após entrar em '
        'Deslocando-se, e de novo só após 5 s (FR-007, FR-008)', (
      tester,
    ) async {
      final service = FakeLocationService();
      final rideState = InMemoryRideStateStore(
        status: DriverRideStatus.deslocandoAtePassageiro,
        active: ActiveRide(
          quoteId: 'quote-1',
          passengerPubkey: passageiroDeTeste.publicKey,
          originLat: 0,
          originLon: 0,
          destinationLat: 0,
          destinationLon: 0,
        ),
      );
      final ambiente = await montar(
        tester,
        locationService: service,
        rideStateStore: rideState,
      );
      final inicio = DateTime(2026, 9, 26, 12);
      DriverPosition em(int segundos) => DriverPosition(
        latitude: -28.9348,
        longitude: -49.49,
        capturedAt: inicio.add(Duration(seconds: segundos)),
      );
      int publicadas() => ambiente.gateway.publicados
          .where((e) => e.kind == NostrEvent.kindDriverLocation)
          .length;

      // Primeira posição: sempre publica (sem instante de referência) —
      // é o que garante a retomada automática após um reinício
      // (FR-009), sem nenhuma ação do motorista.
      service.emitir(em(0));
      await tester.pump();
      expect(publicadas(), 1);

      // 4 s depois, mesmo parado ou em movimento: abaixo do intervalo.
      service.emitir(em(4));
      await tester.pump();
      expect(publicadas(), 1);

      // 5 s depois da última publicação, mesmo sem sair do lugar.
      service.emitir(em(5));
      await tester.pump();
      expect(publicadas(), 2);

      final ultima = ambiente.gateway.publicados
          .where((e) => e.kind == NostrEvent.kindDriverLocation)
          .last;
      expect(ultima.tags, anyElement(equals(['e', 'quote-1'])));
      expect(
        ultima.tags,
        anyElement(equals(['p', passageiroDeTeste.publicKey])),
      );
    });

    testWidgets('não publica localização enquanto o motorista está Aguardando '
        'solicitação de corrida (FR-007)', (tester) async {
      final service = FakeLocationService();
      final ambiente = await montar(tester, locationService: service);

      service.emitir(posicaoDeTeste());
      await tester.pump();

      expect(
        ambiente.gateway.publicados.where(
          (e) => e.kind == NostrEvent.kindDriverLocation,
        ),
        isEmpty,
      );
    });
  });

  group('MapScreen — aceitação com o motorista já comprometido (US4 da feature '
      '010; emenda 16)', () {
    final ativa = ActiveRide(
      quoteId: 'quote-1',
      passengerPubkey: passageiroDeTeste.publicKey,
      originLat: 0,
      originLon: 0,
      destinationLat: 0,
      destinationLon: 0,
    );

    for (final status in [
      DriverRideStatus.deslocandoAtePassageiro,
      DriverRideStatus.emCorrida,
    ]) {
      testWidgets('em ${status.name}: não abre modal e publica kind 20006 ao '
          'passageiro daquela aceitação, sem tocar na corrida ativa '
          '(FR-010)', (tester) async {
        final rideState = InMemoryRideStateStore(status: status, active: ativa);
        final sentQuotes = InMemorySentQuotesStore(
          initial: {'quote-2': _origemPadrao},
        );
        final ambiente = await montar(
          tester,
          rideStateStore: rideState,
          sentQuotesStore: sentQuotes,
        );

        final aceitacao = aceitacaoAssinada(quoteId: 'quote-2');
        ambiente.gateway.emitir(
          IncomingEvent(relayUrl: 'wss://a.test', payload: aceitacao.payload),
        );
        await tester.pump();
        await tester.pump();
        await tester.pump();

        expect(find.text('Orçamento aceito'), findsNothing);

        final recusas = ambiente.gateway.publicados
            .where((e) => e.kind == NostrEvent.kindRideNoLongerAvailable)
            .toList();
        expect(recusas, hasLength(1));
        expect(recusas.single.tags, anyElement(equals(['e', 'quote-2'])));
        expect(
          recusas.single.tags,
          anyElement(equals(['p', aceitacao.passengerPubkey])),
        );

        final (statusFinal, activeFinal) = await ambiente.rideStateStore.load();
        expect(statusFinal, status);
        expect(activeFinal, ativa);
        expect(
          ambiente.rideStateStore.saveCount,
          0,
          reason: 'uma segunda aceitação nunca muda o estado do motorista',
        );
      });
    }

    testWidgets(
      'uma aceitação normal, com o motorista Aguardando, continua abrindo '
      'a modal (sem recusa)',
      (tester) async {
        final sentQuotes = InMemorySentQuotesStore(
          initial: {'quote-1': _origemPadrao},
        );
        final ambiente = await montar(tester, sentQuotesStore: sentQuotes);

        final aceitacao = aceitacaoAssinada(quoteId: 'quote-1');
        ambiente.gateway.emitir(
          IncomingEvent(relayUrl: 'wss://a.test', payload: aceitacao.payload),
        );
        await tester.pump();
        await tester.pump();
        await tester.pump();

        expect(find.text('Orçamento aceito'), findsOneWidget);
        expect(
          ambiente.gateway.publicados.where(
            (e) => e.kind == NostrEvent.kindRideNoLongerAvailable,
          ),
          isEmpty,
        );
      },
    );
  });

  group('MapScreen — notificar chegada ao passageiro (features 011 e 021)', () {
    testWidgets('enviar orçamento grava a origem da solicitação junto do id em '
        'SentQuotesStore (pré-requisito para a checagem de chegada)', (
      tester,
    ) async {
      final service = FakeLocationService();
      final ambiente = await montar(
        tester,
        locationService: service,
        routeDistanceService: FakeRouteDistanceService(
          resultados: [1000, 10000],
        ),
      );
      service.emitir(posicaoDeTeste());
      await tester.pump();
      await tester.tap(find.byType(Switch));
      await tester.pump();

      ambiente.gateway.emitir(
        IncomingEvent(
          relayUrl: 'wss://a.test',
          payload: solicitacaoAssinada(
            originLat: _origemPadrao.$1,
            originLon: _origemPadrao.$2,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      await tester.tap(find.widgetWithText(FilledButton, 'Enviar orçamento'));
      await tester.pumpAndSettle();

      final publicado = ambiente.gateway.publicados.single;
      final origem = await ambiente.sentQuotesStore.originFor(publicado.id);
      expect(origem, _origemPadrao);
    });

    testWidgets('iniciar a corrida persiste a ActiveRide com a origem da '
        'solicitação (FR-001)', (tester) async {
      final sentQuotes = InMemorySentQuotesStore(
        initial: {'quote-1': _origemPadrao},
      );
      final ambiente = await montar(tester, sentQuotesStore: sentQuotes);

      final aceitacao = aceitacaoAssinada(quoteId: 'quote-1');
      ambiente.gateway.emitir(
        IncomingEvent(relayUrl: 'wss://a.test', payload: aceitacao.payload),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump();

      await tester.tap(find.widgetWithText(FilledButton, 'Iniciar corrida'));
      await tester.pumpAndSettle();

      final (_, active) = await ambiente.rideStateStore.load();
      expect(active!.originLat, _origemPadrao.$1);
      expect(active.originLon, _origemPadrao.$2);
    });

    testWidgets(
      'posição dentro do raio de chegada publica kind 20007 com as tags '
      'corretas (FR-002)',
      (tester) async {
        final service = FakeLocationService();
        final rideState = InMemoryRideStateStore(
          status: DriverRideStatus.deslocandoAtePassageiro,
          active: ActiveRide(
            quoteId: 'quote-1',
            passengerPubkey: passageiroDeTeste.publicKey,
            originLat: _origemPadrao.$1,
            originLon: _origemPadrao.$2,
            destinationLat: _destinoPadrao.$1,
            destinationLon: _destinoPadrao.$2,
          ),
        );
        final ambiente = await montar(
          tester,
          locationService: service,
          rideStateStore: rideState,
        );

        // ~5,6 m da origem — dentro do raio de 30 m.
        service.emitir(
          DriverPosition(
            latitude: _origemPadrao.$1 + 0.00005,
            longitude: _origemPadrao.$2,
            capturedAt: DateTime.now(),
          ),
        );
        await tester.pump();

        final chegadas = ambiente.gateway.publicados
            .where((e) => e.kind == NostrEvent.kindArrivalNotice)
            .toList();
        expect(chegadas, hasLength(1));
        expect(chegadas.single.tags, anyElement(equals(['e', 'quote-1'])));
        expect(
          chegadas.single.tags,
          anyElement(equals(['p', passageiroDeTeste.publicKey])),
        );
      },
    );

    testWidgets(
      'posição a ~22 m da origem — marcadores sobrepostos no mapa — publica '
      'kind 20007 (raio de 30 m)',
      (tester) async {
        final service = FakeLocationService();
        final rideState = InMemoryRideStateStore(
          status: DriverRideStatus.deslocandoAtePassageiro,
          active: ActiveRide(
            quoteId: 'quote-1',
            passengerPubkey: passageiroDeTeste.publicKey,
            originLat: _origemPadrao.$1,
            originLon: _origemPadrao.$2,
            destinationLat: _destinoPadrao.$1,
            destinationLon: _destinoPadrao.$2,
          ),
        );
        final ambiente = await montar(
          tester,
          locationService: service,
          rideStateStore: rideState,
        );

        // Os marcadores de 44 px já parecem sobrepostos a ~22 m no zoom 17:
        // com o raio antigo de 10 m a chegada nunca era avisada.
        service.emitir(
          DriverPosition(
            latitude: _origemPadrao.$1 + 0.0002,
            longitude: _origemPadrao.$2,
            capturedAt: DateTime.now(),
          ),
        );
        await tester.pump();

        expect(
          ambiente.gateway.publicados.where(
            (e) => e.kind == NostrEvent.kindArrivalNotice,
          ),
          hasLength(1),
        );
      },
    );

    testWidgets(
      'posição a mais de 30 m da origem não publica kind 20007 (FR-002, '
      'SC-003)',
      (tester) async {
        final service = FakeLocationService();
        final rideState = InMemoryRideStateStore(
          status: DriverRideStatus.deslocandoAtePassageiro,
          active: ActiveRide(
            quoteId: 'quote-1',
            passengerPubkey: passageiroDeTeste.publicKey,
            originLat: _origemPadrao.$1,
            originLon: _origemPadrao.$2,
            destinationLat: _destinoPadrao.$1,
            destinationLon: _destinoPadrao.$2,
          ),
        );
        final ambiente = await montar(
          tester,
          locationService: service,
          rideStateStore: rideState,
        );

        // ~44 m da origem — fora do raio de 30 m.
        service.emitir(
          DriverPosition(
            latitude: _origemPadrao.$1 + 0.0004,
            longitude: _origemPadrao.$2,
            capturedAt: DateTime.now(),
          ),
        );
        await tester.pump();

        expect(
          ambiente.gateway.publicados.where(
            (e) => e.kind == NostrEvent.kindArrivalNotice,
          ),
          isEmpty,
        );
      },
    );

    // Feature 021: o aviso se repete a cada 5 s dentro do raio.
    final base = DateTime(2026, 10, 7, 12);
    DriverPosition noRaio(Duration depois) => DriverPosition(
      latitude: _origemPadrao.$1 + 0.00005, // ~5,6 m da origem
      longitude: _origemPadrao.$2,
      capturedAt: base.add(depois),
    );
    DriverPosition foraDoRaio(Duration depois) => DriverPosition(
      latitude: _origemPadrao.$1 + 0.0005, // ~55 m da origem
      longitude: _origemPadrao.$2,
      capturedAt: base.add(depois),
    );
    ActiveRide corridaACaminho() => ActiveRide(
      quoteId: 'quote-1',
      passengerPubkey: passageiroDeTeste.publicKey,
      originLat: _origemPadrao.$1,
      originLon: _origemPadrao.$2,
      destinationLat: _destinoPadrao.$1,
      destinationLon: _destinoPadrao.$2,
    );
    Iterable<NostrEvent> chegadas(FakeGateway g) =>
        g.publicados.where((e) => e.kind == NostrEvent.kindArrivalNotice);
    Future<void> emitirEm(
      WidgetTester tester,
      FakeLocationService service,
      DriverPosition posicao,
    ) async {
      service.emitir(posicao);
      await tester.pump();
    }

    testWidgets('dentro do raio, só publica de novo quando a posição capturada '
        'avança 5 s da última publicação (FR-002, SC-001)', (tester) async {
      final service = FakeLocationService();
      final ambiente = await montar(
        tester,
        locationService: service,
        rideStateStore: InMemoryRideStateStore(
          status: DriverRideStatus.deslocandoAtePassageiro,
          active: corridaACaminho(),
        ),
      );

      await emitirEm(tester, service, noRaio(Duration.zero));
      expect(chegadas(ambiente.gateway), hasLength(1));

      await emitirEm(tester, service, noRaio(const Duration(seconds: 4)));
      expect(
        chegadas(ambiente.gateway),
        hasLength(1),
        reason: '4 s ainda não completa o intervalo',
      );

      await emitirEm(tester, service, noRaio(const Duration(seconds: 5)));
      expect(chegadas(ambiente.gateway), hasLength(2));
    });

    testWidgets('parado dentro do raio por 30 s, publica um aviso a cada 5 s '
        '(FR-001, SC-001)', (tester) async {
      final service = FakeLocationService();
      final ambiente = await montar(
        tester,
        locationService: service,
        rideStateStore: InMemoryRideStateStore(
          status: DriverRideStatus.deslocandoAtePassageiro,
          active: corridaACaminho(),
        ),
      );

      for (var t = 0; t <= 30; t++) {
        await emitirEm(tester, service, noRaio(Duration(seconds: t)));
      }

      expect(chegadas(ambiente.gateway), hasLength(7)); // t = 0, 5, ... 30
    });

    testWidgets('fora do raio não publica, e ao voltar respeita os 5 s desde o '
        'último aviso (FR-003)', (tester) async {
      final service = FakeLocationService();
      final ambiente = await montar(
        tester,
        locationService: service,
        rideStateStore: InMemoryRideStateStore(
          status: DriverRideStatus.deslocandoAtePassageiro,
          active: corridaACaminho(),
        ),
      );

      await emitirEm(tester, service, noRaio(Duration.zero));
      await emitirEm(tester, service, foraDoRaio(const Duration(seconds: 1)));
      await emitirEm(tester, service, noRaio(const Duration(seconds: 2)));
      expect(
        chegadas(ambiente.gateway),
        hasLength(1),
        reason: 'voltou ao raio 2 s depois: sem rajada',
      );

      await emitirEm(tester, service, foraDoRaio(const Duration(seconds: 7)));
      expect(chegadas(ambiente.gateway), hasLength(1));

      await emitirEm(tester, service, noRaio(const Duration(seconds: 8)));
      expect(chegadas(ambiente.gateway), hasLength(2));
    });

    testWidgets('instante de captura repetido ou anterior à última publicação '
        'não conta como 5 s', (tester) async {
      final service = FakeLocationService();
      final ambiente = await montar(
        tester,
        locationService: service,
        rideStateStore: InMemoryRideStateStore(
          status: DriverRideStatus.deslocandoAtePassageiro,
          active: corridaACaminho(),
        ),
      );

      await emitirEm(tester, service, noRaio(const Duration(seconds: 10)));
      await emitirEm(tester, service, noRaio(const Duration(seconds: 10)));
      await emitirEm(tester, service, noRaio(Duration.zero));

      expect(chegadas(ambiente.gateway), hasLength(1));
    });

    testWidgets('cada aviso sai com as tags e/p da corrida e content cifrado '
        'ao passageiro que decifra para {} (FR-006)', (tester) async {
      final service = FakeLocationService();
      final ambiente = await montar(
        tester,
        locationService: service,
        rideStateStore: InMemoryRideStateStore(
          status: DriverRideStatus.deslocandoAtePassageiro,
          active: corridaACaminho(),
        ),
      );

      await emitirEm(tester, service, noRaio(Duration.zero));
      await emitirEm(tester, service, noRaio(const Duration(seconds: 5)));

      final avisos = chegadas(ambiente.gateway).toList();
      expect(avisos, hasLength(2));
      for (final aviso in avisos) {
        expect(aviso.tags, anyElement(equals(['e', 'quote-1'])));
        expect(
          aviso.tags,
          anyElement(equals(['p', passageiroDeTeste.publicKey])),
        );
        expect(decifradoPeloPassageiro(aviso), '{}');
      }
    });

    testWidgets('depois da confirmação de encontro (Em corrida), nenhum aviso '
        'de chegada à origem sai mais (FR-003, SC-003)', (tester) async {
      final service = FakeLocationService();
      final ambiente = await montar(
        tester,
        locationService: service,
        rideStateStore: InMemoryRideStateStore(
          status: DriverRideStatus.deslocandoAtePassageiro,
          active: corridaACaminho(),
        ),
      );
      await emitirEm(tester, service, noRaio(Duration.zero));
      expect(chegadas(ambiente.gateway), hasLength(1));

      ambiente.gateway.emitir(
        IncomingEvent(
          relayUrl: 'wss://a.test',
          payload: confirmacaoAssinada(
            kind: NostrEvent.kindMeetingConfirmed,
            quoteId: 'quote-1',
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await emitirEm(tester, service, noRaio(const Duration(seconds: 30)));

      expect(chegadas(ambiente.gateway), hasLength(1));
    });

    testWidgets('depois do cancelamento pelo passageiro, nenhum aviso sai mais '
        '(SC-003)', (tester) async {
      final service = FakeLocationService();
      final ambiente = await montar(
        tester,
        locationService: service,
        rideStateStore: InMemoryRideStateStore(
          status: DriverRideStatus.deslocandoAtePassageiro,
          active: corridaACaminho(),
        ),
      );
      await emitirEm(tester, service, noRaio(Duration.zero));

      ambiente.gateway.emitir(
        IncomingEvent(
          relayUrl: 'wss://a.test',
          payload: cancelamentoDoPassageiro(quoteId: 'quote-1'),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await emitirEm(tester, service, noRaio(const Duration(seconds: 30)));

      expect(chegadas(ambiente.gateway), hasLength(1));
    });

    testWidgets('uma corrida nova depois de cancelada não herda o intervalo '
        'da anterior (FR-004)', (tester) async {
      final service = FakeLocationService();
      final sentQuotes = InMemorySentQuotesStore(
        initial: {'quote-2': _origemPadrao},
        initialDestinations: {'quote-2': _destinoPadrao},
      );
      final ambiente = await montar(
        tester,
        locationService: service,
        sentQuotesStore: sentQuotes,
        rideStateStore: InMemoryRideStateStore(
          status: DriverRideStatus.deslocandoAtePassageiro,
          active: corridaACaminho(),
        ),
      );
      await emitirEm(tester, service, noRaio(Duration.zero));

      ambiente.gateway.emitir(
        IncomingEvent(
          relayUrl: 'wss://a.test',
          payload: cancelamentoDoPassageiro(quoteId: 'quote-1'),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      ambiente.gateway.emitir(
        IncomingEvent(
          relayUrl: 'wss://a.test',
          payload: aceitacaoAssinada(quoteId: 'quote-2').payload,
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Iniciar corrida'));
      await tester.pumpAndSettle();

      // 1 s depois do aviso da corrida anterior: sem herdar o intervalo.
      await emitirEm(tester, service, noRaio(const Duration(seconds: 1)));

      final avisos = chegadas(ambiente.gateway).toList();
      expect(avisos, hasLength(2));
      expect(avisos.last.tags, anyElement(equals(['e', 'quote-2'])));
    });

    testWidgets('reiniciar o app dentro do raio republica na primeira '
        'posição, sem marca persistida (FR-004, SC-004)', (tester) async {
      final service = FakeLocationService();
      final rideState = InMemoryRideStateStore(
        status: DriverRideStatus.deslocandoAtePassageiro,
        active: corridaACaminho(),
      );
      final primeira = await montar(
        tester,
        locationService: service,
        rideStateStore: rideState,
      );
      await emitirEm(tester, service, noRaio(Duration.zero));
      expect(chegadas(primeira.gateway), hasLength(1));

      await tester.pumpWidget(const SizedBox());
      final service2 = FakeLocationService();
      final segunda = await montar(
        tester,
        locationService: service2,
        rideStateStore: rideState,
      );
      await tester.pump();
      await emitirEm(tester, service2, noRaio(const Duration(seconds: 1)));

      expect(chegadas(segunda.gateway), hasLength(1));
    });

    testWidgets('sem relay conectado nada é publicado, sem erro (FR-005)', (
      tester,
    ) async {
      final service = FakeLocationService();
      final ambiente = await montar(
        tester,
        locationService: service,
        rideStateStore: InMemoryRideStateStore(
          status: DriverRideStatus.deslocandoAtePassageiro,
          active: corridaACaminho(),
        ),
      );
      await ambiente.relayService.removeRelay('wss://a.test');

      await emitirEm(tester, service, noRaio(Duration.zero));

      expect(chegadas(ambiente.gateway), isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('posição dentro do raio de qualquer ponto não publica chegada '
        'quando o motorista está Aguardando solicitação de corrida (FR-004)', (
      tester,
    ) async {
      final service = FakeLocationService();
      final ambiente = await montar(tester, locationService: service);

      service.emitir(
        DriverPosition(
          latitude: _origemPadrao.$1,
          longitude: _origemPadrao.$2,
          capturedAt: DateTime.now(),
        ),
      );
      await tester.pump();

      expect(
        ambiente.gateway.publicados.where(
          (e) => e.kind == NostrEvent.kindArrivalNotice,
        ),
        isEmpty,
      );
    });
  });

  group('MapScreen — passar a Em corrida ao confirmar o encontro (US1 da '
      'feature 012)', () {
    ActiveRide corridaDeTeste() => ActiveRide(
      quoteId: 'quote-1',
      passengerPubkey: passageiroDeTeste.publicKey,
      originLat: _origemPadrao.$1,
      originLon: _origemPadrao.$2,
      destinationLat: _destinoPadrao.$1,
      destinationLon: _destinoPadrao.$2,
    );

    testWidgets(
      'confirmação de encontro referenciando a corrida ativa transiciona '
      'para Em corrida (FR-001)',
      (tester) async {
        final rideState = InMemoryRideStateStore(
          status: DriverRideStatus.deslocandoAtePassageiro,
          active: corridaDeTeste(),
        );
        final ambiente = await montar(tester, rideStateStore: rideState);

        ambiente.gateway.emitir(
          IncomingEvent(
            relayUrl: 'wss://a.test',
            payload: confirmacaoAssinada(
              kind: NostrEvent.kindMeetingConfirmed,
              quoteId: 'quote-1',
            ),
          ),
        );
        await tester.pump();
        await tester.pump();

        final (status, _) = await ambiente.rideStateStore.load();
        expect(status, DriverRideStatus.emCorrida);
      },
    );

    testWidgets(
      'uma segunda confirmação de encontro (reentrega), já Em corrida, '
      'não altera nada (FR-002)',
      (tester) async {
        final rideState = InMemoryRideStateStore(
          status: DriverRideStatus.emCorrida,
          active: corridaDeTeste(),
        );
        final ambiente = await montar(tester, rideStateStore: rideState);

        ambiente.gateway.emitir(
          IncomingEvent(
            relayUrl: 'wss://a.test',
            payload: confirmacaoAssinada(
              kind: NostrEvent.kindMeetingConfirmed,
              quoteId: 'quote-1',
            ),
          ),
        );
        await tester.pump();
        await tester.pump();

        final (status, _) = await ambiente.rideStateStore.load();
        expect(status, DriverRideStatus.emCorrida);
      },
    );

    testWidgets(
      'confirmação de encontro sem corrida ativa (Aguardando) é ignorada '
      '(FR-002)',
      (tester) async {
        final ambiente = await montar(tester);

        ambiente.gateway.emitir(
          IncomingEvent(
            relayUrl: 'wss://a.test',
            payload: confirmacaoAssinada(
              kind: NostrEvent.kindMeetingConfirmed,
              quoteId: 'quote-qualquer',
            ),
          ),
        );
        await tester.pump();
        await tester.pump();

        final (status, active) = await ambiente.rideStateStore.load();
        expect(status, DriverRideStatus.aguardandoSolicitacao);
        expect(active, isNull);
      },
    );

    testWidgets(
      'confirmação de encontro referenciando outro quoteId é ignorada',
      (tester) async {
        final rideState = InMemoryRideStateStore(
          status: DriverRideStatus.deslocandoAtePassageiro,
          active: corridaDeTeste(),
        );
        final ambiente = await montar(tester, rideStateStore: rideState);

        ambiente.gateway.emitir(
          IncomingEvent(
            relayUrl: 'wss://a.test',
            payload: confirmacaoAssinada(
              kind: NostrEvent.kindMeetingConfirmed,
              quoteId: 'outra-corrida',
            ),
          ),
        );
        await tester.pump();
        await tester.pump();

        final (status, _) = await ambiente.rideStateStore.load();
        expect(status, DriverRideStatus.deslocandoAtePassageiro);
      },
    );
  });

  group('MapScreen — notificar automaticamente a chegada ao destino (US2 da '
      'feature 012)', () {
    testWidgets(
      'posição a 1 km ou menos do destino, Em corrida, publica kind 20009 '
      'com as tags corretas (FR-003, FR-004)',
      (tester) async {
        final service = FakeLocationService();
        final rideState = InMemoryRideStateStore(
          status: DriverRideStatus.emCorrida,
          active: ActiveRide(
            quoteId: 'quote-1',
            passengerPubkey: passageiroDeTeste.publicKey,
            originLat: _origemPadrao.$1,
            originLon: _origemPadrao.$2,
            destinationLat: _destinoPadrao.$1,
            destinationLon: _destinoPadrao.$2,
          ),
        );
        final ambiente = await montar(
          tester,
          locationService: service,
          rideStateStore: rideState,
        );

        // ~890 m do destino — dentro do raio de 1 km (emenda 23).
        service.emitir(
          DriverPosition(
            latitude: _destinoPadrao.$1 + 0.008,
            longitude: _destinoPadrao.$2,
            capturedAt: DateTime.now(),
          ),
        );
        await tester.pump();

        final chegadas = ambiente.gateway.publicados
            .where((e) => e.kind == NostrEvent.kindDestinationArrival)
            .toList();
        expect(chegadas, hasLength(1));
        expect(chegadas.single.tags, anyElement(equals(['e', 'quote-1'])));
        expect(
          chegadas.single.tags,
          anyElement(equals(['p', passageiroDeTeste.publicKey])),
        );
      },
    );

    testWidgets(
      'posição a mais de 1 km do destino não publica (FR-003, SC-005)',
      (tester) async {
        final service = FakeLocationService();
        final rideState = InMemoryRideStateStore(
          status: DriverRideStatus.emCorrida,
          active: ActiveRide(
            quoteId: 'quote-1',
            passengerPubkey: passageiroDeTeste.publicKey,
            originLat: _origemPadrao.$1,
            originLon: _origemPadrao.$2,
            destinationLat: _destinoPadrao.$1,
            destinationLon: _destinoPadrao.$2,
          ),
        );
        final ambiente = await montar(
          tester,
          locationService: service,
          rideStateStore: rideState,
        );

        // ~1,1 km do destino — fora do raio de 1 km.
        service.emitir(
          DriverPosition(
            latitude: _destinoPadrao.$1 + 0.01,
            longitude: _destinoPadrao.$2,
            capturedAt: DateTime.now(),
          ),
        );
        await tester.pump();

        expect(
          ambiente.gateway.publicados.where(
            (e) => e.kind == NostrEvent.kindDestinationArrival,
          ),
          isEmpty,
        );
      },
    );

    testWidgets(
      'depois de publicada, permanecer ou voltar a entrar no raio não '
      'publica de novo (FR-005)',
      (tester) async {
        final service = FakeLocationService();
        final rideState = InMemoryRideStateStore(
          status: DriverRideStatus.emCorrida,
          active: ActiveRide(
            quoteId: 'quote-1',
            passengerPubkey: passageiroDeTeste.publicKey,
            originLat: _origemPadrao.$1,
            originLon: _origemPadrao.$2,
            destinationLat: _destinoPadrao.$1,
            destinationLon: _destinoPadrao.$2,
          ),
        );
        final ambiente = await montar(
          tester,
          locationService: service,
          rideStateStore: rideState,
        );

        service.emitir(
          DriverPosition(
            latitude: _destinoPadrao.$1 + 0.00002,
            longitude: _destinoPadrao.$2,
            capturedAt: DateTime.now(),
          ),
        );
        await tester.pump();
        expect(
          ambiente.gateway.publicados.where(
            (e) => e.kind == NostrEvent.kindDestinationArrival,
          ),
          hasLength(1),
        );

        service.emitir(
          DriverPosition(
            latitude: _destinoPadrao.$1 + 0.00001,
            longitude: _destinoPadrao.$2,
            capturedAt: DateTime.now(),
          ),
        );
        await tester.pump();

        expect(
          ambiente.gateway.publicados.where(
            (e) => e.kind == NostrEvent.kindDestinationArrival,
          ),
          hasLength(1),
        );
      },
    );

    testWidgets('com destinationArrivalNotified já verdadeiro ao restaurar o '
        'estado (reinício), uma posição dentro do raio não publica de novo '
        '(FR-011)', (tester) async {
      final service = FakeLocationService();
      final rideState = InMemoryRideStateStore(
        status: DriverRideStatus.emCorrida,
        active: ActiveRide(
          quoteId: 'quote-1',
          passengerPubkey: passageiroDeTeste.publicKey,
          originLat: _origemPadrao.$1,
          originLon: _origemPadrao.$2,
          destinationLat: _destinoPadrao.$1,
          destinationLon: _destinoPadrao.$2,
          destinationArrivalNotified: true,
        ),
      );
      final ambiente = await montar(
        tester,
        locationService: service,
        rideStateStore: rideState,
      );

      service.emitir(
        DriverPosition(
          latitude: _destinoPadrao.$1 + 0.00002,
          longitude: _destinoPadrao.$2,
          capturedAt: DateTime.now(),
        ),
      );
      await tester.pump();

      expect(
        ambiente.gateway.publicados.where(
          (e) => e.kind == NostrEvent.kindDestinationArrival,
        ),
        isEmpty,
      );
    });

    testWidgets('posição a 5 m ou menos do destino, fora de Em corrida '
        '(Deslocando-se), não publica (FR-006)', (tester) async {
      final service = FakeLocationService();
      final rideState = InMemoryRideStateStore(
        status: DriverRideStatus.deslocandoAtePassageiro,
        active: ActiveRide(
          quoteId: 'quote-1',
          passengerPubkey: passageiroDeTeste.publicKey,
          originLat: _origemPadrao.$1,
          originLon: _origemPadrao.$2,
          destinationLat: _destinoPadrao.$1,
          destinationLon: _destinoPadrao.$2,
        ),
      );
      final ambiente = await montar(
        tester,
        locationService: service,
        rideStateStore: rideState,
      );

      service.emitir(
        DriverPosition(
          latitude: _destinoPadrao.$1 + 0.00002,
          longitude: _destinoPadrao.$2,
          capturedAt: DateTime.now(),
        ),
      );
      await tester.pump();

      expect(
        ambiente.gateway.publicados.where(
          (e) => e.kind == NostrEvent.kindDestinationArrival,
        ),
        isEmpty,
      );
    });
  });

  group('MapScreen — voltar a Aguardando ao confirmar a chegada ao destino '
      '(US3 da feature 012)', () {
    testWidgets('confirmação de destino referenciando a corrida ativa volta o '
        'motorista a Aguardando, sem corrida ativa (FR-007)', (tester) async {
      final rideState = InMemoryRideStateStore(
        status: DriverRideStatus.emCorrida,
        active: ActiveRide(
          quoteId: 'quote-1',
          passengerPubkey: passageiroDeTeste.publicKey,
          originLat: _origemPadrao.$1,
          originLon: _origemPadrao.$2,
          destinationLat: _destinoPadrao.$1,
          destinationLon: _destinoPadrao.$2,
          destinationArrivalNotified: true,
        ),
      );
      final ambiente = await montar(tester, rideStateStore: rideState);

      ambiente.gateway.emitir(
        IncomingEvent(
          relayUrl: 'wss://a.test',
          payload: confirmacaoAssinada(
            kind: NostrEvent.kindDestinationConfirmed,
            quoteId: 'quote-1',
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      final (status, active) = await ambiente.rideStateStore.load();
      expect(status, DriverRideStatus.aguardandoSolicitacao);
      expect(active, isNull);
    });

    testWidgets(
      'confirmação de destino fora de Em corrida (Aguardando) é ignorada '
      '(FR-008)',
      (tester) async {
        final ambiente = await montar(tester);

        ambiente.gateway.emitir(
          IncomingEvent(
            relayUrl: 'wss://a.test',
            payload: confirmacaoAssinada(
              kind: NostrEvent.kindDestinationConfirmed,
              quoteId: 'quote-qualquer',
            ),
          ),
        );
        await tester.pump();
        await tester.pump();

        final (status, active) = await ambiente.rideStateStore.load();
        expect(status, DriverRideStatus.aguardandoSolicitacao);
        expect(active, isNull);
      },
    );

    testWidgets(
      'confirmação de destino referenciando outro quoteId é ignorada',
      (tester) async {
        final rideState = InMemoryRideStateStore(
          status: DriverRideStatus.emCorrida,
          active: ActiveRide(
            quoteId: 'quote-1',
            passengerPubkey: passageiroDeTeste.publicKey,
            originLat: _origemPadrao.$1,
            originLon: _origemPadrao.$2,
            destinationLat: _destinoPadrao.$1,
            destinationLon: _destinoPadrao.$2,
          ),
        );
        final ambiente = await montar(tester, rideStateStore: rideState);

        ambiente.gateway.emitir(
          IncomingEvent(
            relayUrl: 'wss://a.test',
            payload: confirmacaoAssinada(
              kind: NostrEvent.kindDestinationConfirmed,
              quoteId: 'outra-corrida',
            ),
          ),
        );
        await tester.pump();
        await tester.pump();

        final (status, _) = await ambiente.rideStateStore.load();
        expect(status, DriverRideStatus.emCorrida);
      },
    );

    testWidgets(
      'depois de voltar a Aguardando, uma nova solicitação de corrida '
      'volta a abrir modal normalmente (US3 cenário 3 do spec.md)',
      (tester) async {
        final service = FakeLocationService();
        final rideState = InMemoryRideStateStore(
          status: DriverRideStatus.emCorrida,
          active: ActiveRide(
            quoteId: 'quote-1',
            passengerPubkey: passageiroDeTeste.publicKey,
            originLat: _origemPadrao.$1,
            originLon: _origemPadrao.$2,
            destinationLat: _destinoPadrao.$1,
            destinationLon: _destinoPadrao.$2,
          ),
        );
        final ambiente = await montar(
          tester,
          locationService: service,
          rideStateStore: rideState,
        );

        ambiente.gateway.emitir(
          IncomingEvent(
            relayUrl: 'wss://a.test',
            payload: confirmacaoAssinada(
              kind: NostrEvent.kindDestinationConfirmed,
              quoteId: 'quote-1',
            ),
          ),
        );
        await tester.pump();
        await tester.pump();
        await tester.pump();

        // Feature 013: a confirmação de destino também abre a modal de
        // avaliação da corrida — precisa ser dispensada antes de
        // continuar o cenário, mesmo padrão de qualquer outra modal desta
        // fila.
        await tester.tap(find.widgetWithText(TextButton, 'Pular'));
        await tester.pumpAndSettle();

        service.emitir(posicaoDeTeste());
        await tester.pump();
        await tester.tap(find.byType(Switch));
        await tester.pump();

        ambiente.gateway.emitir(
          IncomingEvent(
            relayUrl: 'wss://a.test',
            payload: solicitacaoAssinada(),
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(find.text('Solicitação de corrida'), findsOneWidget);
      },
    );
  });

  group('MapScreen — reputação no orçamento (feature 026, US4)', () {
    /// Motorista online, com uma solicitação de [autor] aberta e o orçamento
    /// enviado pelo botão da modal.
    Future<
      ({FakeGateway gateway, InMemoryReceiptStore receiptStore, String quoteId})
    >
    enviarOrcamento(
      WidgetTester tester, {
      Identity? autor,
      Object? reputacao,
      InMemoryReceiptStore? receiptStore,
      bool relayAceita = true,
    }) async {
      final service = FakeLocationService();
      final ambiente = await montar(
        tester,
        locationService: service,
        receiptStore: receiptStore,
        routeDistanceService: FakeRouteDistanceService(
          resultados: [1000, 10000],
        ),
      );
      ambiente.gateway.aceitarPublicacoes = relayAceita;
      service.emitir(posicaoDeTeste());
      await tester.pump();
      await tester.tap(find.byType(Switch));
      await tester.pump();

      ambiente.gateway.emitir(
        IncomingEvent(
          relayUrl: 'wss://a.test',
          payload: solicitacaoAssinada(autor: autor, reputacao: reputacao),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Enviar orçamento'));
      await tester.pumpAndSettle();

      return (
        gateway: ambiente.gateway,
        receiptStore: ambiente.receiptStore,
        quoteId: ambiente.gateway.publicados.isEmpty
            ? ''
            : ambiente.gateway.publicados.single.id,
      );
    }

    Map<String, dynamic> conteudoDoOrcamento(NostrEvent publicado) =>
        jsonDecode(
          MessageCipher().decryptFrom(
            passageiroDeTeste,
            motoristaDeTeste.publicKey,
            publicado.content,
          )!,
        ) as Map<String, dynamic>;

    Reputation reputacaoDe(Identity dono) {
      final cadeia = signedChain(avaliado: dono.publicKey, notas: [5, 3]);
      return Reputation(
        corridas: 2,
        avaliacoes: 2,
        media: 4.0,
        seqProximo: 2,
        head: cadeia.last.idRecibo,
        recibos: cadeia.reversed.toList(),
      );
    }

    testWidgets('guarda a reputação que o passageiro declarou, ligada ao id do '
        'orçamento', (tester) async {
      final rep = reputacaoDe(passageiroDeTeste);
      final r = await enviarOrcamento(
        tester,
        autor: passageiroDeTeste,
        reputacao: rep.toJson(),
      );

      expect(r.quoteId, isNotEmpty);
      expect(await r.receiptStore.declaredFor(r.quoteId), rep);
    });

    testWidgets('passageiro sem reputação: grava uma reputação vazia (R4)', (
      tester,
    ) async {
      final r = await enviarOrcamento(tester, autor: passageiroDeTeste);

      expect(
        await r.receiptStore.declaredFor(r.quoteId),
        const Reputation.empty(),
      );
    });

    testWidgets('reputação malformada do passageiro: orçamento sai e fica '
        'registrada como vazia', (tester) async {
      final r = await enviarOrcamento(
        tester,
        autor: passageiroDeTeste,
        reputacao: 'lixo',
      );

      expect(r.quoteId, isNotEmpty);
      expect(
        await r.receiptStore.declaredFor(r.quoteId),
        const Reputation.empty(),
      );
    });

    testWidgets('o orçamento leva a reputação própria calculada dos recibos '
        'recebidos', (tester) async {
      final loja = InMemoryReceiptStore();
      for (final r in signedChain(
        avaliado: motoristaDeTeste.publicKey,
        notas: [5, 4],
      )) {
        await loja.saveReceived(r);
      }
      final r = await enviarOrcamento(
        tester,
        autor: passageiroDeTeste,
        receiptStore: loja,
      );

      final conteudo = conteudoDoOrcamento(r.gateway.publicados.single);
      expect(
        Reputation.fromJson(conteudo['reputacao']),
        await loja.myReputation(),
      );
      expect((conteudo['reputacao'] as Map)['seq_proximo'], 2);
    });

    testWidgets('motorista sem recibos: o orçamento omite a chave reputacao', (
      tester,
    ) async {
      final r = await enviarOrcamento(tester, autor: passageiroDeTeste);

      expect(
        conteudoDoOrcamento(r.gateway.publicados.single)
            .containsKey('reputacao'),
        isFalse,
      );
    });

    testWidgets('nenhum relay aceitou o orçamento: nada é registrado', (
      tester,
    ) async {
      final rep = reputacaoDe(passageiroDeTeste);
      final r = await enviarOrcamento(
        tester,
        autor: passageiroDeTeste,
        reputacao: rep.toJson(),
        relayAceita: false,
      );

      expect(r.gateway.publicados, hasLength(1));
      expect(
        await r.receiptStore.declaredFor(r.gateway.publicados.single.id),
        isNull,
      );
    });
  });

  group('MapScreen — recibos recebidos do passageiro (feature 026, US3)', () {
    Receipt reciboDoPassageiro({int? nota = 5, int seq = 0, int guid = 1}) =>
        signedReceipt(
          avaliador: passageiroDeTeste,
          avaliado: motoristaDeTeste.publicKey,
          seq: seq,
          nota: nota,
          guid: fakeGuid(guid),
        );

    Receipt reciboEmitido() => signedReceipt(
      avaliador: motoristaDeTeste,
      avaliado: passageiroDeTeste.publicKey,
      seq: 0,
      guid: fakeGuid(9),
    );

    testWidgets('20014 válido é gravado e confirmado com um 20015', (
      tester,
    ) async {
      final ambiente = await montar(tester);
      final r = reciboDoPassageiro();
      // Emenda 26: o orçamento da corrida foi enviado a esse passageiro.
      await ambiente.receiptStore.saveDeclared(
        r.guidCorrida,
        passageiroDeTeste.publicKey,
        const Reputation.empty(),
      );

      ambiente.gateway.emitir(
        IncomingEvent(
          relayUrl: 'wss://a.test',
          payload: reciboAssinado(recibo: r),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(await ambiente.receiptStore.receivedFor(r.guidCorrida), r);
      expect((await ambiente.receiptStore.myReputation()).corridas, 1);
      expect(ambiente.gateway.publicados, hasLength(1));
      expect(
        ambiente.gateway.publicados.single.kind,
        NostrEvent.kindReceiptAck,
      );
    });

    testWidgets('20014 em claro é descartado, sem efeito nem confirmação', (
      tester,
    ) async {
      final ambiente = await montar(tester);

      ambiente.gateway.emitir(
        IncomingEvent(
          relayUrl: 'wss://a.test',
          payload: reciboAssinado(recibo: reciboDoPassageiro(), emClaro: true),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect((await ambiente.receiptStore.myReputation()).corridas, 0);
      expect(ambiente.gateway.publicados, isEmpty);
    });

    testWidgets('o mesmo 20014 entregue por dois relays tem um único efeito', (
      tester,
    ) async {
      final ambiente = await montar(tester);
      await ambiente.receiptStore.saveDeclared(
        fakeGuid(1),
        passageiroDeTeste.publicKey,
        const Reputation.empty(),
      );
      final payload = reciboAssinado(recibo: reciboDoPassageiro());

      for (final relay in ['wss://a.test', 'wss://b.test']) {
        ambiente.gateway.emitir(
          IncomingEvent(relayUrl: relay, payload: payload),
        );
        await tester.pump();
      }
      await tester.pump();

      expect((await ambiente.receiptStore.myReputation()).corridas, 1);
      expect(ambiente.gateway.publicados, hasLength(1));
    });

    testWidgets('20014 válido de um estranho com corrida inventada é ignorado '
        '(emenda 26)', (tester) async {
      final ambiente = await montar(tester);
      final estranho = identidadeDeTeste();
      final r = signedReceipt(
        avaliador: estranho,
        avaliado: motoristaDeTeste.publicKey,
        seq: 0,
        nota: 1,
        guid: fakeGuid(9006),
      );

      ambiente.gateway.emitir(
        IncomingEvent(
          relayUrl: 'wss://a.test',
          payload: reciboAssinado(recibo: r, autor: estranho),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect((await ambiente.receiptStore.myReputation()).corridas, 0);
      expect(ambiente.gateway.publicados, isEmpty);
    });

    testWidgets('20015 do avaliado confirma o recibo emitido pendente', (
      tester,
    ) async {
      final loja = InMemoryReceiptStore();
      final emitido = reciboEmitido();
      await loja.saveIssued(emitido);
      final ambiente = await montar(tester, receiptStore: loja);

      ambiente.gateway.emitir(
        IncomingEvent(
          relayUrl: 'wss://a.test',
          payload: confirmacaoDeReciboAssinada(
            guid: emitido.guidCorrida,
            idRecibo: emitido.idRecibo,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(await loja.pendingIssued(), isEmpty);
    });

    testWidgets('20015 de quem não é o avaliado não confirma nada', (
      tester,
    ) async {
      final loja = InMemoryReceiptStore();
      final emitido = reciboEmitido();
      await loja.saveIssued(emitido);
      final ambiente = await montar(tester, receiptStore: loja);

      ambiente.gateway.emitir(
        IncomingEvent(
          relayUrl: 'wss://a.test',
          payload: confirmacaoDeReciboAssinada(
            guid: emitido.guidCorrida,
            idRecibo: emitido.idRecibo,
            autor: identidadeDeTeste(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(await loja.pendingIssued(), [emitido]);
    });
  });

  group('MapScreen — avaliar corrida (US1 da feature 013)', () {
    /// Monta a tela com uma corrida ativa em "Em corrida" e entrega a
    /// confirmação de destino (`kind: 20010`) — deixa a corrida encerrada e
    /// a modal de avaliação aberta, mesmo estado esperado pelos testes
    /// desta feature.
    Future<
      ({
        InMemoryRideStateStore rideStateStore,
        InMemoryRideRatingStore rideRatingStore,
      })
    >
    montarComCorridaEncerrada(
      WidgetTester tester, {
      String quoteId = 'quote-1',
    }) async {
      final rideState = InMemoryRideStateStore(
        status: DriverRideStatus.emCorrida,
        active: ActiveRide(
          quoteId: quoteId,
          passengerPubkey: passageiroDeTeste.publicKey,
          originLat: _origemPadrao.$1,
          originLon: _origemPadrao.$2,
          destinationLat: _destinoPadrao.$1,
          destinationLon: _destinoPadrao.$2,
          destinationArrivalNotified: true,
        ),
      );
      final rideRatings = InMemoryRideRatingStore();
      final ambiente = await montar(
        tester,
        rideStateStore: rideState,
        rideRatingStore: rideRatings,
      );

      ambiente.gateway.emitir(
        IncomingEvent(
          relayUrl: 'wss://a.test',
          payload: confirmacaoAssinada(
            kind: NostrEvent.kindDestinationConfirmed,
            quoteId: quoteId,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump();

      return (rideStateStore: rideState, rideRatingStore: rideRatings);
    }

    testWidgets('confirmação de destino que encerra a corrida exibe a tela de '
        'avaliação, com cinco estrelas e nenhuma pré-selecionada (FR-001, '
        'FR-002)', (tester) async {
      await montarComCorridaEncerrada(tester);

      expect(find.text('Avalie a corrida'), findsOneWidget);
      expect(find.byIcon(Icons.star), findsNothing);
      expect(find.byIcon(Icons.star_border), findsNWidgets(5));
    });

    testWidgets(
      'tocar na estrela de posição N seleciona as estrelas 1..N e nenhuma '
      'das demais (FR-003)',
      (tester) async {
        await montarComCorridaEncerrada(tester);

        await tester.tap(find.byIcon(Icons.star_border).at(1));
        await tester.pump();

        expect(find.byIcon(Icons.star), findsNWidgets(2));
        expect(find.byIcon(Icons.star_border), findsNWidgets(3));
      },
    );

    testWidgets(
      'selecionar uma nota e confirmar persiste a avaliação associada ao '
      'quoteId da corrida e fecha a tela (FR-004, FR-005)',
      (tester) async {
        final ambiente = await montarComCorridaEncerrada(
          tester,
          quoteId: 'quote-42',
        );

        await tester.tap(find.byIcon(Icons.star_border).at(3));
        await tester.pump();
        await tester.tap(find.widgetWithText(FilledButton, 'Confirmar'));
        await tester.pumpAndSettle();

        expect(find.text('Avalie a corrida'), findsNothing);
        expect(ambiente.rideRatingStore.salvos, hasLength(1));
        expect(ambiente.rideRatingStore.salvos.single.rideId, 'quote-42');
        expect(ambiente.rideRatingStore.salvos.single.stars, 4);
      },
    );

    testWidgets(
      'pular a avaliação fecha a tela sem persistir nenhuma nota (FR-008)',
      (tester) async {
        final ambiente = await montarComCorridaEncerrada(tester);

        await tester.tap(find.widgetWithText(TextButton, 'Pular'));
        await tester.pumpAndSettle();

        expect(find.text('Avalie a corrida'), findsNothing);
        expect(ambiente.rideRatingStore.salvos, isEmpty);
      },
    );
  });

  group(
    'MapScreen — emissão do recibo ao fim da corrida (feature 026, US2)',
    () {
      Reputation declaradaDoPassageiro() {
        final cadeia = signedChain(
          avaliado: passageiroDeTeste.publicKey,
          notas: [5, 3],
        );
        return Reputation(
          corridas: 2,
          avaliacoes: 2,
          media: 4.0,
          seqProximo: 2,
          head: cadeia.last.idRecibo,
          recibos: cadeia.reversed.toList(),
        );
      }

      /// Corrida "Em corrida" encerrada pela confirmação de destino, com a
      /// reputação do passageiro já registrada (como o envio do orçamento faz).
      Future<
        ({
          InMemoryReceiptStore receiptStore,
          InMemoryRideRatingStore rideRatingStore,
          FakeGateway gateway,
        })
      >
      encerrarCorrida(
        WidgetTester tester, {
        Reputation? declarada,
        bool registrar = true,
        InMemoryRideRatingStore? rideRatingStore,
        bool relayAceita = true,
      }) async {
        final loja = InMemoryReceiptStore();
        if (registrar) {
          await loja.saveDeclared(
            'quote-1',
            passageiroDeTeste.publicKey,
            declarada ?? declaradaDoPassageiro(),
          );
        }
        final ratings = rideRatingStore ?? InMemoryRideRatingStore();
        final ambiente = await montar(
          tester,
          receiptStore: loja,
          rideRatingStore: ratings,
          rideStateStore: InMemoryRideStateStore(
            status: DriverRideStatus.emCorrida,
            active: ActiveRide(
              quoteId: 'quote-1',
              passengerPubkey: passageiroDeTeste.publicKey,
              originLat: _origemPadrao.$1,
              originLon: _origemPadrao.$2,
              destinationLat: _destinoPadrao.$1,
              destinationLon: _destinoPadrao.$2,
              destinationArrivalNotified: true,
            ),
          ),
        );
        ambiente.gateway.aceitarPublicacoes = relayAceita;
        ambiente.gateway.emitir(
          IncomingEvent(
            relayUrl: 'wss://a.test',
            payload: confirmacaoAssinada(
              kind: NostrEvent.kindDestinationConfirmed,
              quoteId: 'quote-1',
            ),
          ),
        );
        await tester.pump();
        await tester.pump();
        await tester.pump();
        return (
          receiptStore: loja,
          rideRatingStore: ratings,
          gateway: ambiente.gateway,
        );
      }

      Iterable<NostrEvent> recibosPublicados(FakeGateway g) =>
          g.publicados.where((e) => e.kind == NostrEvent.kindReceipt);

      testWidgets('confirmar com nota emite o recibo, pendente, e o publica', (
        tester,
      ) async {
        final rep = declaradaDoPassageiro();
        final a = await encerrarCorrida(tester, declarada: rep);

        await tester.tap(find.byIcon(Icons.star_border).at(3));
        await tester.pump();
        await tester.tap(find.widgetWithText(FilledButton, 'Confirmar'));
        await tester.pumpAndSettle();

        expect(a.rideRatingStore.salvos, hasLength(1));
        final emitido = (await a.receiptStore.pendingIssued()).single;
        expect(emitido.nota, 4);
        expect(emitido.seq, 2);
        expect(emitido.hashAnterior, rep.head);
        expect(emitido.guidCorrida, 'quote-1');
        expect(emitido.pubkeyAvaliado, passageiroDeTeste.publicKey);
        expect(recibosPublicados(a.gateway), hasLength(1));
      });

      testWidgets('pular a avaliação emite o recibo sem nota', (tester) async {
        final a = await encerrarCorrida(tester);

        await tester.tap(find.widgetWithText(TextButton, 'Pular'));
        await tester.pumpAndSettle();

        expect(a.rideRatingStore.salvos, isEmpty);
        final emitido = (await a.receiptStore.pendingIssued()).single;
        expect(emitido.nota, isNull);
        expect(recibosPublicados(a.gateway), hasLength(1));
      });

      testWidgets('o recibo só é emitido depois de a nota local ser gravada', (
        tester,
      ) async {
        final liberar = Completer<void>();
        final lento = _RatingLento(liberar.future);
        final a = await encerrarCorrida(tester, rideRatingStore: lento);

        await tester.tap(find.byIcon(Icons.star_border).at(4));
        await tester.pump();
        await tester.tap(find.widgetWithText(FilledButton, 'Confirmar'));
        await tester.pump();
        await tester.pump();

        expect(await a.receiptStore.pendingIssued(), isEmpty);
        expect(recibosPublicados(a.gateway), isEmpty);

        liberar.complete();
        await tester.pumpAndSettle();

        expect(lento.salvos, hasLength(1));
        expect(await a.receiptStore.pendingIssued(), hasLength(1));
      });

      testWidgets('reputação inconsistente: nenhum recibo, aviso de uma linha, '
          'nota local mantida', (tester) async {
        final rep = declaradaDoPassageiro();
        final a = await encerrarCorrida(
          tester,
          declarada: Reputation(
            corridas: rep.corridas,
            avaliacoes: rep.avaliacoes,
            media: rep.media,
            seqProximo: rep.seqProximo,
            head: fakeGuid(31337),
            recibos: rep.recibos,
          ),
        );

        await tester.tap(find.byIcon(Icons.star_border).at(2));
        await tester.pump();
        await tester.tap(find.widgetWithText(FilledButton, 'Confirmar'));
        await tester.pumpAndSettle();

        expect(a.rideRatingStore.salvos, hasLength(1));
        expect(await a.receiptStore.pendingIssued(), isEmpty);
        expect(recibosPublicados(a.gateway), isEmpty);
        expect(
          find.text(
            'Recibo não emitido: a reputação do passageiro está inconsistente.',
          ),
          findsOneWidget,
        );
      });

      testWidgets(
        'falha ao publicar não bloqueia a interface e deixa pendente',
        (tester) async {
          final a = await encerrarCorrida(tester, relayAceita: false);

          await tester.tap(find.widgetWithText(TextButton, 'Pular'));
          await tester.pumpAndSettle();

          expect(find.text('Avalie a corrida'), findsNothing);
          expect(await a.receiptStore.pendingIssued(), hasLength(1));
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets('corrida sem registro da reputação (anterior à feature): '
          'nenhum recibo, sem aviso', (tester) async {
        final a = await encerrarCorrida(tester, registrar: false);

        await tester.tap(find.widgetWithText(TextButton, 'Pular'));
        await tester.pumpAndSettle();

        expect(await a.receiptStore.pendingIssued(), isEmpty);
        expect(recibosPublicados(a.gateway), isEmpty);
        expect(find.byType(SnackBar), findsNothing);
      });

      testWidgets('corrida cancelada pelo passageiro não gera recibo', (
        tester,
      ) async {
        final loja = InMemoryReceiptStore();
        await loja.saveDeclared(
          'quote-1',
          passageiroDeTeste.publicKey,
          declaradaDoPassageiro(),
        );
        final ambiente = await montar(
          tester,
          receiptStore: loja,
          rideStateStore: InMemoryRideStateStore(
            status: DriverRideStatus.deslocandoAtePassageiro,
            active: ActiveRide(
              quoteId: 'quote-1',
              passengerPubkey: passageiroDeTeste.publicKey,
              originLat: _origemPadrao.$1,
              originLon: _origemPadrao.$2,
              destinationLat: _destinoPadrao.$1,
              destinationLon: _destinoPadrao.$2,
            ),
          ),
        );

        ambiente.gateway.emitir(
          IncomingEvent(
            relayUrl: 'wss://a.test',
            payload: cancelamentoDoPassageiro(quoteId: 'quote-1'),
          ),
        );
        await tester.pump();
        await tester.pump();
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();

        expect(await loja.pendingIssued(), isEmpty);
        expect(recibosPublicados(ambiente.gateway), isEmpty);
      });
    },
  );

  group('MapScreen — rota da corrida no mapa (feature 016)', () {
    const origem = LatLng(-28.9298, -49.4753);
    const destino = LatLng(-28.6721, -49.3671);

    ActiveRide corridaDeTeste() => ActiveRide(
      quoteId: 'quote-1',
      passengerPubkey: passageiroDeTeste.publicKey,
      originLat: -28.9298,
      originLon: -49.4753,
      destinationLat: -28.6721,
      destinationLon: -49.3671,
    );

    DriverPosition em(double lat, double lon) => DriverPosition(
      latitude: lat,
      longitude: lon,
      capturedAt: DateTime.now(),
    );

    // ~11 m ao norte de `_base`, e ~111 m ao norte.
    const baseLat = -28.9350;
    const baseLon = -49.4800;
    DriverPosition base() => em(baseLat, baseLon);
    DriverPosition pertoDaBase() => em(-28.9349, baseLon);
    DriverPosition longeDaBase() => em(-28.9340, baseLon);

    Future<void> assentar(WidgetTester tester) async {
      await tester.pump();
      await tester.pump();
    }

    final polilinhas = find.byWidgetPredicate((w) => w is PolylineLayer);
    final marcadorEmbarque = find.byIcon(Icons.person);
    final marcadorDestino = find.byIcon(Icons.flag);
    final faixaDeFalha = find.text('Não foi possível traçar a rota agora.');

    PolylineLayer camadaDaRota(WidgetTester tester) =>
        tester.widget<PolylineLayer>(polilinhas);

    LatLng centroDoMapa(WidgetTester tester) => tester
        .widget<FlutterMap>(find.byType(FlutterMap))
        .mapController!
        .camera
        .center;

    Future<
      ({
        FakeLocationService localizacao,
        FakeRouteDistanceService rotas,
        InMemoryRideStateStore rideState,
        FakeGateway gateway,
      })
    >
    iniciarEm(WidgetTester tester, DriverRideStatus status) async {
      final localizacao = FakeLocationService();
      final rotas = FakeRouteDistanceService();
      final rideState = InMemoryRideStateStore(
        status: status,
        active: status == DriverRideStatus.aguardandoSolicitacao
            ? null
            : corridaDeTeste(),
      );
      final ambiente = await montar(
        tester,
        locationService: localizacao,
        routeDistanceService: rotas,
        rideStateStore: rideState,
      );
      return (
        localizacao: localizacao,
        rotas: rotas,
        rideState: rideState,
        gateway: ambiente.gateway,
      );
    }

    group('Deslocando-se até o passageiro (US1)', () {
      testWidgets(
        'mostra o marcador de embarque e o trajeto roxo de 5 px até a origem '
        '(FR-001, FR-009), restaurados do ActiveRide sem ação do motorista '
        '(FR-006)',
        (tester) async {
          final a = await iniciarEm(
            tester,
            DriverRideStatus.deslocandoAtePassageiro,
          );

          a.localizacao.emitir(base());
          await assentar(tester);

          expect(a.rotas.traceChamadas, hasLength(1));
          expect(a.rotas.traceChamadas.single.destination, origem);
          expect(marcadorEmbarque, findsOneWidget);
          expect(marcadorDestino, findsNothing);
          final linha = camadaDaRota(tester).polylines.single;
          expect(linha.strokeWidth, 5);
          expect(linha.color, const Color(0xFF6B3FE0));
          expect(faixaDeFalha, findsNothing);
        },
      );

      testWidgets(
        'recalcula só ao sair 50 m ou mais da rota traçada, nunca a cada '
        'posição (FR-004, SC-004)',
        (tester) async {
          final a = await iniciarEm(
            tester,
            DriverRideStatus.deslocandoAtePassageiro,
          );

          a.localizacao.emitir(base());
          await assentar(tester);
          a.localizacao.emitir(pertoDaBase());
          await assentar(tester);
          expect(a.rotas.traceChamadas, hasLength(1));

          final distante = longeDaBase();
          a.localizacao.emitir(distante);
          await assentar(tester);

          expect(a.rotas.traceChamadas, hasLength(2));
          expect(
            a.rotas.traceChamadas.last.origin,
            LatLng(distante.latitude, distante.longitude),
          );
        },
      );

      testWidgets(
        'andar sobre a rota já traçada, por centenas de metros, não consulta '
        'de novo',
        (tester) async {
          final a = await iniciarEm(tester, DriverRideStatus.emCorrida);

          a.localizacao.emitir(base());
          await assentar(tester);
          // ~290 m adiante, em cima da reta base → destino devolvida pelo
          // dublê.
          a.localizacao.emitir(em(-28.932371, -49.478871));
          await assentar(tester);
          a.localizacao.emitir(em(-28.929742, -49.477742));
          await assentar(tester);

          expect(a.rotas.traceChamadas, hasLength(1));
        },
      );

      testWidgets('nunca há duas consultas de rota em voo ao mesmo tempo', (
        tester,
      ) async {
        final a = await iniciarEm(
          tester,
          DriverRideStatus.deslocandoAtePassageiro,
        );
        final bloqueio = Completer<void>();
        a.rotas.traceBloqueio = bloqueio;

        a.localizacao.emitir(base());
        await assentar(tester);
        a.localizacao.emitir(longeDaBase());
        await assentar(tester);
        expect(
          a.rotas.traceChamadas,
          hasLength(1),
          reason: 'a primeira ainda não respondeu',
        );

        bloqueio.complete();
        await assentar(tester);

        expect(
          a.rotas.traceChamadas,
          hasLength(2),
          reason: 'o motorista andou 50 m+ durante a espera',
        );
      });

      testWidgets(
        'falha do serviço: sem trajeto, com marcador e faixa de aviso, sem '
        'bloquear a localização (FR-005); a falha conta para o limiar e a '
        'recuperação remove a faixa',
        (tester) async {
          final a = await iniciarEm(
            tester,
            DriverRideStatus.deslocandoAtePassageiro,
          );
          a.rotas.traceErro = Exception('sem rede');

          a.localizacao.emitir(base());
          await assentar(tester);

          expect(polilinhas, findsNothing);
          expect(marcadorEmbarque, findsOneWidget);
          expect(faixaDeFalha, findsOneWidget);
          expect(
            a.gateway.publicados.where(
              (e) => e.kind == NostrEvent.kindDriverLocation,
            ),
            isNotEmpty,
            reason: 'a publicação de localização segue funcionando',
          );

          a.localizacao.emitir(pertoDaBase());
          await assentar(tester);
          expect(
            a.rotas.traceChamadas,
            hasLength(1),
            reason: 'a tentativa falha conta: sem nova consulta a < 50 m',
          );

          a.rotas.traceErro = null;
          a.localizacao.emitir(longeDaBase());
          await assentar(tester);

          expect(a.rotas.traceChamadas, hasLength(2));
          expect(polilinhas, findsOneWidget);
          expect(faixaDeFalha, findsNothing);
        },
      );

      testWidgets(
        'o enquadramento do primeiro trajeto não é desfeito pela posição '
        'seguinte; "Centralizar" volta a seguir o motorista (FR-010)',
        (tester) async {
          final a = await iniciarEm(
            tester,
            DriverRideStatus.deslocandoAtePassageiro,
          );

          a.localizacao.emitir(base());
          await assentar(tester);
          final enquadrado = centroDoMapa(tester);
          expect(
            enquadrado,
            isNot(const LatLng(baseLat, baseLon)),
            reason: 'enquadrou motorista + embarque, não só o motorista',
          );

          a.localizacao.emitir(pertoDaBase());
          await assentar(tester);
          expect(centroDoMapa(tester), enquadrado);

          // Recálculo de 50 m troca a linha, mas não reenquadra.
          a.localizacao.emitir(longeDaBase());
          await assentar(tester);
          expect(a.rotas.traceChamadas, hasLength(2));
          expect(centroDoMapa(tester), enquadrado);

          await tester.tap(find.byIcon(Icons.my_location));
          await assentar(tester);
          expect(
            centroDoMapa(tester),
            const LatLng(-28.9340, baseLon),
            reason: 'a última posição recebida, a de longeDaBase()',
          );

          // Com o foco de volta, a próxima posição é seguida de novo.
          a.localizacao.emitir(pertoDaBase());
          await assentar(tester);
          expect(centroDoMapa(tester), const LatLng(-28.9349, baseLon));
        },
      );
    });

    group('Em corrida (US2)', () {
      testWidgets(
        'mostra a bandeira do destino e o trajeto até ele, sem o embarque '
        '(FR-002)',
        (tester) async {
          final a = await iniciarEm(tester, DriverRideStatus.emCorrida);

          a.localizacao.emitir(base());
          await assentar(tester);

          expect(a.rotas.traceChamadas.single.destination, destino);
          expect(marcadorDestino, findsOneWidget);
          expect(marcadorEmbarque, findsNothing);
          expect(camadaDaRota(tester).polylines.single.points.last, destino);
        },
      );

      testWidgets(
        'a confirmação de encontro troca o trecho: some o embarque, surge o '
        'destino, com nova consulta ao destino (SC-002)',
        (tester) async {
          final a = await iniciarEm(
            tester,
            DriverRideStatus.deslocandoAtePassageiro,
          );
          final ambiente = a;
          a.localizacao.emitir(base());
          await assentar(tester);
          expect(marcadorEmbarque, findsOneWidget);

          ambiente.gateway.emitir(
            IncomingEvent(
              relayUrl: 'wss://a.test',
              payload: confirmacaoAssinada(
                kind: NostrEvent.kindMeetingConfirmed,
                quoteId: 'quote-1',
              ),
            ),
          );
          await assentar(tester);
          await assentar(tester);

          expect(marcadorEmbarque, findsNothing);
          expect(marcadorDestino, findsOneWidget);
          expect(a.rotas.traceChamadas, hasLength(2));
          expect(a.rotas.traceChamadas.last.destination, destino);
          expect(camadaDaRota(tester).polylines.single.points.last, destino);
        },
      );

      testWidgets('resposta tardia do trecho anterior é descartada (FR-002)', (
        tester,
      ) async {
        final a = await iniciarEm(
          tester,
          DriverRideStatus.deslocandoAtePassageiro,
        );
        final bloqueio = Completer<void>();
        a.rotas.traceBloqueio = bloqueio;
        a.localizacao.emitir(base());
        await assentar(tester);
        expect(a.rotas.traceChamadas, hasLength(1));

        a.gateway.emitir(
          IncomingEvent(
            relayUrl: 'wss://a.test',
            payload: confirmacaoAssinada(
              kind: NostrEvent.kindMeetingConfirmed,
              quoteId: 'quote-1',
            ),
          ),
        );
        await assentar(tester);
        bloqueio.complete();
        await assentar(tester);
        await assentar(tester);

        expect(a.rotas.traceChamadas, hasLength(2));
        expect(a.rotas.traceChamadas.last.destination, destino);
        final pontos = camadaDaRota(tester).polylines.single.points;
        expect(
          pontos.last,
          destino,
          reason: 'só o trajeto do destino fica; o do embarque foi descartado',
        );
      });
    });

    group('publicação da rota ao passageiro (feature 017)', () {
      Iterable<NostrEvent> rotasPublicadas(FakeGateway gateway) =>
          gateway.publicados.where((e) => e.kind == NostrEvent.kindRideRoute);

      testWidgets(
        'em Em corrida publica um kind 20011 por trajeto, com as tags da '
        'corrida e os pontos do trajeto (FR-002, FR-003, FR-004)',
        (tester) async {
          final a = await iniciarEm(tester, DriverRideStatus.emCorrida);

          a.localizacao.emitir(base());
          await assentar(tester);

          final publicadas = rotasPublicadas(a.gateway).toList();
          expect(publicadas, hasLength(1));
          expect(publicadas.single.tags, anyElement(equals(['e', 'quote-1'])));
          expect(
            publicadas.single.tags,
            anyElement(equals(['p', passageiroDeTeste.publicKey])),
          );
          final pontos =
              (jsonDecode(decifradoPeloPassageiro(publicadas.single)!)
                      as Map<String, dynamic>)['points']
                  as List<dynamic>;
          expect(pontos, hasLength(2));
          expect(pontos.last, [destino.latitude, destino.longitude]);
        },
      );

      testWidgets(
        'republica a cada recálculo (fora da rota) sem nenhuma consulta além '
        'das do mapa (FR-004, FR-007, SC-003)',
        (tester) async {
          final a = await iniciarEm(tester, DriverRideStatus.emCorrida);

          a.localizacao.emitir(base());
          await assentar(tester);
          // ~195 m a oeste: bem fora da rota base → destino.
          a.localizacao.emitir(em(baseLat, baseLon - 0.002));
          await assentar(tester);

          expect(rotasPublicadas(a.gateway), hasLength(2));
          expect(a.rotas.traceChamadas, hasLength(2));
        },
      );

      testWidgets(
        'após um reinício do app já em Em corrida, o trajeto recalculado é '
        'publicado de novo (Edge Case)',
        (tester) async {
          final a = await iniciarEm(tester, DriverRideStatus.emCorrida);
          a.localizacao.emitir(base());
          await assentar(tester);
          expect(rotasPublicadas(a.gateway), hasLength(1));

          // Novo mapa com o mesmo estado persistido: o que um reinício faz.
          await tester.pumpWidget(const SizedBox());
          final b = await iniciarEm(tester, DriverRideStatus.emCorrida);
          b.localizacao.emitir(base());
          await assentar(tester);

          expect(rotasPublicadas(b.gateway), hasLength(1));
        },
      );

      testWidgets(
        'em Deslocando-se até o passageiro não publica a rota do embarque '
        '(FR-005)',
        (tester) async {
          final a = await iniciarEm(
            tester,
            DriverRideStatus.deslocandoAtePassageiro,
          );

          a.localizacao.emitir(base());
          await assentar(tester);

          expect(a.rotas.traceChamadas, hasLength(1));
          expect(rotasPublicadas(a.gateway), isEmpty);
        },
      );

      testWidgets('em Aguardando nunca publica rota (FR-005)', (tester) async {
        final a = await iniciarEm(
          tester,
          DriverRideStatus.aguardandoSolicitacao,
        );

        a.localizacao.emitir(base());
        await assentar(tester);

        expect(rotasPublicadas(a.gateway), isEmpty);
      });

      testWidgets(
        'resposta tardia depois de a corrida terminar não é publicada '
        '(FR-005)',
        (tester) async {
          final a = await iniciarEm(tester, DriverRideStatus.emCorrida);
          final bloqueio = Completer<void>();
          a.rotas.traceBloqueio = bloqueio;
          a.localizacao.emitir(base());
          await assentar(tester);

          a.gateway.emitir(
            IncomingEvent(
              relayUrl: 'wss://a.test',
              payload: confirmacaoAssinada(
                kind: NostrEvent.kindDestinationConfirmed,
                quoteId: 'quote-1',
              ),
            ),
          );
          await assentar(tester);
          bloqueio.complete();
          await assentar(tester);
          await assentar(tester);

          expect(rotasPublicadas(a.gateway), isEmpty);
        },
      );

      testWidgets(
        'o trecho do embarque calculado antes do encontro não é publicado, '
        'só o do destino depois dele (FR-005)',
        (tester) async {
          final a = await iniciarEm(
            tester,
            DriverRideStatus.deslocandoAtePassageiro,
          );
          a.localizacao.emitir(base());
          await assentar(tester);
          expect(rotasPublicadas(a.gateway), isEmpty);

          a.gateway.emitir(
            IncomingEvent(
              relayUrl: 'wss://a.test',
              payload: confirmacaoAssinada(
                kind: NostrEvent.kindMeetingConfirmed,
                quoteId: 'quote-1',
              ),
            ),
          );
          await assentar(tester);
          await assentar(tester);

          expect(rotasPublicadas(a.gateway), hasLength(1));
        },
      );

      testWidgets('falha do serviço de rotas não publica nada e não bloqueia a '
          'localização (FR-006, SC-005)', (tester) async {
        final a = await iniciarEm(tester, DriverRideStatus.emCorrida);
        a.rotas.traceErro = StateError('sem rede');

        a.localizacao.emitir(base());
        await assentar(tester);

        expect(rotasPublicadas(a.gateway), isEmpty);
        expect(faixaDeFalha, findsOneWidget);
        expect(
          a.gateway.publicados.where(
            (e) => e.kind == NostrEvent.kindDriverLocation,
          ),
          isNotEmpty,
        );
      });

      testWidgets(
        'trajeto com um só ponto não publica e não derruba o mapa (FR-006)',
        (tester) async {
          final a = await iniciarEm(tester, DriverRideStatus.emCorrida);
          a.rotas.tracePontos = const [LatLng(-28.9, -49.4)];

          a.localizacao.emitir(base());
          await assentar(tester);

          expect(rotasPublicadas(a.gateway), isEmpty);
          expect(find.byType(FlutterMap), findsOneWidget);
        },
      );
    });

    group('Fora da corrida (US3)', () {
      testWidgets(
        'Aguardando: nenhum trajeto, marcador ou aviso, e nenhuma consulta '
        '(FR-003)',
        (tester) async {
          final a = await iniciarEm(
            tester,
            DriverRideStatus.aguardandoSolicitacao,
          );

          a.localizacao.emitir(base());
          await assentar(tester);

          expect(polilinhas, findsNothing);
          expect(marcadorEmbarque, findsNothing);
          expect(marcadorDestino, findsNothing);
          expect(faixaDeFalha, findsNothing);
          expect(a.rotas.traceChamadas, isEmpty);
          expect(
            centroDoMapa(tester),
            const LatLng(baseLat, baseLon),
            reason: 'sem trajeto, o mapa segue o motorista como antes',
          );
        },
      );

      testWidgets(
        'a confirmação de destino encerra a corrida: trajeto e marcador somem '
        'e uma resposta em voo é descartada (FR-003)',
        (tester) async {
          final a = await iniciarEm(tester, DriverRideStatus.emCorrida);
          a.localizacao.emitir(base());
          await assentar(tester);
          expect(polilinhas, findsOneWidget);

          a.gateway.emitir(
            IncomingEvent(
              relayUrl: 'wss://a.test',
              payload: confirmacaoAssinada(
                kind: NostrEvent.kindDestinationConfirmed,
                quoteId: 'quote-1',
              ),
            ),
          );
          await assentar(tester);
          await assentar(tester);

          expect(polilinhas, findsNothing);
          expect(marcadorDestino, findsNothing);
          expect(a.rotas.traceChamadas, hasLength(1));
        },
      );

      testWidgets(
        'resposta de rota que chega depois do encerramento não reaparece',
        (tester) async {
          final a = await iniciarEm(tester, DriverRideStatus.emCorrida);
          final bloqueio = Completer<void>();
          a.rotas.traceBloqueio = bloqueio;
          a.localizacao.emitir(base());
          await assentar(tester);

          a.gateway.emitir(
            IncomingEvent(
              relayUrl: 'wss://a.test',
              payload: confirmacaoAssinada(
                kind: NostrEvent.kindDestinationConfirmed,
                quoteId: 'quote-1',
              ),
            ),
          );
          await assentar(tester);
          await assentar(tester);
          bloqueio.complete();
          await assentar(tester);

          expect(polilinhas, findsNothing);
          expect(marcadorDestino, findsNothing);
          expect(a.rotas.traceChamadas, hasLength(1));
        },
      );

      testWidgets(
        'corrida sem coordenada gravada (origem 0,0) fica sem trajeto e sem '
        'consulta',
        (tester) async {
          final localizacao = FakeLocationService();
          final rotas = FakeRouteDistanceService();
          await montar(
            tester,
            locationService: localizacao,
            routeDistanceService: rotas,
            rideStateStore: InMemoryRideStateStore(
              status: DriverRideStatus.deslocandoAtePassageiro,
              active: ActiveRide(
                quoteId: 'quote-1',
                passengerPubkey: passageiroDeTeste.publicKey,
                originLat: 0,
                originLon: 0,
                destinationLat: 0,
                destinationLon: 0,
              ),
            ),
          );

          localizacao.emitir(base());
          await assentar(tester);

          expect(rotas.traceChamadas, isEmpty);
          expect(polilinhas, findsNothing);
          expect(marcadorEmbarque, findsNothing);
        },
      );
    });
  });

  group('MapScreen — cancelar corrida (feature 018)', () {
    const botao = Key('botao-cancelar-corrida');
    const origem = LatLng(-28.9298, -49.4753);
    const destino = LatLng(-28.6721, -49.3671);

    ActiveRide corrida({String quoteId = 'quote-1'}) => ActiveRide(
      quoteId: quoteId,
      passengerPubkey: passageiroDeTeste.publicKey,
      originLat: origem.latitude,
      originLon: origem.longitude,
      destinationLat: destino.latitude,
      destinationLon: destino.longitude,
    );

    DriverPosition em(double lat, double lon) => DriverPosition(
      latitude: lat,
      longitude: lon,
      capturedAt: DateTime.now(),
    );

    final polilinhas = find.byWidgetPredicate((w) => w is PolylineLayer);
    // O botão do cartão de status tem a chave `botao`; o da modal, não.
    final confirmar = find.ancestor(
      of: find.text('Cancelar corrida'),
      matching: find.byWidgetPredicate(
        (w) => w is FilledButton && w.key == null,
      ),
    );
    final voltar = find.widgetWithText(TextButton, 'Voltar');
    final modalDeAvaliacao = find.widgetWithText(TextButton, 'Pular');

    Iterable<NostrEvent> cancelamentos(FakeGateway g) =>
        g.publicados.where((e) => e.kind == NostrEvent.kindRideCancelled);

    Future<void> assentar(WidgetTester tester) async {
      await tester.pump();
      await tester.pump();
    }

    Future<
      ({
        FakeLocationService localizacao,
        FakeRouteDistanceService rotas,
        InMemoryRideStateStore rideState,
        InMemoryRideRatingStore ratings,
        FakeGateway gateway,
        RelayService relayService,
      })
    >
    iniciarEm(
      WidgetTester tester,
      DriverRideStatus status, {
      InMemoryRideStateStore? rideState,
    }) async {
      final localizacao = FakeLocationService();
      final rotas = FakeRouteDistanceService();
      final estado =
          rideState ??
          InMemoryRideStateStore(
            status: status,
            active: status == DriverRideStatus.aguardandoSolicitacao
                ? null
                : corrida(),
          );
      final ambiente = await montar(
        tester,
        locationService: localizacao,
        routeDistanceService: rotas,
        rideStateStore: estado,
      );
      return (
        localizacao: localizacao,
        rotas: rotas,
        rideState: estado,
        ratings: ambiente.rideRatingStore,
        gateway: ambiente.gateway,
        relayService: ambiente.relayService,
      );
    }

    Future<void> cancelar(WidgetTester tester) async {
      await tester.tap(find.byKey(botao));
      await tester.pumpAndSettle();
      await tester.tap(confirmar);
      await tester.pumpAndSettle();
    }

    group('Aparência dos botões de cancelar (feature 022)', () {
      ButtonStyle estilo(WidgetTester tester, Finder botao) =>
          tester.widget<FilledButton>(botao).style!;
      Color fundoDe(ButtonStyle e) => e.backgroundColor!.resolve({})!;
      Color textoDe(ButtonStyle e) => e.foregroundColor!.resolve({})!;

      double razaoDeContraste(Color a, Color b) {
        final la = a.computeLuminance();
        final lb = b.computeLuminance();
        final claro = la > lb ? la : lb;
        final escuro = la > lb ? lb : la;
        return (claro + 0.05) / (escuro + 0.05);
      }

      for (final status in [
        DriverRideStatus.deslocandoAtePassageiro,
        DriverRideStatus.emCorrida,
      ]) {
        testWidgets('o botão do mapa é roxo com texto branco e contraste '
            '>= 4,5:1 em ${status.name} (FR-001, FR-002, FR-005, SC-001, '
            'SC-002)', (tester) async {
          await iniciarEm(tester, status);

          final e = estilo(tester, find.byKey(botao));
          expect(fundoDe(e), IdentidadeVisual.roxo);
          expect(textoDe(e), Colors.white);
          expect(
            razaoDeContraste(fundoDe(e), textoDe(e)),
            greaterThanOrEqualTo(4.5),
          );
          expect(
            find.descendant(
              of: find.byKey(botao),
              matching: find.text('Cancelar corrida'),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: find.byKey(botao),
              matching: find.byIcon(Icons.close),
            ),
            findsOneWidget,
          );
          expect(tester.getSize(find.byKey(botao)).height, 48);
        });
      }

      testWidgets('o botão do mapa e o da confirmação têm as mesmas cores '
          '(FR-003, SC-003)', (tester) async {
        await iniciarEm(tester, DriverRideStatus.deslocandoAtePassageiro);

        final doMapa = estilo(tester, find.byKey(botao));
        await tester.tap(find.byKey(botao));
        await tester.pumpAndSettle();
        final daModal = estilo(tester, confirmar);

        expect(fundoDe(daModal), fundoDe(doMapa));
        expect(textoDe(daModal), textoDe(doMapa));
      });
    });

    group('Deslocando-se até o passageiro (US1)', () {
      testWidgets('o botão existe em Deslocando-se até o passageiro (FR-001)', (
        tester,
      ) async {
        await iniciarEm(tester, DriverRideStatus.deslocandoAtePassageiro);
        expect(find.byKey(botao), findsOneWidget);
      });

      testWidgets('o botão não existe em Aguardando (FR-001)', (tester) async {
        await iniciarEm(tester, DriverRideStatus.aguardandoSolicitacao);
        expect(find.byKey(botao), findsNothing);
      });

      testWidgets('tocar no botão abre a modal; "Voltar" desiste sem efeito '
          '(FR-002, SC-003)', (tester) async {
        final a = await iniciarEm(
          tester,
          DriverRideStatus.deslocandoAtePassageiro,
        );

        await tester.tap(find.byKey(botao));
        await tester.pumpAndSettle();
        expect(find.text('Cancelar corrida?'), findsOneWidget);

        await tester.tap(voltar);
        await tester.pumpAndSettle();

        expect(find.text('Cancelar corrida?'), findsNothing);
        final (status, active) = await a.rideState.load();
        expect(status, DriverRideStatus.deslocandoAtePassageiro);
        expect(active, corrida());
        expect(cancelamentos(a.gateway), isEmpty);
        expect(find.byKey(botao), findsOneWidget);
      });

      testWidgets('confirmar volta a Aguardando, zera e persiste a corrida e '
          'publica um único kind 20012 com as tags da corrida '
          '(FR-003, FR-004, SC-002)', (tester) async {
        final a = await iniciarEm(
          tester,
          DriverRideStatus.deslocandoAtePassageiro,
        );

        await cancelar(tester);

        final (status, active) = await a.rideState.load();
        expect(status, DriverRideStatus.aguardandoSolicitacao);
        expect(active, isNull);
        final publicados = cancelamentos(a.gateway).toList();
        expect(publicados, hasLength(1));
        expect(decifradoPeloPassageiro(publicados.single), '{}');
        expect(publicados.single.tags, anyElement(equals(['e', 'quote-1'])));
        expect(
          publicados.single.tags,
          anyElement(equals(['p', passageiroDeTeste.publicKey])),
        );
        expect(find.byKey(botao), findsNothing);
        expect(
          modalDeAvaliacao,
          findsNothing,
          reason: 'cancelar não abre a avaliação (FR-006)',
        );
      });

      testWidgets('falha ao cifrar (destinatário inválido): nada é publicado '
          'em claro, o cancelamento local acontece e o app segue de pé '
          '(FR-004 da feature 019)', (tester) async {
        final a = await iniciarEm(
          tester,
          DriverRideStatus.deslocandoAtePassageiro,
          rideState: InMemoryRideStateStore(
            status: DriverRideStatus.deslocandoAtePassageiro,
            active: ActiveRide(
              quoteId: 'quote-1',
              passengerPubkey: 'pubkey-invalida',
              originLat: -28.9298,
              originLon: -49.4753,
              destinationLat: -28.6721,
              destinationLon: -49.3671,
            ),
          ),
        );

        await cancelar(tester);

        expect(cancelamentos(a.gateway), isEmpty);
        expect(
          a.gateway.publicados
              .where((e) => e.content == '' || e.content.startsWith('{'))
              .where((e) => e.kind != NostrEvent.kindRideRequest),
          isEmpty,
        );
        final (status, active) = await a.rideState.load();
        expect(status, DriverRideStatus.aguardandoSolicitacao);
        expect(active, isNull);
        expect(tester.takeException(), isNull);
      });

      testWidgets('depois de cancelar, nenhuma localização é publicada e o '
          'marcador e a rota somem (FR-005)', (tester) async {
        final a = await iniciarEm(
          tester,
          DriverRideStatus.deslocandoAtePassageiro,
        );
        a.localizacao.emitir(em(-28.9350, -49.4800));
        await assentar(tester);
        expect(polilinhas, findsOneWidget);
        expect(find.byIcon(Icons.person), findsOneWidget);

        await cancelar(tester);
        final antes = a.gateway.publicados
            .where((e) => e.kind == NostrEvent.kindDriverLocation)
            .length;

        a.localizacao.emitir(em(-28.9300, -49.4800));
        await assentar(tester);

        expect(
          a.gateway.publicados
              .where((e) => e.kind == NostrEvent.kindDriverLocation)
              .length,
          antes,
        );
        expect(polilinhas, findsNothing);
        expect(find.byIcon(Icons.person), findsNothing);
      });
    });

    group('Em corrida (US2)', () {
      testWidgets('o botão existe em Em corrida (FR-001)', (tester) async {
        await iniciarEm(tester, DriverRideStatus.emCorrida);
        expect(find.byKey(botao), findsOneWidget);
      });

      testWidgets('confirmar tem os mesmos efeitos, sem avaliação e sem '
          'marcador de destino nem rota (FR-001, FR-003, FR-004, FR-006)', (
        tester,
      ) async {
        final a = await iniciarEm(tester, DriverRideStatus.emCorrida);
        a.localizacao.emitir(em(-28.9350, -49.4800));
        await assentar(tester);
        expect(find.byIcon(Icons.flag), findsOneWidget);

        await cancelar(tester);

        final (status, active) = await a.rideState.load();
        expect(status, DriverRideStatus.aguardandoSolicitacao);
        expect(active, isNull);
        expect(cancelamentos(a.gateway), hasLength(1));
        expect(modalDeAvaliacao, findsNothing);
        expect(find.byIcon(Icons.flag), findsNothing);
        expect(polilinhas, findsNothing);
      });

      testWidgets('um cálculo de rota ainda em voo, concluído depois do '
          'cancelamento, não publica kind 20011 nem redesenha o trajeto '
          '(FR-005)', (tester) async {
        final a = await iniciarEm(tester, DriverRideStatus.emCorrida);
        final bloqueio = Completer<void>();
        a.rotas.traceBloqueio = bloqueio;

        a.localizacao.emitir(em(-28.9350, -49.4800));
        await assentar(tester);
        expect(a.rotas.traceChamadas, hasLength(1));

        await cancelar(tester);
        bloqueio.complete();
        await assentar(tester);

        expect(
          a.gateway.publicados.where((e) => e.kind == NostrEvent.kindRideRoute),
          isEmpty,
        );
        expect(polilinhas, findsNothing);
      });
    });

    group('reinício e isolamento (US3)', () {
      testWidgets(
        'reabrir depois de cancelar mostra o motorista em Aguardando '
        'sem corrida, sem botão e sem publicar localização (FR-003, SC-004)',
        (tester) async {
          final a = await iniciarEm(tester, DriverRideStatus.emCorrida);
          await cancelar(tester);

          final b = await iniciarEm(
            tester,
            DriverRideStatus.aguardandoSolicitacao,
            rideState: a.rideState,
          );
          b.localizacao.emitir(em(-28.9350, -49.4800));
          await assentar(tester);

          expect(find.byKey(botao), findsNothing);
          expect(polilinhas, findsNothing);
          expect(
            b.gateway.publicados.where(
              (e) => e.kind == NostrEvent.kindDriverLocation,
            ),
            isEmpty,
          );
        },
      );

      testWidgets('confirmações de encontro e de destino da corrida cancelada, '
          'chegando depois, são ignoradas (FR-007)', (tester) async {
        final a = await iniciarEm(tester, DriverRideStatus.emCorrida);
        await cancelar(tester);

        for (final kind in [
          NostrEvent.kindMeetingConfirmed,
          NostrEvent.kindDestinationConfirmed,
        ]) {
          a.gateway.emitir(
            IncomingEvent(
              relayUrl: 'wss://a.test',
              payload: confirmacaoAssinada(kind: kind, quoteId: 'quote-1'),
            ),
          );
          await assentar(tester);
        }

        final (status, active) = await a.rideState.load();
        expect(status, DriverRideStatus.aguardandoSolicitacao);
        expect(active, isNull);
        expect(modalDeAvaliacao, findsNothing);
      });

      testWidgets('cancelar sem relay conectado deixa o motorista livre e '
          'nada é publicado (FR-008)', (tester) async {
        final a = await iniciarEm(tester, DriverRideStatus.emCorrida);
        await a.relayService.removeRelay('wss://a.test');

        await cancelar(tester);

        final (status, active) = await a.rideState.load();
        expect(status, DriverRideStatus.aguardandoSolicitacao);
        expect(active, isNull);
        expect(a.gateway.publicados, isEmpty);
      });

      testWidgets('uma nova corrida depois do cancelamento segue normal e o '
          'novo cancelamento cita só o quoteId dela (SC-005, FR-010)', (
        tester,
      ) async {
        final sentQuotes = InMemorySentQuotesStore(
          initial: {'quote-2': _origemPadrao},
          initialDestinations: {'quote-2': _destinoPadrao},
        );
        final rideState = InMemoryRideStateStore(
          status: DriverRideStatus.deslocandoAtePassageiro,
          active: corrida(),
        );
        final ambiente = await montar(
          tester,
          rideStateStore: rideState,
          sentQuotesStore: sentQuotes,
        );
        await cancelar(tester);

        ambiente.gateway.emitir(
          IncomingEvent(
            relayUrl: 'wss://a.test',
            payload: aceitacaoAssinada(quoteId: 'quote-2').payload,
          ),
        );
        await tester.pump();
        await tester.pump();
        await tester.pump();
        await tester.tap(find.widgetWithText(FilledButton, 'Iniciar corrida'));
        await tester.pumpAndSettle();
        expect(
          (await rideState.load()).$1,
          DriverRideStatus.deslocandoAtePassageiro,
        );

        await cancelar(tester);

        final publicados = cancelamentos(ambiente.gateway).toList();
        expect(publicados, hasLength(2));
        expect(publicados.first.tags, anyElement(equals(['e', 'quote-1'])));
        expect(publicados.last.tags, anyElement(equals(['e', 'quote-2'])));
      });
    });
  });

  group('MapScreen — recepção cifrada (feature 019, emenda 17)', () {
    ActiveRide corridaAtiva() => ActiveRide(
      quoteId: 'quote-1',
      passengerPubkey: passageiroDeTeste.publicKey,
      originLat: _origemPadrao.$1,
      originLon: _origemPadrao.$2,
      destinationLat: _destinoPadrao.$1,
      destinationLon: _destinoPadrao.$2,
    );

    // Cada variante é um jeito de o evento chegar assinado e bem-formado, mas
    // inválido pela regra de recepção 7: tem de ser descartado em silêncio.
    final variantes =
        <
          String,
          Map<String, dynamic> Function(
            Map<String, dynamic> Function({
              String? motoristaPubkey,
              String? cifrarPara,
              String? conteudoBruto,
              String conteudo,
            })
            monta,
          )
        >{
          'em claro': (monta) => monta(conteudoBruto: '{}'),
          'cifrado a outra chave': (monta) =>
              monta(cifrarPara: identidadeDeTeste().publicKey),
          'tag p de outro destinatário': (monta) =>
              monta(motoristaPubkey: identidadeDeTeste().publicKey),
          'MAC adulterado': (monta) {
            final bytes = base64.decode(
              MessageCipher().encryptFor(
                passageiroDeTeste,
                motoristaDeTeste.publicKey,
                '',
              ),
            )..[60] ^= 0x01;
            return monta(conteudoBruto: base64.encode(bytes));
          },
          'texto diferente de {}': (monta) => monta(conteudo: '{"a":1}'),
        };

    for (final entrada in variantes.entries) {
      testWidgets('20003 ${entrada.key}: nenhuma modal, nenhum efeito '
          '(FR-006)', (tester) async {
        final sentQuotes = InMemorySentQuotesStore(
          initial: {'quote-1': _origemPadrao},
        );
        final ambiente = await montar(tester, sentQuotesStore: sentQuotes);

        final payload = entrada.value(
          ({motoristaPubkey, cifrarPara, conteudoBruto, conteudo = ''}) =>
              aceitacaoAssinada(
                quoteId: 'quote-1',
                motoristaPubkey: motoristaPubkey,
                cifrarPara: cifrarPara,
                conteudoBruto: conteudoBruto,
                conteudo: conteudo,
              ).payload,
        );
        ambiente.gateway.emitir(
          IncomingEvent(relayUrl: 'wss://a.test', payload: payload),
        );
        await tester.pump();
        await tester.pump();
        await tester.pump();

        expect(find.text('Orçamento aceito'), findsNothing);
        expect(ambiente.rideStateStore.saveCount, 0);
        expect(tester.takeException(), isNull);
      });

      for (final (kind, antes, rotulo) in [
        (
          NostrEvent.kindMeetingConfirmed,
          DriverRideStatus.deslocandoAtePassageiro,
          '20008',
        ),
        (
          NostrEvent.kindDestinationConfirmed,
          DriverRideStatus.emCorrida,
          '20010',
        ),
      ]) {
        testWidgets('$rotulo ${entrada.key}: o estado da corrida não muda '
            '(FR-006)', (tester) async {
          final rideState = InMemoryRideStateStore(
            status: antes,
            active: corridaAtiva(),
          );
          final ambiente = await montar(tester, rideStateStore: rideState);

          final payload = entrada.value(
            ({motoristaPubkey, cifrarPara, conteudoBruto, conteudo = ''}) =>
                confirmacaoAssinada(
                  kind: kind,
                  quoteId: 'quote-1',
                  motoristaPubkey: motoristaPubkey,
                  cifrarPara: cifrarPara,
                  conteudoBruto: conteudoBruto,
                  conteudo: conteudo,
                ),
          );
          ambiente.gateway.emitir(
            IncomingEvent(relayUrl: 'wss://a.test', payload: payload),
          );
          await tester.pump();
          await tester.pump();

          final (status, active) = await rideState.load();
          expect(status, antes);
          expect(active, corridaAtiva());
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  group('MapScreen — corrida cancelada pelo passageiro (feature 020)', () {
    const botao = Key('botao-cancelar-corrida');
    const mensagem = 'O passageiro cancelou a corrida.';

    ActiveRide corrida({String quoteId = 'quote-1', String? passageiro}) =>
        ActiveRide(
          quoteId: quoteId,
          passengerPubkey: passageiro ?? passageiroDeTeste.publicKey,
          originLat: _origemPadrao.$1,
          originLon: _origemPadrao.$2,
          destinationLat: _destinoPadrao.$1,
          destinationLon: _destinoPadrao.$2,
        );

    Future<void> assentar(WidgetTester tester) async {
      await tester.pump();
      await tester.pump();
      await tester.pump();
    }

    Future<
      ({
        FakeLocationService localizacao,
        InMemoryRideStateStore rideState,
        InMemoryRideRatingStore ratings,
        FakeGateway gateway,
      })
    >
    iniciarEm(
      WidgetTester tester,
      DriverRideStatus status, {
      InMemoryRideStateStore? rideState,
      Identity? identity,
    }) async {
      final localizacao = FakeLocationService();
      final estado =
          rideState ??
          InMemoryRideStateStore(
            status: status,
            active: status == DriverRideStatus.aguardandoSolicitacao
                ? null
                : corrida(),
          );
      final ambiente = await montar(
        tester,
        locationService: localizacao,
        rideStateStore: estado,
        identity: identity,
      );
      return (
        localizacao: localizacao,
        rideState: estado,
        ratings: ambiente.rideRatingStore,
        gateway: ambiente.gateway,
      );
    }

    void entregar(FakeGateway gateway, Map<String, dynamic> payload) => gateway
        .emitir(IncomingEvent(relayUrl: 'wss://a.test', payload: payload));

    Iterable<NostrEvent> avisos(FakeGateway g) => g.publicados.where(
      (e) =>
          e.kind == NostrEvent.kindRideCancelled ||
          e.kind == NostrEvent.kindRideCancelledByPassenger,
    );

    final modalDeAvaliacao = find.widgetWithText(TextButton, 'Pular');

    for (final (status, rotulo) in [
      (
        DriverRideStatus.deslocandoAtePassageiro,
        'Deslocando-se até o passageiro',
      ),
      (DriverRideStatus.emCorrida, 'Em corrida'),
    ]) {
      testWidgets('aviso válido em "$rotulo": volta a Aguardando, zera e '
          'persiste a corrida e abre a modal informativa (FR-003, FR-005, '
          'FR-006)', (tester) async {
        final a = await iniciarEm(tester, status);

        entregar(a.gateway, cancelamentoDoPassageiro(quoteId: 'quote-1'));
        await assentar(tester);

        final (estado, ativa) = await a.rideState.load();
        expect(estado, DriverRideStatus.aguardandoSolicitacao);
        expect(ativa, isNull);
        expect(find.text('Corrida cancelada'), findsOneWidget);
        expect(find.text(mensagem), findsOneWidget);
        expect(find.byKey(botao), findsNothing);
        expect(
          modalDeAvaliacao,
          findsNothing,
          reason: 'cancelar não abre a avaliação (FR-006)',
        );
        expect(
          a.gateway.publicados,
          isEmpty,
          reason: 'o motorista não publica nada em resposta (FR-006)',
        );

        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
        expect(find.text(mensagem), findsNothing);
        expect(a.gateway.publicados, isEmpty);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('depois do cancelamento, novas posições não publicam '
        'localização (FR-004)', (tester) async {
      final a = await iniciarEm(
        tester,
        DriverRideStatus.deslocandoAtePassageiro,
      );

      entregar(a.gateway, cancelamentoDoPassageiro(quoteId: 'quote-1'));
      await assentar(tester);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      a.localizacao.emitir(posicaoDeTeste());
      await assentar(tester);

      expect(
        a.gateway.publicados.where(
          (e) => e.kind == NostrEvent.kindDriverLocation,
        ),
        isEmpty,
      );
    });

    testWidgets('em "Em corrida" o marcador de destino e a rota saem do mapa '
        '(FR-004)', (tester) async {
      final a = await iniciarEm(tester, DriverRideStatus.emCorrida);
      a.localizacao.emitir(posicaoDeTeste());
      await assentar(tester);
      expect(find.byIcon(Icons.flag), findsOneWidget);

      entregar(a.gateway, cancelamentoDoPassageiro(quoteId: 'quote-1'));
      await assentar(tester);

      expect(find.byWidgetPredicate((w) => w is PolylineLayer), findsNothing);
      expect(find.byIcon(Icons.flag), findsNothing);
    });

    final invalidos =
        <
          String,
          ({DriverRideStatus status, Map<String, dynamic> Function() monta})
        >{
          'autor diferente do passageiro da corrida': (
            status: DriverRideStatus.deslocandoAtePassageiro,
            monta: () => cancelamentoDoPassageiro(
              quoteId: 'quote-1',
              autor: identidadeDeTeste(),
            ),
          ),
          'referência a outra corrida': (
            status: DriverRideStatus.deslocandoAtePassageiro,
            monta: () => cancelamentoDoPassageiro(quoteId: 'quote-outra'),
          ),
          'tag p de outro motorista': (
            status: DriverRideStatus.deslocandoAtePassageiro,
            monta: () => cancelamentoDoPassageiro(
              quoteId: 'quote-1',
              motoristaPubkey: identidadeDeTeste().publicKey,
            ),
          ),
          'content em claro': (
            status: DriverRideStatus.deslocandoAtePassageiro,
            monta: () => cancelamentoDoPassageiro(
              quoteId: 'quote-1',
              conteudoBruto: '{}',
            ),
          ),
          'texto cifrado diferente de {}': (
            status: DriverRideStatus.emCorrida,
            monta: () => cancelamentoDoPassageiro(
              quoteId: 'quote-1',
              conteudo: '{"a":1}',
            ),
          ),
        };

    for (final entrada in invalidos.entries) {
      testWidgets('aviso inválido (${entrada.key}): ignorado, sem modal e sem '
          'efeito (SC-002)', (tester) async {
        final a = await iniciarEm(tester, entrada.value.status);

        entregar(a.gateway, entrada.value.monta());
        await assentar(tester);

        final (estado, ativa) = await a.rideState.load();
        expect(estado, entrada.value.status);
        expect(ativa, corrida());
        expect(find.text(mensagem), findsNothing);
        expect(a.rideState.saveCount, 0);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('em Aguardando o aviso é ignorado, sem modal', (tester) async {
      final a = await iniciarEm(tester, DriverRideStatus.aguardandoSolicitacao);

      entregar(a.gateway, cancelamentoDoPassageiro(quoteId: 'quote-1'));
      await assentar(tester);

      expect(find.text(mensagem), findsNothing);
      expect(a.rideState.saveCount, 0);
    });

    testWidgets(
      'o mesmo aviso reentregue tem um único efeito (FR-007, SC-003)',
      (tester) async {
        final a = await iniciarEm(
          tester,
          DriverRideStatus.deslocandoAtePassageiro,
        );
        final aviso = cancelamentoDoPassageiro(quoteId: 'quote-1');

        entregar(a.gateway, aviso);
        await assentar(tester);
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
        entregar(a.gateway, aviso);
        await assentar(tester);

        expect(find.text(mensagem), findsNothing);
        expect(a.rideState.saveCount, 1);
      },
    );

    testWidgets('com "Cancelar corrida?" aberta, o aviso fecha a confirmação, '
        'abre a informativa e nada é publicado ao passageiro (D4)', (
      tester,
    ) async {
      final a = await iniciarEm(
        tester,
        DriverRideStatus.deslocandoAtePassageiro,
      );
      await tester.tap(find.byKey(botao));
      await tester.pumpAndSettle();
      expect(find.text('Cancelar corrida?'), findsOneWidget);

      entregar(a.gateway, cancelamentoDoPassageiro(quoteId: 'quote-1'));
      await tester.pumpAndSettle();

      expect(find.text('Cancelar corrida?'), findsNothing);
      expect(find.text(mensagem), findsOneWidget);
      expect(avisos(a.gateway), isEmpty);
      final (estado, ativa) = await a.rideState.load();
      expect(estado, DriverRideStatus.aguardandoSolicitacao);
      expect(ativa, isNull);
    });

    testWidgets('um reinício depois do cancelamento reabre em Aguardando, '
        'sem corrida ativa (SC-004)', (tester) async {
      final a = await iniciarEm(tester, DriverRideStatus.emCorrida);
      entregar(a.gateway, cancelamentoDoPassageiro(quoteId: 'quote-1'));
      await assentar(tester);

      await tester.pumpWidget(const SizedBox());
      final b = await montar(tester, rideStateStore: a.rideState);
      await assentar(tester);

      expect(find.byKey(botao), findsNothing);
      final (estado, ativa) = await b.rideStateStore.load();
      expect(estado, DriverRideStatus.aguardandoSolicitacao);
      expect(ativa, isNull);
    });

    testWidgets('confirmações atrasadas da corrida cancelada são ignoradas '
        '(FR-008)', (tester) async {
      final a = await iniciarEm(
        tester,
        DriverRideStatus.deslocandoAtePassageiro,
      );
      entregar(a.gateway, cancelamentoDoPassageiro(quoteId: 'quote-1'));
      await assentar(tester);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      final salvamentos = a.rideState.saveCount;

      entregar(
        a.gateway,
        confirmacaoAssinada(
          kind: NostrEvent.kindMeetingConfirmed,
          quoteId: 'quote-1',
        ),
      );
      entregar(
        a.gateway,
        confirmacaoAssinada(
          kind: NostrEvent.kindDestinationConfirmed,
          quoteId: 'quote-1',
        ),
      );
      await assentar(tester);

      final (estado, ativa) = await a.rideState.load();
      expect(estado, DriverRideStatus.aguardandoSolicitacao);
      expect(ativa, isNull);
      expect(a.rideState.saveCount, salvamentos);
      expect(modalDeAvaliacao, findsNothing);
    });

    testWidgets('o aviso vale com o motorista offline (status online/offline '
        'só controla solicitações)', (tester) async {
      final a = await iniciarEm(tester, DriverRideStatus.emCorrida);

      entregar(a.gateway, cancelamentoDoPassageiro(quoteId: 'quote-1'));
      await assentar(tester);

      expect(find.text(mensagem), findsOneWidget);
    });
  });
  group('MapScreen — recorte geográfico das solicitações (feature 027, US1)', () {
    // A posição de teste é (-28.935, -49.49): Araranguá, raio padrão de 10 km.
    Future<({FakeGateway gateway, EventFeed eventFeed})> ficarOnline(
      WidgetTester tester,
    ) async {
      final service = FakeLocationService();
      final ambiente = await montar(
        tester,
        locationService: service,
        routeDistanceService: FakeRouteDistanceService(
          resultados: [1000, 10000],
        ),
      );
      service.emitir(posicaoDeTeste());
      await tester.pump();
      await tester.tap(find.byType(Switch));
      await tester.pump();
      return (gateway: ambiente.gateway, eventFeed: ambiente.eventFeed);
    }

    Future<void> chega(
      WidgetTester tester,
      FakeGateway gateway,
      Map<String, dynamic> payload,
    ) async {
      gateway.emitir(IncomingEvent(relayUrl: 'wss://a.test', payload: payload));
      await tester.pump();
      await tester.pump();
    }

    testWidgets('a ~3 km do motorista online: abre a modal e entra na lista', (
      tester,
    ) async {
      final a = await ficarOnline(tester);
      final gateway = a.gateway;

      await chega(tester, gateway, solicitacaoAssinada(originLat: -28.908));

      expect(find.text('Solicitação de corrida'), findsOneWidget);
      expect(a.eventFeed.events, hasLength(1));
    });

    testWidgets(
      'de São Paulo: não abre modal e não entra na lista de eventos',
      (tester) async {
        // O dublê do gateway entrega tudo, ignorando o `#g`, como um relay que
        // não respeita o filtro (SC-003).
        final a = await ficarOnline(tester);
        final gateway = a.gateway;

        await chega(
          tester,
          gateway,
          solicitacaoAssinada(originLat: -23.5505, originLon: -46.6333),
        );

        expect(find.text('Solicitação de corrida'), findsNothing);
        expect(a.eventFeed.events, isEmpty);
        expect(a.eventFeed.discardedOutOfCoverageCount, 1);
      },
    );

    testWidgets(
      'sem tag g: não abre modal, mesmo com a origem dentro do raio',
      (tester) async {
        final a = await ficarOnline(tester);
        final gateway = a.gateway;

        await chega(
          tester,
          gateway,
          solicitacaoAssinada(originLat: -28.908, tags: [prototypeMarkerTag]),
        );

        expect(find.text('Solicitação de corrida'), findsNothing);
        expect(a.eventFeed.events, isEmpty);
      },
    );

    testWidgets('g incoerente (célula de outra cidade): não abre modal', (
      tester,
    ) async {
      final a = await ficarOnline(tester);
      final gateway = a.gateway;

      await chega(
        tester,
        gateway,
        solicitacaoAssinada(
          originLat: -28.908,
          tags: tagsDeSolicitacao(lat: -23.5505, lon: -46.6333),
        ),
      );

      expect(find.text('Solicitação de corrida'), findsNothing);
      expect(a.eventFeed.events, isEmpty);
    });

    testWidgets('g na célula, mas origem a ~15 km: o filtro exato descarta', (
      tester,
    ) async {
      final a = await ficarOnline(tester);
      final gateway = a.gateway;

      await chega(tester, gateway, solicitacaoAssinada(originLat: -28.80));

      expect(find.text('Solicitação de corrida'), findsNothing);
      expect(a.eventFeed.events, isEmpty);
    });

    testWidgets('offline nada abre, mesmo dentro do raio', (tester) async {
      final service = FakeLocationService();
      final ambiente = await montar(tester, locationService: service);
      service.emitir(posicaoDeTeste());
      await tester.pump();

      await chega(tester, ambiente.gateway, solicitacaoAssinada());

      expect(find.text('Solicitação de corrida'), findsNothing);
    });

    testWidgets(
      'ficar online pede as células ao gateway; ficar offline as retira',
      (tester) async {
        final a = await ficarOnline(tester);
        final gateway = a.gateway;

        final pedidas = gateway.celulasPedidas.last!;
        expect(pedidas.length, lessThanOrEqualTo(9));
        expect(pedidas, isNotEmpty);
        expect(
          pedidas,
          contains(Geohash.encode(-28.935, -49.49, pedidas.first.length)),
        );

        await tester.tap(find.byType(Switch));
        await tester.pump();

        expect(gateway.celulasPedidas.last, isNull);
      },
    );

    testWidgets(
      'o raio e a posição de referência não saem em evento publicado',
      (tester) async {
        final a = await ficarOnline(tester);
        final gateway = a.gateway;
        await chega(tester, gateway, solicitacaoAssinada(originLat: -28.908));

        await tester.tap(find.widgetWithText(FilledButton, 'Enviar orçamento'));
        await tester.pumpAndSettle();

        expect(gateway.publicados, hasLength(1));
        final texto =
            '${gateway.publicados.single.content}'
            '${gateway.publicados.single.tags}';
        expect(texto, isNot(contains('-28.935')));
        expect(texto, isNot(contains('-49.49')));
        expect(texto, isNot(contains('raio')));
        expect(texto, isNot(contains('"g"')));
      },
    );
  });
  group('MapScreen — referência fixa e ciclo online/offline (feature 027, US3)', () {
    // Posição de teste: (-28.935, -49.49). 0,27° de latitude ≈ 30 km.
    DriverPosition em(double lat, double lon) => DriverPosition(
      latitude: lat,
      longitude: lon,
      capturedAt: DateTime.now(),
    );
    final longe = em(-28.935 + 0.27, -49.49);

    Future<void> chega(
      WidgetTester tester,
      FakeGateway gateway,
      Map<String, dynamic> payload,
    ) async {
      gateway.emitir(IncomingEvent(relayUrl: 'wss://a.test', payload: payload));
      await tester.pump();
      await tester.pump();
    }

    Future<void> alternar(WidgetTester tester) async {
      await tester.tap(find.byType(Switch));
      await tester.pump();
    }

    Future<void> fechaModal(WidgetTester tester) async {
      await tester.tap(find.text('Recusar corrida'));
      await tester.pumpAndSettle();
    }

    testWidgets(
      'a referência não acompanha o motorista: perto de A chega, perto do novo ponto não',
      (tester) async {
        final service = FakeLocationService();
        final m = await montar(tester, locationService: service);
        service.emitir(posicaoDeTeste());
        await tester.pump();
        await alternar(tester);
        final celulas = m.gateway.celulasPedidas.last;

        service.emitir(longe);
        await tester.pump();

        // Perto do novo ponto (a ~30 km de A): fora da cobertura.
        await chega(
          tester,
          m.gateway,
          solicitacaoAssinada(
            originLat: longe.latitude,
            originLon: longe.longitude,
          ),
        );
        expect(find.text('Solicitação de corrida'), findsNothing);
        // Perto de A: chega.
        await chega(tester, m.gateway, solicitacaoAssinada(originLat: -28.908));
        expect(find.text('Solicitação de corrida'), findsOneWidget);
        // E a inscrição nunca foi refeita por causa do deslocamento.
        expect(m.gateway.celulasPedidas.last, celulas);
        expect(m.gateway.celulasPedidas, hasLength(1));
      },
    );

    testWidgets(
      'offline e online de novo em outro ponto: a referência passa a ser o novo ponto',
      (tester) async {
        final service = FakeLocationService();
        final m = await montar(tester, locationService: service);
        service.emitir(posicaoDeTeste());
        await tester.pump();
        await alternar(tester);
        service.emitir(longe);
        await tester.pump();

        await alternar(tester); // offline
        expect(m.gateway.celulasPedidas.last, isNull);
        await alternar(tester); // online no novo ponto
        expect(m.gateway.celulasPedidas.last, isNotNull);

        await chega(tester, m.gateway, solicitacaoAssinada(originLat: -28.908));
        expect(find.text('Solicitação de corrida'), findsNothing);
        await chega(
          tester,
          m.gateway,
          solicitacaoAssinada(
            originLat: longe.latitude,
            originLon: longe.longitude,
          ),
        );
        expect(find.text('Solicitação de corrida'), findsOneWidget);
      },
    );

    testWidgets(
      'localização perdida online: fica offline, retira a cobertura e nada é aceito',
      (tester) async {
        final service = FakeLocationService();
        final m = await montar(tester, locationService: service);
        service.emitir(posicaoDeTeste());
        await tester.pump();
        await alternar(tester);
        expect(m.gateway.celulasPedidas.last, isNotNull);

        service.emitirErro(const LocationUnavailable(null));
        await tester.pump();
        await tester.pump();

        expect(
          find.text('Você ficou offline porque a localização foi perdida.'),
          findsOneWidget,
        );
        expect(m.gateway.celulasPedidas.last, isNull);
        expect(m.relayService.coverage, isNull);
        await chega(tester, m.gateway, solicitacaoAssinada());
        expect(find.text('Solicitação de corrida'), findsNothing);
      },
    );

    testWidgets(
      'sem posição válida não fica online, não cria cobertura nem pede o 20001',
      (tester) async {
        final m = await montar(tester);

        await alternar(tester);

        expect(
          find.text('É preciso ter uma localização válida para ficar online.'),
          findsOneWidget,
        );
        expect(m.gateway.celulasPedidas, isEmpty);
        expect(m.relayService.coverage, isNull);
        await chega(tester, m.gateway, solicitacaoAssinada());
        expect(find.text('Solicitação de corrida'), findsNothing);
      },
    );

    testWidgets(
      'raio alterado com o motorista online só vale na próxima vez que ficar online',
      (tester) async {
        final service = FakeLocationService();
        final perfil = ValueNotifier<DriverProfile?>(perfilComPreco(2.5));
        final m = await montar(
          tester,
          locationService: service,
          perfilAoVivo: perfil,
        );
        service.emitir(posicaoDeTeste());
        await tester.pump();
        await alternar(tester);
        final coberturaAntes = m.relayService.coverage;
        expect(coberturaAntes!.radiusKm, kRaioPadraoKm);

        perfil.value = perfilComPreco(2.5).copyWith(raioAtendimentoKm: 50);
        await tester.pump();

        // A cobertura em uso não mudou: 12 km ao norte continua fora dos 10 km.
        expect(m.relayService.coverage, same(coberturaAntes));
        await chega(tester, m.gateway, solicitacaoAssinada(originLat: -28.827));
        expect(find.text('Solicitação de corrida'), findsNothing);

        await alternar(tester); // offline
        await alternar(tester); // online: o raio novo entra
        expect(m.relayService.coverage!.radiusKm, 50);
        await chega(tester, m.gateway, solicitacaoAssinada(originLat: -28.827));
        expect(find.text('Solicitação de corrida'), findsOneWidget);
        await fechaModal(tester);
      },
    );
  });
}

class _MemoryKeyStore implements KeyStore {
  final _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);
}
