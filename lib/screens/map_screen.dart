import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../domain/active_ride.dart';
import '../domain/availability_status.dart';
import '../domain/driver_position.dart';
import '../domain/driver_profile.dart';
import '../domain/driver_ride_status.dart';
import '../domain/geo_distance.dart';
import '../domain/identity.dart';
import '../domain/nostr_event.dart';
import '../domain/quote_accepted.dart';
import '../domain/reputation.dart';
import '../domain/ride_quote.dart';
import '../domain/ride_leg.dart';
import '../domain/ride_rating.dart';
import '../domain/ride_request_filter.dart';
import '../domain/ride_request_received.dart';
import '../domain/route_trace.dart';
import '../domain/service_state.dart';
import '../services/cadastro_store.dart';
import 'identidade_visual.dart';
import '../services/event_feed.dart';
import '../services/identity_service.dart';
import '../services/location_service.dart';
import '../services/background/service_controller.dart';
import '../services/receipt_service.dart';
import '../services/receipt_store.dart';
import '../services/relay_connection.dart';
import '../services/ride_rating_store.dart';
import '../services/ride_state_store.dart';
import '../services/reverse_geocoding_service.dart';
import '../services/route_distance_service.dart';
import '../services/sent_quotes_store.dart';
import 'camada_mapa_base.dart';
import 'cancel_ride_modal.dart';
import 'quote_accepted_modal.dart';
import 'ride_cancelled_by_passenger_modal.dart';
import 'ride_rating_modal.dart';
import 'ride_request_modal.dart';

/// Tela inicial do aplicativo: mapa centrado na posição real do motorista,
/// com um indicador dessa posição (US1), o controle de status online/offline
/// (US2), a modal de solicitação de corrida recebida (feature 007) e, desde a
/// feature 010, a modal de aceitação de orçamento, o estado "Deslocando-se
/// até o passageiro" e a publicação de localização durante o deslocamento.
///
/// Único arquivo do aplicativo, além de `main.dart`, que conhece tipos de
/// `package:flutter_map` (Princípio III).
class MapScreen extends StatefulWidget {
  const MapScreen({
    super.key,
    required this.locationService,
    required this.eventFeed,
    required this.cadastroStore,
    required this.routeDistanceService,
    required this.reverseGeocodingService,
    required this.identity,
    required this.identityService,
    required this.relayService,
    required this.rideStateStore,
    required this.sentQuotesStore,
    required this.rideRatingStore,
    this.driverProfile,
    this.serviceController,
    this.receiptStore,
    this.receiptService,
  });

  final LocationService locationService;
  final EventFeed eventFeed;
  final CadastroStore cadastroStore;
  final RouteDistanceService routeDistanceService;
  final ReverseGeocodingService reverseGeocodingService;

  /// Nulo enquanto a identidade não pôde ser criada/recuperada
  /// (`_startupError` em `main.dart`) — nesse caso, enviar orçamento falha
  /// com uma mensagem em vez de lançar.
  final Identity? identity;
  final IdentityService identityService;
  final RelayConnection relayService;

  /// Persistência do estado "Aguardando"/"Deslocando-se" (feature 010,
  /// FR-003).
  final RideStateStore rideStateStore;

  /// Orçamentos publicados com sucesso por este motorista — usado para
  /// validar uma aceitação recebida (FR-011).
  final SentQuotesStore sentQuotesStore;

  /// Persistência da avaliação da corrida (feature 013, FR-004/FR-005).
  final RideRatingStore rideRatingStore;

  /// Recibos de reputação (feature 026): fonte da reputação própria declarada
  /// no orçamento e guarda da reputação do passageiro em cada corrida. Nulo =
  /// recibos desligados (testes de fluxos que não os exercitam); `main.dart`
  /// sempre o passa.
  final ReceiptStore? receiptStore;

  /// Recebe `20014`/`20015` do feed (feature 026). Nulo = recibos desligados.
  final ReceiptService? receiptService;

  /// Cadastro corrente do motorista, repassado pela casca a cada alteração.
  /// A tela fica montada o tempo todo, então sem isto uma edição de formas de
  /// pagamento ou de preço só valeria depois de reiniciar o app. Opcional:
  /// sem ele a tela usa o que `cadastroStore` carregou ao iniciar.
  final DriverProfile? driverProfile;

  /// Liga a tela ao serviço em segundo plano (feature 025): recebe dela o estado
  /// de que o serviço depende e diz se o motorista estava online quando o app
  /// foi fechado. Nulo nos testes e sempre que a conexão com os relays fica no
  /// isolate da interface.
  final ServiceController? serviceController;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

/// Item pendente de apresentação em modal — unifica a fila sequencial entre
/// solicitações de corrida e aceitações de orçamento (nunca duas modais
/// simultâneas, D3 de `specs/007.../research.md`, estendido pela feature
/// 010).
sealed class _PendingModal {}

class _PendingRideRequest extends _PendingModal {
  _PendingRideRequest(this.request);
  final RideRequestReceived request;
}

class _PendingQuoteAccepted extends _PendingModal {
  _PendingQuoteAccepted(this.accepted);
  final QuoteAccepted accepted;
}

class _MapScreenState extends State<MapScreen> {
  /// Nome do pacote exigido pela política de uso dos mosaicos do
  /// OpenStreetMap (D2 de `research.md`).

  /// Intervalo mínimo entre duas publicações de localização (FR-008 de
  /// `specs/010-iniciar-corrida`, trocado de 50 m percorridos para tempo
  /// decorrido — o passageiro recebe atualizações mesmo com o motorista
  /// parado).
  static const _intervaloLocalizacao = Duration(seconds: 5);

  /// Raio, em metros, em que o motorista é considerado no ponto de origem da
  /// corrida ativa (FR-001, FR-002 de `specs/011-notificar-chegada/spec.md`;
  /// desde a feature 021 o aviso se repete a cada [_intervaloLocalizacao]
  /// enquanto a posição está dentro dele). 30 m, não 10: o GPS real erra de 5
  /// a 15 m, e no zoom do mapa os marcadores de 44 px já parecem sobrepostos
  /// a ~22 m, de modo que 10 m deixava o motorista "em cima" do passageiro
  /// sem nunca avisar a chegada (emenda 21 do contrato).
  static const _raioDeChegadaMetros = 30;

  /// Raio, em metros, para considerar que o motorista chegou ao destino da
  /// corrida ativa (FR-003, FR-004 de
  /// `specs/012-confirmar-encontro-destino/spec.md`). 1 km, não 5 m nem 30 m: a
  /// busca de endereço (Photon) nem sempre localiza o destino com precisão,
  /// e o ponto gravado pode ficar a centenas de metros do local real (emenda
  /// 23 do contrato; antes, 30 m pela emenda 22).
  static const _raioDeChegadaAoDestinoMetros = 1000;

  final _mapController = MapController();
  StreamSubscription<DriverPosition>? _assinatura;
  DriverPosition? _posicao;
  String? _mensagemIndisponibilidade;
  bool _carregando = true;

  /// Sempre offline ao abrir a tela (FR-010 da feature 004) — nunca lido de
  /// nenhum armazenamento.
  AvailabilityStatus _status = AvailabilityStatus.offline;
  String? _avisoStatus;

  /// Cadastro do motorista — fonte do preço padrão (feature 006) e, desde a
  /// feature 009, dos dados incluídos no orçamento (nome, veículo);
  /// carregado uma vez, ao iniciar a tela.
  DriverProfile? _perfil;

  StreamSubscription<void>? _assinaturaFeed;

  /// Acompanha o estado dos relays para a faixa "Sem conexão com os relays".
  StreamSubscription<void>? _assinaturaRelays;
  bool _reconectandoRelays = false;

  /// `id`s de eventos já processados (enfileirados ou descartados por
  /// `content`/tags malformados) — evita reprocessar o mesmo evento a cada
  /// mudança do `EventFeed` (ele já deduplica por `id`, mas continua
  /// entregando `changes` a cada novo evento de qualquer kind). Um único
  /// conjunto serve para todos os kinds: o `id` é um hash único do evento,
  /// não específico de um kind.
  final _idsProcessados = <String>{};

  /// Contexto do diálogo de confirmação "Cancelar corrida?" (feature 018)
  /// enquanto ele está aberto — o aviso de cancelamento do passageiro (feature
  /// 020) o fecha, pois a corrida que ele cancelaria já foi encerrada.
  BuildContext? _contextoConfirmacaoCancelamento;

