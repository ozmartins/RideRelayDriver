import 'adb.dart';
import 'checkpoint.dart';
import 'classificacao.dart';
import 'config.dart';
import 'evidencia.dart';
import 'observador.dart';
import 'relogio.dart';
import 'telas.dart';
import 'ui.dart';

/// Um ciclo do fluxo completo da corrida (FR-001, FR-002): etapas E01–E12 e a
/// volta ao estado inicial (R), com espera por condição e timeout em cada uma.

/// Falha de uma etapa. Carrega o que a classificação precisa saber.
class FalhaEtapa implements Exception {
  FalhaEtapa(
    this.motivo, {
    this.timeout = false,
    this.efeitoRemoto = false,
    this.ciclo = false,
  });

  final String motivo;

  /// A condição esperada não apareceu dentro do prazo.
  final bool timeout;

  /// A condição que faltou é o efeito de um evento no outro app.
  final bool efeitoRemoto;

  /// O que estourou foi o tempo total do ciclo.
  final bool ciclo;

  @override
  String toString() => 'FalhaEtapa: $motivo';
}

/// O orçamento do período (ou um pedido de parada) acabou no meio do ciclo: o
/// ciclo é gravado como `interrompido`, nem válido nem falha.
class CicloInterrompido implements Exception {
  const CicloInterrompido();
}

class EventoEsperado {
  const EventoEsperado(this.kind, this.autor, this.apos);

  final int kind;
  final String autor;
  final DateTime apos;
}

class ContextoCiclo {
  ContextoCiclo({
    required this.adb,
    required this.serialMotorista,
    required this.serialPassageiro,
    required this.observador,
    required this.evidencia,
    required this.relogio,
    required this.periodo,
    this.limites = const Limites(),
    Set<String>? telasCapturadas,
  }) : telasCapturadas = telasCapturadas ?? <String>{};

  final Adb adb;
  final String serialMotorista;
  final String serialPassageiro;
  final Observador observador;
  final Evidencia evidencia;
  final Relogio relogio;

  /// `1`, `2` ou `ensaio`.
  final String periodo;
  final Limites limites;

  /// Telas fixas já capturadas neste período (FR-027).
  final Set<String> telasCapturadas;

  /// Instante em que o orçamento do período acaba (ou agora, num pedido de
  /// parada). Definido pelo executor do período antes de cada ciclo.
  DateTime? prazoGlobal;
}

class ResultadoCiclo {
  const ResultadoCiclo({
    required this.ciclo,
    this.limiteDiarioOrs = false,
    this.recuperacaoFalhou = false,
  });

  final Ciclo ciclo;

  /// A falha foi 429 da OpenRouteService: parar o período (FR-021).
  final bool limiteDiarioOrs;

  /// O roteiro não conseguiu devolver os apps ao estado inicial (D8).
  final bool recuperacaoFalhou;
}

const _kindsDeAnomalia = {20004, 20006, 20012, 20013};

class ExecutorCiclo {
  ExecutorCiclo(this.ctx);

  final ContextoCiclo ctx;

  Adb get _adb => ctx.adb;
  String get _mot => ctx.serialMotorista;
  String get _pax => ctx.serialPassageiro;
  Relogio get _relogio => ctx.relogio;

  // Estado do ciclo em andamento.
  late int _numero;
  late DateTime _inicio;
  late DateTime _prazoDoCiclo;
  late DateTime _prazoDaEtapa;
  final List<Etapa> _etapas = [];
  final List<String> _capturas = [];
  final List<String> _desvios = [];
  List<Acao> _acoes = [];
  EventoEsperado? _esperado;
  bool _acaoDaEtapa = false;
  String? _ultimoTextoMot;
  String? _ultimoTextoPax;

  String _prefixo(String rotulo, String papel) =>
      'c${_numero.toString().padLeft(3, '0')}-$rotulo-$papel';

