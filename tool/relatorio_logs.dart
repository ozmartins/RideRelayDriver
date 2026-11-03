// Gera o relatório do TCC a partir dos logs dos dois aplicativos.
//
//   dart run tool/relatorio_logs.dart --motorista DIR [--passageiro DIR]
//       [--exec ID] [--meta 60] [--saida DIR]
//
// DIR contém os `fluxo-*.jsonl` extraídos do aparelho (adb run-as ... cat).
import 'dart:io';

import 'logs/analise.dart';
import 'logs/linhas.dart';
import 'logs/relatorio_logs.dart';

void main(List<String> args) {
  String? valor(String nome) {
    final i = args.indexOf(nome);
    return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
  }

  final mot = valor('--motorista');
  if (mot == null) {
    stderr.writeln(
      'uso: dart run tool/relatorio_logs.dart --motorista DIR '
      '[--passageiro DIR] [--exec ID] [--meta 60] [--saida DIR]',
    );
    exit(64);
  }
  final pax = valor('--passageiro');
  final exec = valor('--exec');
  final meta = int.tryParse(valor('--meta') ?? '') ?? 60;
  final saida = Directory(valor('--saida') ?? 'e2e_saida/logs');

  LeituraLog ler(String caminho) {
    final d = Directory(caminho);
    if (!d.existsSync()) {
      stderr.writeln('pasta inexistente: $caminho');
      exit(66);
    }
    return lerPasta(d);
  }

  List<Linha> filtra(List<Linha> ls) => exec == null
      ? ls
      : [
          for (final l in ls)
            if (l.exec == exec) l,
        ];

  final m = ler(mot);
  final p = pax == null ? null : ler(pax);
  final analise = analisar(filtra(m.linhas), filtra(p?.linhas ?? const []));
  final r = gerarRelatorioLogs(
    analise,
    meta: meta,
    linhasInvalidas: m.invalidas + (p?.invalidas ?? 0),
  );

  final dados = Directory('${saida.path}/dados')..createSync(recursive: true);
  File('${saida.path}/relatorio.md').writeAsStringSync(r.markdown);
  r.csvs.forEach(
    (nome, conteudo) => File('${dados.path}/$nome').writeAsStringSync(conteudo),
  );
  stdout.writeln('Relatório em ${saida.path}/relatorio.md');
}