  /// Itens ainda não apresentados em modal (D3 de `research.md` da feature
  /// 007, estendido pela feature 010 para incluir aceitações de orçamento).
  final _fila = <_PendingModal>[];
  _PendingModal? _modalAtual;

  /// Estado "Aguardando"/"Deslocando-se" (feature 010). Default local até o
  /// carregamento assíncrono de `RideStateStore.load()` terminar (FR-003,
  /// FR-009).
  DriverRideStatus _rideStatus = DriverRideStatus.aguardandoSolicitacao;
  ActiveRide? _activeRide;

  /// Instante (`capturedAt`) da última posição publicada — `null` força a
  /// próxima posição recebida a publicar, tanto no início de uma corrida
  /// quanto ao retomar após um reinício (FR-009): não há necessidade de
  /// persistir este instante, só o estado e a corrida ativa.
  DateTime? _ultimaPublicacaoEm;

  /// Instante (`capturedAt`) da última posição que gerou um aviso de chegada
  /// à origem (`kind: 20007`, feature 021) — `null` faz a próxima posição
  /// dentro do raio publicar na hora. Só em memória, como
  /// [_ultimaPublicacaoEm]: um reinício dentro do raio republica, que é o
  /// desejado. Fora do raio não é zerado, para a oscilação do GPS na borda
  /// do raio não gerar rajada.
  DateTime? _ultimaChegadaEm;

  /// Trajeto exibido até o ponto-alvo do trecho vigente (feature 016) — só
  /// em memória, nunca persistido (FR-006).
  RouteTrace? _rota;

  /// Base do recálculo (D3 de `specs/016-rota-no-mapa/research.md`): trecho
  /// e posição da última consulta de rota, bem-sucedida ou não — uma falha
  /// também conta, para não consultar o serviço a cada atualização de GPS.
  ({RideLeg leg, LatLng origin})? _ultimaTentativaRota;

  /// Endereço legível do alvo do trecho vigente (bloco "corrida em andamento"
  /// do cartão de status) — só em memória. `_enderecoAlvoDe` diz a qual alvo
  /// ele pertence; em falha vale a coordenada, como na modal de solicitação.
  String? _enderecoAlvo;
  LatLng? _enderecoAlvoDe;

  /// Uma única consulta de rota em voo por vez.
  bool _rotaEmCalculo = false;

  /// Liga a faixa "Não foi possível traçar a rota agora." (FR-005).
  bool _rotaIndisponivel = false;

  /// Trecho cujo primeiro trajeto já foi enquadrado (FR-010): recálculos de
  /// 50 m trocam a polilinha sem reenquadrar.
  RideLeg? _trechoEnquadrado;

  /// Se o mapa recentraliza na posição a cada atualização. Fica `false` do
  /// primeiro trajeto de um trecho até o botão "Centralizar" ou o fim do
  /// trajeto — senão o enquadramento seria desfeito na posição seguinte
  /// (FR-010, D5 de `research.md`).
  bool _seguindoMotorista = true;

  @override
  void didUpdateWidget(MapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final perfil = widget.driverProfile;
    if (perfil != null && perfil != oldWidget.driverProfile) _perfil = perfil;
  }

  /// Verdadeiro entre o serviço dizer que o motorista estava online (FR-012 da
  /// feature 025) e a primeira posição válida: nesse intervalo o serviço já o
  /// vê como online, para não perder uma solicitação, mas a tela ainda não
  /// pode ficar online sem posição.
  bool _retomandoOnline = false;
  Timer? _prazoRetomada;

  /// Verdadeiro desde a abertura até o serviço dizer se o motorista estava
  /// online. Nesse intervalo ainda não se sabe, então uma solicitação não é
  /// recusada por "offline": fica estacionada em [_estacionadas].
  late bool _aguardandoServico = widget.serviceController != null;

  /// Solicitações aceitas pela regra enquanto o estado online ainda era
  /// incerto — a reentrega do serviço chega antes de a posição e do cadastro
  /// estarem prontos (FR-007 da feature 025). Abrem a modal assim que a
  /// retomada termina com o motorista online; se ela termina offline, somem.
  final List<_PendingRideRequest> _estacionadas = [];

  /// Quanto esperar por uma posição válida para retomar o estado online.
  static const _esperaRetomada = Duration(seconds: 20);

  @override
  void initState() {
    super.initState();
    _prepararRetomadaOnline();
    _iniciar();
    _carregarPrecoPadrao();
    _carregarEstadoCorrida();
    _assinaturaFeed = widget.eventFeed.changes.listen(
      (_) => _aoAtualizarFeed(),
    );
    _assinaturaRelays = widget.relayService.statusChanges.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _prazoRetomada?.cancel();
    unawaited(_assinatura?.cancel());
    unawaited(_assinaturaFeed?.cancel());
    unawaited(_assinaturaRelays?.cancel());
    super.dispose();
  }

  /// FR-012 da feature 025: se o serviço guardou o motorista como online (o app
  /// foi fechado assim), a tela volta online assim que há posição válida.
  /// Sem posição dentro de [_esperaRetomada], ou ao perdê-la, fica offline.
  void _prepararRetomadaOnline() {
    final controlador = widget.serviceController;
    if (controlador == null) return;
    unawaited(
      controlador.resumeOnline.then((estavaOnline) {
        if (!mounted) return;
        _aguardandoServico = false;
        if (!estavaOnline) {
          _estacionadas.clear();
          return;
        }
        if (_status == AvailabilityStatus.online) {
          _liberarEstacionadas();
          return;
        }
        if (_posicao != null) {
          setState(() => _status = AvailabilityStatus.online);
          _liberarEstacionadas();
          return;
        }
        setState(() => _retomandoOnline = true);
        _prazoRetomada = Timer(_esperaRetomada, _desistirDaRetomada);
      }),
    );
  }

  void _desistirDaRetomada() {
    if (!mounted || !_retomandoOnline) return;
    _estacionadas.clear();
    setState(() => _retomandoOnline = false);
  }

  /// Abre as solicitações estacionadas, se o motorista terminou online e a tela
  /// já tem posição e cadastro (a modal precisa dos dois). Se ainda falta um
  /// deles, espera: quem os traz chama este método de novo.
  void _liberarEstacionadas() {
    if (_estacionadas.isEmpty || _aguardandoServico || _retomandoOnline) return;
    if (_status != AvailabilityStatus.online) {
      _estacionadas.clear();
      return;
    }
    if (_posicao == null || _perfil == null) return;
    final itens = List.of(_estacionadas);
    _estacionadas.clear();
    for (final item in itens) {
      _enfileirarOuAbrir(item);
    }
  }

  Future<void> _reconectarRelays() async {
    // Desabilita o botão durante a chamada: toque duplo não sobrepõe rodadas.
    setState(() => _reconectandoRelays = true);
    try {
      await widget.relayService.reconnectNow();
    } finally {
      if (mounted) setState(() => _reconectandoRelays = false);
    }
  }

  Future<void> _carregarPrecoPadrao() async {
    final perfil = await widget.cadastroStore.load();
    if (!mounted || perfil == null) return;
    setState(() => _perfil = perfil);
    _liberarEstacionadas();
  }

  /// Restaura o estado "Aguardando"/"Deslocando-se" persistido (FR-003,
  /// FR-009) — sem isto, o motorista voltaria sempre a "Aguardando" ao
  /// reabrir o app, mesmo tendo confirmado uma corrida antes de fechá-lo.
  Future<void> _carregarEstadoCorrida() async {
    final (status, active) = await widget.rideStateStore.load();
    if (!mounted) return;
    setState(() {
      _rideStatus = status;
      _activeRide = active;
    });
    _sincronizarRota();
  }

