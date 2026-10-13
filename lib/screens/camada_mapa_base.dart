import 'package:flutter/material.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

/// Camada de base do mapa: tiles vetoriais do OpenFreeMap (estilo `positron`,
/// claro e neutro), tingidos com o lilás `mapa-base` da identidade visual.
///
/// O estilo é lido uma única vez ao montar. Enquanto não chega — ou se a
/// leitura falhar — o mapa mostra só o fundo `mapa-base`, sem tile algum:
/// não há segundo provedor de reserva (exceção da constituição 2.13.0 cobre um
/// único serviço de tiles). Os marcadores e a rota, camadas acima desta,
/// continuam funcionando.
class CamadaMapaBase extends StatefulWidget {
  const CamadaMapaBase({super.key});

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
      final estilo = await StyleReader(uri: CamadaMapaBase.estiloUrl).read();
      if (mounted) setState(() => _estilo = estilo);
    } catch (_) {
      // Sem estilo, o mapa fica só com o fundo; nada a informar ao usuário
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