  Future<ResultadoCiclo> executar(int numero) async {
    _numero = numero;
    _inicio = _relogio.agora();
    _prazoDoCiclo = _inicio.add(ctx.limites.ciclo);
    _etapas.clear();
    _capturas.clear();
    _desvios.clear();
    _esperado = null;
    _ultimoTextoMot = null;
    _ultimoTextoPax = null;

    String? etapaFalha;
    Classificacao? classificacao;
    var limiteOrs = false;
    var recuperacaoFalhou = false;
    var interrompido = false;
    var fim = _relogio.agora();

    try {
      await _adb.limparLogcat(_mot);
      await _adb.limparLogcat(_pax);
    } on AdbFalha {
      // o primeiro uso do adb na etapa E01 acusa a falha de ambiente
    }

    final passos = <(String, Duration, Future<void> Function())>[
      ('E01', ctx.limites.etapa, _e01EstadoInicial),
      ('E02', ctx.limites.etapaComBusca, _e02Solicitar),
      ('E03', ctx.limites.etapa, _e03MotoristaRecebe),
      ('E04', ctx.limites.etapaComRota, _e04Orcamento),
      ('E05', ctx.limites.etapa, _e05Selecao),
      ('E06', ctx.limites.etapa, _e06Inicio),
      ('E07', ctx.limites.etapa, _e07Chegada),
      ('E08', ctx.limites.etapa, _e08Encontro),
      ('E09', ctx.limites.etapa, _e09Destino),
      ('E10', ctx.limites.etapa, _e10ConfirmarDestino),
      ('E11', ctx.limites.etapa, _e11Avaliacoes),
      ('E12', ctx.limites.etapa, _e12Recibos),
    ];

    for (final (id, limite, corpo) in passos) {
      final falha = await _executarEtapa(id, limite, corpo, noCiclo: true);
      if (falha is CicloInterrompido) {
        interrompido = true;
        etapaFalha = id;
        fim = _relogio.agora();
        break;
      }
      if (falha != null) {
        etapaFalha = id;
        fim = _relogio.agora();
        final c = await _tratarFalha(id, falha);
        classificacao = c.$1;
        limiteOrs = c.$2;
        break;
      }
    }

    if (etapaFalha == null) {
      // R: volta ao estado inicial, fora do tempo do ciclo (limite próprio).
      fim = _relogio.agora();
      final falha = await _executarEtapa(
        'R',
        ctx.limites.voltaAoInicio,
        _voltaAoEstadoInicial,
        noCiclo: false,
      );
      if (falha is CicloInterrompido) {
        interrompido = true;
        etapaFalha = 'R';
      } else if (falha != null) {
        etapaFalha = 'R';
        final c = await _tratarFalha('R', falha);
        classificacao = c.$1;
        limiteOrs = c.$2;
      }
      fim = _relogio.agora();
    }

    if (etapaFalha != null && !interrompido) {
      recuperacaoFalhou = !await _recuperar();
    }

    final janela = ctx.observador.naJanela(_inicio, fim);
    final anomalias = {
      for (final e in janela)
        if (_kindsDeAnomalia.contains(e.kind)) e.kind,
    }.toList()..sort();
    final ids = {for (final e in janela) e.id}.toList()..sort();

    final falhou = etapaFalha != null;
    final externo = classificacao?.origem == OrigemFalha.servicoExterno;
    final ciclo = Ciclo(
      ciclo: numero,
      periodo: ctx.periodo,
      inicioUtc: _inicio,
      fimUtc: fim,
      etapas: List.of(_etapas),
      resultado: interrompido ? 'interrompido' : (falhou ? 'falha' : 'sucesso'),
      valido: !externo && !interrompido,
      etapaFalha: etapaFalha,
      origem: classificacao?.origem.codigo,
      servicoExterno: classificacao?.servicoExterno,
      origemBruta: classificacao?.origemBruta,
      sinalExterno: classificacao?.sinal?.toJson(),
      capturas: List.of(_capturas),
      anomalias: anomalias,
      desvios: List.of(_desvios),
      eventos: ids,
    );
    return ResultadoCiclo(
      ciclo: ciclo,
      limiteDiarioOrs: limiteOrs,
      recuperacaoFalhou: recuperacaoFalhou,
    );
  }