  /// Reage a qualquer mudança do `EventFeed`, tratando solicitações de
  /// corrida (`kind: 20001`, FR-001 da feature 007) e aceitações de
  /// orçamento (`kind: 20003`, FR-001 da feature 010) ainda não
  /// processadas.
  void _aoAtualizarFeed() {
    for (final evento in widget.eventFeed.events) {
      if (evento.kind == NostrEvent.kindRideRequest) {
        if (!_idsProcessados.add(evento.id)) continue;
        _processarSolicitacaoRecebida(evento);
      } else if (evento.kind == NostrEvent.kindQuoteAccepted) {
        if (!_idsProcessados.add(evento.id)) continue;
        unawaited(_processarAceitacaoRecebida(evento));
      } else if (evento.kind == NostrEvent.kindMeetingConfirmed) {
        if (!_idsProcessados.add(evento.id)) continue;
        _processarConfirmacaoDeEncontro(evento);
      } else if (evento.kind == NostrEvent.kindDestinationConfirmed) {
        if (!_idsProcessados.add(evento.id)) continue;
        _processarConfirmacaoDeDestino(evento);
      } else if (evento.kind == NostrEvent.kindRideCancelledByPassenger) {
        if (!_idsProcessados.add(evento.id)) continue;
        _processarCancelamentoDoPassageiro(evento);
      } else if (evento.kind == NostrEvent.kindReceipt) {
        if (!_idsProcessados.add(evento.id)) continue;
        // Regra 7 e validação ficam no serviço; nada aqui bloqueia a interface.
        unawaited(_absorver(widget.receiptService?.onReceiptEvent(evento)));
      } else if (evento.kind == NostrEvent.kindReceiptAck) {
        if (!_idsProcessados.add(evento.id)) continue;
        unawaited(_absorver(widget.receiptService?.onAckEvent(evento)));
      }
    }
  }

  /// Falha ao tratar um recibo ou confirmação não pode derrubar a tela nem
  /// virar erro não tratado: o avaliador reenvia (1.7 passo 5).
  Future<void> _absorver(Future<void>? tarefa) async {
    try {
      await tarefa;
    } on Object {
      // Absorvida.
    }
  }

  /// Regra de recepção 7 do contrato (emenda 17) para os kinds do passageiro
  /// sem dado próprio (`20003`, `20008`, `20010`): a tag `p` precisa ser a
  /// chave deste motorista e o `content` precisa decifrar para exatamente
  /// `{}`. Falso → o evento é descartado em silêncio, sem efeito algum (a
  /// assinatura já foi verificada pelo `EventFeed`).
  bool _decifraSemDadoProprio(NostrEvent evento) {
    final identity = widget.identity;
    if (identity == null) return false;
    return widget.identityService.decryptContent(
          identity: identity,
          event: evento,
          emptyMarker: true,
        ) !=
        null;
  }

  /// Reconhece a confirmação de encontro (`kind: 20008`) e transiciona para
  /// "Em corrida" (FR-001, FR-002 da feature 012) — ignorada fora do estado
  /// "Deslocando-se até o passageiro" ou referenciando outra corrida.
  void _processarConfirmacaoDeEncontro(NostrEvent evento) {
    if (!_decifraSemDadoProprio(evento)) return;
    final ativa = _activeRide;
    if (ativa == null || evento.referencedEventId != ativa.quoteId) return;
    if (!DriverRideRules.canConfirmMeeting(_rideStatus)) return;

    setState(() => _rideStatus = DriverRideStatus.emCorrida);
    unawaited(widget.rideStateStore.save(_rideStatus, ativa));
    _sincronizarRota();
  }

  /// Reconhece a confirmação de destino (`kind: 20010`) e volta o motorista
  /// a "Aguardando solicitação de corrida", encerrando a corrida ativa
  /// (FR-007, FR-008 da feature 012) — ignorada fora do estado "Em corrida"
  /// ou referenciando outra corrida.
  void _processarConfirmacaoDeDestino(NostrEvent evento) {
    if (!_decifraSemDadoProprio(evento)) return;
    final ativa = _activeRide;
    if (ativa == null || evento.referencedEventId != ativa.quoteId) return;
    if (!DriverRideRules.canConfirmDestinationArrival(_rideStatus)) return;

    setState(() {
      _rideStatus = DriverRideStatus.aguardandoSolicitacao;
      _activeRide = null;
      _ultimaPublicacaoEm = null;
      _ultimaChegadaEm = null;
    });
    unawaited(widget.rideStateStore.save(_rideStatus, null));
    _sincronizarRota();
    unawaited(_mostrarModalAvaliacao(ativa));
  }

