// Teste E2E automatizado do fluxo completo da corrida (feature 029).
//
// Roteiro de linha de comando que opera os dois emuladores por ADB e gera as
// evidências do TCC. Contrato: specs/029-teste-e2e-fluxo-corrida/contracts/cli.md.
//
// ignore_for_file: avoid_print — é uma ferramenta de linha de comando, em que a
// saída padrão é a própria interface; não faz parte do aplicativo.
//
// Uso:
//   dart run tool/e2e/e2e.dart --periodo 1
//   dart run tool/e2e/e2e.dart --periodo 1 --retomar
//   dart run tool/e2e/e2e.dart --relatorio
//   dart run tool/e2e/e2e.dart --verificar-saida
//   dart run tool/e2e/e2e.dart --ajuda
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:driver/services/event_verifier.dart';
import 'package:driver/services/ws_relay_transport.dart';

import 'src/adb.dart';
import 'src/checkpoint.dart';
import 'src/ciclo.dart';
import 'src/config.dart';
import 'src/evidencia.dart';
import 'src/observador.dart';
import 'src/opcoes.dart';
import 'src/periodo.dart';
import 'src/preparo.dart';
import 'src/registro.dart';
import 'src/relatorio.dart';
import 'src/relogio.dart';
import 'src/varredura_saida.dart';

const _modeloDesvios = '''# Desvios e conferências do período

Registre aqui, com o motivo, tudo que diferir do spec (FR-040): ajuste de limite de
tempo, rótulo de tela diferente do previsto, conferência manual (por exemplo, a
distância entre o destino do `geo fix` e o ponto devolvido pelo Photon), tela não
capturada. O que não está aqui não foi alterado.

| Data (UTC) | O que mudou ou foi conferido | Motivo |
|------------|------------------------------|--------|
''';

Future<void> main(List<String> args) async {
  final Opcoes opcoes;
  try {
    opcoes = parseOpcoes(args);
  } on OpcoesInvalidas catch (e) {
    stderr.writeln('${e.mensagem}\n\n$textoDeAjuda');
    exit(2);
  }
  final codigo = switch (opcoes.comando) {
    Comando.ajuda => _ajuda(),
    Comando.verificarSaida => _verificarSaida(opcoes),
    Comando.relatorio => _relatorio(opcoes),
    Comando.periodo => await _periodo(opcoes),
  };
  exit(codigo);
}

int _ajuda() {
  print(textoDeAjuda);
  return 0;
}

// ---- varredura ---------------------------------------------------------------

int _verificarSaida(Opcoes o) {
  final raiz = Directory(o.saida);
  if (!raiz.existsSync()) {
    stderr.writeln('pasta de saída inexistente: ${o.saida}');
    return 2;
  }
  return _varrer(raiz) ? 0 : 1;
}

/// Roda a varredura e imprime os achados (sem os valores). Verdadeiro se limpo.
bool _varrer(Directory raiz) {
  final chave = lerChaveOrs();
  if (chave == null) {
    print(
      'aviso: chave do openrouteservice não encontrada; padrão da chave ORS não verificado',
    );
  }
  final achados = varrerSaida(raiz, chaveOrs: chave);
  if (achados.isEmpty) {
    print('varredura: nenhum padrão proibido em ${raiz.path}');
    return true;
  }
  for (final a in achados) {
    stderr.writeln('PROIBIDO: $a');
  }
  return false;
}

// ---- relatório combinado -----------------------------------------------------