  /// Executa uma etapa e a registra. Devolve a falha, ou `null` se deu certo.
  Future<Object?> _executarEtapa(
    String id,
    Duration limite,
    Future<void> Function() corpo, {
    required bool noCiclo,
  }) async {
    final inicio = _relogio.agora();
    _acoes = [];
    _acaoDaEtapa = false;
    Object? falha;
    String resultado = 'ok';
    if (_globalEstourado()) {
      falha = const CicloInterrompido();
      resultado = 'interrompido';
    } else if (noCiclo && !_relogio.agora().isBefore(_prazoDoCiclo)) {
      falha = FalhaEtapa(
        'o ciclo excedeu o tempo máximo',
        timeout: true,
        ciclo: true,
      );
      resultado = 'timeout';
    } else {
      _prazoDaEtapa = inicio.add(limite);
      try {
        await corpo();
      } on CicloInterrompido catch (e) {
        falha = e;
        resultado = 'interrompido';
      } on FalhaEtapa catch (e) {
        falha = e;
        resultado = e.timeout ? 'timeout' : 'falha';
      } on AdbFalha catch (e) {
        falha = e;
        resultado = 'falha';
      }
    }
    _etapas.add(
      Etapa(
        id: id,
        resultado: resultado,
        inicioUtc: inicio,
        fimUtc: _relogio.agora(),
        limiteMs: limite.inMilliseconds,
        acoes: List.of(_acoes),
      ),
    );
    return falha;
  }

  bool _globalEstourado() {
    final g = ctx.prazoGlobal;
    return g != null && !_relogio.agora().isBefore(g);
  }

  // ---- falha: evidências e classificação -----------------------------------

  Future<(Classificacao, bool)> _tratarFalha(String etapa, Object falha) async {
    final adbFora = falha is AdbFalha;
    final prefixoMot = _prefixo('$etapa-falha', 'motorista');
    final prefixoPax = _prefixo('$etapa-falha', 'passageiro');
    if (!adbFora) {
      _capturas.addAll(
        await ctx.evidencia.capturar(
          serial: _mot,
          prefixo: prefixoMot,
          comDump: true,
        ),
      );
      _capturas.addAll(
        await ctx.evidencia.capturar(
          serial: _pax,
          prefixo: prefixoPax,
          comDump: true,
        ),
      );
    }

    var sinal = detectarSinalExterno(
      textoTela: '${_ultimoTextoMot ?? ''}\n${_ultimoTextoPax ?? ''}',
    );
    if (!adbFora) {
      try {
        final linhas = [...await _adb.logcat(_mot), ...await _adb.logcat(_pax)];
        sinal ??= detectarSinalExterno(linhasLogcat: linhas);
      } on AdbFalha {
        // sem logcat: a classificação segue com o que já tem
      }
    }

    var processoAusente = false;
    if (!adbFora) {
      try {
        processoAusente =
            !await _adb.processoVivo(_mot, pacoteMotorista) ||
            !await _adb.processoVivo(_pax, pacotePassageiro);
      } on AdbFalha {
        processoAusente = false;
      }
    }

    final esperado = _esperado;
    final remoto = falha is FalhaEtapa && falha.efeitoRemoto;
    final evidencias = Evidencias(
      adbIndisponivel: adbFora,
      observadorSemRelays:
          ctx.observador.relaysProntos.isEmpty && ctx.observador.todosCaidos,
      sinalExterno: sinal,
      acaoExecutada: _acaoDaEtapa || esperado != null,
      eventoEsperado: esperado != null,
      eventoObservado:
          esperado != null &&
          ctx.observador.vistoEmAlgumRelay(
            kind: esperado.kind,
            autor: esperado.autor,
            apos: esperado.apos,
          ),
      efeitoRemotoAusente: remoto,
      processoAppAusente: processoAusente,
    );
    return (classificar(evidencias), limiteDiarioOrsEsgotado(sinal));
  }