  /// Abre a confirmação do cancelamento (feature 018, FR-002) — mesmo padrão
  /// de `_mostrarModalAvaliacao`. "Voltar" fecha sem efeito; "Cancelar
  /// corrida" fecha e efetiva.
  Future<void> _mostrarModalCancelamento() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        _contextoConfirmacaoCancelamento = dialogContext;
        return CancelRideModal(
          onBack: () => Navigator.of(dialogContext).pop(),
          onConfirm: () {
            Navigator.of(dialogContext).pop();
            _cancelarCorrida();
          },
        );
      },
    );
    _contextoConfirmacaoCancelamento = null;
  }

  /// Cancela a corrida ativa (feature 018, FR-003 a FR-008): volta a
  /// "Aguardando solicitação de corrida", zera e persiste a corrida, limpa
  /// a rota e avisa o passageiro (`kind: 20012`).
  ///
  /// Todo o efeito local acontece antes de qualquer `await`, de modo que um
  /// segundo acionamento já vê "Aguardando" e sai — no máximo um aviso por
  /// corrida (D3 de `specs/018-cancelar-corrida-motorista/research.md`).
  /// Diferente da conclusão (`_processarConfirmacaoDeDestino`), não abre a
  /// avaliação (FR-006).
  void _cancelarCorrida() {
    final ativa = _activeRide;
    if (ativa == null || !DriverRideRules.canCancelRide(_rideStatus)) return;

    _encerrarCorridaLocalmente();
    unawaited(_publicarCancelamento(ativa));
  }

  /// Efeito local comum ao cancelamento pelo motorista (feature 018) e ao
  /// aviso de cancelamento do passageiro (feature 020): volta a "Aguardando
  /// solicitação de corrida", zera e persiste a corrida e limpa a rota e o
  /// marcador. Tudo antes de qualquer `await`, de modo que uma segunda
  /// chamada já encontra o repouso e sai nas guardas dos chamadores.
  void _encerrarCorridaLocalmente() {
    setState(() {
      _rideStatus = DriverRideStatus.aguardandoSolicitacao;
      _activeRide = null;
      _ultimaPublicacaoEm = null;
      _ultimaChegadaEm = null;
    });
    unawaited(widget.rideStateStore.save(_rideStatus, null));
    _sincronizarRota();
  }

  /// Reconhece o cancelamento da corrida pelo passageiro (`kind: 20013`,
  /// emenda 19, feature 020). Só vale o aviso do passageiro da corrida ativa
  /// (autor e `["e", quoteId]` — a tag é pública no relay, então a autoria
  /// precisa bater), cifrado a este motorista, com o motorista em
  /// "Deslocando-se até o passageiro" ou "Em corrida"
  /// (`DriverRideRules.canBeCancelledByPassenger`); qualquer outro é
  /// ignorado sem erro.
  ///
  /// A corrida é encerrada no instante do recebimento, não ao tocar "OK"
  /// (FR-003). Não abre a avaliação nem publica nada (FR-006); uma
  /// confirmação de cancelamento própria que esteja aberta é fechada, porque
  /// a corrida que ela cancelaria já não existe (D4 de `research.md`).
  void _processarCancelamentoDoPassageiro(NostrEvent evento) {
    if (!_decifraSemDadoProprio(evento)) return;
    final ativa = _activeRide;
    if (ativa == null || evento.referencedEventId != ativa.quoteId) return;
    if (evento.authorPublicKey != ativa.passengerPubkey) return;
    if (!DriverRideRules.canBeCancelledByPassenger(_rideStatus)) return;

    _encerrarCorridaLocalmente();

    final confirmacao = _contextoConfirmacaoCancelamento;
    if (confirmacao != null && confirmacao.mounted) {
      Navigator.of(confirmacao).pop();
    }
    unawaited(_mostrarModalCancelamentoPeloPassageiro());
  }

  /// Exibe a modal informativa do cancelamento pelo passageiro (feature 020,
  /// FR-005) — mesmo padrão de `_mostrarModalAceitacao`, fora da fila de
  /// solicitações, que só trata modais de "Aguardando".
  Future<void> _mostrarModalCancelamentoPeloPassageiro() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => RideCancelledByPassengerModal(
        onClose: () => Navigator.of(dialogContext).pop(),
      ),
    );
  }

  /// Publica o cancelamento ao passageiro da corrida cancelada. Melhor
  /// esforço, como `_publicarChegada`: sem identidade ou sem relay
  /// conectado, ou se a publicação falhar, o cancelamento local prevalece e
  /// nada é reenviado (FR-008).
  Future<void> _publicarCancelamento(ActiveRide ativa) async {
    final identity = widget.identity;
    if (identity == null) return;
    if (!widget.relayService.hasConnectedRelay) return;

    try {
      final signed = widget.identityService.signRideCancelled(
        identity: identity,
        quoteId: ativa.quoteId,
        passengerPubkey: ativa.passengerPubkey,
      );
      await widget.relayService
          .publish(signed.event, payload: signed.payload)
          .toList();
    } on Object {
      // Absorvida: sem fila nem reenvio (D4).
    }
  }

  /// Exibe a tela de avaliação da corrida recém-encerrada (feature 013,
  /// FR-001) — mesmo padrão de `_mostrarModalAceitacao`. Confirmar persiste
  /// a nota via `RideRatingStore` (FR-004, FR-005); pular fecha sem
  /// persistir nada (FR-008). Nos dois casos, **depois** de gravar a nota local,
  /// tenta emitir o recibo de reputação (feature 026, 1.7); isso nunca bloqueia
  /// a interface.
  Future<void> _mostrarModalAvaliacao(ActiveRide corrida) async {
    final quoteId = corrida.quoteId;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => RideRatingModal(
        onConfirm: (stars) async {
          // Identidade nula (falha de inicialização, D3 de
          // specs/014-integridade-row-signing/research.md): não há chave
          // para assinar a avaliação, então ela não é persistida — mesma
          // guarda já usada por outros métodos desta tela que assinam algo.
          final identity = widget.identity;
          if (identity != null) {
            await widget.rideRatingStore.save(
              RideRating(
                rideId: quoteId,
                stars: stars,
                ratedAt: DateTime.now(),
              ),
              identity,
            );
          }
          if (dialogContext.mounted) Navigator.of(dialogContext).pop();
          unawaited(_emitirRecibo(corrida, stars));
        },
        onSkip: () {
          Navigator.of(dialogContext).pop();
          unawaited(_emitirRecibo(corrida, null));
        },
      ),
    );
  }

  /// Emite o recibo da [corrida] encerrada (1.7). Reputação inconsistente do
  /// passageiro: nenhum recibo e um aviso de uma linha; a nota local já está
  /// gravada. Qualquer falha é absorvida: o recibo, se gravado, é reenviado.
  Future<void> _emitirRecibo(ActiveRide corrida, int? stars) async {
    final servico = widget.receiptService;
    if (servico == null) return;
    try {
      final resultado = await servico.issueFor(corrida, stars);
      if (resultado == ReceiptIssue.inconsistent && mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text(
              'Recibo não emitido: a reputação do passageiro está inconsistente.',
            ),
          ),
        );
      }
    } on Object {
      // Absorvida.
    }
  }

  /// A regra de aceitação (offline, corrida em andamento, `content`
  /// malformado, pagamento não aceito) é a de [RideRequestFilter], a mesma que
  /// o serviço em segundo plano usa para decidir notificar (feature 025,
  /// FR-005). Uma solicitação recusada é ignorada em silêncio, sem modal.
  void _processarSolicitacaoRecebida(NostrEvent evento) {
    // Enquanto o serviço não disse se o motorista estava online (ou a retomada
    // espera posição), "offline" ainda não é um fato: a solicitação é avaliada
    // como se estivesse online e estacionada até a retomada terminar.
    final retomando = _aguardandoServico || _retomandoOnline;
    final decisao = RideRequestFilter.evaluate(
      evento,
      _estadoDoServico.copyWith(online: retomando ? true : null),
    );
    if (!decisao.accepted) return;
    final item = _PendingRideRequest(decisao.request!);
    if (retomando) {
      _estacionadas.add(item);
      return;
    }
    _enfileirarOuAbrir(item);
  }

  /// O que o filtro de solicitações precisa do estado desta tela.
  ServiceState get _estadoDoServico => ServiceState(
    online: _status == AvailabilityStatus.online,
    acceptedPayments: _perfil?.paymentMethods.map((m) => m.wireValue).toSet(),
    rideStatus: _rideStatus,
  );

  /// O estado como o serviço o recebe: durante a retomada (FR-012) ele já vê o
  /// motorista como online, para não perder solicitações enquanto a tela
  /// espera a posição.
  ServiceState get _estadoParaOServico =>
      _estadoDoServico.copyWith(online: _retomandoOnline ? true : null);

  /// Sem cadastro carregado ainda não há o que comparar: não descarta aqui, e
  /// a guarda de [_abrirProximaModal] trata a janela sem perfil.
  bool _aceitaPagamento(RideRequestReceived solicitacao) =>
      RideRequestFilter.acceptsPayment(
        _estadoDoServico.acceptedPayments,
        solicitacao.payment,
      );

  Future<void> _processarAceitacaoRecebida(NostrEvent evento) async {
    if (!_decifraSemDadoProprio(evento)) return;
    QuoteAccepted aceitacao;
    try {
      aceitacao = QuoteAccepted.fromNostrEvent(evento);
    } on FormatException {
      // tag "e" ausente/malformada é dado, nunca instrução (regra 3 de
      // recepção) — descartada sem exibir modal, sem travar o app.
      return;
    }

    // FR-011: ignora aceitação que não corresponde a um orçamento
    // efetivamente enviado por este motorista — mesmo após um reinício do
    // app entre o envio e a chegada da aceitação, já que `SentQuotesStore`
    // é persistido (D6 de `research.md`, achado C1 do `/speckit-analyze`).
    if (!await widget.sentQuotesStore.contains(aceitacao.quoteId)) return;
    if (!mounted) return;

    _enfileirarOuAbrir(_PendingQuoteAccepted(aceitacao));
  }

  void _enfileirarOuAbrir(_PendingModal item) {
    if (_modalAtual == null) {
      unawaited(_abrirProximaModal(item));
    } else {
      _fila.add(item);
    }
  }

  Future<void> _abrirProximaModal(_PendingModal item) async {
    switch (item) {
      case _PendingRideRequest(:final request):
        // Sem posição ou sem cadastro carregado ainda, não há como montar a
        // modal (o cadastro é obrigatório antes de qualquer tela, feature
        // 003 — isto é defensivo para a janela entre abrir a tela e o
        // load() terminar). O item é descartado, e a fila segue adiante.
        if (_posicao == null || _perfil == null) {
          _abrirProximaDaFila();
          return;
        }
        // O cadastro pode ter mudado enquanto a solicitação esperava na fila.
        if (!_aceitaPagamento(request)) {
          _abrirProximaDaFila();
          return;
        }
        setState(() => _modalAtual = item);
        await _mostrarModalSolicitacao(request);
      case _PendingQuoteAccepted(:final accepted):
        // FR-010: uma aceitação só abre a modal "Orçamento aceito" com o
        // motorista em "Aguardando". Em "Deslocando-se" ou "Em corrida" ele
        // já está comprometido — "Iniciar corrida" sobrescreveria a corrida
        // ativa — e o passageiro dessa aceitação é avisado (kind 20006).
        // Reavaliado aqui, e não só na chegada, porque a aceitação pode ter
        // ficado enfileirada.
        if (!DriverRideRules.canStartRide(_rideStatus)) {
          unawaited(_publicarCorridaIndisponivel(accepted));
          _abrirProximaDaFila();
          return;
        }
        setState(() => _modalAtual = item);
        await _mostrarModalAceitacao(accepted);
    }

    if (!mounted) return;
    setState(() => _modalAtual = null);
    _abrirProximaDaFila();
  }

  void _abrirProximaDaFila() {
    if (_fila.isNotEmpty) {
      unawaited(_abrirProximaModal(_fila.removeAt(0)));
    }
  }

  Future<void> _mostrarModalSolicitacao(RideRequestReceived solicitacao) async {
    final posicaoAtual = _posicao!;
    final perfil = _perfil!;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => RideRequestModal(
        request: solicitacao,
        driverPosition: LatLng(posicaoAtual.latitude, posicaoAtual.longitude),
        driverProfile: perfil,
        routeDistanceService: widget.routeDistanceService,
        reverseGeocodingService: widget.reverseGeocodingService,
        onSendQuote: (quote) =>
            _enviarOrcamento(dialogContext, quote, solicitacao),
        onReject: () => Navigator.of(dialogContext).pop(),
      ),
    );
  }

  Future<void> _mostrarModalAceitacao(QuoteAccepted aceitacao) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => QuoteAcceptedModal(
        onStartRide: () => _iniciarCorrida(dialogContext, aceitacao),
      ),
    );
  }

  /// Publica o orçamento (FR-011, FR-017 da feature 007); fecha a modal só
  /// se ao menos um relay aceitar (FR-013); devolve a mensagem de erro sem
  /// fechar a modal se nenhum relay estiver conectado (FR-012).
  ///
  /// Registra o `id` do orçamento em `SentQuotesStore`, junto da origem de
  /// [solicitacao], assim que a publicação é aceita (FR-011 da feature 010;
  /// a origem é o que a feature 011 usa depois para saber a que ponto
  /// comparar a posição do motorista, D1 de
  /// `specs/011-notificar-chegada/research.md`) — o envio de um orçamento
  /// nunca muda `_rideStatus` (FR-006): nenhuma linha abaixo toca esse
  /// campo.
  Future<String?> _enviarOrcamento(
    BuildContext dialogContext,
    RideQuote quote,
    RideRequestReceived solicitacao,
  ) async {
    final identity = widget.identity;
    if (identity == null) {
      return 'Identidade indisponível. O orçamento não foi enviado.';
    }
    if (!widget.relayService.hasConnectedRelay) {
      return 'Nenhum relay conectado. O orçamento não foi enviado — '
          'conecte-se a um relay e tente novamente.';
    }

    final minhaReputacao = await _reputacaoPropria();
    final SignedEvent signed;
    try {
      signed = widget.identityService.signRideQuote(
        identity: identity,
        quote: quote.withReputation(minhaReputacao),
      );
    } on Object {
      // Emenda 17: sem cifrar, não se publica — nunca em claro.
      return 'Não foi possível cifrar o orçamento. O orçamento não foi enviado.';
    }
    final resultados = await widget.relayService
        .publish(signed.event, payload: signed.payload)
        .toList();
    final aceitos = resultados.where((r) => r.accepted).length;
    if (aceitos == 0) {
      return 'Nenhum relay aceitou o orçamento.';
    }

    await widget.sentQuotesStore.add(
      signed.event.id,
      originLat: solicitacao.origin.latitude,
      originLon: solicitacao.origin.longitude,
      destinationLat: solicitacao.destination.latitude,
      destinationLon: solicitacao.destination.longitude,
    );
    await _guardarReputacaoDoPassageiro(signed.event.id, solicitacao);
    if (dialogContext.mounted) Navigator.of(dialogContext).pop();
    return null;
  }

  /// Reputação própria a declarar no orçamento (emenda 25): a calculada dos
  /// recibos recebidos, ou `null` — chave omitida — sem histórico. Falha de
  /// leitura nunca impede o orçamento: ele sai sem o campo.
  Future<Reputation?> _reputacaoPropria() async {
    final loja = widget.receiptStore;
    if (loja == null) return null;
    try {
      final minha = await loja.myReputation();
      return minha.corridas == 0 ? null : minha;
    } on Object {
      return null;
    }
  }

  /// Guarda a reputação que o passageiro declarou na solicitação respondida,
  /// ligada ao `id` do orçamento (a corrida), para o recibo do fim da corrida
  /// usar exatamente o que foi apresentado na negociação (1.7 passo 1). Sem
  /// reputação gravamos uma vazia: linha presente = corrida registrada, passageiro
  /// sem histórico (R4 de `specs/026-recibos-de-reputacao/research.md`). Falha
  /// aqui não desfaz o orçamento já publicado; só deixa a corrida sem recibo.
  Future<void> _guardarReputacaoDoPassageiro(
    String quoteId,
    RideRequestReceived solicitacao,
  ) async {
    final loja = widget.receiptStore;
    if (loja == null) return;
    try {
      await loja.saveDeclared(
        quoteId,
        solicitacao.passengerPubkey,
        solicitacao.reputation ?? const Reputation.empty(),
      );
    } on Object {
      // Absorvida: sem registro, a corrida simplesmente não gera recibo.
    }
  }

  /// Transiciona para "Deslocando-se até o passageiro" (FR-002), persiste o
  /// novo estado (FR-003) e descarta a fila de solicitações pendente
  /// (FR-005) — o envio de orçamento (acima) nunca chama este método.
  ///
  /// A origem gravada em `ActiveRide` vem de `SentQuotesStore.originFor`
  /// (feature 011, D1 de `research.md`) — a aceitação em si não a repete.
  Future<void> _iniciarCorrida(
    BuildContext dialogContext,
    QuoteAccepted aceitacao,
  ) async {
    final origem = await widget.sentQuotesStore.originFor(aceitacao.quoteId);
    final destino = await widget.sentQuotesStore.destinationFor(
      aceitacao.quoteId,
    );
    final activeRide = ActiveRide(
      quoteId: aceitacao.quoteId,
      passengerPubkey: aceitacao.passengerPubkey,
      // Defensivo: FR-011 já validou que este quoteId está em
      // SentQuotesStore antes de a modal ser aberta, então originFor/
      // destinationFor nunca deveriam devolver null aqui.
      originLat: origem?.$1 ?? 0,
      originLon: origem?.$2 ?? 0,
      destinationLat: destino?.$1 ?? 0,
      destinationLon: destino?.$2 ?? 0,
    );
    setState(() {
      _rideStatus = DriverRideStatus.deslocandoAtePassageiro;
      _activeRide = activeRide;
      _fila.removeWhere((item) => item is _PendingRideRequest);
      _ultimaPublicacaoEm = null;
      _ultimaChegadaEm = null;
    });
    _sincronizarRota();
    await widget.rideStateStore.save(_rideStatus, activeRide);
    if (dialogContext.mounted) Navigator.of(dialogContext).pop();
  }

  /// Publica `kind: 20006` ao passageiro de uma aceitação que chegou (ou foi
  /// reavaliada) enquanto o motorista já estava comprometido com outra
  /// corrida, em "Deslocando-se" ou "Em corrida" (FR-010; emenda 16 do
  /// contrato). Melhor esforço: sem identidade ou sem relay conectado, não há
  /// nada a fazer — a UI não é interrompida por isso.
  Future<void> _publicarCorridaIndisponivel(QuoteAccepted aceitacao) async {
    final identity = widget.identity;
    if (identity == null) return;
    if (!widget.relayService.hasConnectedRelay) return;

    final SignedEvent signed;
    try {
      signed = widget.identityService.signRideNoLongerAvailable(
        identity: identity,
        quoteId: aceitacao.quoteId,
        passengerPubkey: aceitacao.passengerPubkey,
      );
    } on Object {
      // Falha ao cifrar (emenda 17): nada é publicado em claro; absorvida, sem
      // fila nem reenvio — mesmo tratamento de uma publicação que falha.
      return;
    }
    await widget.relayService
        .publish(signed.event, payload: signed.payload)
        .toList();
  }

  Future<void> _iniciar() async {
    try {
      await widget.locationService.ensurePermission();
    } catch (erro) {
      if (!mounted) return;
      setState(() {
        _carregando = false;
        _retomandoOnline = false;
        _estacionadas.clear();
        _mensagemIndisponibilidade = _descrever(erro);
      });
      return;
    }

    if (mounted) setState(() => _carregando = false);

    _assinatura = widget.locationService.positions.listen(
      _aoReceberPosicao,
      onError: (Object erro) {
        if (!mounted) return;
        setState(() {
          _mensagemIndisponibilidade = _descrever(erro);
          // A posição que tínhamos não é mais confiável — sem isso,
          // AvailabilityRules.canGoOnline continuaria vendo uma posição
          // válida que já não existe.
          _posicao = null;
          _retomandoOnline = false;
          _estacionadas.clear();
          if (_status == AvailabilityStatus.online) {
            // FR-009: perder a localização estando online força offline
            // automaticamente, com explicação distinta de uma recusa comum.
            _status = AvailabilityStatus.offline;
            _avisoStatus =
                'Você ficou offline porque a localização foi perdida.';
          }
        });
      },
    );
  }

  /// Alterna entre online e offline (FR-006, FR-008 da feature 004).
  ///
  /// Função síncrona, sem nenhum `await`: Dart processa um toque até o fim
  /// antes de começar a tratar o próximo, então dois toques disparados em
  /// sequência rápida não podem se intercalar e produzir um estado
  /// intermediário — não é necessário (nem faria sentido) um mecanismo de
  /// bloqueio adicional aqui (edge case de toques repetidos do `spec.md`).
  void _alternarStatus() {
    if (_status == AvailabilityStatus.offline) {
      if (!AvailabilityRules.canGoOnline(hasValidPosition: _posicao != null)) {
        setState(
          () => _avisoStatus =
              'É preciso ter uma localização válida para ficar online.',
        );
        return;
      }
      setState(() {
        _status = AvailabilityStatus.online;
        _avisoStatus = null;
      });
      unawaited(_garantirPermissaoDeNotificacao());
    } else {
      setState(() {
        _status = AvailabilityStatus.offline;
        _avisoStatus = null;
      });
    }
  }

  /// FR-009 da feature 025: a permissão de notificação é pedida ao ficar online,
  /// nunca ao abrir o app. Negada, o motorista é avisado de que só será avisado
  /// de corridas com o app aberto.
  Future<void> _garantirPermissaoDeNotificacao() async {
    final controlador = widget.serviceController;
    if (controlador == null) return;
    final concedida = await controlador.ensureNotificationPermission();
    if (concedida || !mounted || _status != AvailabilityStatus.online) return;
    setState(
      () => _avisoStatus =
          'Sem a permissão de notificações você só será avisado de '
          'corridas com o app aberto.',
    );
  }

  void _aoReceberPosicao(DriverPosition posicao) {
    if (!mounted) return;
    setState(() {
      _posicao = posicao;
      _mensagemIndisponibilidade = null;
      if (_retomandoOnline) {
        _retomandoOnline = false;
        _prazoRetomada?.cancel();
        _status = AvailabilityStatus.online;
      }
    });
    _liberarEstacionadas();
    final ponto = LatLng(posicao.latitude, posicao.longitude);
    if (_seguindoMotorista && !_mapController.camera.zoom.isNaN) {
      _mapController.move(ponto, _mapController.camera.zoom);
    }

    _sincronizarRota();
    _talvezPublicarLocalizacao(posicao);
    _talvezNotificarChegada(posicao);
    _talvezNotificarChegadaAoDestino(posicao);
  }

  /// Mantém o trajeto até o ponto-alvo do trecho vigente em dia (feature
  /// 016): sem trecho (FR-003), limpa tudo; com trecho e posição, consulta o
  /// serviço de rota se [RideLeg.shouldRefresh] mandar (troca de trecho, ou
  /// 50 m fora do trajeto já traçado; sem trajeto, 50 m desde a última
  /// tentativa — FR-004, alterado a pedido para poupar a cota do serviço).
  void _sincronizarRota() {
    if (!mounted) return;
    final leg = RideLeg.of(_rideStatus, _activeRide);
    if (leg == null) {
      _limparRota();
      return;
    }

    _buscarEnderecoDoAlvo(leg.target);

    final rota = _rota;
    if (rota != null && rota.target != leg.target) {
      // Trecho mudou: o trajeto do anterior não vale mais.
      setState(() {
        _rota = null;
        _rotaIndisponivel = false;
      });
    }

    final posicao = _posicao;
    if (posicao == null || _rotaEmCalculo) return;
    final atual = LatLng(posicao.latitude, posicao.longitude);
    if (!RideLeg.shouldRefresh(
      leg: leg,
      current: atual,
      lastAttempt: _ultimaTentativaRota,
      // Trajeto vigente só conta se a última tentativa deu certo; se falhou,
      // volta a regra de 50 m desde a tentativa, para tentar de novo.
      route: _rotaIndisponivel ? null : _rota?.points,
    )) {
      return;
    }
    unawaited(_calcularRota(leg, atual));
  }

  /// Resolve o endereço do alvo do trecho, uma vez por alvo.
  void _buscarEnderecoDoAlvo(LatLng alvo) {
    if (_enderecoAlvoDe == alvo) return;
    _enderecoAlvoDe = alvo;
    _enderecoAlvo = null;
    unawaited(() async {
      String texto;
      try {
        texto = await widget.reverseGeocodingService.addressOf(alvo);
      } on Object {
        texto =
            '${alvo.latitude.toStringAsFixed(5)}, '
            '${alvo.longitude.toStringAsFixed(5)}';
      }
      if (!mounted || _enderecoAlvoDe != alvo) return;
      setState(() => _enderecoAlvo = texto);
    }());
  }

  void _limparRota() {
    _enderecoAlvoDe = null;
    _enderecoAlvo = null;
    if (_rota == null &&
        !_rotaIndisponivel &&
        _ultimaTentativaRota == null &&
        _trechoEnquadrado == null &&
        _seguindoMotorista) {
      return;
    }
    setState(() {
      _rota = null;
      _rotaIndisponivel = false;
      _ultimaTentativaRota = null;
      _trechoEnquadrado = null;
      _seguindoMotorista = true;
    });
  }

  /// Consulta o trajeto do trecho [leg] a partir de [origem] e o guarda para o
  /// mapa. Em "Em corrida", o trajeto bem-sucedido também é publicado ao
  /// passageiro (feature 017, D4).
  Future<void> _calcularRota(RideLeg leg, LatLng origem) async {
    _rotaEmCalculo = true;
    _ultimaTentativaRota = (leg: leg, origin: origem);
    try {
      final trajeto = await widget.routeDistanceService.trace(
        origin: origem,
        destination: leg.target,
      );
      // Resposta tardia de um trecho que já acabou ou mudou: descartada.
      if (!mounted || RideLeg.of(_rideStatus, _activeRide) != leg) return;
      setState(() {
        _rota = trajeto;
        _rotaIndisponivel = false;
      });
      _enquadrarPrimeiroTrajeto(leg, trajeto);
      // Feature 017: o mesmo trajeto, já calculado para o mapa, segue ao
      // passageiro — só em "Em corrida" (FR-004, FR-005) e sem consulta nova
      // (FR-007).
      final corrida = _activeRide;
      if (_rideStatus == DriverRideStatus.emCorrida && corrida != null) {
        unawaited(_publicarRota(corrida, trajeto));
      }
    } on Object {
      // FR-005: qualquer falha é absorvida — o mapa segue útil e nada da
      // corrida é bloqueado. Um trajeto anterior, se houver, continua.
      if (!mounted || RideLeg.of(_rideStatus, _activeRide) != leg) return;
      setState(() => _rotaIndisponivel = true);
    } finally {
      _rotaEmCalculo = false;
      _sincronizarRota();
    }
  }

  /// Enquadra posição, trajeto e alvo na primeira vez que o trecho `leg`
  /// recebe um trajeto, e para de seguir o motorista até ele tocar em
  /// "Centralizar" (FR-010).
  void _enquadrarPrimeiroTrajeto(RideLeg leg, RouteTrace trajeto) {
    if (_trechoEnquadrado == leg) return;
    _trechoEnquadrado = leg;
    setState(() => _seguindoMotorista = false);
    if (_mapController.camera.zoom.isNaN) return;
    _mapController.fitCamera(
      CameraFit.coordinates(
        coordinates: [trajeto.originUsed, ...trajeto.points, leg.target],
        padding: const EdgeInsets.fromLTRB(48, 96, 48, 290),
        maxZoom: 17,
      ),
    );
  }

  /// Volta a seguir o motorista (botão "Centralizar", FR-010).
  void _centralizarNoMotorista(LatLng ponto) {
    setState(() => _seguindoMotorista = true);
    _mapController.move(ponto, 16);
  }

  /// Publica a chegada (`kind: 20007`) a cada [_intervaloLocalizacao] —
  /// enquanto, e somente enquanto, o motorista está "Deslocando-se até o
  /// passageiro" e a posição está a [_raioDeChegadaMetros] ou menos da
  /// origem da corrida ativa (FR-001 a FR-003 da feature 021, que substituiu
  /// o aviso único da feature 011). A primeira publicação sai na primeira
  /// posição dentro do raio; as seguintes, quando o instante de captura
  /// avança o intervalo desde a última (mesmo critério do `kind: 20005`).
  void _talvezNotificarChegada(DriverPosition posicao) {
    if (_rideStatus != DriverRideStatus.deslocandoAtePassageiro) return;
    final activeRide = _activeRide;
    if (activeRide == null) return;

    final distancia = metersBetween(
      activeRide.originLat,
      activeRide.originLon,
      posicao.latitude,
      posicao.longitude,
    );
    if (distancia > _raioDeChegadaMetros) return;

    final ultima = _ultimaChegadaEm;
    if (ultima != null &&
        posicao.capturedAt.difference(ultima) < _intervaloLocalizacao) {
      return;
    }

    _ultimaChegadaEm = posicao.capturedAt;
    unawaited(_publicarChegada(activeRide));
  }

  Future<void> _publicarChegada(ActiveRide activeRide) async {
    final identity = widget.identity;
    if (identity == null) return;
    if (!widget.relayService.hasConnectedRelay) return;

    final SignedEvent signed;
    try {
      signed = widget.identityService.signArrivalNotice(
        identity: identity,
        quoteId: activeRide.quoteId,
        passengerPubkey: activeRide.passengerPubkey,
      );
    } on Object {
      // Falha ao cifrar (emenda 17): nada é publicado em claro; absorvida, sem
      // fila nem reenvio — mesmo tratamento de uma publicação que falha.
      return;
    }
    await widget.relayService
        .publish(signed.event, payload: signed.payload)
        .toList();
  }

  /// Publica a chegada ao destino (`kind: 20009`) quando — e somente quando
  /// — o motorista está "Em corrida", a posição está a 1 km ou menos do
  /// destino da corrida ativa, e essa chegada ainda não foi avisada (FR-003
  /// a FR-006 da feature 012).
  void _talvezNotificarChegadaAoDestino(DriverPosition posicao) {
    if (_rideStatus != DriverRideStatus.emCorrida) return;
    final activeRide = _activeRide;
    if (activeRide == null || activeRide.destinationArrivalNotified) return;

    final distancia = metersBetween(
      activeRide.destinationLat,
      activeRide.destinationLon,
      posicao.latitude,
      posicao.longitude,
    );
    if (distancia > _raioDeChegadaAoDestinoMetros) return;

    final atualizada = activeRide.copyWith(destinationArrivalNotified: true);
    setState(() => _activeRide = atualizada);
    unawaited(widget.rideStateStore.save(_rideStatus, atualizada));
    unawaited(_publicarChegadaAoDestino(activeRide));
  }

  Future<void> _publicarChegadaAoDestino(ActiveRide activeRide) async {
    final identity = widget.identity;
    if (identity == null) return;
    if (!widget.relayService.hasConnectedRelay) return;

    final SignedEvent signed;
    try {
      signed = widget.identityService.signDestinationArrival(
        identity: identity,
        quoteId: activeRide.quoteId,
        passengerPubkey: activeRide.passengerPubkey,
      );
    } on Object {
      // Falha ao cifrar (emenda 17): nada é publicado em claro; absorvida, sem
      // fila nem reenvio — mesmo tratamento de uma publicação que falha.
      return;
    }
    await widget.relayService
        .publish(signed.event, payload: signed.payload)
        .toList();
  }

  /// Publica a rota da corrida (`kind: 20011`, emenda 13 do contrato,
  /// feature 017) com os pontos de [trajeto]. Qualquer falha — sem
  /// identidade, sem relay conectado, rota com menos de 2 pontos, relay que
  /// recusa — é absorvida: nada disso bloqueia o mapa nem a corrida, e não há
  /// reenvio (D5); a próxima rota calculada será publicada normalmente.
  Future<void> _publicarRota(ActiveRide activeRide, RouteTrace trajeto) async {
    final identity = widget.identity;
    if (identity == null) return;
    if (!widget.relayService.hasConnectedRelay) return;

    try {
      final signed = widget.identityService.signRideRoute(
        identity: identity,
        quoteId: activeRide.quoteId,
        passengerPubkey: activeRide.passengerPubkey,
        points: trajeto.points,
      );
      await widget.relayService
          .publish(signed.event, payload: signed.payload)
          .toList();
    } on Object {
      // Ver comentário acima.
    }
  }

  /// Publica a localização atual quando — e somente quando — o motorista
  /// está "Deslocando-se até o passageiro" ou "Em corrida" e a nova posição
  /// foi capturada ao menos [_intervaloLocalizacao] depois da última
  /// publicação (FR-007, FR-008 da feature 010). Continua durante "Em corrida" (Assumptions da
  /// feature 012: nada pede para parar).
  void _talvezPublicarLocalizacao(DriverPosition posicao) {
    if (_rideStatus == DriverRideStatus.aguardandoSolicitacao) return;
    final activeRide = _activeRide;
    if (activeRide == null) return;

    final ultima = _ultimaPublicacaoEm;
    if (ultima != null &&
        posicao.capturedAt.difference(ultima) < _intervaloLocalizacao) {
      return;
    }

    _ultimaPublicacaoEm = posicao.capturedAt;
    unawaited(_publicarLocalizacao(activeRide, posicao));
  }

  Future<void> _publicarLocalizacao(
    ActiveRide activeRide,
    DriverPosition posicao,
  ) async {
    final identity = widget.identity;
    if (identity == null) return;
    if (!widget.relayService.hasConnectedRelay) return;

    final SignedEvent signed;
    try {
      signed = widget.identityService.signDriverLocation(
        identity: identity,
        quoteId: activeRide.quoteId,
        passengerPubkey: activeRide.passengerPubkey,
        lat: posicao.latitude,
        lon: posicao.longitude,
      );
    } on Object {
      // Falha ao cifrar (emenda 17): nada é publicado em claro; absorvida, sem
      // fila nem reenvio — mesmo tratamento de uma publicação que falha.
      return;
    }
    await widget.relayService
        .publish(signed.event, payload: signed.payload)
        .toList();
  }

  static String _descrever(Object erro) {
    if (erro is LocationPermissionDenied) {
      return erro.permanently
          ? 'Permissão de localização negada permanentemente. Conceda-a '
                'pelas configurações do aparelho para usar o mapa.'
          : 'É preciso permitir o acesso à localização para mostrar o mapa '
                'e para ficar online.';
    }
    if (erro is LocationUnavailable) {
      return 'Não foi possível obter sua localização agora. Verifique se a '
          'localização está ligada no aparelho.';
    }
    return 'Não foi possível obter sua localização.';
  }

  @override
  Widget build(BuildContext context) {
    // Informa ao serviço o estado de que ele depende (feature 025). Feito aqui,
    // e não em cada atribuição de `_status`/`_rideStatus`/`_perfil`, para
    // nenhuma mudança escapar; o controlador só age se algo mudou, então
    // repetir a cada reconstrução não custa nada.
    widget.serviceController?.update(_estadoParaOServico);

    final posicao = _posicao;
    final ponto = posicao == null
        ? const LatLng(0, 0)
        : LatLng(posicao.latitude, posicao.longitude);
    final trecho = RideLeg.of(_rideStatus, _activeRide);
    final emCorridaAtiva = DriverRideRules.canCancelRide(_rideStatus);

    return Scaffold(
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                // Contorno `roxo` da identidade visual (constituição 2.6.0)
                // rente às bordas da tela, sem margem; o cartão de status e
                // o botão ficam sobrepostos. `foregroundDecoration`: o
                // contorno é pintado por cima do mapa, senão o mapa o
                // cobriria por inteiro.
                Container(
                  foregroundDecoration: BoxDecoration(
                    border: Border.all(color: IdentidadeVisual.roxo, width: 4),
                  ),
                  child: ClipRect(
                    child: FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: ponto,
                        initialZoom: 16,
                        backgroundColor: _MapaTokens.base,
                      ),
                      children: [
                        const CamadaMapaBase(),
                        if (_rota != null && _rota!.points.length >= 2)
                          PolylineLayer(
                            polylines: [
                              Polyline(
                                points: _rota!.points,
                                color: IdentidadeVisual.roxo,
                                strokeWidth: 5,
                              ),
                            ],
                          ),
                        if (trecho != null)
                          MarkerLayer(
                            markers: [
                              Marker(
                                point: trecho.target,
                                width: 44,
                                height: 44,
                                child: trecho.kind == RideLegKind.pickup
                                    ? const _MarcadorCircular(
                                        icon: Icons.person,
                                        semanticLabel: 'Ponto de embarque',
                                      )
                                    : const _MarcadorCircular(
                                        icon: Icons.flag,
                                        semanticLabel: 'Destino da corrida',
                                      ),
                              ),
                            ],
                          ),
                        if (posicao != null)
                          MarkerLayer(
                            markers: [
                              Marker(
                                point: ponto,
                                width: 44,
                                height: 44,
                                child: const _MarcadorCircular(
                                  icon: Icons.directions_car,
                                  semanticLabel: 'Sua posição',
                                ),
                              ),
                            ],
                          ),
                        // Acima do cartão de status, como no mockup; o widget já
                        // antepõe o "©" ao texto.
                        Padding(
                          padding: EdgeInsets.only(
                            bottom: emCorridaAtiva ? 230 : 104,
                          ),
                          child: const SimpleAttributionWidget(
                            source: Text(
                              'OpenFreeMap, OpenMapTiles\nOpenStreetMap contributors',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (posicao != null)
                  Positioned(
                    right: 16,
                    bottom: emCorridaAtiva ? 276 : 150,
                    child: _BotaoCentralizar(
                      onPressed: () => _centralizarNoMotorista(ponto),
                    ),
                  ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 16,
                  child: _BarraDeStatus(
                    status: _status,
                    aviso: _avisoStatus,
                    onAlternar: _alternarStatus,
                    corrida: DriverRideRules.canCancelRide(_rideStatus)
                        ? _CorridaEmAndamento(
                            endereco: _enderecoAlvo,
                            duracao: _rota?.durationSeconds,
                            onCancelar: _mostrarModalCancelamento,
                          )
                        : null,
                  ),
                ),
                if (!widget.relayService.hasConnectedRelay)
                  Positioned(
                    top: 48,
                    left: 16,
                    right: 16,
                    child: _FaixaSemRelays(
                      reconectando: _reconectandoRelays,
                      onReconectar: _reconectarRelays,
                    ),
                  ),
                if (_rotaIndisponivel && trecho != null)
                  Positioned(
                    // Abaixo da faixa de relays, quando as duas aparecem.
                    top: widget.relayService.hasConnectedRelay ? 48 : 112,
                    left: 16,
                    right: 16,
                    child: const _FaixaRotaIndisponivel(),
                  ),
                if (_mensagemIndisponibilidade != null)
                  _AvisoIndisponibilidade(
                    mensagem: _mensagemIndisponibilidade!,
                    onTentarDeNovo: _iniciar,
                  ),
              ],
            ),
    );
  }
}

/// Tokens exclusivos do mapa (constituição 2.7.0); os demais vêm de
/// [IdentidadeVisual].
class _MapaTokens {
  static const indicadorOffline = Color(0xFF6E6789);

  /// Fundo do mapa (tom `mapa-base`), visto enquanto os tiles não chegam.
  static const base = Color(0xFFE5DFEF);
}

/// Marcador circular de 44 px da identidade visual (`fundo`, borda branca de
/// 2 px, ícone em `destaque`) — o mesmo do motorista, do ponto de embarque e
/// do destino da corrida; só o ícone muda.
class _MarcadorCircular extends StatelessWidget {
  const _MarcadorCircular({required this.icon, required this.semanticLabel});

  final IconData icon;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: IdentidadeVisual.fundo,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Icon(
        icon,
        color: IdentidadeVisual.destaque,
        size: 24,
        semanticLabel: semanticLabel,
      ),
    );
  }
}

