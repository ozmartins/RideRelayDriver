import 'checkpoint.dart';
import 'ciclo.dart';
import 'coordenacao.dart';
import 'opcoes.dart' show Papel;
import 'relogio.dart';

/// Laço da execução (FR-012 a FR-019): ciclos até a meta de válidos, com teto
/// de ciclos executados, orçamento de tempo ativo, checkpoint a cada ciclo,
/// reposição de ciclos externos e parada controlada.
///
/// Em duas máquinas (`contracts/coordenacao.md`) o passageiro coordena: decide
/// quando parar e publica a decisão; o motorista a segue. As barreiras
/// `fim-ciclo`, `pronto-para-reiniciar` e `inicio-ciclo` mantêm os dois laços
/// no mesmo ciclo, e o resultado de cada lado é fundido no `fim-ciclo`.

/// O que um lado conta ao outro no `fim-ciclo`: só metadados da decisão.
class ResumoCiclo {
  const ResumoCiclo({
    required this.resultado,
    required this.valido,
    this.etapaFalha,
    this.origem,
    this.servicoExterno,
    this.origemBruta,
    this.limiteDiarioOrs = false,
    this.recuperacaoFalhou = false,
    this.consequencia = false,
  });

  factory ResumoCiclo.de(ResultadoCiclo r) => ResumoCiclo(
    resultado: r.ciclo.resultado,
    valido: r.ciclo.valido,
    etapaFalha: r.ciclo.etapaFalha,
    origem: r.ciclo.origem,
    servicoExterno: r.ciclo.servicoExterno,
    origemBruta: r.ciclo.origemBruta,
    limiteDiarioOrs: r.limiteDiarioOrs,
    recuperacaoFalhou: r.recuperacaoFalhou,
    consequencia: r.consequencia,
  );

  final String resultado;
  final bool valido;
  final String? etapaFalha;
  final String? origem;
  final String? servicoExterno;
  final String? origemBruta;
  final bool limiteDiarioOrs;
  final bool recuperacaoFalhou;

  /// A falha foi reflexo da falha do outro lado; só vale se o outro não tiver
  /// uma causa própria.
  final bool consequencia;

  Map<String, Object?> toJson() => {
    'resultado': resultado,
    'valido': valido,
    'etapaFalha': ?etapaFalha,
    'origem': ?origem,
    'servicoExterno': ?servicoExterno,
    'origemBruta': ?origemBruta,
    'limiteDiarioOrs': limiteDiarioOrs,
    'recuperacaoFalhou': recuperacaoFalhou,
    'consequencia': consequencia,
  };

  static ResumoCiclo? fromJson(Map<String, Object?>? j) {
    if (j == null) return null;
    final resultado = j['resultado'];
    final valido = j['valido'];
    final limite = j['limiteDiarioOrs'];
    final recuperacao = j['recuperacaoFalhou'];
    String? texto(String k) => j[k] is String ? j[k] as String : null;
    if (resultado is! String ||
        !const {'sucesso', 'falha', 'interrompido'}.contains(resultado) ||
        valido is! bool ||
        limite is! bool ||
        recuperacao is! bool) {
      return null;
    }
    return ResumoCiclo(
      resultado: resultado,
      valido: valido,
      etapaFalha: texto('etapaFalha'),
      origem: texto('origem'),
      servicoExterno: texto('servicoExterno'),
      origemBruta: texto('origemBruta'),
      limiteDiarioOrs: limite,
      recuperacaoFalhou: recuperacao,
      consequencia: j['consequencia'] == true,
    );
  }
}

int _ordemDaEtapa(String? id) => id == null
    ? 1 << 20
    : (id == 'R' ? 1 << 10 : int.tryParse(id.substring(1)) ?? 1 << 10);