  /// Devolve os apps ao mapa ocioso pelos botões de cancelar (D8). Falso se não
  /// conseguir.
  Future<bool> _recuperar() async {
    try {
      final fim = _relogio.agora().add(ctx.limites.voltaAoInicio);
      while (_relogio.agora().isBefore(fim)) {
        final telaMot = Tela.parse(await _adb.dump(_mot));
        final telaPax = Tela.parse(await _adb.dump(_pax));
        if (_ocioso(telaMot, telaPax)) return true;
        await _fecharPendencias(_mot, telaMot, [
          Rotulos.cancelarMotorista,
          'Pular',
        ]);
        await _fecharPendencias(_pax, telaPax, [
          Rotulos.cancelarPassageiro,
          'Pular',
        ]);
        await _relogio.dormir(const Duration(seconds: 2));
      }
      final telaMot = Tela.parse(await _adb.dump(_mot));
      final telaPax = Tela.parse(await _adb.dump(_pax));
      return _ocioso(telaMot, telaPax);
    } on AdbFalha {
      return false;
    }
  }

  bool _ocioso(Tela mot, Tela pax) =>
      pax.tem(Rotulos.campoDestino) &&
      !pax.tem(Rotulos.aguardandoOrcamentos) &&
      (mot.tem(Rotulos.motoristaOnline) || mot.tem(Rotulos.motoristaOffline)) &&
      !mot.tem(Rotulos.corridaEmAndamento) &&
      !mot.tem(Rotulos.solicitacaoDeCorrida);

  Future<void> _fecharPendencias(
    String serial,
    Tela tela,
    List<String> rotulos,
  ) async {
    for (final r in rotulos) {
      final b = tela.botao(r);
      if (b != null) {
        await _adb.tocar(serial, b.limites.centroX, b.limites.centroY);
        return;
      }
    }
  }

  // ---- utilitários de etapa -----------------------------------------------

  Future<Tela> _ler(String serial) async {
    final tela = Tela.parse(await _adb.dump(serial));
    if (serial == _mot) {
      _ultimoTextoMot = tela.textoVisivel;
    } else {
      _ultimoTextoPax = tela.textoVisivel;
    }
    return tela;
  }

  Future<Tela> _aguardar(
    String serial,
    String descricao,
    bool Function(Tela) condicao,
    Duration timeout, {
    bool efeitoRemoto = false,
  }) async {
    // O teto da etapa prevalece sobre o limite da espera quando for menor.
    final efetivo = _restanteDaEtapa(timeout);
    final tela = efetivo <= Duration.zero
        ? null
        : await esperarCondicao<Tela>(_relogio, () async {
            final t = await _ler(serial);
            return condicao(t) ? t : null;
          }, timeout: efetivo);
    if (tela == null) {
      if (_globalEstourado()) throw const CicloInterrompido();
      throw FalhaEtapa(
        'esperava $descricao',
        timeout: true,
        efeitoRemoto: efeitoRemoto,
      );
    }
    return tela;
  }

  Future<void> _tocarNo(String serial, No no) =>
      _adb.tocar(serial, no.limites.centroX, no.limites.centroY);

  /// Toque que não é uma ação medida (campo de texto, "OK", ficar online).
  Future<void> _tocarSemAcao(String serial, Tela tela, String rotulo) async {
    final b = tela.botao(rotulo);
    if (b == null) throw FalhaEtapa('botão "$rotulo" ausente');
    await _tocarNo(serial, b);
  }

  /// Toque que dispara a publicação de um evento esperado (FR-028).
  Future<void> _tocarComAcao(
    String serial,
    Tela tela,
    String rotulo,
    String acaoId, {
    required int kind,
    required String autor,
  }) async {
    final b = tela.botao(rotulo);
    if (b == null) throw FalhaEtapa('botão "$rotulo" ausente');
    final inicio = _relogio.agora();
    await _tocarNo(serial, b);
    final fim = _relogio.agora();
    _registrarAcao(acaoId, 'toque', inicio, fim, kind, autor);
  }

