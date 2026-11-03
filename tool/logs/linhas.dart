import 'dart:convert';
import 'dart:io';

/// Uma linha do log do fluxo (`specs/029-.../contracts/logs.md`).
class Linha {
  const Linha({
    required this.t,
    required this.papel,
    required this.exec,
    required this.iso,
    required this.comp,
    required this.op,
    required this.res,
    this.kind,
    this.id,
    this.relay,
    this.guid,
    this.motivo,
    this.ext,
    this.n,
    this.ms,
  });

  final int t;
  final String papel, exec, iso, comp, op, res;
  final int? kind, n, ms;
  final String? id, relay, guid, motivo, ext;

  /// `null` se a linha não tem a forma do contrato (nunca lança).
  static Linha? tentar(String texto) {
    try {
      final j = jsonDecode(texto);
      if (j is! Map) return null;
      final t = j['t'];
      String? s(String k) => j[k] is String ? j[k] as String : null;
      final papel = s('papel'), op = s('op'), res = s('res');
      if (t is! int || papel == null || op == null || res == null) return null;
      return Linha(
        t: t,
        papel: papel,
        exec: s('exec') ?? '',
        iso: s('iso') ?? '',
        comp: s('comp') ?? '',
        op: op,
        res: res,
        kind: j['kind'] is int ? j['kind'] as int : null,
        id: s('id'),
        relay: s('relay'),
        guid: s('guid'),
        motivo: s('motivo'),
        ext: s('ext'),
        n: j['n'] is int ? j['n'] as int : null,
        ms: j['ms'] is int ? j['ms'] as int : null,
      );
    } on FormatException {
      return null;
    }
  }
}

/// Linhas lidas de uma pasta e o que foi ignorado.
class LeituraLog {
  LeituraLog(this.linhas, this.invalidas, this.arquivos);
  final List<Linha> linhas;
  final int invalidas;
  final int arquivos;
}

LeituraLog lerTexto(Iterable<String> textos) {
  final linhas = <Linha>[];
  var invalidas = 0;
  for (final texto in textos) {
    if (texto.trim().isEmpty) continue;
    final l = Linha.tentar(texto);
    l == null ? invalidas++ : linhas.add(l);
  }
  linhas.sort((a, b) => a.t.compareTo(b.t));
  return LeituraLog(linhas, invalidas, 1);
}

/// Lê todos os `fluxo-*.jsonl` e `fluxo-*.jsonl.1` de [pasta].
LeituraLog lerPasta(Directory pasta) {
  final arquivos = [
    for (final f in pasta.listSync().whereType<File>())
      if (RegExp(r'fluxo-.*\.jsonl(\.1)?$').hasMatch(f.path)) f,
  ];
  final textos = [for (final f in arquivos) ...f.readAsLinesSync()];
  final r = lerTexto(textos);
  return LeituraLog(r.linhas, r.invalidas, arquivos.length);
}
