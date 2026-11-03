import 'config.dart';

/// Linha de comando do roteiro (`contracts/cli.md`).

class OpcoesInvalidas implements Exception {
  OpcoesInvalidas(this.mensagem);

  final String mensagem;

  @override
  String toString() => mensagem;
}

enum Papel { motorista, passageiro }

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
    this.semReinicioEntreCiclos = false,
    this.reinicioEntreCiclos = false,
    this.papel,
    this.coordenador,
    this.porta = portaCoordenacaoPadrao,
    this.token,
    this.juntar,
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
  final bool semReinicioEntreCiclos;

  /// Só com `--papel`: liga o reinício do emulador entre ciclos, que nesse modo
  /// vem desligado (um emulador por máquina não disputa memória).
  final bool reinicioEntreCiclos;

  /// Duas máquinas (`contracts/coordenacao.md`); nulo = modo de uma máquina.
  final Papel? papel;

  /// `ip:porta` do coordenador (só com `--papel motorista`).
  final String? coordenador;
  final int porta;
  final String? token;

  /// Só com `--relatorio`: pasta da execução da outra máquina, para juntar.
  final String? juntar;
}

const int portaCoordenacaoPadrao = 8765;

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
  --sem-reinicio-entre-ciclos
                         não desliga e sobe os emuladores entre um ciclo e o próximo
  --reinicio-entre-ciclos
                         (só com --papel) reinicia o emulador entre os ciclos; desligado
                         por padrão nesse modo
  --papel P              motorista|passageiro: opera só o emulador do papel, em duas
                         máquinas; o passageiro coordena (contracts/coordenacao.md)
  --coordenador IP:PORTA (só com --papel motorista) endereço do coordenador
  --porta N              (só com --papel passageiro; padrão $portaCoordenacaoPadrao)
  --token SEGREDO        (obrigatório com --papel) segredo compartilhado
  --juntar DIR           (só com --relatorio) junta a execução da outra máquina, copiada
                         para DIR (a pasta `execucao` dela), num relatório só
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
    'papel',
    'coordenador',
    'porta',
    'token',
    'juntar',
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
    'sem-reinicio-entre-ciclos',
    'reinicio-entre-ciclos',
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

  if (flags.contains('reinicio-entre-ciclos') && valores['papel'] == null) {
    throw OpcoesInvalidas('--reinicio-entre-ciclos exige --papel');
  }
  if (valores.containsKey('juntar') && comando != Comando.relatorio) {
    throw OpcoesInvalidas('--juntar só vale com --relatorio');
  }
  Papel? papel;
  final papelTexto = valores['papel'];
  if (papelTexto != null) {
    papel = Papel.values.where((p) => p.name == papelTexto).firstOrNull;
    if (papel == null) {
      throw OpcoesInvalidas('--papel inválido: $papelTexto');
    }
  }
  final coordenador = valores['coordenador'];
  final token = valores['token'];
  if (papel == null &&
      (coordenador != null || token != null || valores.containsKey('porta'))) {
    throw OpcoesInvalidas('--coordenador, --porta e --token exigem --papel');
  }
  if (papel != null) {
    if (token == null || token.isEmpty) {
      throw OpcoesInvalidas('--papel exige --token');
    }
    if (papel == Papel.motorista && coordenador == null) {
      throw OpcoesInvalidas('--papel motorista exige --coordenador IP:PORTA');
    }
    if (papel == Papel.passageiro && coordenador != null) {
      throw OpcoesInvalidas('--coordenador só vale com --papel motorista');
    }
    if (papel == Papel.motorista && valores.containsKey('porta')) {
      throw OpcoesInvalidas('--porta só vale com --papel passageiro');
    }
    if (comando == Comando.relatorio || comando == Comando.zerar) {
      throw OpcoesInvalidas('--papel não combina com --relatorio nem --zerar');
    }
  }
  if (coordenador != null &&
      !RegExp(r'^[^:\s]+:\d{1,5}$').hasMatch(coordenador)) {
    throw OpcoesInvalidas('--coordenador inválido: $coordenador');
  }
  final porta = inteiro('porta') ?? portaCoordenacaoPadrao;
  if (porta > 65535) throw OpcoesInvalidas('--porta inválida: $porta');

  return Opcoes(
    comando: comando,
    papel: papel,
    coordenador: coordenador,
    porta: porta,
    token: token,
    juntar: valores['juntar'],
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
    semReinicioEntreCiclos: flags.contains('sem-reinicio-entre-ciclos'),
    reinicioEntreCiclos: flags.contains('reinicio-entre-ciclos'),
  );
}
