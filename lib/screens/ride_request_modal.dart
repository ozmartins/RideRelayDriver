import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../domain/driver_profile.dart';
import '../domain/ride_quote.dart';
import '../domain/ride_request_received.dart';
import '../services/reverse_geocoding_service.dart';
import '../services/route_distance_service.dart';
import 'identidade_visual.dart';

/// Modal exibida quando o motorista, online, recebe uma solicitação de
/// carona (feature 007).
///
/// Widget apresentacional (como `CadastroScreen`): [onSendQuote] devolve uma
/// mensagem de erro em caso de falha (nenhum relay conectado) ou `null` em
/// caso de sucesso — e é responsabilidade de quem a chama fechar a modal
/// (`Navigator.pop`) nesses dois casos, não deste widget (FR-013, FR-014).
/// Isso mantém a modal testável sem depender de rotas.
class RideRequestModal extends StatefulWidget {
  const RideRequestModal({
    super.key,
    required this.request,
    required this.driverPosition,
    required this.driverProfile,
    required this.routeDistanceService,
    required this.reverseGeocodingService,
    required this.onSendQuote,
    required this.onReject,
  });

  final RideRequestReceived request;
  final LatLng driverPosition;

  /// Cadastro do motorista — fonte do preço padrão (feature 006), nome e
  /// dados do veículo (feature 009) incluídos no orçamento. Editar o preço
  /// nesta modal MUST NOT alterá-lo (FR-007 da feature 007).
  final DriverProfile driverProfile;

  final RouteDistanceService routeDistanceService;

  /// Endereço legível de origem e destino (feature 015). Falha ou demora não
  /// bloqueia nada: a modal continua mostrando latitude e longitude.
  final ReverseGeocodingService reverseGeocodingService;

  /// Publica o orçamento; devolve a mensagem a exibir em caso de falha, ou
  /// `null` em caso de sucesso (FR-011, FR-012, FR-013).
  final Future<String?> Function(RideQuote quote) onSendQuote;

  /// Chamado ao tocar em "Recusar corrida" — nenhum evento é publicado
  /// (FR-014).
  final VoidCallback onReject;

  @override
  State<RideRequestModal> createState() => _RideRequestModalState();
}

class _RideRequestModalState extends State<RideRequestModal> {
  late final TextEditingController _preco;

  double? _distanciaAteOrigemMetros;
  int? _etaAteOrigemMinutos;
  var _falhaDistanciaAteOrigem = false;
  var _aproximadaAteOrigem = false;

  double? _distanciaTrajetoMetros;
  var _falhaDistanciaTrajeto = false;
  var _aproximadaTrajeto = false;

  String? _enderecoOrigem;
  String? _enderecoDestino;
  var _falhaEnderecoOrigem = false;
  var _falhaEnderecoDestino = false;

  var _enviando = false;
  String? _erroEnvio;

  @override
  void initState() {
    super.initState();
    _preco = TextEditingController(
      text: widget.driverProfile.precoPorKm
          .toStringAsFixed(2)
          .replaceAll('.', ','),
    )..addListener(() => setState(() {}));
    _calcularDistancias();
    unawaited(_buscarEnderecos());
  }

  @override
  void dispose() {
    _preco.dispose();
    super.dispose();
  }

  Future<void> _calcularDistancias() async {
    unawaited(
      widget.routeDistanceService
          .estimate(
            origin: widget.driverPosition,
            destination: widget.request.origin,
          )
          .then(
            (estimativa) {
              if (!mounted) return;
              setState(() {
                _distanciaAteOrigemMetros = estimativa.distanceMeters;
                // D1 de specs/009-detalhes-do-orcamento/research.md: mesma
                // chamada, sem requisição extra.
                _aproximadaAteOrigem = estimativa.approximate;
                final duracao = estimativa.durationSeconds;
                _etaAteOrigemMinutos = duracao == null
                    ? null
                    : (duracao / 60).round();
              });
            },
            onError: (Object erro) {
              debugPrint('Distância motorista→origem falhou: $erro');
              if (!mounted) return;
              setState(() => _falhaDistanciaAteOrigem = true);
            },
          ),
    );

    unawaited(
      widget.routeDistanceService
          .estimate(
            origin: widget.request.origin,
            destination: widget.request.destination,
          )
          .then(
            (estimativa) {
              if (!mounted) return;
              setState(() {
                _distanciaTrajetoMetros = estimativa.distanceMeters;
                _aproximadaTrajeto = estimativa.approximate;
              });
            },
            onError: (Object erro) {
              debugPrint('Distância origem→destino falhou: $erro');
              if (!mounted) return;
              setState(() => _falhaDistanciaTrajeto = true);
            },
          ),
    );
  }

