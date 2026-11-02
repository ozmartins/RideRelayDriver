import 'dart:async';

import 'package:flutter/material.dart';

import 'domain/cadastro_progress.dart';
import 'domain/driver_profile.dart';
import 'domain/identity.dart';
import 'screens/cadastro_screen.dart';
import 'screens/identidade_visual.dart';
import 'screens/map_screen.dart';
import 'screens/more_screen.dart';
import 'services/ors_api_key.dart';

import 'services/background/background_service.dart';
import 'services/background/foreground_task_channels.dart';
import 'services/background/service_controller.dart';
import 'services/cadastro_store.dart';
import 'services/consumed_kinds.dart';
import 'services/event_feed.dart';
import 'services/geolocator_location_service.dart';
import 'services/identity_service.dart';
import 'services/key_store.dart';
import 'services/key_value_store.dart';
import 'services/location_service.dart';
import 'services/ws_relay_gateway.dart';
import 'services/relay_gateway.dart';
import 'services/relay_repository.dart';
import 'services/relay_connection.dart';
import 'services/relay_service.dart';
import 'services/remote_relay_connection.dart';
import 'services/receipt_service.dart';
import 'services/receipt_store.dart';
import 'services/ride_rating_store.dart';
import 'services/ride_state_store.dart';
import 'services/reverse_geocoding_service.dart';
import 'services/route_distance_service.dart';
import 'services/sent_quotes_store.dart';
import 'services/sqflite_cadastro_store.dart';

/// Título do aplicativo, usado como identificação dele no sistema.
const String appTitle = 'Corridas Motorista';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await OrsApiKey.load();
  ForegroundTaskBackgroundService.initCommunicationPort();
  runApp(const CorridasDriverApp());
}

/// Raiz do aplicativo do motorista.
///
/// Compõe as dependências aqui, com injeção explícita: cada serviço recebe seu
/// armazenamento ou transporte, o que permite substituí-los por dublês nos
/// testes (decisão D5).
class CorridasDriverApp extends StatefulWidget {
  const CorridasDriverApp({
    super.key,
    this.keyStore,
    this.keyValueStore,
    this.gateway,
    this.relayConnection,
    this.cadastroStore,
    this.locationService,
    this.routeDistanceService,
    this.reverseGeocodingService,
    this.receiptStore,
  });

  /// Dependências injetáveis. Em produção ficam nulas e as implementações
  /// reais são usadas; nos testes recebem dublês, para que nenhum teste
  /// dependa de plugin de plataforma, de Keystore ou de rede (decisão D5).
  final KeyStore? keyStore;
  final KeyValueStore? keyValueStore;
  final RelayGateway? gateway;

  /// Conexão com os relays pronta, no lugar da composta aqui. Em produção
  /// (nem `gateway` nem esta) a conexão vive no serviço em segundo plano
  /// (feature 025); passar `gateway` ou esta mantém tudo no isolate da
  /// interface, como os testes precisam.
  final RelayConnection? relayConnection;

  /// Idem, para o cadastro do motorista — nenhum teste toca SQLite real
  /// (decisão D1 de `specs/003-cadastro-motorista/research.md`).
  final CadastroStore? cadastroStore;

  /// Idem, para a localização do motorista — nenhum teste toca sensor real
  /// (decisão D1 de `specs/004-mapa-status-motorista/research.md`).
  final LocationService? locationService;

  /// Idem, para o cálculo de distância de rota — nenhum teste toca a API
  /// real (decisão D1 de `specs/007-receber-solicitacao-corrida/research.md`).
  final RouteDistanceService? routeDistanceService;
  final ReverseGeocodingService? reverseGeocodingService;

  /// Idem, para os recibos de reputação (feature 026) — nenhum teste toca SQLite.
  final ReceiptStore? receiptStore;

  @override
  State<CorridasDriverApp> createState() => _CorridasDriverAppState();
}

