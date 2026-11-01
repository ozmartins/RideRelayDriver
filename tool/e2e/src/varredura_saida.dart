import 'dart:convert';
import 'dart:io';

/// Verificação automática de padrões proibidos nos arquivos de saída (FR-029,
/// D11). Hex de 64 caracteres identifica tanto uma chave privada quanto um id
/// de evento ou uma chave pública, então só passa o que estiver na lista de
/// permitidos (ids observados e chaves públicas dos períodos).

class Achado {
  const Achado(this.arquivo, this.padrao);

  /// Caminho relativo à raiz varrida.
  final String arquivo;

  /// Nome do padrão. O valor encontrado **nunca** é guardado nem impresso.
  final String padrao;

  @override
  String toString() => '$arquivo: $padrao';
}

const _extensoesDeTexto = {
  '.json',
  '.jsonl',
  '.md',
  '.csv',
  '.xml',
  '.log',
  '.txt',
};

final _nsec = RegExp(r'nsec1[a-z0-9]{20,}', caseSensitive: false);
final _hex128 = RegExp(r'(?<![0-9a-fA-F])[0-9a-fA-F]{128}(?![0-9a-fA-F])');
final _hex64 = RegExp(r'(?<![0-9a-fA-F])[0-9a-fA-F]{64}(?![0-9a-fA-F])');
final _campoContent = RegExp(r'"content"\s*:');

/// Lê a chave do openrouteservice de [ambiente] (`ORS_API_KEY`) ou do arquivo
/// local ignorado pelo Git. Nunca imprime. `null` se não houver.
String? lerChaveOrs({
  Map<String, String>? ambiente,
  String caminhoArquivo = 'assets/ors_api_key.txt',
}) {
  final env = (ambiente ?? Platform.environment)['ORS_API_KEY'];
  if (env != null && env.trim().isNotEmpty) return env.trim();
  final arquivo = File(caminhoArquivo);
  if (arquivo.existsSync()) {
    final texto = arquivo.readAsStringSync().trim();
    if (texto.isNotEmpty) return texto;
  }
  return null;
}

/// Ids de evento e chaves públicas permitidos, colhidos dos `eventos.jsonl` e
/// `checkpoint.json` sob [raiz].
Set<String> colherPermitidos(Directory raiz) {
  final permitidos = <String>{};
  if (!raiz.existsSync()) return permitidos;
  for (final entidade in raiz.listSync(recursive: true)) {
    if (entidade is! File) continue;
    final nome = entidade.uri.pathSegments.last;
    try {
      if (nome == 'eventos.jsonl') {
        for (final linha in entidade.readAsLinesSync()) {
          if (linha.trim().isEmpty) continue;
          final id = (jsonDecode(linha) as Map)['id'];
          if (id is String) permitidos.add(id.toLowerCase());
        }
      } else if (nome == 'checkpoint.json') {
        final ids =
            (jsonDecode(entidade.readAsStringSync()) as Map)['identidades'];
        if (ids is Map) {
          for (final v in ids.values) {
            if (v is String && v.isNotEmpty) permitidos.add(v.toLowerCase());
          }
        }
      }
    } on FormatException {
      // arquivo ilegível: a varredura dele segue sem permitidos adicionais
    }
  }
  return permitidos;
}

/// Varre todos os arquivos de texto sob [raiz]. [chaveOrs], se houver, reprova
/// ao aparecer como substring.
List<Achado> varrerSaida(
  Directory raiz, {
  String? chaveOrs,
  Set<String> permitidosExtras = const {},
}) {
  final achados = <Achado>[];
  if (!raiz.existsSync()) return achados;
  final permitidos = {...colherPermitidos(raiz), ...permitidosExtras};
  for (final entidade in raiz.listSync(recursive: true)) {
    if (entidade is! File) continue;
    final caminho = entidade.path;
    final ponto = caminho.lastIndexOf('.');
    if (ponto < 0 || !_extensoesDeTexto.contains(caminho.substring(ponto))) {
      continue;
    }
    final relativo = caminho.startsWith(raiz.path)
        ? caminho
              .substring(raiz.path.length)
              .replaceFirst(RegExp(r'^[/\\]'), '')
        : caminho;
    final String texto;
    try {
      texto = entidade.readAsStringSync();
    } on FileSystemException {
      achados.add(Achado(relativo, 'arquivo ilegível'));
      continue;
    }
    if (_nsec.hasMatch(texto)) achados.add(Achado(relativo, 'nsec'));
    if (_hex128.hasMatch(texto)) {
      achados.add(Achado(relativo, 'hex de 128 caracteres'));
    }
    if (_campoContent.hasMatch(texto)) {
      achados.add(Achado(relativo, 'campo "content"'));
    }
    if (_hex64
        .allMatches(texto)
        .any((m) => !permitidos.contains(m.group(0)!.toLowerCase()))) {
      achados.add(
        Achado(relativo, 'hex de 64 caracteres fora da lista de permitidos'),
      );
    }
    if (chaveOrs != null && chaveOrs.length >= 8 && texto.contains(chaveOrs)) {
      achados.add(Achado(relativo, 'chave do openrouteservice'));
    }
  }
  return achados;
}