  Future<void> _posicionar(
    String serial,
    PontoGeo ponto, {
    String? acaoId,
    int? kind,
    String? autor,
  }) async {
    final inicio = _relogio.agora();
    await _adb.geoFix(serial, ponto.lat, ponto.lon);
    final fim = _relogio.agora();
    if (acaoId != null) {
      _registrarAcao(acaoId, 'posicionamento', inicio, fim, kind!, autor!);
    }
  }

  void _registrarAcao(
    String id,
    String tipo,
    DateTime inicio,
    DateTime fim,
    int kind,
    String autor,
  ) {
    _acoes.add(Acao(id: id, tipo: tipo, inicioUtc: inicio, fimUtc: fim));
    _acaoDaEtapa = true;
    _esperado = EventoEsperado(kind, autor, inicio);
  }

  Future<void> _capturarFixa(String rotulo) async {
    if (ctx.telasCapturadas.contains(rotulo)) return;
    ctx.telasCapturadas.add(rotulo);
    _capturas.addAll(
      await ctx.evidencia.capturar(
        serial: _mot,
        prefixo: _prefixo(rotulo, 'motorista'),
      ),
    );
    _capturas.addAll(
      await ctx.evidencia.capturar(
        serial: _pax,
        prefixo: _prefixo(rotulo, 'passageiro'),
      ),
    );
  }

  // ---- etapas --------------------------------------------------------------

  Future<void> _e01EstadoInicial() async {
    await _posicionar(_mot, partidaDoMotorista);
    await _posicionar(_pax, pontoDeEncontro);
    await _aguardar(
      _pax,
      'mapa ocioso do passageiro',
      (t) =>
          t.tem(Rotulos.campoDestino) && !t.tem(Rotulos.aguardandoOrcamentos),
      ctx.limites.elementoLocal,
    );
    var tela = await _aguardar(
      _mot,
      'mapa do motorista',
      (t) => t.tem(Rotulos.motoristaOnline) || t.tem(Rotulos.motoristaOffline),
      ctx.limites.elementoLocal,
    );
    if (tela.tem(Rotulos.motoristaOffline)) {
      await _tocarSemAcao(_mot, tela, Rotulos.ficarOnline);
      tela = await _aguardar(
        _mot,
        'motorista online',
        (t) => t.tem(Rotulos.motoristaOnline),
        ctx.limites.elementoLocal,
      );
    }
  }

  Future<void> _e02Solicitar() async {
    var tela = await _ler(_pax);
    await _tocarSemAcao(_pax, tela, Rotulos.campoDestino);
    await _adb.digitar(_pax, destinoBusca);
    tela = await _aguardar(
      _pax,
      'resultado da busca de endereço',
      (t) => _resultadoDaBusca(t) != null,
      ctx.limites.buscaPhoton,
    );
    await _tocarNo(_pax, _resultadoDaBusca(tela)!);
    tela = await _aguardar(
      _pax,
      'botão "${Rotulos.solicitar}" habilitado',
      (t) => t.botao(Rotulos.solicitar) != null,
      ctx.limites.rota,
    );
    await _tocarComAcao(
      _pax,
      tela,
      Rotulos.solicitar,
      'solicitar',
      kind: 20001,
      autor: 'passageiro',
    );
    await _aguardar(
      _pax,
      Rotulos.aguardandoOrcamentos,
      (t) => t.tem(Rotulos.aguardandoOrcamentos),
      ctx.limites.elementoLocal,
    );
    await _capturarFixa('solicitacao-enviada');
  }

  /// Primeiro item de resultado: clicável, com o trecho esperado, e que não é o
  /// próprio campo de texto (cujo conteúdo é exatamente o digitado).
  No? _resultadoDaBusca(Tela t) {
    for (final n in t.todos) {
      if (!n.contem(destinoResultadoContem)) continue;
      if (n.texto == destinoBusca || n.descricao == destinoBusca) continue;
      No? alvo = n;
      while (alvo != null && !alvo.clicavel) {
        alvo = alvo.pai;
      }
      if (alvo != null && alvo.pai != null) return alvo;
    }
    return null;
  }