int _relatorio(Opcoes o) {
  final raiz = Directory(o.saida);
  final dados = <DadosPeriodo>[];
  for (final n in ['1', '2']) {
    final pasta = Directory('${raiz.path}/periodo-$n');
    if (!pasta.existsSync()) continue;
    try {
      dados.add(lerDadosPeriodo(pasta));
    } on FormatException catch (e) {
      stderr.writeln('período $n ilegível: ${e.message}');
      return 2;
    }
  }
  if (dados.isEmpty) {
    stderr.writeln('nenhum período em ${raiz.path}; execute --periodo 1 antes');
    return 2;
  }
  final r = gerarRelatorio(dados);
  File('${raiz.path}/relatorio.md').writeAsStringSync(r.markdown);
  final dir = Directory('${raiz.path}/dados')..createSync(recursive: true);
  for (final e in r.csvs.entries) {
    File('${dir.path}/${e.key}').writeAsStringSync(e.value);
  }
  print(
    'relatório gerado em ${raiz.path}/relatorio.md (${dados.length} período(s))',
  );
  if (!_varrer(raiz)) {
    stderr.writeln(
      'o relatório NÃO deve ser considerado íntegro: a varredura reprovou',
    );
    return 1;
  }
  return 0;
}

// ---- período -----------------------------------------------------------------

Future<bool> _ignoradaPeloGit(String saida) async {
  final raizRepo = Directory.current.absolute.path;
  final absoluta = Directory(saida).absolute.path;
  if (!absoluta.startsWith(raizRepo)) return true; // fora do repositório
  final amostra = '$absoluta/.verificacao';
  final r = await Process.run('git', ['check-ignore', '-q', amostra]);
  return r.exitCode == 0;
}

