// Teste E2E automatizado do fluxo completo da corrida (feature 029).
//
// Roteiro de linha de comando que opera os dois emuladores por ADB e gera as
// evidências do TCC. Contrato: specs/029-teste-e2e-fluxo-corrida/contracts/cli.md.
//
// ignore_for_file: avoid_print — é uma ferramenta de linha de comando, em que a
// saída padrão é a própria interface; não faz parte do aplicativo.
//
// Uso:
//   dart run tool/e2e/e2e.dart --executar
//   dart run tool/e2e/e2e.dart --preparar
//   dart run tool/e2e/e2e.dart --retomar
//   dart run tool/e2e/e2e.dart --relatorio
//   dart run tool/e2e/e2e.dart --verificar-saida
//   dart run tool/e2e/e2e.dart --zerar
//   dart run tool/e2e/e2e.dart --ajuda
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:driver/services/event_verifier.dart';
import 'package:driver/services/ws_relay_transport.dart';

import 'src/adb.dart';
import 'src/ambiente.dart';
import 'src/checkpoint.dart';
import 'src/ciclo.dart';
import 'src/config.dart';
import 'src/coordenacao.dart';
import 'src/evidencia.dart';
import 'src/execucao.dart';
import 'src/observador.dart';
import 'src/opcoes.dart';
import 'src/papel.dart';
import 'src/preparo.dart';
import 'src/registro.dart';
import 'src/relatorio.dart';
import 'src/relogio.dart';
import 'src/varredura_saida.dart';
import 'src/zerar.dart';