/// Funde o resultado local com o do outro lado. O ciclo só é válido se os dois
/// forem; a falha vale pela etapa mais cedo, e a de serviço externo prevalece
/// (o ciclo é reposto). Etapas, ações e capturas continuam só as do lado local.
ResultadoCiclo fundirResultados(ResultadoCiclo local, ResumoCiclo outro) {
  final l = local.ciclo;
  final resultado =
      l.resultado == 'interrompido' || outro.resultado == 'interrompido'
      ? 'interrompido'
      : (l.resultado == 'falha' || outro.resultado == 'falha'
            ? 'falha'
            : 'sucesso');
  final lado = <ResumoCiclo>[
    ResumoCiclo.de(local),
    outro,
  ].where((x) => x.etapaFalha != null).toList();
  lado.sort((a, b) {
    // A causa vem antes do reflexo; entre causas, o serviço externo primeiro.
    if (a.consequencia != b.consequencia) return a.consequencia ? 1 : -1;
    final ea = a.origem == 'servico_externo' ? 0 : 1;
    final eb = b.origem == 'servico_externo' ? 0 : 1;
    if (ea != eb) return ea - eb;
    return _ordemDaEtapa(a.etapaFalha) - _ordemDaEtapa(b.etapaFalha);
  });
  final causa = lado.isEmpty ? null : lado.first;
  final doLocal =
      causa != null &&
      causa.etapaFalha == l.etapaFalha &&
      causa.origem == l.origem;
  final ciclo = Ciclo(
    ciclo: l.ciclo,
    inicioUtc: l.inicioUtc,
    fimUtc: l.fimUtc,
    etapas: l.etapas,
    resultado: resultado,
    valido: l.valido && outro.valido,
    repostoPor: l.repostoPor,
    etapaFalha: causa?.etapaFalha,
    origem: causa?.origem,
    servicoExterno: causa?.servicoExterno,
    origemBruta: causa?.origemBruta,
    sinalExterno: doLocal ? l.sinalExterno : null,
    capturas: l.capturas,
    anomalias: l.anomalias,
    desvios: l.desvios,
    eventos: l.eventos,
  );
  return ResultadoCiclo(
    ciclo: ciclo,
    limiteDiarioOrs: local.limiteDiarioOrs || outro.limiteDiarioOrs,
    recuperacaoFalhou: local.recuperacaoFalhou || outro.recuperacaoFalhou,
  );
}

class ExecutorExecucao {
  ExecutorExecucao({
    required this.execucao,
    required this.repositorio,
    required this.relogio,
    required this.contexto,
    required this.executarCiclo,
    required this.prontoParaCiclo,
    this.entreCiclos,
    this.coordenacao,
    this.papel,
    this.log,
  }) : assert((coordenacao == null) == (papel == null));

  final Execucao execucao;
  final RepositorioExecucao repositorio;
  final Relogio relogio;
  final ContextoCiclo contexto;

  /// Roda um ciclo de número [numero].
  final Future<ResultadoCiclo> Function(int numero) executarCiclo;

  /// Confirma que o observador está conectado e inscrito (FR-023). Falso ⇒ o
  /// execução para como parcial por `ambiente`.
  final Future<bool> Function() prontoParaCiclo;

  /// Roda entre dois ciclos, depois do checkpoint do anterior e só se houver
  /// um próximo (nunca depois do último): o roteiro reinicia os emuladores aqui.
  /// Falso ⇒ a execução para como parcial por `ambiente`. Fica fora do tempo e
  /// da janela de eventos de qualquer ciclo, mas dentro do orçamento da execução.
  final Future<bool> Function()? entreCiclos;

  /// Duas máquinas: o canal com o outro lado e o papel desta (nulos = uma só).
  final Coordenacao? coordenacao;
  final Papel? papel;

  final void Function(String)? log;

  bool _parar = false;

  bool get _coordenador => coordenacao != null && papel == Papel.passageiro;
  bool get _seguidor => coordenacao != null && papel == Papel.motorista;

  /// Pedido de parada (Ctrl+C): o ciclo em andamento vira `interrompido`.
  void pedirParada() {
    _parar = true;
    contexto.prazoGlobal = relogio.agora();
  }

  void _registrar(String m) => log?.call(m);