class _CorridasDriverAppState extends State<CorridasDriverApp>
    with WidgetsBindingObserver {
  late final IdentityService _identityService = IdentityService(
    widget.keyStore ?? SecureKeyStore(),
  );
  late final RelayRepository _relayRepository = RelayRepository(
    widget.keyValueStore ?? PreferencesStore(),
  );

  /// Em produção a conexão com os relays vive no serviço em primeiro plano
  /// (feature 025) e a interface a vê por mensagens; com `gateway` ou
  /// `relayConnection` injetados (testes) ela fica aqui, no isolate da
  /// interface.
  late final bool _remoto =
      widget.relayConnection == null && widget.gateway == null;
  late final RelayGateway? _gateway = _remoto
      ? null
      : (widget.gateway ?? WsRelayGateway());
  late final BackgroundService? _backgroundService = _remoto
      ? ForegroundTaskBackgroundService(channel: UiMessageChannel())
      : null;

  /// Decide quando o serviço roda e o que ele sabe do app. Só existe quando a
  /// conexão vive no serviço.
  late final ServiceController? _serviceController = _remoto
      ? ServiceController(
          service: _backgroundService!,
          connection: _relayService as RemoteRelayConnection,
        )
      : null;

  late final RelayConnection _relayService =
      widget.relayConnection ??
      (_remoto
          ? RemoteRelayConnection(_backgroundService!.channel)
          : RelayService(
              _gateway!,
              subscriptionKinds: driverConsumedKinds.toList(),
            ));
  late final EventFeed _feed = EventFeed(
    incoming: _relayService.incoming,
    acceptedKinds: driverConsumedKinds,
    // Feature 027: o recorte geográfico do `20001` usa a cobertura que a tela
    // entrega à conexão ao ficar online.
    coverage: () => _relayService.coverage,
  );
  late final CadastroStore _cadastroStore =
      widget.cadastroStore ?? SqfliteCadastroStore();
  late final LocationService _locationService =
      widget.locationService ?? const GeolocatorLocationService();
  late final RouteDistanceService _routeDistanceService =
      widget.routeDistanceService ??
      FallbackRouteDistanceService(OrsRouteDistanceService());
  late final ReverseGeocodingService _reverseGeocodingService =
      widget.reverseGeocodingService ?? PhotonReverseGeocodingService();

  /// Mesmo `KeyValueStore` já usado por `RelayRepository` — os dois novos
  /// dados persistidos da feature 010 (D1/D6 de `research.md`) não
  /// justificam um parâmetro injetável próprio: testes que já injetam
  /// `keyValueStore` (via `CorridasDriverApp`) recebem estes dois dublês
  /// automaticamente, sobre o mesmo armazenamento em memória.
  late final RideStateStore _rideStateStore = PreferencesRideStateStore(
    widget.keyValueStore ?? PreferencesStore(),
  );
  late final SentQuotesStore _sentQuotesStore = PreferencesSentQuotesStore(
    widget.keyValueStore ?? PreferencesStore(),
  );
  final RideRatingStore _rideRatingStore = SqfliteRideRatingStore();
  late final ReceiptStore _receiptStore =
      widget.receiptStore ?? SqfliteReceiptStore();
  late final ReceiptService _receiptService = ReceiptService(
    store: _receiptStore,
    identityService: _identityService,
    identity: () => _identity,
    publish: (signed) async {
      final resultados = await _relayService
          .publish(signed.event, payload: signed.payload)
          .toList();
      return resultados.any((r) => r.accepted);
    },
  );

  Identity? _identity;
  String? _startupError;

  /// Cadastro do motorista, ou `null` se ainda não foi preenchido. É a
  /// ausência dele — não a mera existência do widget — que decide se o
  /// formulário aparece (FR-001).
  DriverProfile? _driverProfile;

  /// Etapas do cadastro já salvas — é dela que o wizard sabe em que etapa
  /// abrir (retomada depois de fechar o aplicativo no meio).
  CadastroProgress _progress = const CadastroProgress.empty();

  /// Falso enquanto o resultado de [CadastroStore.load] ainda não chegou: o
  /// aplicativo não pode decidir entre o formulário e a tela principal sem
  /// saber se há cadastro (evita o "flash" de uma tela errada por um
  /// instante).
  bool _cadastroCarregado = false;

  /// Informa ao serviço (feature 025) se o app está visível: com a tela à vista
  /// a solicitação abre a modal; sem ela, vira notificação. `inactive` fica de
  /// fora de propósito — é o que o Android dispara com um diálogo de permissão
  /// por cima, e o app continua visível.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controlador = _serviceController;
    if (controlador == null) return;
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(controlador.onForeground(true));
      case AppLifecycleState.paused ||
          AppLifecycleState.hidden ||
          AppLifecycleState.detached:
        unawaited(controlador.onForeground(false));
      case AppLifecycleState.inactive:
        break;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _relayService.statusChanges.listen((_) {
      _refresh();
      // 1.7 passo 5: a cada reconexão de relay, reenvia os recibos pendentes.
      if (_relayService.hasConnectedRelay) {
        unawaited(_receiptService.retryPending());
      }
    });
    _feed.changes.listen((_) {
      _refresh();
    });
    _bootstrap();
    _carregarCadastro();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _receiptService.dispose();
    unawaited(_serviceController?.dispose());
    _feed.dispose();
    _relayService.dispose();
    _backgroundService?.channel.close();
    final gateway = _gateway;
    if (gateway is WsRelayGateway) gateway.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _bootstrap() async {
    try {
      _identity = await _identityService.loadOrCreate();
    } on KeyStoreUnavailable catch (error) {
      _startupError =
          'Não foi possível acessar o armazenamento protegido do '
          'aparelho: $error';
    } on CorruptedIdentityStorage catch (error) {
      _startupError = 'A identidade guardada está inválida: $error';
    }

    // Recibos pendentes (feature 026, 1.7 passo 5): reenvia ao abrir o app e a
    // cada 60 s enquanto a interface existir. Sem identidade não faz nada.
    _receiptService.start();
    unawaited(_receiptService.retryPending());

    try {
      // O serviço conecta sozinho à lista persistida; a interface só o inicia
      // e se apresenta a ele.
      await _serviceController?.start();
      final relays = await _relayRepository.load();
      await _relayService.connectAll(relays);
      _relayService.enableAutoRetry();
    } catch (error) {
      if (mounted) {
        setState(() {
          _startupError ??= 'Falha ao carregar a lista de relays: $error';
        });
      }
    }
  }

  /// Carrega o cadastro do motorista, se houver, para decidir entre o
  /// formulário e a tela principal (FR-001). Roda em paralelo com
  /// [_bootstrap]: identidade e relays não dependem do cadastro existir.
  Future<void> _carregarCadastro() async {
    try {
      _progress = await _cadastroStore.loadProgress();
      _driverProfile = _progress.toProfile();
    } on CorruptedDriverProfile {
      // FR-010: tratado como ausência de cadastro, nunca como erro visível
      // — ao contrário da identidade Nostr (Princípio I), este dado não é
      // segredo irrecuperável.
      _progress = const CadastroProgress.empty();
      _driverProfile = null;
    } catch (error) {
      if (mounted) {
        setState(() {
          _startupError ??= 'Falha ao carregar o cadastro do motorista: $error';
        });
      }
    }
    if (mounted) setState(() => _cadastroCarregado = true);
  }

  /// Grava uma etapa do cadastro e atualiza o progresso. Devolve `null` em
  /// sucesso, ou uma mensagem de erro sem perder o que foi digitado (FR-006,
  /// FR-007, FR-008). Quando a terceira etapa completa o cadastro,
  /// [_driverProfile] passa a existir e a tela principal substitui o wizard.
  Future<String?> _salvarEtapa(
    Future<void> Function() gravar,
    CadastroProgress Function(CadastroProgress) aplicar,
  ) async {
    try {
      await gravar();
    } on CadastroStoreUnavailable catch (error) {
      return 'Não foi possível salvar o cadastro: $error';
    }
    if (mounted) {
      setState(() {
        _progress = aplicar(_progress);
        _driverProfile = _progress.toProfile();
      });
    }
    return null;
  }

  Future<String?> _salvarDadosPessoais(DriverPersonalData data) => _salvarEtapa(
    () => _cadastroStore.savePersonal(data),
    (p) => p.copyWith(personal: data),
  );

  Future<String?> _salvarVeiculo(DriverVehicleData data) => _salvarEtapa(
    () => _cadastroStore.saveVehicle(data),
    (p) => p.copyWith(vehicle: data),
  );

  Future<String?> _salvarFinanceiro(DriverFinancialData data) => _salvarEtapa(
    () => _cadastroStore.saveFinancial(data),
    (p) => p.copyWith(financial: data),
  );

  Future<String?> _addRelay(String url) async {
    try {
      final atualizada = await _relayRepository.add(url, _relayService.relays);
      await _relayService.addRelay(atualizada.last.url);
      return null;
    } on InvalidRelayUrl {
      return 'Endereço inválido. Use wss:// ou ws:// com um domínio válido.';
    } on DuplicateRelayUrl {
      return 'Este relay já está na lista.';
    }
  }

  Future<void> _removeRelay(String url) async {
    await _relayRepository.remove(url, _relayService.relays);
    await _relayService.removeRelay(url);
  }

  Future<void> _restoreDefaults() async {
    final padrao = await _relayRepository.restoreDefaults();
    await _relayService.connectAll(padrao);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: appTitle,
      themeMode: ThemeMode.system,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ),
      ),
      home: !_cadastroCarregado
          ? const _CarregandoCadastro()
          : _driverProfile == null
          ? CadastroScreen(
              initial: _progress,
              onSavePersonal: _salvarDadosPessoais,
              onSaveVehicle: _salvarVeiculo,
              onSaveFinancial: _salvarFinanceiro,
            )
          : _Shell(
              identity: _identity,
              driverProfile: _driverProfile,
              startupError: _startupError,
              onAddRelay: _addRelay,
              onRemoveRelay: _removeRelay,
              onRestoreDefaults: _restoreDefaults,
              progress: _progress,
              onSavePersonal: _salvarDadosPessoais,
              onSaveVehicle: _salvarVeiculo,
              onSaveFinancial: _salvarFinanceiro,
              locationService: _locationService,
              eventFeed: _feed,
              cadastroStore: _cadastroStore,
              routeDistanceService: _routeDistanceService,
              reverseGeocodingService: _reverseGeocodingService,
              identityService: _identityService,
              relayService: _relayService,
              serviceController: _serviceController,
              rideStateStore: _rideStateStore,
              sentQuotesStore: _sentQuotesStore,
              rideRatingStore: _rideRatingStore,
              receiptStore: _receiptStore,
              receiptService: _receiptService,
            ),
    );
  }
}

