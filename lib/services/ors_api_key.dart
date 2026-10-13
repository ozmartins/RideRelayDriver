import 'package:flutter/services.dart';

/// Chave de API do openrouteservice (feature de rotas).
///
/// Lida do arquivo de configuração `assets/ors_api_key.txt`, embutido no app
/// (decisão do autor: protótipo acadêmico, chave sem sigilo). Um
/// `--dart-define=ORS_API_KEY=...` no build tem precedência sobre o arquivo.
/// Arquivo ausente ou vazio deixa a chave vazia, e a rota cai no fallback.
class OrsApiKey {
  const OrsApiKey._();

  static const _definida = String.fromEnvironment('ORS_API_KEY');
  static var _doArquivo = '';

  /// Carrega o arquivo de configuração; chamar uma vez antes de `runApp`.
  static Future<void> load([AssetBundle? bundle]) async {
    try {
      _doArquivo = (await (bundle ?? rootBundle).loadString(
        'assets/ors_api_key.txt',
      )).trim();
    } on Object {
      _doArquivo = '';
    }
  }

  static String get value => _definida.isNotEmpty ? _definida : _doArquivo;
}