/// Faixa de estado de alerta (identidade visual): avisa que o trajeto não
/// pôde ser traçado, sem bloquear nada (FR-005).
class _FaixaRotaIndisponivel extends StatelessWidget {
  const _FaixaRotaIndisponivel();

  @override
  Widget build(BuildContext context) {
    final erro = Theme.of(context).colorScheme.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: IdentidadeVisual.campo,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(Icons.alt_route, size: 18, color: erro),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Não foi possível traçar a rota agora.',
              style: TextStyle(fontSize: 13, color: erro),
            ),
          ),
        ],
      ),
    );
  }
}

/// Faixa de estado de alerta: nenhum relay conectado, logo o motorista não
/// recebe solicitações nem publica nada. Oferece a reconexão na hora, sem
/// esperar o ciclo automático.
class _FaixaSemRelays extends StatelessWidget {
  const _FaixaSemRelays({
    required this.reconectando,
    required this.onReconectar,
  });

  final bool reconectando;
  final VoidCallback onReconectar;

  @override
  Widget build(BuildContext context) {
    final erro = Theme.of(context).colorScheme.error;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      decoration: BoxDecoration(
        color: IdentidadeVisual.campo,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off, size: 18, color: erro),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Sem conexão com os relays.',
              style: TextStyle(fontSize: 13, color: erro),
            ),
          ),
          FilledButton(
            key: const Key('botao-reconectar-mapa'),
            onPressed: reconectando ? null : onReconectar,
            // `estiloAcaoPrimaria` ocupa a largura toda; numa `Row` isso
            // estoura, então a largura mínima volta a zero.
            style: IdentidadeVisual.estiloAcaoPrimaria().copyWith(
              minimumSize: const WidgetStatePropertyAll(Size(0, 40)),
              padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: 16),
              ),
            ),
            child: Text(reconectando ? 'Reconectando…' : 'Reconectar'),
          ),
        ],
      ),
    );
  }
}