const _modeloDesvios = '''# Desvios e conferências da execução

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
    Comando.zerar => zerarExecucao(
      saida: Directory(opcoes.saida),
      lerLinha: stdin.readLineSync,
      escrever: print,
    ),
    Comando.preparar => await _preparar(opcoes),
    Comando.executar => await _executar(opcoes),
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

// ---- relatório ---------------------------------------------------------------

int _relatorio(Opcoes o) {
  final raiz = Directory(o.saida);
  final pasta = Directory('${raiz.path}/execucao');
  if (!pasta.existsSync()) {
    stderr.writeln(
      'nenhuma execução em ${pasta.path}; execute --executar antes',
    );
    return 2;
  }
  final DadosExecucao dados;
  try {
    final propria = lerDadosExecucao(pasta);
    final outra = o.juntar;
    if (outra == null) {
      dados = propria;
    } else {
      final pastaOutra = Directory(outra);
      if (!pastaOutra.existsSync()) {
        stderr.writeln('pasta a juntar inexistente: $outra');
        return 2;
      }
      dados = juntarDados(propria, lerDadosExecucao(pastaOutra));
    }
  } on FormatException catch (e) {
    stderr.writeln('execução ilegível: ${e.message}');
    return 2;
  }
  final r = gerarRelatorio(dados);
  File('${raiz.path}/relatorio.md').writeAsStringSync(r.markdown);
  final dir = Directory('${raiz.path}/dados')..createSync(recursive: true);
  for (final e in r.csvs.entries) {
    File('${dir.path}/${e.key}').writeAsStringSync(e.value);
  }
  print('relatório gerado em ${raiz.path}/relatorio.md');
  if (!_varrer(raiz)) {
    stderr.writeln(
      'o relatório NÃO deve ser considerado íntegro: a varredura reprovou',
    );
    return 1;
  }
  return 0;
}

// ---- ambiente ----------------------------------------------------------------

Directory get _repoPassageiro =>
    Directory('${Directory.current.parent.path}/RideRelayPassenger');

/// Sobe os dois emuladores (se preciso) e, com [instalar], compila e instala os
/// dois apps. Devolve `false` e escreve o motivo se algo falhar.
Future<bool> _prepararAmbiente(Opcoes o, {required bool instalar}) async {
  final passageiro = _repoPassageiro;
  if (instalar && !passageiro.existsSync()) {
    stderr.writeln(
      'repositório do passageiro não encontrado em ${passageiro.path}',
    );
    return false;
  }
  final preparo = _criarPreparo(o, log: (t) => print('ambiente: $t'));
  try {
    final seriais = await preparo.subirEmuladores(
      avdMotorista: o.avdDoMotorista,
      avdPassageiro: o.avdDoPassageiro,
    );
    if (instalar) {
      await preparo.compilarEInstalar(
        rotulo: 'motorista',
        diretorio: Directory.current.path,
        serial: seriais.motorista,
      );
      await preparo.compilarEInstalar(
        rotulo: 'passageiro',
        diretorio: passageiro.path,
        serial: seriais.passageiro,
      );
    }
  } on PreCondicaoFalha catch (e) {
    stderr.writeln('preparo do ambiente falhou: ${e.mensagem}');
    return false;
  }
  return true;
}

PreparoAmbiente _criarPreparo(
  Opcoes o, {
  required void Function(String) log,
  void Function(String)? desvio,
}) {
  const sistema = SistemaReal();
  final adbExe = localizarAdb(Platform.environment, sistema);
  return PreparoAmbiente(
    sistema: sistema,
    adb: AdbProcesso(executavel: adbExe),
    adbExecutavel: adbExe,
    relogio: const RelogioReal(),
    emulator: localizarEmulator(Platform.environment, sistema),
    log: log,
    semJanela: o.semJanela,
    desvio: desvio,
  );
}

Future<int> _preparar(Opcoes o) async {
  if (o.papel != null) return await _prepararEmuladorDoPapel(o) != null ? 0 : 2;
  return await _prepararAmbiente(o, instalar: true) ? 0 : 2;
}

/// Duas máquinas: sobe só o emulador do papel desta máquina e, com [instalar],
/// compila e instala só o app dele. Devolve o serial, ou `null` se falhar.
Future<String?> _prepararEmuladorDoPapel(
  Opcoes o, {
  bool instalar = true,
}) async {
  final motorista = o.papel == Papel.motorista;
  final repoApp = motorista ? Directory.current : _repoPassageiro;
  if (instalar && !repoApp.existsSync()) {
    stderr.writeln('repositório do app não encontrado em ${repoApp.path}');
    return null;
  }
  final preparo = _criarPreparo(o, log: (t) => print('ambiente: $t'));
  try {
    final serial = await preparo.subirEmulador(
      avd: motorista ? o.avdDoMotorista : o.avdDoPassageiro,
    );
    if (instalar) {
      await preparo.compilarEInstalar(
        rotulo: o.papel!.name,
        diretorio: repoApp.path,
        serial: serial,
      );
    }
    return serial;
  } on PreCondicaoFalha catch (e) {
    stderr.writeln('preparo do ambiente falhou: ${e.mensagem}');
    return null;
  }
}

// ---- execução ----------------------------------------------------------------

Future<bool> _ignoradaPeloGit(String saida) async {
  final raizRepo = Directory.current.absolute.path;
  final absoluta = Directory(saida).absolute.path;
  if (!absoluta.startsWith(raizRepo)) return true; // fora do repositório
  final amostra = '$absoluta/.verificacao';
  final r = await Process.run('git', ['check-ignore', '-q', amostra]);
  return r.exitCode == 0;
}

Future<int> _executar(Opcoes o) async {
  const relogio = RelogioReal();
  final nome = o.ensaio ? 'ensaio' : 'execução';
  final saida = Directory(o.saida);

  if (!await _ignoradaPeloGit(o.saida)) {
    stderr.writeln('a pasta de saída ${o.saida} não está ignorada pelo Git');
    return 2;
  }

  // Pasta da execução.
  Directory pasta;
  if (o.ensaio && o.retomar) {
    final existentes = saida.existsSync()
        ? (saida
              .listSync()
              .whereType<Directory>()
              .where((d) => RegExp(r'[\\/]ensaio-').hasMatch(d.path))
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
    pasta = Directory('${saida.path}/execucao');
  }
  final repo = RepositorioExecucao(pasta);
  if (!o.retomar && repo.existe) {
    stderr.writeln('${pasta.path} já existe; use --retomar para continuar');
    return 2;
  }
  if (o.retomar && !repo.existe) {
    stderr.writeln('${pasta.path} não tem checkpoint; não há o que retomar');
    return 2;
  }

  // Teto de ciclos (FR-013). No ensaio, proporcional à meta reduzida.
  final teto = o.ensaio
      ? (o.metaValidos ?? metaValidosDaExecucao) * 2 + 2
      : tetoDeCiclosExecutados;

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

  if (o.papel != null) {
    return _executarPorPapel(
      o,
      nome: nome,
      pasta: pasta,
      repo: repo,
      teto: teto,
      chaveOrs: chaveOrs,
    );
  }

  // Emuladores e apps (nada é apagado aqui). Na retomada só garante os
  // emuladores: os apps instalados são os da execução original.
  if (!o.semPreparo && !await _prepararAmbiente(o, instalar: !o.retomar)) {
    return 2;
  }

  // Pré-condições (nada apagado até aqui).
  final adbExe = localizarAdb(Platform.environment, const SistemaReal());
  final adb = AdbProcesso(executavel: adbExe);
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
      final r = await Process.run(adbExe, [
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
  final repoPassageiro = _repoPassageiro;
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
  final Execucao execucao;
  try {
    if (o.retomar) {
      execucao = repo.lerCheckpoint()!;
      repo.lerCiclos(); // recusa ciclos ilegíveis antes de qualquer ação
      log.escrever('retomando ${pasta.path}');
      // Apps reabertos e conferência das chaves: mais adiante, depois de o
      // executor existir (uma corrida restaurada precisa ser cancelada antes).
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
      execucao = Execucao(
        ensaio: o.ensaio,
        metaValidos: o.metaValidos ?? metaValidosDaExecucao,
        tetoExecutados: teto,
        orcamentoMs: Duration(
          minutes: o.orcamentoMin ?? const Limites().execucao.inMinutes,
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
      repo.gravarCheckpoint(execucao);
    }
  } on PreCondicaoFalha catch (e) {
    stderr.writeln('preparo interrompido: ${e.mensagem}');
    stderr.writeln(
      'os dados dos apps podem ter sido apagados; refaça a execução',
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
      motorista: execucao.motoristaPub,
      passageiro: execucao.passageiroPub,
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
    telasCapturadas: execucao.telasCapturadas.toSet(),
  );
  final executorCiclo = ExecutorCiclo(contexto);

  if (o.retomar) {
    try {
      if (!await executorCiclo.devolverAppsAoMapa()) {
        stderr.writeln(
          'os apps reabriram com uma corrida que não pôde ser cancelada; '
          'cancele-a nos emuladores e use --retomar de novo',
        );
        await observador.parar();
        return 2;
      }
      final pubMot = await lerChavePublica(adb, relogio, mot);
      final pubPax = await lerChavePublica(adb, relogio, pax);
      if (pubMot != execucao.motoristaPub || pubPax != execucao.passageiroPub) {
        stderr.writeln(
          'as chaves públicas dos apps não conferem com o checkpoint; recusando',
        );
        await observador.parar();
        return 2;
      }
    } on PreCondicaoFalha catch (e) {
      stderr.writeln('retomada interrompida: ${e.mensagem}');
      await observador.parar();
      return 2;
    } on AdbFalha catch (e) {
      stderr.writeln('adb falhou na retomada: ${e.mensagem}');
      await observador.parar();
      return 2;
    }
  }

  // Entre dois ciclos os dois emuladores são desligados e subidos de novo, para
  // que a memória que eles seguravam volte ao hospedeiro (o `earlyoom` matava um
  // deles por volta do terceiro ciclo). Sem preparo, não há quem suba de volta.
  final reiniciar = o.semPreparo || o.semReinicioEntreCiclos
      ? null
      : _criarPreparo(
          o,
          log: (t) => log.escrever('ambiente: $t'),
          desvio: registrarDesvio,
        );
  if (reiniciar != null) {
    registrarDesvio(
      'os dois emuladores são desligados e subidos de novo entre cada ciclo '
      '(fora do tempo e da janela de eventos do ciclo), com o mesmo AVD e os '
      'dados preservados',
    );
  }
  Future<bool> reiniciarEmuladores() async {
    // Uma segunda tentativa antes de desistir: o primeiro boot a frio depois de
    // um desligamento é o mais sujeito a demorar mais que o prazo.
    for (var tentativa = 1; tentativa <= 2; tentativa++) {
      try {
        final novos = await reiniciar!.reiniciarEmuladores(
          avdMotorista: o.avdDoMotorista,
          avdPassageiro: o.avdDoPassageiro,
          serialMotorista: contexto.serialMotorista,
          serialPassageiro: contexto.serialPassageiro,
        );
        contexto.serialMotorista = novos.motorista;
        contexto.serialPassageiro = novos.passageiro;
        return true;
      } on PreCondicaoFalha catch (e) {
        log.escrever(
          'reinício dos emuladores falhou (tentativa $tentativa de 2): '
          '${e.mensagem}',
        );
      }
    }
    return false;
  }

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

  final executor = ExecutorExecucao(
    execucao: execucao,
    repositorio: repo,
    relogio: relogio,
    contexto: contexto,
    executarCiclo: executorCiclo.executar,
    prontoParaCiclo: pronto,
    entreCiclos: reiniciar == null ? null : reiniciarEmuladores,
    log: log.escrever,
  );
  final sub = ProcessSignal.sigint.watch().listen((_) {
    log.escrever(
      'Ctrl+C: encerrando o ciclo em andamento e gravando o checkpoint',
    );
    executor.pedirParada();
  });

  Execucao final_;
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
  final dados = lerDadosExecucao(pasta);
  File('${pasta.path}/relatorio-execucao.md')
      .writeAsStringSync(gerarRelatorio(dados).markdown);
  final limpo = _varrer(pasta);
  if (!limpo) return 1;
  return final_.estado == EstadoExecucao.concluido ? 0 : 1;
}

// ---- execução em duas máquinas ----------------------------------------------

/// Uma máquina, um emulador, um papel (`contracts/coordenacao.md`). O passageiro
/// coordena (servidor na LAN); o motorista é cliente. Trocam as chaves
/// **públicas** pelo canal de coordenação antes do primeiro ciclo.
Future<int> _executarPorPapel(
  Opcoes o, {
  required String nome,
  required Directory pasta,
  required RepositorioExecucao repo,
  required int teto,
  required String? chaveOrs,
}) async {
  const relogio = RelogioReal();
  final papel = o.papel!;
  final souMotorista = papel == Papel.motorista;
  final avd = souMotorista ? o.avdDoMotorista : o.avdDoPassageiro;
  final pacote = souMotorista ? pacoteMotorista : pacotePassageiro;
  final repoApp = souMotorista ? Directory.current : _repoPassageiro;

  String? serial;
  if (!o.semPreparo) {
    serial = await _prepararEmuladorDoPapel(o, instalar: !o.retomar);
    if (serial == null) return 2;
  }

  final adbExe = localizarAdb(Platform.environment, const SistemaReal());
  final adb = AdbProcesso(executavel: adbExe);
  final Map<String, Object?> descricaoAmbiente;
  try {
    final v = await verificarEmulador(adb, avd: avd, papel: papel.name);
    serial = v.serial;
    descricaoAmbiente = v.descricao;
    final r = await Process.run(adbExe, [
      '-s',
      serial,
      'shell',
      'pm',
      'path',
      pacote,
    ]);
    if (r.exitCode != 0 || (r.stdout as String).trim().isEmpty) {
      throw PreCondicaoFalha('pacote $pacote não instalado em $serial');
    }
  } on PreCondicaoFalha catch (e) {
    stderr.writeln('pré-condição não atendida: ${e.mensagem}');
    return 2;
  }

  // Canal de coordenação.
  final Coordenacao coord;
  ServidorCoordenacao? servidor;
  if (souMotorista) {
    coord = ClienteCoordenacao.deOpcoes(o);
  } else {
    final nucleo = NucleoCoordenacao();
    servidor = ServidorCoordenacao(nucleo: nucleo, token: o.token!);
    try {
      await servidor.iniciar(porta: o.porta);
    } on SocketException catch (e) {
      stderr.writeln('não foi possível abrir a porta ${o.porta}: ${e.message}');
      return 2;
    }
    coord = CoordenacaoLocal(nucleo, papel);
    print(
      'coordenador escutando na porta ${o.porta}; '
      'o motorista deve usar --coordenador <IP desta máquina>:${o.porta}',
    );
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

  Future<int> terminar(int codigo, {Observador? observador}) async {
    await observador?.parar();
    await servidor?.parar();
    return codigo;
  }

  final Execucao execucao;
  try {
    // Chave pública e versão do app desta máquina; a retomada confere com o
    // checkpoint (o app foi reaberto no mapa antes de ler a chave).
    final minhaVersao = await lerVersao(repoApp.path);
    final String minhaPub;
    Execucao? anterior;
    if (o.retomar) {
      anterior = repo.lerCheckpoint()!;
      repo.lerCiclos(); // recusa ciclos ilegíveis antes de qualquer ação
      log.escrever('retomando ${pasta.path} como ${papel.name}');
      final inicial = ContextoCiclo(
        adb: adb,
        serialMotorista: souMotorista ? serial : '',
        serialPassageiro: souMotorista ? '' : serial,
        papel: papel,
        observador: Observador(
          transport: const WsRelayTransport(),
          verifier: const NostrEventVerifier(),
          identidades: Identidades(
            motorista: anterior.motoristaPub,
            passageiro: anterior.passageiroPub,
          ),
          relogio: relogio,
        ),
        evidencia: Evidencia(
          adb: adb,
          pasta: Directory('${pasta.path}/capturas'),
        ),
        relogio: relogio,
      );
      if (!await ExecutorCiclo(inicial).devolverAppsAoMapa()) {
        stderr.writeln(
          'o app reabriu com uma corrida que não pôde ser cancelada; '
          'cancele-a no emulador e use --retomar de novo',
        );
        return await terminar(2);
      }
      minhaPub = await lerChavePublica(adb, relogio, serial);
      final esperada = souMotorista
          ? anterior.motoristaPub
          : anterior.passageiroPub;
      if (minhaPub != esperada) {
        stderr.writeln(
          'a chave pública do app não confere com o checkpoint; recusando',
        );
        return await terminar(2);
      }
    } else {
      log.escrever(
        'preparando $nome (${papel.name}): pm clear, permissões e cadastro',
      );
      await limparEConceder(adb, serial, pacote);
      if (souMotorista) {
        await adb.geoFix(
          serial,
          partidaDoMotorista.lat,
          partidaDoMotorista.lon,
        );
        await cadastrarMotorista(adb, relogio, serial);
      } else {
        await adb.geoFix(serial, pontoDeEncontro.lat, pontoDeEncontro.lon);
        await cadastrarPassageiro(adb, relogio, serial);
      }
      await conferirRelays(adb, relogio, serial);
      minhaPub = await lerChavePublica(adb, relogio, serial);
    }

    log.escrever('trocando as chaves públicas com o outro lado');
    final outro = await trocarIdentidades(
      coord,
      minhaPub: minhaPub,
      minhaVersao: minhaVersao,
      relogio: relogio,
      log: log.escrever,
    );

    if (anterior != null) {
      final pubOutro = souMotorista
          ? anterior.passageiroPub
          : anterior.motoristaPub;
      if (outro.pub != pubOutro) {
        stderr.writeln(
          'a chave pública do outro lado não confere com o checkpoint; recusando',
        );
        return await terminar(2);
      }
      execucao = anterior;
    } else {
      final agora = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
      final deriva = await adb.epochEmulador(serial) - agora;
      int? deslocamentoMs;
      try {
        deslocamentoMs = (await coord.deslocamentoDeRelogio()).inMilliseconds;
      } on CoordenadorInalcancavel {
        deslocamentoMs = null;
      }
      execucao = Execucao(
        ensaio: o.ensaio,
        metaValidos: o.metaValidos ?? metaValidosDaExecucao,
        tetoExecutados: teto,
        orcamentoMs: Duration(
          minutes: o.orcamentoMin ?? const Limites().execucao.inMinutes,
        ).inMilliseconds,
        motoristaPub: souMotorista ? minhaPub : outro.pub,
        passageiroPub: souMotorista ? outro.pub : minhaPub,
        versoes: {
          papel.name: minhaVersao,
          (souMotorista ? 'passageiro' : 'motorista'): outro.versao,
        },
        ambiente: {
          ...descricaoAmbiente,
          'papel': papel.name,
          'deriva_relogio_s': {papel.name: deriva},
          // Relógio do coordenador menos o desta máquina; só metadado.
          'deslocamento_relogio_coordenador_ms': deslocamentoMs,
        },
      );
      repo.gravarCheckpoint(execucao);
    }
  } on PreCondicaoFalha catch (e) {
    stderr.writeln('preparo interrompido: ${e.mensagem}');
    return await terminar(2);
  } on AdbFalha catch (e) {
    stderr.writeln('adb falhou no preparo: ${e.mensagem}');
    return await terminar(2);
  }

  final eventosArquivo = File('${pasta.path}/eventos.jsonl');
  late final Observador observador;
  observador = Observador(
    transport: const WsRelayTransport(),
    verifier: const NostrEventVerifier(),
    identidades: Identidades(
      motorista: execucao.motoristaPub,
      passageiro: execucao.passageiroPub,
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
    serialMotorista: souMotorista ? serial : '',
    serialPassageiro: souMotorista ? '' : serial,
    papel: papel,
    coordenacao: coord,
    observador: observador,
    evidencia: Evidencia(adb: adb, pasta: Directory('${pasta.path}/capturas')),
    relogio: relogio,
    telasCapturadas: execucao.telasCapturadas.toSet(),
  );
  final executorCiclo = ExecutorCiclo(contexto);

  // Um emulador por máquina não disputa memória: o reinício a frio entre ciclos
  // fica desligado, a menos que se peça.
  final reiniciar = o.semPreparo || !o.reinicioEntreCiclos
      ? null
      : _criarPreparo(
          o,
          log: (t) => log.escrever('ambiente: $t'),
          desvio: registrarDesvio,
        );
  if (reiniciar != null) {
    registrarDesvio(
      'o emulador do ${papel.name} é desligado e subido de novo entre cada '
      'ciclo (fora do tempo e da janela de eventos do ciclo), com os dados '
      'preservados',
    );
  }
  Future<bool> reiniciarEmulador() async {
    for (var tentativa = 1; tentativa <= 2; tentativa++) {
      try {
        final atual = souMotorista
            ? contexto.serialMotorista
            : contexto.serialPassageiro;
        final novo = await reiniciar!.reiniciarEmulador(
          avd: avd,
          serial: atual,
        );
        if (souMotorista) {
          contexto.serialMotorista = novo;
        } else {
          contexto.serialPassageiro = novo;
        }
        return true;
      } on PreCondicaoFalha catch (e) {
        log.escrever(
          'reinício do emulador falhou (tentativa $tentativa de 2): '
          '${e.mensagem}',
        );
      }
    }
    return false;
  }

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

  final executor = ExecutorExecucao(
    execucao: execucao,
    repositorio: repo,
    relogio: relogio,
    contexto: contexto,
    executarCiclo: executorCiclo.executar,
    prontoParaCiclo: pronto,
    entreCiclos: reiniciar == null ? null : reiniciarEmulador,
    coordenacao: coord,
    papel: papel,
    log: log.escrever,
  );
  final sub = ProcessSignal.sigint.watch().listen((_) {
    log.escrever(
      'Ctrl+C: encerrando o ciclo em andamento e gravando o checkpoint',
    );
    executor.pedirParada();
  });

  Execucao final_;
  try {
    final_ = await executor.executar();
    if (servidor != null) {
      // O motorista lê a decisão final por polling; o servidor fica no ar um
      // pouco mais para ele não achar que o coordenador caiu.
      log.escrever('aguardando o motorista ler a decisão final');
      await relogio.dormir(const Duration(seconds: 15));
    }
  } finally {
    await sub.cancel();
    await observador.parar();
    await servidor?.parar();
  }

  final c = Contadores.de(repo.lerCiclos());
  log.escrever(
    '$nome (${papel.name}): ${final_.estado.name}${final_.motivoParcial != null ? ' (${final_.motivoParcial})' : ''}; '
    'executados ${c.executados}, válidos ${c.validos}, falhas ${c.falhasValidas}, '
    'externos repostos ${c.externosRepostos}',
  );
  final dados = lerDadosExecucao(pasta);
  File('${pasta.path}/relatorio-execucao.md')
      .writeAsStringSync(gerarRelatorio(dados).markdown);
  final limpo = _varrer(pasta);
  if (!limpo) return 1;
  return final_.estado == EstadoExecucao.concluido ? 0 : 1;
}
