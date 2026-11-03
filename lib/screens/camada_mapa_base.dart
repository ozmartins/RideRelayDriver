
import 'package:flutter/material.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

import '../services/flow_log.dart';

/// Camada de base do mapa: tiles vetoriais do OpenFreeMap (estilo `positron`,
/// claro e neutro), tingidos com o lilás `mapa-base` da identidade visual.
///
/// O estilo é lido uma única vez ao montar. Enquanto não chega — ou se a
/// leitura falhar — o mapa mostra só o fundo `mapa-base`, sem tile algum:
/// não há segundo provedor de reserva (exceção da constituição 2.13.0 cobre um
/// único serviço de tiles). Os marcadores e a rota, camadas acima desta,
/// continuam funcionando.
class CamadaMapaBase extends StatefulWidget {
  const CamadaMapaBase({super.key, this.log = const NoFlowLog()});

  /// Log do fluxo (feature 029): falha ao ler o estilo do OpenFreeMap.
  final FlowLog log;

  static const estiloUrl = 'https://tiles.openfreemap.org/styles/positron';

  /// Multiplicador lilás aplicado aos tiles (tom `mapa-base`).
  static const tinta = Color(0xFFEDE8F7);

  @override
  State<CamadaMapaBase> createState() => _CamadaMapaBaseState();
}

class _CamadaMapaBaseState extends State<CamadaMapaBase> {
  Style? _estilo;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final log = widget.log;
      final lido = await log.chamadaExterna(
        'openfreemap',
        'estilo',
        () => StyleReader(uri: CamadaMapaBase.estiloUrl).read(),
      );
      // Os tiles não são registrados (volume alto); só o estilo e o atlas de ícones.
      final sprites = lido.sprites;
      final estilo = Style(
        name: lido.name,
        theme: lido.theme,
        center: lido.center,
        zoom: lido.zoom,
        providers: lido.providers,
        sprites: sprites == null
            ? null
            : SpriteStyle(
                index: sprites.index,
                atlasProvider: () => log.chamadaExterna(
                  'openfreemap',
                  'sprite',
                  sprites.atlasProvider,
                  tamanho: (bytes) => bytes.length,
                ),
              ),
      );
      if (mounted) setState(() => _estilo = estilo);
    } catch (_) {
      // Já registrado por `chamadaExterna`. Sem estilo, o mapa fica só com o fundo; nada a informar ao usuário
      // além do que a própria ausência de tiles já mostra.
    }
  }

  @override
  Widget build(BuildContext context) {
    final estilo = _estilo;
    if (estilo == null) return const SizedBox.shrink();
    return ColorFiltered(
      colorFilter: const ColorFilter.mode(
        CamadaMapaBase.tinta,
        BlendMode.modulate,
      ),
      child: VectorTileLayer(
        theme: estilo.theme,
        sprites: estilo.sprites,
        tileProviders: estilo.providers,
      ),
    );
  }
}