  Future<void> _e03MotoristaRecebe() async {
    await _aguardar(
      _mot,
      Rotulos.solicitacaoDeCorrida,
      (t) => t.tem(Rotulos.solicitacaoDeCorrida),
      ctx.limites.efeitoRemoto,
      efeitoRemoto: true,
    );
  }

  Future<void> _e04Orcamento() async {
    var tela = await _aguardar(
      _mot,
      'botão "${Rotulos.enviarOrcamento}" habilitado',
      (t) => t.botao(Rotulos.enviarOrcamento) != null,
      ctx.limites.rota,
    );
    await _tocarComAcao(
      _mot,
      tela,
      Rotulos.enviarOrcamento,
      'orcamento',
      kind: 20002,
      autor: 'motorista',
    );
    await _aguardar(
      _pax,
      Rotulos.orcamentosRecebidos,
      (t) =>
          t.tem(Rotulos.orcamentosRecebidos) &&
          t.botao(Rotulos.aceitar) != null,
      ctx.limites.efeitoRemoto,
      efeitoRemoto: true,
    );
    await _capturarFixa('orcamento-recebido');
  }

  Future<void> _e05Selecao() async {
    final tela = await _ler(_pax);
    await _tocarComAcao(
      _pax,
      tela,
      Rotulos.aceitar,
      'aceitar',
      kind: 20003,
      autor: 'passageiro',
    );
    await _aguardar(
      _mot,
      Rotulos.iniciarCorrida,
      (t) => t.botao(Rotulos.iniciarCorrida) != null,
      ctx.limites.efeitoRemoto,
      efeitoRemoto: true,
    );
  }

  Future<void> _e06Inicio() async {
    final telaMot = await _ler(_mot);
    await _tocarSemAcao(_mot, telaMot, Rotulos.iniciarCorrida);
    final telaPax = await _aguardar(
      _pax,
      Rotulos.motoristaACaminho,
      (t) => t.tem(Rotulos.motoristaACaminho),
      ctx.limites.efeitoRemoto,
      efeitoRemoto: true,
    );
    await _capturarFixa('motorista-a-caminho');
    final ok = telaPax.botao(Rotulos.ok, exato: true);
    if (ok != null) await _tocarNo(_pax, ok);
  }

  Future<void> _e07Chegada() async {
    await _posicionar(
      _mot,
      pontoDeEncontro,
      acaoId: 'chegada-origem',
      kind: 20007,
      autor: 'motorista',
    );
    await _aguardar(
      _pax,
      Rotulos.motoristaChegou,
      (t) => t.tem(Rotulos.motoristaChegou),
      ctx.limites.posicionamento,
      efeitoRemoto: true,
    );
  }

  Future<void> _e08Encontro() async {
    final tela = await _ler(_pax);
    await _tocarComAcao(
      _pax,
      tela,
      Rotulos.confirmarEncontro,
      'confirmar-encontro',
      kind: 20008,
      autor: 'passageiro',
    );
    await _aguardar(
      _mot,
      Rotulos.corridaEmAndamento,
      (t) => t.tem(Rotulos.corridaEmAndamento),
      ctx.limites.efeitoRemoto,
      efeitoRemoto: true,
    );
    await _capturarFixa('corrida-em-andamento');
  }

  Future<void> _e09Destino() async {
    await _posicionar(
      _mot,
      destinoDaCorrida,
      acaoId: 'chegada-destino',
      kind: 20009,
      autor: 'motorista',
    );
    await _aguardar(
      _pax,
      'botão "${Rotulos.confirmarDestino}"',
      (t) => t.botao(Rotulos.confirmarDestino) != null,
      ctx.limites.posicionamento,
      efeitoRemoto: true,
    );
  }