  /// Executa (ou retoma) a execução. Devolve o checkpoint final, já gravado.
  Future<Execucao> executar() async {
    final inicioExecucao = relogio.agora();
    final tempoAtivoInicial = execucao.tempoAtivoMs;
    final invocacao = <String, Object?>{
      'inicio_utc': inicioExecucao.toIso8601String(),
      'fim_utc': null,
      'motivo_parada': null,
    };
    execucao.invocacoes = [...execucao.invocacoes, invocacao];
    execucao.estado = EstadoExecucao.emAndamento;
    execucao.motivoParcial = null;
    repositorio.gravarCheckpoint(execucao);

    void atualizarTempo() {
      execucao.tempoAtivoMs =
          tempoAtivoInicial +
          relogio.agora().difference(inicioExecucao).inMilliseconds;
    }

    void encerrar(EstadoExecucao estado, String? motivo) {
      atualizarTempo();
      execucao.estado = estado;
      execucao.motivoParcial = motivo;
      invocacao['fim_utc'] = relogio.agora().toIso8601String();
      invocacao['motivo_parada'] = motivo ?? 'meta_atingida';
      repositorio.gravarCheckpoint(execucao);
    }

    var ciclos = repositorio.lerCiclos();
    var rodouCiclo = false;
    final coord = coordenacao;

    int ultimo() => ciclos.isEmpty
        ? 0
        : ciclos.map((x) => x.ciclo).reduce((a, b) => a > b ? a : b);

    SituacaoExecucao situacao({required bool encerrado, String? motivo}) {
      final c = Contadores.de(ciclos);
      return SituacaoExecucao(
        ciclo: ultimo(),
        validos: c.validos,
        executados: c.executados,
        ativoMs: execucao.tempoAtivoMs,
        encerrado: encerrado,
        motivo: motivo,
      );
    }

    // Encerra a execução. Em duas máquinas o coordenador publica a decisão, e
    // quem para por conta própria solta o outro lado das barreiras.
    // [daDecisao]: o motivo veio do coordenador, nada a avisar.
    Future<Execucao> sair(
      EstadoExecucao estado,
      String? motivo, {
      bool daDecisao = false,
    }) async {
      encerrar(estado, motivo);
      if (coord != null && !daDecisao) {
        try {
          if (_coordenador) {
            await coord.publicarSituacao(
              situacao(encerrado: true, motivo: motivo ?? 'meta_atingida'),
            );
          }
          await coord.abortar(ultimo() + 1, motivo ?? 'meta_atingida');
          await coord.abortar(ultimo(), motivo ?? 'meta_atingida');
        } on CoordenadorInalcancavel catch (e) {
          _registrar('$e');
        }
      }
      return execucao;
    }

    // Espera o coordenador decidir sobre o ciclo que acabou (só o motorista).
    Future<SituacaoExecucao?> aguardarDecisao() async {
      final alvo = ultimo();
      final fim = relogio.agora().add(const Duration(seconds: 90));
      while (true) {
        try {
          final s = await coord!.estado();
          if (s.ciclo >= alvo) return s;
        } on CoordenadorInalcancavel catch (e) {
          _registrar('$e');
          return null;
        }
        if (!relogio.agora().isBefore(fim)) return null;
        await relogio.dormir(const Duration(seconds: 1));
      }
    }

    Future<Execucao> seguirDecisao(SituacaoExecucao d) => sair(
      d.motivo == 'meta_atingida'
          ? EstadoExecucao.concluido
          : EstadoExecucao.parcial,
      d.motivo == 'meta_atingida' ? null : (d.motivo ?? 'ambiente'),
      daDecisao: true,
    );

    // Uma barreira não liberou: se o coordenador já decidiu parar, vale o motivo
    // dele; senão é falha de ambiente.
    Future<Execucao> pararPorBarreira(String nome) async {
      _registrar('barreira $nome não liberada');
      if (_seguidor) {
        try {
          final d = await coord!.estado();
          if (d.encerrado && d.ciclo >= ultimo()) {
            return await seguirDecisao(d);
          }
        } on CoordenadorInalcancavel {
          // cai na falha de ambiente
        }
      }
      return sair(EstadoExecucao.parcial, 'ambiente');
    }

    Future<bool> passar(String nome, int n) async {
      try {
        final r = await coord!.barreira(nome, n);
        return r.resultado == ResultadoBarreira.liberada;
      } on CoordenadorInalcancavel catch (e) {
        _registrar('$e');
        return false;
      }
    }

    // Troca o resultado do ciclo com o outro lado e funde os dois.
    Future<ResultadoCiclo?> trocar(int n, ResultadoCiclo local) async {
      try {
        final r = await coord!.barreira(
          'fim-ciclo',
          n,
          dados: ResumoCiclo.de(local).toJson(),
        );
        if (r.resultado != ResultadoBarreira.liberada) return null;
        final outro = ResumoCiclo.fromJson(r.outro);
        return outro == null ? null : fundirResultados(local, outro);
      } on CoordenadorInalcancavel catch (e) {
        _registrar('$e');
        return null;
      }
    }

    while (true) {
      final c = Contadores.de(ciclos);
      if (!_seguidor && c.validos >= execucao.metaValidos) {
        return sair(EstadoExecucao.concluido, null);
      }
      if (!_seguidor && c.executados >= execucao.tetoExecutados) {
        return sair(EstadoExecucao.parcial, 'teto_executados');
      }
      atualizarTempo();
      if (!_seguidor && execucao.tempoAtivoMs >= execucao.orcamentoMs) {
        return sair(EstadoExecucao.parcial, 'orcamento');
      }
      if (_parar) {
        return sair(EstadoExecucao.parcial, 'interrompido');
      }
      if (_coordenador) {
        await coord!.publicarSituacao(situacao(encerrado: false));
      }
      if (_seguidor) {
        final d = await aguardarDecisao();
        if (d == null ||
            d.executados != c.executados ||
            d.validos != c.validos) {
          _registrar('o coordenador não decidiu ou os ciclos não conferem');
          return sair(EstadoExecucao.parcial, 'ambiente');
        }
        if (d.encerrado) return seguirDecisao(d);
      }
      if (rodouCiclo && entreCiclos != null) {
        _registrar('entre ciclos: reiniciando os emuladores');
        if (!await entreCiclos!()) {
          _registrar('não foi possível reiniciar os emuladores');
          return sair(EstadoExecucao.parcial, 'ambiente');
        }
        // A pausa pode ter consumido o que restava do orçamento ou ter sido
        // interrompida por Ctrl+C.
        atualizarTempo();
        if (!_seguidor && execucao.tempoAtivoMs >= execucao.orcamentoMs) {
          return sair(EstadoExecucao.parcial, 'orcamento');
        }
        if (_parar) {
          return sair(EstadoExecucao.parcial, 'interrompido');
        }
      }
      if (coord != null &&
          rodouCiclo &&
          !await passar('pronto-para-reiniciar', ultimo())) {
        return pararPorBarreira('pronto-para-reiniciar');
      }
      if (!await prontoParaCiclo()) {
        _registrar('observador sem conexão com nenhum relay: execução parada');
        return sair(EstadoExecucao.parcial, 'ambiente');
      }

      final numero = ultimo() + 1;
      if (coord != null && !await passar('inicio-ciclo', numero)) {
        return pararPorBarreira('inicio-ciclo');
      }
      // O Ctrl+C pode ter chegado enquanto se esperava o outro lado na barreira.
      if (_parar) return sair(EstadoExecucao.parcial, 'interrompido');
      contexto.prazoGlobal = inicioExecucao.add(
        Duration(milliseconds: execucao.orcamentoMs - tempoAtivoInicial),
      );
      if (_parar) contexto.prazoGlobal = relogio.agora();
      _registrar('ciclo $numero: início');
      contexto.observador.cicloAtual = numero;
      var resultado = await executarCiclo(numero);
      if (coord != null) {
        final fundido = await trocar(numero, resultado);
        if (fundido == null) return pararPorBarreira('fim-ciclo');
        resultado = fundido;
      }
      final ciclo = resultado.ciclo;
      repositorio.acrescentarCiclo(ciclo);
      ciclos = [...ciclos, ciclo];
      rodouCiclo = true;
      atualizarTempo();
      _registrar(
        'ciclo $numero: ${ciclo.resultado}'
        '${ciclo.etapaFalha != null ? ' em ${ciclo.etapaFalha}' : ''}'
        '${ciclo.origem != null ? ' (${ciclo.origem})' : ''}'
        '${ciclo.valido ? '' : ' [não válido]'}',
      );
      execucao.telasCapturadas = contexto.telasCapturadas.toList();
      repositorio.gravarCheckpoint(execucao);

      if (resultado.limiteDiarioOrs) {
        return sair(EstadoExecucao.parcial, 'limite_diario_ors');
      }
      if (ciclo.resultado == 'interrompido') {
        final motivo = _parar ? 'interrompido' : 'orcamento';
        return sair(EstadoExecucao.parcial, motivo);
      }
      if (resultado.recuperacaoFalhou) {
        _registrar('não foi possível devolver os apps ao estado inicial');
        return sair(EstadoExecucao.parcial, 'ambiente');
      }
    }
  }
}
