import 'checkpoint.dart';
import 'ciclo.dart';
import 'relogio.dart';

/// Laço da execução (FR-012 a FR-019): ciclos até a meta de válidos, com teto
/// de ciclos executados, orçamento de tempo ativo, checkpoint a cada ciclo,
/// reposição de ciclos externos e parada controlada.

class ExecutorExecucao {
  ExecutorExecucao({
    required this.execucao,
    required this.repositorio,
    required this.relogio,
    required this.contexto,
    required this.executarCiclo,
    required this.prontoParaCiclo,
    this.log,
  });

  final Execucao execucao;
  final RepositorioExecucao repositorio;
  final Relogio relogio;
  final ContextoCiclo contexto;

  /// Roda um ciclo de número [numero].
  final Future<ResultadoCiclo> Function(int numero) executarCiclo;

  /// Confirma que o observador está conectado e inscrito (FR-023). Falso ⇒ o
  /// execução para como parcial por `ambiente`.
  final Future<bool> Function() prontoParaCiclo;

  final void Function(String)? log;

  bool _parar = false;

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
    while (true) {
      final c = Contadores.de(ciclos);
      if (c.validos >= execucao.metaValidos) {
        encerrar(EstadoExecucao.concluido, null);
        return execucao;
      }
      if (c.executados >= execucao.tetoExecutados) {
        encerrar(EstadoExecucao.parcial, 'teto_executados');
        return execucao;
      }
      atualizarTempo();
      if (execucao.tempoAtivoMs >= execucao.orcamentoMs) {
        encerrar(EstadoExecucao.parcial, 'orcamento');
        return execucao;
      }
      if (_parar) {
        encerrar(EstadoExecucao.parcial, 'interrompido');
        return execucao;
      }
      if (!await prontoParaCiclo()) {
        _registrar('observador sem conexão com nenhum relay: execução parada');
        encerrar(EstadoExecucao.parcial, 'ambiente');
        return execucao;
      }

      final numero = ciclos.isEmpty
          ? 1
          : ciclos.map((x) => x.ciclo).reduce((a, b) => a > b ? a : b) + 1;
      contexto.prazoGlobal = inicioExecucao.add(
        Duration(milliseconds: execucao.orcamentoMs - tempoAtivoInicial),
      );
      if (_parar) contexto.prazoGlobal = relogio.agora();
      _registrar('ciclo $numero: início');
      contexto.observador.cicloAtual = numero;
      final resultado = await executarCiclo(numero);
      final ciclo = resultado.ciclo;
      repositorio.acrescentarCiclo(ciclo);
      ciclos = [...ciclos, ciclo];
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
        encerrar(EstadoExecucao.parcial, 'limite_diario_ors');
        return execucao;
      }
      if (ciclo.resultado == 'interrompido') {
        final motivo = _parar ? 'interrompido' : 'orcamento';
        encerrar(EstadoExecucao.parcial, motivo);
        return execucao;
      }
      if (resultado.recuperacaoFalhou) {
        _registrar('não foi possível devolver os apps ao estado inicial');
        encerrar(EstadoExecucao.parcial, 'ambiente');
        return execucao;
      }
    }
  }
}