/// Tela mínima exibida só pelo instante entre abrir o aplicativo e saber se
/// há cadastro salvo — evita alternar de tela assim que a resposta chega.
class _CarregandoCadastro extends StatelessWidget {
  const _CarregandoCadastro();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

/// Casca com a navegação entre o mapa (tela inicial) e a tela "Mais".
class _Shell extends StatefulWidget {
  const _Shell({
    required this.identity,
    required this.driverProfile,
    required this.startupError,
    required this.onAddRelay,
    required this.onRemoveRelay,
    required this.onRestoreDefaults,
    required this.progress,
    required this.onSavePersonal,
    required this.onSaveVehicle,
    required this.onSaveFinancial,
    required this.locationService,
    required this.eventFeed,
    required this.cadastroStore,
    required this.routeDistanceService,
    required this.reverseGeocodingService,
    required this.identityService,
    required this.relayService,
    required this.serviceController,
    required this.rideStateStore,
    required this.sentQuotesStore,
    required this.rideRatingStore,
    required this.receiptStore,
    required this.receiptService,
  });

  final Identity? identity;
  final LocationService locationService;
  final EventFeed eventFeed;
  final CadastroStore cadastroStore;
  final RouteDistanceService routeDistanceService;
  final ReverseGeocodingService reverseGeocodingService;
  final IdentityService identityService;
  final RelayConnection relayService;
  final ServiceController? serviceController;
  final RideStateStore rideStateStore;
  final SentQuotesStore sentQuotesStore;
  final RideRatingStore rideRatingStore;
  final ReceiptStore receiptStore;
  final ReceiptService receiptService;