  Future<void> _e10ConfirmarDestino() async {
    final tela = await _ler(_pax);
    await _tocarComAcao(
      _pax,
      tela,
      Rotulos.confirmarDestino,
      'confirmar-destino',
      kind: 20010,
      autor: 'passageiro',
    );
    await _aguardar(
      _mot,
      Rotulos.avalieACorrida,
      (t) => t.tem(Rotulos.avalieACorrida),
      ctx.limites.efeitoRemoto,
      efeitoRemoto: true,
    );
    await _capturarFixa('corrida-encerrada');
  }

  Future<void> _e11Avaliacoes() async {
    await _avaliar(_mot, 'avaliacao-motorista', 'motorista');
    await _avaliar(_pax, 'avaliacao-passageiro', 'passageiro');
    await _capturarFixa('avaliacao-concluida');
  }

  Future<void> _avaliar(String serial, String acaoId, String autor) async {
    var tela = await _aguardar(
      serial,
      'modal de avaliação',
      (t) => t.estrelas(Rotulos.avalieACorrida).length >= 5,
      ctx.limites.elementoLocal,
    );
    await _tocarNo(serial, tela.estrelas(Rotulos.avalieACorrida).last);
    tela = await _aguardar(
      serial,
      'botão "${Rotulos.confirmar}" habilitado',
      (t) => t.botao(Rotulos.confirmar) != null,
      ctx.limites.elementoLocal,
    );
    await _tocarComAcao(
      serial,
      tela,
      Rotulos.confirmar,
      acaoId,
      kind: 20014,
      autor: autor,
    );
    await _aguardar(
      serial,
      'modal de avaliação fechada',
      (t) => !t.tem(Rotulos.avalieACorrida),
      ctx.limites.elementoLocal,
    );
  }

  /// O menor entre [timeout], o que resta da etapa e o que resta do orçamento.
  Duration _restanteDaEtapa(Duration timeout) {
    var efetivo = timeout;
    final restante = _prazoDaEtapa.difference(_relogio.agora());
    if (restante < efetivo) efetivo = restante;
    final g = ctx.prazoGlobal;
    if (g != null) {
      final doOrcamento = g.difference(_relogio.agora());
      if (doOrcamento < efetivo) efetivo = doOrcamento;
    }
    return efetivo < Duration.zero ? Duration.zero : efetivo;
  }

  Future<void> _e12Recibos() async {
    final inicio = _etapas.where((e) => e.id == 'E11').isNotEmpty
        ? _etapas.firstWhere((e) => e.id == 'E11').inicioUtc
        : _inicio;
    for (final autor in const ['motorista', 'passageiro']) {
      final visto = await esperarCondicao<bool>(_relogio, () async {
        return ctx.observador.vistoEmAlgumRelay(
              kind: 20014,
              autor: autor,
              apos: inicio,
            )
            ? true
            : null;
      }, timeout: _restanteDaEtapa(ctx.limites.efeitoRemoto));
      if (visto == null) {
        if (_globalEstourado()) throw const CicloInterrompido();
        _esperado = EventoEsperado(20014, autor, inicio);
        throw FalhaEtapa('recibo 20014 de $autor não observado', timeout: true);
      }
    }
  }

  Future<void> _voltaAoEstadoInicial() async {
    await _posicionar(_mot, partidaDoMotorista);
    await _posicionar(_pax, pontoDeEncontro);
    await _aguardar(
      _pax,
      'mapa ocioso do passageiro',
      (t) =>
          t.tem(Rotulos.campoDestino) && !t.tem(Rotulos.aguardandoOrcamentos),
      ctx.limites.voltaAoInicio,
    );
    await _aguardar(
      _mot,
      'mapa ocioso do motorista',
      (t) =>
          (t.tem(Rotulos.motoristaOnline) || t.tem(Rotulos.motoristaOffline)) &&
          !t.tem(Rotulos.corridaEmAndamento),
      ctx.limites.voltaAoInicio,
    );
  }
}