  /// Origem e destino em sequência, não em paralelo: a Photon pública limita
  /// a taxa, e a rajada de duas consultas deixava o destino sem endereço.
  Future<void> _buscarEnderecos() async {
    try {
      final endereco = await widget.reverseGeocodingService.addressOf(
        widget.request.origin,
      );
      if (!mounted) return;
      setState(() => _enderecoOrigem = endereco);
    } on Object catch (erro) {
      debugPrint('Endereço da origem falhou: $erro');
      if (!mounted) return;
      setState(() => _falhaEnderecoOrigem = true);
    }
    try {
      final endereco = await widget.reverseGeocodingService.addressOf(
        widget.request.destination,
      );
      if (!mounted) return;
      setState(() => _enderecoDestino = endereco);
    } on Object catch (erro) {
      debugPrint('Endereço do destino falhou: $erro');
      if (!mounted) return;
      setState(() => _falhaEnderecoDestino = true);
    }
  }

  static String _coordenadas(LatLng p) =>
      '${p.latitude.toStringAsFixed(4)}, ${p.longitude.toStringAsFixed(4)}';

  static String _enderecoOuFallback(
    String? endereco,
    bool falhou,
    LatLng ponto,
  ) {
    if (endereco != null) return endereco;
    return falhou ? _coordenadas(ponto) : 'buscando endereço…';
  }

  double? get _precoValido => DriverProfile.parsePrecoPorKm(_preco.text);

  double? get _total {
    final trajeto = _distanciaTrajetoMetros;
    final preco = _precoValido;
    if (trajeto == null || preco == null) return null;
    return preco * trajeto / 1000;
  }

  Future<void> _enviarOrcamento() async {
    final preco = _precoValido;
    if (preco == null || _enviando) return;

    final trajeto = _distanciaTrajetoMetros;
    if (trajeto == null) {
      setState(
        () => _erroEnvio =
            'A distância da corrida ainda não foi calculada. Tente de novo '
            'em instantes.',
      );
      return;
    }

    setState(() {
      _enviando = true;
      _erroEnvio = null;
    });
    final erro = await widget.onSendQuote(
      RideQuote(
        requestId: widget.request.requestId,
        passengerPubkey: widget.request.passengerPubkey,
        pricePerKm: preco,
        total: preco * trajeto / 1000,
        driverName: widget.driverProfile.nome,
        carBrand: widget.driverProfile.marcaVeiculo,
        carModel: widget.driverProfile.modeloVeiculo,
        carYear: widget.driverProfile.anoVeiculo,
        etaMinutes: _etaAteOrigemMinutos,
      ),
    );
    if (!mounted) return;
    setState(() {
      _enviando = false;
      _erroEnvio = erro;
    });
  }

  @override
  Widget build(BuildContext context) {
    final total = _total;
    return ModalTematizado(
      titulo: 'Solicitação de carona',
      conteudo: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _Linha(
              'Origem',
              _enderecoOuFallback(
                _enderecoOrigem,
                _falhaEnderecoOrigem,
                widget.request.origin,
              ),
            ),
            _Linha(
              'Destino',
              _enderecoOuFallback(
                _enderecoDestino,
                _falhaEnderecoDestino,
                widget.request.destination,
              ),
            ),
            _Linha(
              'Distância até a origem',
              _formatarDistancia(
                _distanciaAteOrigemMetros,
                _falhaDistanciaAteOrigem,
                _aproximadaAteOrigem,
              ),
            ),
            _Linha(
              'Distância da corrida',
              _formatarDistancia(
                _distanciaTrajetoMetros,
                _falhaDistanciaTrajeto,
                _aproximadaTrajeto,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _preco,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              style: IdentidadeVisual.estiloValor,
              decoration: decoracaoCampo(
                rotulo: 'Preço por quilômetro (só para esta corrida)',
                erro: _preco.text.isEmpty || _precoValido != null
                    ? null
                    : 'Informe um preço válido, maior que zero',
              ),
            ),
            const SizedBox(height: 8),
            _Linha(
              'Total',
              total == null ? '—' : 'R\$ ${total.toStringAsFixed(2)}',
            ),
            if (_erroEnvio != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _erroEnvio!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      acoes: [
        TextButton(
          style: IdentidadeVisual.estiloAcaoSecundaria,
          onPressed: _enviando ? null : widget.onReject,
          child: const Text('Recusar corrida'),
        ),
        FilledButton(
          style: IdentidadeVisual.estiloAcaoPrimaria(altura: 48)
              .copyWith(minimumSize: const WidgetStatePropertyAll(Size(0, 48))),
          onPressed: (_precoValido == null || _enviando)
              ? null
              : _enviarOrcamento,
          child: _enviando
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Enviar orçamento'),
        ),
      ],
    );
  }

  static String _formatarDistancia(
    double? metros,
    bool falhou,
    bool aproximada,
  ) {
    if (falhou) return 'não calculada';
    if (metros == null) return 'calculando…';
    final texto = metros < 1000
        ? '${metros.round()} m'
        : '${(metros / 1000).toStringAsFixed(1)} km';
    return aproximada ? '≈ $texto (linha reta)' : texto;
  }
}

class _Linha extends StatelessWidget {
  const _Linha(this.rotulo, this.valor);

  final String rotulo;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(
            '$rotulo: ',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: IdentidadeVisual.texto,
            ),
          ),
          Expanded(child: Text(valor)),
        ],
      ),
    );
  }
}