  /// Sempre não nulo aqui: o `_Shell` só é exibido depois que FR-001 decidiu
  /// que o cadastro existe. Mesmo assim é passado, e não lido de um estado
  /// global, para que a tela de edição (US3) sempre mostre o valor corrente.
  final DriverProfile? driverProfile;
  final String? startupError;
  final Future<String?> Function(String url) onAddRelay;
  final Future<void> Function(String url) onRemoveRelay;
  final Future<void> Function() onRestoreDefaults;
  final CadastroProgress progress;
  final Future<String?> Function(DriverPersonalData data) onSavePersonal;
  final Future<String?> Function(DriverVehicleData data) onSaveVehicle;
  final Future<String?> Function(DriverFinancialData data) onSaveFinancial;

  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final erro = widget.startupError;

    final telas = [
      MapScreen(
        locationService: widget.locationService,
        eventFeed: widget.eventFeed,
        cadastroStore: widget.cadastroStore,
        routeDistanceService: widget.routeDistanceService,
        reverseGeocodingService: widget.reverseGeocodingService,
        identity: widget.identity,
        identityService: widget.identityService,
        relayService: widget.relayService,
        serviceController: widget.serviceController,
        rideStateStore: widget.rideStateStore,
        sentQuotesStore: widget.sentQuotesStore,
        rideRatingStore: widget.rideRatingStore,
        receiptStore: widget.receiptStore,
        receiptService: widget.receiptService,
        driverProfile: widget.driverProfile,
      ),
      MoreScreen(
        relayService: widget.relayService,
        identity: widget.identity,
        progress: widget.progress,
        onAddRelay: widget.onAddRelay,
        onRemoveRelay: widget.onRemoveRelay,
        onRestoreDefaults: widget.onRestoreDefaults,
        onSavePersonal: widget.onSavePersonal,
        onSaveVehicle: widget.onSaveVehicle,
        onSaveFinancial: widget.onSaveFinancial,
      ),
    ];

