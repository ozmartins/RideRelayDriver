import 'config.dart';

/// Linha de comando do roteiro (`contracts/cli.md`).

class OpcoesInvalidas implements Exception {
  OpcoesInvalidas(this.mensagem);

  final String mensagem;

  @override
  String toString() => mensagem;
}

enum Comando { executar, preparar, relatorio, verificarSaida, zerar, ajuda }

class Opcoes {
  const Opcoes({
    required this.comando,
    this.retomar = false,
    this.ensaio = false,
    this.metaValidos,
    this.orcamentoMin,
    this.avdDoMotorista = avdMotorista,
    this.avdDoPassageiro = avdPassageiro,
    this.saida = 'e2e_saida',
    this.exigirChaveOrs = false,
    this.semPreparo = false,
    this.semJanela = false,
  });

  final Comando comando;
  final bool retomar;
  final bool ensaio;
  final int? metaValidos;
  final int? orcamentoMin;
  final String avdDoMotorista;
  final String avdDoPassageiro;
  final String saida;
  final bool exigirChaveOrs;
  final bool semPreparo;
  final bool semJanela;
}

const String textoDeAjuda =
    '''
Uso: dart run tool/e2e/e2e.dart <comando> [opções]

Comandos:
  --executar             executa a avaliação completa (60 ciclos válidos, até 12 h)
  --preparar             sobe os dois emuladores e instala os apps, sem executar nada
  --retomar              continua a execução a partir do checkpoint
  --relatorio            gera relatorio.md e dados/*.csv a partir da execução gravada
  --verificar-saida      varre a saída em busca de padrões proibidos (saída 1 se achar)
  --zerar                apaga a execução e o relatório da saída, após confirmação digitada
  --ajuda                esta mensagem

Opções:
  --ensaio               grava em <saida>/ensaio-<data>/; não vale para o TCC
  --meta-validos N       (só com --ensaio) meta menor que 60
  --orcamento-min N      (só com --ensaio) orçamento menor que 12 h
  --avd-motorista NOME   (padrão $avdMotorista)
  --avd-passageiro NOME  (padrão $avdPassageiro)
  --saida DIR            pasta de saída (padrão e2e_saida)
  --sem-preparo          não sobe emuladores nem instala apps (já estão prontos)
  --sem-janela           emuladores sem janela (-no-window), se o roteiro os iniciar
  --exigir-chave-ors     recusa se a chave do openrouteservice não for encontrada

Códigos de saída: 0 ok; 1 execução parcial ou varredura reprovada; 2 uso incorreto
ou pré-condição não atendida (nada foi apagado).
''';

Opcoes parseOpcoes(List<String> args) {
  final valores = <String, String>{};
  final flags = <String>{};
  const comValor = {
    'meta-validos',
    'orcamento-min',
    'avd-motorista',
    'avd-passageiro',
    'saida',
  };
  const semValor = {
    'executar',
    'retomar',
    'ensaio',
    'relatorio',
    'verificar-saida',
    'zerar',
    'ajuda',
    'exigir-chave-ors',
    'preparar',
    'sem-preparo',
    'sem-janela',
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

  final executa =
      flags.contains('executar') ||
      flags.contains('retomar') ||
      flags.contains('ensaio');
  final comandos = [
    if (flags.contains('preparar')) Comando.preparar,
    if (flags.contains('relatorio')) Comando.relatorio,
    if (flags.contains('verificar-saida')) Comando.verificarSaida,
    if (flags.contains('zerar')) Comando.zerar,
    if (flags.contains('ajuda')) Comando.ajuda,
  ];
  if (comandos.isEmpty && !executa) {
    throw OpcoesInvalidas(
      'informe um comando (--executar, --retomar, --preparar, --relatorio, --verificar-saida, --zerar)',
    );
  }
  if (comandos.length > 1 || (comandos.isNotEmpty && executa)) {
    throw OpcoesInvalidas('use um comando por vez');
  }
  final comando = comandos.isEmpty ? Comando.executar : comandos.single;
  if (comando == Comando.ajuda) return const Opcoes(comando: Comando.ajuda);

  if (flags.contains('sem-preparo') && comando == Comando.preparar) {
    throw OpcoesInvalidas('--sem-preparo não combina com --preparar');
  }
  final ensaio = flags.contains('ensaio');
  final meta = inteiro('meta-validos');
  final orcamento = inteiro('orcamento-min');
  if ((meta != null || orcamento != null) && !ensaio) {
    throw OpcoesInvalidas(
      '--meta-validos e --orcamento-min só valem com --ensaio',
    );
  }
  if (meta != null && meta > metaValidosDaExecucao) {
    throw OpcoesInvalidas(
      '--meta-validos não pode passar de $metaValidosDaExecucao',
    );
  }
  if (orcamento != null && orcamento > const Limites().execucao.inMinutes) {
    throw OpcoesInvalidas(
      '--orcamento-min não pode passar de ${const Limites().execucao.inMinutes}',
    );
  }

  return Opcoes(
    comando: comando,
    retomar: flags.contains('retomar'),
    ensaio: ensaio,
    metaValidos: meta,
    orcamentoMin: orcamento,
    avdDoMotorista: valores['avd-motorista'] ?? avdMotorista,
    avdDoPassageiro: valores['avd-passageiro'] ?? avdPassageiro,
    saida: valores['saida'] ?? 'e2e_saida',
    exigirChaveOrs: flags.contains('exigir-chave-ors'),
    semPreparo: flags.contains('sem-preparo'),
    semJanela: flags.contains('sem-janela'),
  );
}