/// Bloco "corrida em andamento" do cartão de status (constituição 2.10.0):
/// endereço do alvo do trecho, tempo estimado e o botão de ação destrutiva
/// "Cancelar corrida" (feature 018).
class _CorridaEmAndamento extends StatelessWidget {
  const _CorridaEmAndamento({
    required this.endereco,
    required this.duracao,
    required this.onCancelar,
  });

  final String? endereco;
  final double? duracao;
  final VoidCallback onCancelar;

  @override
  Widget build(BuildContext context) {
    final minutos = duracao == null ? null : (duracao! / 60).ceil();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Divider(height: 1, thickness: 1, color: Color(0x1FFFFFFF)),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'CORRIDA EM ANDAMENTO',
                    style: TextStyle(
                      color: Color(0xB3FFFFFF),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    endereco ?? 'Buscando endereço…',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            if (minutos != null)
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Text(
                  '$minutos min',
                  style: const TextStyle(
                    color: IdentidadeVisual.brancoSuave,
                    fontSize: 13,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton.icon(
            key: const Key('botao-cancelar-corrida'),
            onPressed: onCancelar,
            style: IdentidadeVisual.estiloAcaoPrimaria(altura: 48),
            icon: const Icon(Icons.close, size: 20),
            label: const Text('Cancelar corrida'),
          ),
        ),
      ],
    );
  }
}

