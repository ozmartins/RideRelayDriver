import 'checkpoint.dart';
import 'ciclo.dart';
import 'relogio.dart';

/// Laço de um período (FR-012 a FR-019): ciclos até a meta de válidos, com teto
/// de ciclos executados, orçamento de tempo ativo, checkpoint a cada ciclo,
/// reposição de ciclos externos e parada controlada.

class ExecutorPeriodo {
  ExecutorPeriodo({
    required this.periodo,
    required this.repositorio,
    required this.relogio,
    required this.contexto,
    required this.executarCiclo,
    required this.prontoParaCiclo,
    this.log,
  });

  final Periodo periodo;
  final RepositorioPeriodo repositorio;
  final Relogio relogio;
  final ContextoCiclo contexto;

  /// Roda um ciclo de número [numero].
  final Future<ResultadoCiclo> Function(int numero) executarCiclo;

  /// Confirma que o observador está conectado e inscrito (FR-023). Falso ⇒ o
  /// período para como parcial por `ambiente`.
  final Future<bool> Function() prontoParaCiclo;

  final void Function(String)? log;

  bool _parar = false;

  /// Pedido de parada (Ctrl+C): o ciclo em andamento vira `interrompido`.
  void pedirParada() {
    _parar = true;
    contexto.prazoGlobal = relogio.agora();
  }

  void _registrar(String m) => log?.call(m);

  /// Executa (ou retoma) o período. Devolve o checkpoint final, já gravado.
  Future<Periodo> executar() async {
    final inicioExecucao = relogio.agora();
    final tempoAtivoInicial = periodo.tempoAtivoMs;
    final execucao = <String, Object?>{
      'inicio_utc': inicioExecucao.toIso8601String(),
      'fim_utc': null,
      'motivo_parada': null,
    };
    periodo.execucoes = [...periodo.execucoes, execucao];
    periodo.estado = EstadoPeriodo.emAndamento;
    periodo.motivoParcial = null;
    repositorio.gravarCheckpoint(periodo);

    void atualizarTempo() {
      periodo.tempoAtivoMs =
          tempoAtivoInicial +
          relogio.agora().difference(inicioExecucao).inMilliseconds;
    }

    void encerrar(EstadoPeriodo estado, String? motivo) {
      atualizarTempo();
      periodo.estado = estado;
      periodo.motivoParcial = motivo;
      execucao['fim_utc'] = relogio.agora().toIso8601String();
      execucao['motivo_parada'] = motivo ?? 'meta_atingida';
      repositorio.gravarCheckpoint(periodo);
    }

    var ciclos = repositorio.lerCiclos();
    while (true) {
      final c = Contadores.de(ciclos);
      if (c.validos >= periodo.metaValidos) {
        encerrar(EstadoPeriodo.concluido, null);
        return periodo;
      }
      if (c.executados >= periodo.tetoExecutados) {
        encerrar(EstadoPeriodo.parcial, 'teto_executados');
        return periodo;
      }
      atualizarTempo();
      if (periodo.tempoAtivoMs >= periodo.orcamentoMs) {
        encerrar(EstadoPeriodo.parcial, 'orcamento');
        return periodo;
      }
      if (_parar) {
        encerrar(EstadoPeriodo.parcial, 'interrompido');
        return periodo;
      }
      if (!await prontoParaCiclo()) {
        _registrar('observador sem conexão com nenhum relay: período parado');
        encerrar(EstadoPeriodo.parcial, 'ambiente');
        return periodo;
      }

      final numero = ciclos.isEmpty
          ? 1
          : ciclos.map((x) => x.ciclo).reduce((a, b) => a > b ? a : b) + 1;
      contexto.prazoGlobal = inicioExecucao.add(
        Duration(milliseconds: periodo.orcamentoMs - tempoAtivoInicial),
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
      periodo.telasCapturadas = contexto.telasCapturadas.toList();
      repositorio.gravarCheckpoint(periodo);

      if (resultado.limiteDiarioOrs) {
        encerrar(EstadoPeriodo.parcial, 'limite_diario_ors');
        return periodo;
      }
      if (ciclo.resultado == 'interrompido') {
        final motivo = _parar ? 'interrompido' : 'orcamento';
        encerrar(EstadoPeriodo.parcial, motivo);
        return periodo;
      }
      if (resultado.recuperacaoFalhou) {
        _registrar('não foi possível devolver os apps ao estado inicial');
        encerrar(EstadoPeriodo.parcial, 'ambiente');
        return periodo;
      }
    }
  }
}