Future<int> _periodo(Opcoes o) async {
  const relogio = RelogioReal();
  final nome = o.ensaio ? 'ensaio' : '${o.periodo}';
  final saida = Directory(o.saida);

  if (!await _ignoradaPeloGit(o.saida)) {
    stderr.writeln('a pasta de saída ${o.saida} não está ignorada pelo Git');
    return 2;
  }

  // Pasta do período.
  Directory pasta;
  if (o.ensaio && o.retomar) {
    final existentes = saida.existsSync()
        ? (saida
              .listSync()
              .whereType<Directory>()
              .where((d) => d.path.contains('/ensaio-'))
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path)))
        : <Directory>[];
    if (existentes.isEmpty) {
      stderr.writeln('nenhum ensaio para retomar em ${o.saida}');
      return 2;
    }
    pasta = existentes.last;
  } else if (o.ensaio) {
    final agora = DateTime.now();
    String d2(int v) => v.toString().padLeft(2, '0');
    pasta = Directory(
      '${saida.path}/ensaio-${agora.year}${d2(agora.month)}${d2(agora.day)}-${d2(agora.hour)}${d2(agora.minute)}',
    );
  } else {
    pasta = Directory('${saida.path}/periodo-${o.periodo}');
  }
  final repo = RepositorioPeriodo(pasta);
  if (!o.retomar && repo.existe) {
    stderr.writeln('${pasta.path} já existe; use --retomar para continuar');
    return 2;
  }
  if (o.retomar && !repo.existe) {
    stderr.writeln('${pasta.path} não tem checkpoint; não há o que retomar');
    return 2;
  }

  // Teto de ciclos.
  var teto = tetoPeriodo1;
  if (o.ensaio) {
    teto = (o.metaValidos ?? metaValidosPorPeriodo) * 2 + 2;
  } else if (o.periodo == 2) {
    int? executados1 = o.tetoPeriodo1Executados;
    final anterior = Directory('${saida.path}/periodo-1');
    if (executados1 == null && anterior.existsSync()) {
      try {
        executados1 = RepositorioPeriodo(anterior).lerCiclos().length;
      } on FormatException {
        stderr.writeln(
          'ciclos do período 1 ilegíveis; informe --teto-periodo-1-executados',
        );
        return 2;
      }
    }
    if (executados1 == null) {
      stderr.writeln(
        'período 1 ausente: informe --teto-periodo-1-executados N',
      );
      return 2;
    }
    teto = tetoDoPeriodo(2, executadosPeriodo1: executados1);
    if (teto == 0) {
      stderr.writeln(
        'o limite de $tetoTotal ciclos já foi consumido pelo período 1',
      );
      return 2;
    }
  }

  final chaveOrs = lerChaveOrs();
  if (chaveOrs == null) {
    final msg =
        'chave do openrouteservice não encontrada (ORS_API_KEY ou '
        'assets/ors_api_key.txt); o padrão da chave ORS não será verificado';
    if (o.exigirChaveOrs) {
      stderr.writeln(msg);
      return 2;
    }
    print('aviso: $msg');
  }

  // Pré-condições (nada apagado até aqui).
  final adb = AdbProcesso();
  final AmbienteVerificado ambiente;
  try {
    ambiente = await verificarEmuladores(
      adb,
      avdDoMotorista: o.avdDoMotorista,
      avdDoPassageiro: o.avdDoPassageiro,
    );
    for (final pacote in [
      (ambiente.serialMotorista, pacoteMotorista),
      (ambiente.serialPassageiro, pacotePassageiro),
    ]) {
      final r = await Process.run('adb', [
        '-s',
        pacote.$1,
        'shell',
        'pm',
        'path',
        pacote.$2,
      ]);
      if (r.exitCode != 0 || (r.stdout as String).trim().isEmpty) {
        throw PreCondicaoFalha(
          'pacote ${pacote.$2} não instalado em ${pacote.$1}',
        );
      }
    }
  } on PreCondicaoFalha catch (e) {
    stderr.writeln('pré-condição não atendida: ${e.mensagem}');
    return 2;
  }
  final repoPassageiro = Directory(
    '${Directory.current.parent.path}/RideRelayPassenger',
  );
  if (!repoPassageiro.existsSync()) {
    stderr.writeln(
      'repositório do passageiro não encontrado em ${repoPassageiro.path}',
    );
    return 2;
  }

  pasta.createSync(recursive: true);
  final log = RegistroExecucao(
    arquivo: File('${pasta.path}/execucao.log'),
    chaveOrs: chaveOrs,
  );
  final desvios = File('${pasta.path}/desvios.md');
  if (!desvios.existsSync()) desvios.writeAsStringSync(_modeloDesvios);
  void registrarDesvio(String texto) {
    desvios.writeAsStringSync(
      '| ${DateTime.now().toUtc().toIso8601String()} | ${sanitizar(texto, chaveOrs: chaveOrs)} | automático |\n',
      mode: FileMode.append,
    );
  }

  final mot = ambiente.serialMotorista;
  final pax = ambiente.serialPassageiro;
  final Periodo periodo;
  try {
    if (o.retomar) {
      periodo = repo.lerCheckpoint()!;
      repo.lerCiclos(); // recusa ciclos ilegíveis antes de qualquer ação
      log.escrever('retomando ${pasta.path}');
      await adb.iniciarApp(mot, pacoteMotorista);
      await adb.iniciarApp(pax, pacotePassageiro);
      await relogio.dormir(const Duration(seconds: 3));
      final pubMot = await lerChavePublica(adb, relogio, mot);
      final pubPax = await lerChavePublica(adb, relogio, pax);
      if (pubMot != periodo.motoristaPub || pubPax != periodo.passageiroPub) {
        stderr.writeln(
          'as chaves públicas dos apps não conferem com o checkpoint; recusando',
        );
        return 2;
      }
    } else {
      log.escrever('preparando $nome: pm clear, permissões e cadastros');
      await limparEConceder(adb, mot, pacoteMotorista);
      await limparEConceder(adb, pax, pacotePassageiro);
      await adb.geoFix(mot, partidaDoMotorista.lat, partidaDoMotorista.lon);
      await adb.geoFix(pax, pontoDeEncontro.lat, pontoDeEncontro.lon);
      await cadastrarPassageiro(adb, relogio, pax);
      await cadastrarMotorista(adb, relogio, mot);
      await conferirRelays(adb, relogio, mot);
      await conferirRelays(adb, relogio, pax);
      final pubMot = await lerChavePublica(adb, relogio, mot);
      final pubPax = await lerChavePublica(adb, relogio, pax);
      final agora = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
      final derivaMot = await adb.epochEmulador(mot) - agora;
      final derivaPax = await adb.epochEmulador(pax) - agora;
      periodo = Periodo(
        periodo: nome,
        metaValidos: o.metaValidos ?? metaValidosPorPeriodo,
        tetoExecutados: teto,
        orcamentoMs: Duration(
          minutes: o.orcamentoMin ?? const Limites().periodo.inMinutes,
        ).inMilliseconds,
        motoristaPub: pubMot,
        passageiroPub: pubPax,
        versoes: {
          'motorista': await lerVersao(Directory.current.path),
          'passageiro': await lerVersao(repoPassageiro.path),
        },
        ambiente: {
          ...ambiente.descricao,
          'deriva_relogio_s': {'motorista': derivaMot, 'passageiro': derivaPax},
        },
      );
      repo.gravarCheckpoint(periodo);
    }
  } on PreCondicaoFalha catch (e) {
    stderr.writeln('preparo interrompido: ${e.mensagem}');
    stderr.writeln(
      'os dados dos apps podem ter sido apagados; refaça o período',
    );
    return 2;
  } on AdbFalha catch (e) {
    stderr.writeln('adb falhou no preparo: ${e.mensagem}');
    return 2;
  }

  // Observador (independente dos apps): conectado antes do primeiro ciclo.
  final eventosArquivo = File('${pasta.path}/eventos.jsonl');
  late final Observador observador;
  observador = Observador(
    transport: const WsRelayTransport(),
    verifier: const NostrEventVerifier(),
    identidades: Identidades(
      motorista: periodo.motoristaPub,
      passageiro: periodo.passageiroPub,
    ),
    relogio: relogio,
    aoRegistrar: (e) {
      eventosArquivo.writeAsStringSync(
        '${jsonEncode(e.toJson(ciclo: observador.cicloAtual))}\n',
        mode: FileMode.append,
      );
    },
  );
  await observador.iniciar();

  final contexto = ContextoCiclo(
    adb: adb,
    serialMotorista: mot,
    serialPassageiro: pax,
    observador: observador,
    evidencia: Evidencia(adb: adb, pasta: Directory('${pasta.path}/capturas')),
    relogio: relogio,
    periodo: nome,
    telasCapturadas: periodo.telasCapturadas.toSet(),
  );
  final executorCiclo = ExecutorCiclo(contexto);

  Future<bool> pronto() async {
    for (var i = 0; i < 20; i++) {
      await observador.garantirConexoes();
      if (observador.relaysProntos.length == relaysDoRoteiro.length) {
        return true;
      }
      await relogio.dormir(const Duration(milliseconds: 1500));
    }
    if (observador.relaysProntos.isNotEmpty) {
      final texto =
          'observador sem todos os relays; prontos: ${observador.relaysProntos.join(', ')}';
      log.escrever(texto);
      registrarDesvio(texto);
      return true;
    }
    return false;
  }

  final executor = ExecutorPeriodo(
    periodo: periodo,
    repositorio: repo,
    relogio: relogio,
    contexto: contexto,
    executarCiclo: executorCiclo.executar,
    prontoParaCiclo: pronto,
    log: log.escrever,
  );
  final sub = ProcessSignal.sigint.watch().listen((_) {
    log.escrever(
      'Ctrl+C: encerrando o ciclo em andamento e gravando o checkpoint',
    );
    executor.pedirParada();
  });

  Periodo final_;
  try {
    final_ = await executor.executar();
  } finally {
    await sub.cancel();
    await observador.parar();
  }

  final c = Contadores.de(repo.lerCiclos());
  log.escrever(
    '$nome: ${final_.estado.name}${final_.motivoParcial != null ? ' (${final_.motivoParcial})' : ''}; '
    'executados ${c.executados}, válidos ${c.validos}, falhas ${c.falhasValidas}, '
    'externos repostos ${c.externosRepostos}',
  );
  final dados = lerDadosPeriodo(pasta);
  File('${pasta.path}/relatorio-periodo.md')
      .writeAsStringSync(gerarRelatorio([dados]).markdown);
  final limpo = _varrer(pasta);
  if (!limpo) return 1;
  return final_.estado == EstadoPeriodo.concluido ? 0 : 1;
}