/// Botão circular que recentraliza o mapa na posição do motorista.
class _BotaoCentralizar extends StatelessWidget {
  const _BotaoCentralizar({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 3,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: const SizedBox(
          width: 48,
          height: 48,
          child: Icon(
            Icons.my_location,
            color: IdentidadeVisual.roxo,
            semanticLabel: 'Centralizar no mapa',
          ),
        ),
      ),
    );
  }
}

/// Controle de status online/offline (US2) — sempre visível na tela de mapa
/// (FR-006, FR-007 da feature 004).
class _BarraDeStatus extends StatelessWidget {
  const _BarraDeStatus({
    required this.status,
    required this.aviso,
    required this.onAlternar,
    this.corrida,
  });

  /// Bloco "corrida em andamento", só com corrida cancelável.
  final Widget? corrida;
  final AvailabilityStatus status;
  final String? aviso;
  final VoidCallback onAlternar;

  @override
  Widget build(BuildContext context) {
    final online = status == AvailabilityStatus.online;

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (aviso != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: IdentidadeVisual.fundoProfundo,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                aviso!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: IdentidadeVisual.fundoProfundo,
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x40000000),
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: online
                            ? IdentidadeVisual.destaque
                            : _MapaTokens.indicadorOffline,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            online ? 'Você está online' : 'Você está offline',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            online
                                ? 'Toque para parar de receber solicitações'
                                : 'Toque para receber solicitações',
                            style: const TextStyle(
                              color: IdentidadeVisual.brancoSuave,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Transform.scale(
                      scale: 1.15,
                      child: Switch(
                        value: online,
                        onChanged: (_) => onAlternar(),
                        thumbColor: const WidgetStatePropertyAll(Colors.white),
                        trackColor: WidgetStatePropertyAll(
                          online
                              ? IdentidadeVisual.roxo
                              : IdentidadeVisual.segmentoInativo,
                        ),
                        trackOutlineColor: const WidgetStatePropertyAll(
                          Colors.transparent,
                        ),
                      ),
                    ),
                  ],
                ),
                ?corrida,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AvisoIndisponibilidade extends StatelessWidget {
  const _AvisoIndisponibilidade({
    required this.mensagem,
    required this.onTentarDeNovo,
  });

  final String mensagem;
  final VoidCallback onTentarDeNovo;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: IdentidadeVisual.folha.withValues(alpha: 0.96),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.location_off,
                  size: 48,
                  color: IdentidadeVisual.roxo,
                ),
                const SizedBox(height: 16),
                Text(
                  mensagem,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    color: IdentidadeVisual.texto,
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  style: IdentidadeVisual.estiloAcaoPrimaria(),
                  onPressed: onTentarDeNovo,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Tentar de novo'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
