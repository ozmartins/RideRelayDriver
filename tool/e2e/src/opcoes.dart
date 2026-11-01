import 'config.dart';

/// Linha de comando do roteiro (`contracts/cli.md`).

class OpcoesInvalidas implements Exception {
  OpcoesInvalidas(this.mensagem);

  final String mensagem;

  @override
  String toString() => mensagem;
}

enum Comando { periodo, relatorio, verificarSaida, ajuda }

class Opcoes {
  const Opcoes({
    required this.comando,
    this.periodo,
    this.retomar = false,
    this.ensaio = false,
    this.metaValidos,
    this.orcamentoMin,
    this.tetoPeriodo1Executados,
    this.avdDoMotorista = avdMotorista,
    this.avdDoPassageiro = avdPassageiro,
    this.saida = 'e2e_saida',
    this.exigirChaveOrs = false,
  });

  final Comando comando;

  /// 1 ou 2.
  final int? periodo;
  final bool retomar;
  final bool ensaio;
  final int? metaValidos;
  final int? orcamentoMin;
  final int? tetoPeriodo1Executados;
  final String avdDoMotorista;
  final String avdDoPassageiro;
  final String saida;
  final bool exigirChaveOrs;
}

const String textoDeAjuda =
    '''
Uso: dart run tool/e2e/e2e.dart <comando> [opções]

Comandos:
  --periodo 1|2          executa um período completo (30 ciclos válidos, até 3 h)
  --periodo N --retomar  continua o período N a partir do checkpoint
  --relatorio            gera relatorio.md e dados/*.csv a partir dos períodos gravados
  --verificar-saida      varre a saída em busca de padrões proibidos (saída 1 se achar)
  --ajuda                esta mensagem

Opções:
  --ensaio               grava em <saida>/ensaio-<data>/; não vale para o TCC
  --meta-validos N       (só com --ensaio) meta menor que 30
  --orcamento-min N      (só com --ensaio) orçamento menor que 3 h
  --teto-periodo-1-executados N   (só no período 2) ciclos executados no período 1
  --avd-motorista NOME   (padrão $avdMotorista)
  --avd-passageiro NOME  (padrão $avdPassageiro)
  --saida DIR            pasta de saída (padrão e2e_saida)
  --exigir-chave-ors     recusa se a chave do openrouteservice não for encontrada

Códigos de saída: 0 ok; 1 período parcial ou varredura reprovada; 2 uso incorreto
ou pré-condição não atendida (nada foi apagado).
''';

Opcoes parseOpcoes(List<String> args) {
  final valores = <String, String>{};
  final flags = <String>{};
  const comValor = {
    'periodo',
    'meta-validos',
    'orcamento-min',
    'teto-periodo-1-executados',
    'avd-motorista',
    'avd-passageiro',
    'saida',
  };
  const semValor = {
    'retomar',
    'ensaio',
    'relatorio',
    'verificar-saida',
    'ajuda',
    'exigir-chave-ors',
  };
  for (var i = 0; i < args.length; i++) {
    var a = args[i];
    if (!a.startsWith('--')) throw OpcoesInvalidas('argumento inesperado: $a');
    a = a.substring(2);
    String? inline;
    final eq = a.indexOf('=');
    if (eq >= 0) {
      inline = a.substring(eq + 1);
      a = a.substring(0, eq);
    }
    if (semValor.contains(a)) {
      flags.add(a);
    } else if (comValor.contains(a)) {
      final v = inline ?? (i + 1 < args.length ? args[++i] : null);
      if (v == null) throw OpcoesInvalidas('--$a precisa de um valor');
      valores[a] = v;
    } else {
      throw OpcoesInvalidas('opção desconhecida: --$a');
    }
  }

  int? inteiro(String nome, {int minimo = 1}) {
    final v = valores[nome];
    if (v == null) return null;
    final n = int.tryParse(v);
    if (n == null || n < minimo) {
      throw OpcoesInvalidas('--$nome inválido: $v');
    }
    return n;
  }

  final comandos = [
    if (valores.containsKey('periodo')) Comando.periodo,
    if (flags.contains('relatorio')) Comando.relatorio,
    if (flags.contains('verificar-saida')) Comando.verificarSaida,
    if (flags.contains('ajuda')) Comando.ajuda,
  ];
  if (comandos.isEmpty) {
    throw OpcoesInvalidas(
      'informe um comando (--periodo, --relatorio, --verificar-saida)',
    );
  }
  if (comandos.length > 1) {
    throw OpcoesInvalidas('use um comando por vez');
  }
  final comando = comandos.single;
  if (comando == Comando.ajuda) return const Opcoes(comando: Comando.ajuda);

  final periodo = inteiro('periodo');
  if (comando == Comando.periodo && periodo != 1 && periodo != 2) {
    throw OpcoesInvalidas('--periodo deve ser 1 ou 2');
  }
  final ensaio = flags.contains('ensaio');
  final meta = inteiro('meta-validos');
  final orcamento = inteiro('orcamento-min');
  final teto1 = inteiro('teto-periodo-1-executados', minimo: 0);
  if ((meta != null || orcamento != null) && !ensaio) {
    throw OpcoesInvalidas(
      '--meta-validos e --orcamento-min só valem com --ensaio',
    );
  }
  if (meta != null && meta > metaValidosPorPeriodo) {
    throw OpcoesInvalidas(
      '--meta-validos não pode passar de $metaValidosPorPeriodo',
    );
  }
  if (orcamento != null && orcamento > const Limites().periodo.inMinutes) {
    throw OpcoesInvalidas('--orcamento-min não pode passar de 180');
  }
  if (teto1 != null && periodo != 2) {
    throw OpcoesInvalidas('--teto-periodo-1-executados só vale no período 2');
  }
  if (flags.contains('retomar') && comando != Comando.periodo) {
    throw OpcoesInvalidas('--retomar só vale com --periodo');
  }
  if (ensaio && comando != Comando.periodo) {
    throw OpcoesInvalidas('--ensaio só vale com --periodo');
  }

  return Opcoes(
    comando: comando,
    periodo: periodo,
    retomar: flags.contains('retomar'),
    ensaio: ensaio,
    metaValidos: meta,
    orcamentoMin: orcamento,
    tetoPeriodo1Executados: teto1,
    avdDoMotorista: valores['avd-motorista'] ?? avdMotorista,
    avdDoPassageiro: valores['avd-passageiro'] ?? avdPassageiro,
    saida: valores['saida'] ?? 'e2e_saida',
    exigirChaveOrs: flags.contains('exigir-chave-ors'),
  );
}