    return Scaffold(
      body: erro != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(erro, textAlign: TextAlign.center),
              ),
            )
          // IndexedStack, não `telas[_index]`: mantém as duas telas
          // montadas o tempo todo, para que trocar de aba não desmonte e
          // remonte MapScreen — descartando o status online/offline, a
          // corrida em andamento e a deduplicação de eventos já tratados
          // (achado da investigação de 22/09/2026, sessão de teste manual
          // em aparelho).
          : IndexedStack(index: _index, children: telas),
      bottomNavigationBar: NavigationBarTheme(
        // Identidade visual (constituição 2.6.0): barra `fundo-profundo`,
        // destino selecionado em pílula `roxo`, demais em branco a 70%.
        data: NavigationBarThemeData(
          backgroundColor: IdentidadeVisual.fundoProfundo,
          indicatorColor: IdentidadeVisual.roxo,
          height: 68,
          iconTheme: WidgetStateProperty.resolveWith(
            (estados) => IconThemeData(
              color: estados.contains(WidgetState.selected)
                  ? Colors.white
                  : const Color(0xB3FFFFFF),
            ),
          ),
          labelTextStyle: WidgetStateProperty.resolveWith(
            (estados) => TextStyle(
              fontSize: 11,
              fontWeight: estados.contains(WidgetState.selected)
                  ? FontWeight.w700
                  : FontWeight.w500,
              color: estados.contains(WidgetState.selected)
                  ? Colors.white
                  : const Color(0xB3FFFFFF),
            ),
          ),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.grid_view_rounded),
              label: 'Mapa',
            ),
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              label: 'Mais',
            ),
          ],
        ),
      ),
    );
  }
}
