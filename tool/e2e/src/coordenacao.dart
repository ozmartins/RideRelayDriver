import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'opcoes.dart';

/// Coordenação entre as duas máquinas do E2E (`contracts/coordenacao.md`).
/// Só circulam metadados: ciclo, papel, status e instantes. Nunca chave
/// privada, `content` ou chave da ORS.

/// Barreiras de um ciclo, na ordem em que ocorrem.
const List<String> barreirasDoCiclo = <String>[
  'inicio-ciclo',
  'fim-ciclo',
  'pronto-para-reiniciar',
];

const int _maxCorpoBytes = 4096;

enum ResultadoBarreira { liberada, abortado, expirada }

/// Resposta de uma barreira. [outro] são os `dados` que o outro papel levou à
/// mesma barreira (só metadados), presentes quando [resultado] é `liberada`.
class RespostaBarreira {
  const RespostaBarreira(this.resultado, [this.outro]);

  final ResultadoBarreira resultado;
  final Map<String, Object?>? outro;
}

class CoordenadorInalcancavel implements Exception {
  CoordenadorInalcancavel(this.detalhe);

  final String detalhe;

  @override
  String toString() => 'coordenador inalcançável: $detalhe';
}

/// Situação da execução, mantida pelo coordenador.
class SituacaoExecucao {
  const SituacaoExecucao({
    this.ciclo = -1,
    this.validos = 0,
    this.executados = 0,
    this.ativoMs = 0,
    this.encerrado = false,
    this.motivo,
  });

  /// Último ciclo já decidido pelo coordenador (-1 = nada decidido ainda).
  final int ciclo;
  final int validos;
  final int executados;
  final int ativoMs;
  final bool encerrado;

  /// Com [encerrado]: `meta_atingida` ou o motivo da parada parcial.
  final String? motivo;

  Map<String, Object> toJson() => {
    'ciclo': ciclo,
    'validos': validos,
    'executados': executados,
    'ativoMs': ativoMs,
    'encerrado': encerrado,
    'motivo': ?motivo,
  };

  static SituacaoExecucao? fromJson(Object? json) {
    if (json is! Map) return null;
    final ciclo = json['ciclo'];
    final validos = json['validos'];
    final executados = json['executados'];
    final ativoMs = json['ativoMs'];
    final encerrado = json['encerrado'];
    final motivo = json['motivo'];
    if (motivo != null && motivo is! String) return null;
    if (ciclo is! int ||
        validos is! int ||
        executados is! int ||
        ativoMs is! int ||
        encerrado is! bool) {
      return null;
    }
    return SituacaoExecucao(
      ciclo: ciclo,
      validos: validos,
      executados: executados,
      ativoMs: ativoMs,
      encerrado: encerrado,
      motivo: motivo as String?,
    );
  }
}

/// Visão que cada lado tem da coordenação: o passageiro usa a [NucleoCoordenacao]
/// direto; o motorista usa o [ClienteCoordenacao].
abstract interface class Coordenacao {
  /// Espera o outro papel chegar à barreira [nome] do [ciclo]. [dados] (só
  /// metadados) são entregues ao outro lado na resposta dele.
  Future<RespostaBarreira> barreira(
    String nome,
    int ciclo, {
    Map<String, Object?>? dados,
  });

  /// Marca o [ciclo] como abortado para os dois lados.
  Future<void> abortar(int ciclo, String motivo);

  Future<SituacaoExecucao> estado();

  /// Avisa que este lado falhou na [etapa] do [ciclo], para o outro parar de
  /// esperar por um efeito que não virá.
  Future<void> sinalizarFalha(int ciclo, String etapa);

  /// Etapa em que o outro lado falhou no [ciclo], ou `null`.
  Future<String?> falhaDoOutro(int ciclo);

  /// Só o coordenador publica a situação; o cliente lança [StateError].
  Future<void> publicarSituacao(SituacaoExecucao situacao);

  /// Diferença (relógio do coordenador − relógio local). Só metadado de relatório.
  Future<Duration> deslocamentoDeRelogio();
}

class _Barreira {
  final Set<Papel> chegaram = <Papel>{};
  final Map<Papel, Map<String, Object?>?> dados =
      <Papel, Map<String, Object?>?>{};
  final Completer<ResultadoBarreira> concluida = Completer<ResultadoBarreira>();
}

/// Lógica pura das barreiras, sem rede.
class NucleoCoordenacao {
  NucleoCoordenacao({
    this.espera = const Duration(minutes: 10),
    DateTime Function()? agora,
  }) : _agora = agora ?? (() => DateTime.now().toUtc());

  final Duration espera;
  final DateTime Function() _agora;
  final Map<String, _Barreira> _barreiras = <String, _Barreira>{};
  final Map<int, String> _abortados = <int, String>{};
  final Map<int, Map<Papel, String>> _falhas = <int, Map<Papel, String>>{};
  SituacaoExecucao _estado = const SituacaoExecucao();

  SituacaoExecucao get estado => _estado;

  void atualizarEstado(SituacaoExecucao novo) => _estado = novo;

  String? motivoDeAborto(int ciclo) => _abortados[ciclo];

  void registrarFalha(int ciclo, Papel papel, String etapa) =>
      (_falhas[ciclo] ??= <Papel, String>{}).putIfAbsent(papel, () => etapa);

  /// Etapa em que o papel que NÃO é [papel] falhou no [ciclo].
  String? falhaDoOutro(int ciclo, Papel papel) {
    final f = _falhas[ciclo];
    if (f == null) return null;
    return f[Papel.values.firstWhere((p) => p != papel)];
  }

  DateTime agora() => _agora();

  Future<RespostaBarreira> chegar(
    String nome,
    int ciclo,
    Papel papel, {
    Map<String, Object?>? dados,
    Duration? esperaMaxima,
  }) async {
    if (!barreirasDoCiclo.contains(nome)) {
      throw ArgumentError.value(nome, 'nome', 'barreira desconhecida');
    }
    if (ciclo < 0) throw ArgumentError.value(ciclo, 'ciclo');
    if (_abortados.containsKey(ciclo)) {
      return const RespostaBarreira(ResultadoBarreira.abortado);
    }

    final chave = '$nome#$ciclo';
    final b = _barreiras.putIfAbsent(chave, _Barreira.new);
    b.chegaram.add(papel);
    b.dados[papel] = dados;
    if (b.chegaram.length == Papel.values.length && !b.concluida.isCompleted) {
      b.concluida.complete(ResultadoBarreira.liberada);
    }
    final resultado = await b.concluida.future.timeout(
      esperaMaxima ?? espera,
      onTimeout: () => ResultadoBarreira.expirada,
    );
    if (resultado == ResultadoBarreira.liberada) {
      final outro = Papel.values.firstWhere((p) => p != papel);
      return RespostaBarreira(resultado, b.dados[outro]);
    }
    if (resultado == ResultadoBarreira.expirada) {
      // Quem expirou sai da barreira: uma nova tentativa pode chegar de novo.
      b.chegaram.remove(papel);
      b.dados.remove(papel);
      if (b.chegaram.isEmpty && identical(_barreiras[chave], b)) {
        _barreiras.remove(chave);
      }
    }
    return RespostaBarreira(resultado);
  }

  void abortar(int ciclo, String motivo) {
    _abortados.putIfAbsent(ciclo, () => motivo);
    final sufixo = '#$ciclo';
    for (final e in _barreiras.entries) {
      if (e.key.endsWith(sufixo) && !e.value.concluida.isCompleted) {
        e.value.concluida.complete(ResultadoBarreira.abortado);
      }
    }
  }

  /// Resposta de `POST /relogio`: eco de `t0`, recebimento e envio no coordenador.
  Map<String, String> relogio(String t0) {
    final t1 = _agora();
    return {
      't0': t0,
      't1': t1.toIso8601String(),
      't2': _agora().toIso8601String(),
    };
  }
}

/// Estimativa NTP simplificada: ((t1 − t0) + (t2 − t3)) / 2, com t0 e t3 no
/// relógio local e t1 e t2 no do coordenador.
Duration deslocamentoNtp({
  required DateTime t0,
  required DateTime t1,
  required DateTime t2,
  required DateTime t3,
}) {
  final soma =
      t1.difference(t0).inMicroseconds + t2.difference(t3).inMicroseconds;
  return Duration(microseconds: soma ~/ 2);
}

/// Lado do coordenador (passageiro): usa o núcleo sem passar pela rede.
class CoordenacaoLocal implements Coordenacao {
  CoordenacaoLocal(this.nucleo, this.papel);

  final NucleoCoordenacao nucleo;
  final Papel papel;

  @override
  Future<RespostaBarreira> barreira(
    String nome,
    int ciclo, {
    Map<String, Object?>? dados,
  }) => nucleo.chegar(nome, ciclo, papel, dados: dados);

  @override
  Future<void> abortar(int ciclo, String motivo) async =>
      nucleo.abortar(ciclo, motivo);

  @override
  Future<SituacaoExecucao> estado() async => nucleo.estado;

  @override
  Future<void> sinalizarFalha(int ciclo, String etapa) async =>
      nucleo.registrarFalha(ciclo, papel, etapa);

  @override
  Future<String?> falhaDoOutro(int ciclo) async =>
      nucleo.falhaDoOutro(ciclo, papel);

  @override
  Future<void> publicarSituacao(SituacaoExecucao situacao) async =>
      nucleo.atualizarEstado(situacao);

  @override
  Future<Duration> deslocamentoDeRelogio() async => Duration.zero;
}

bool _tokenConfere(String? recebido, String esperado) {
  if (recebido == null || recebido.length != esperado.length) return false;
  var diff = 0;
  for (var i = 0; i < esperado.length; i++) {
    diff |= recebido.codeUnitAt(i) ^ esperado.codeUnitAt(i);
  }
  return diff == 0;
}

/// Servidor HTTP do coordenador.
class ServidorCoordenacao {
  ServidorCoordenacao({required this.nucleo, required this.token});

  final NucleoCoordenacao nucleo;
  final String token;
  HttpServer? _servidor;

  int get porta => _servidor!.port;

  Future<void> iniciar({
    int porta = portaCoordenacaoPadrao,
    InternetAddress? endereco,
  }) async {
    final s = await HttpServer.bind(endereco ?? InternetAddress.anyIPv4, porta);
    _servidor = s;
    unawaited(
      s.forEach((req) {
        unawaited(_atender(req));
      }),
    );
  }

  Future<void> parar() async {
    await _servidor?.close(force: true);
    _servidor = null;
  }

  Future<void> _atender(HttpRequest req) async {
    try {
      if (!_tokenConfere(req.headers.value('X-E2E-Token'), token)) {
        return await _responder(req, HttpStatus.unauthorized, {
          'erro': 'token',
        });
      }
      final rota = '${req.method} ${req.uri.path}';
      if (rota == 'GET /estado') {
        return await _responder(req, HttpStatus.ok, nucleo.estado.toJson());
      }
      if (rota == 'GET /falha') {
        final ciclo = int.tryParse(req.uri.queryParameters['ciclo'] ?? '');
        final papel = _papel(req.uri.queryParameters['papel']);
        if (ciclo == null || ciclo < 0 || papel == null) {
          return await _responder(req, HttpStatus.badRequest, {
            'erro': 'campos',
          });
        }
        return await _responder(req, HttpStatus.ok, {
          'etapa': ?nucleo.falhaDoOutro(ciclo, papel),
        });
      }
      final corpo = await _lerCorpo(req);
      if (corpo == null) {
        return await _responder(req, HttpStatus.badRequest, {'erro': 'corpo'});
      }
      switch (rota) {
        case 'POST /barreira':
          final papel = _papel(corpo['papel']);
          final nome = corpo['nome'];
          final ciclo = corpo['ciclo'];
          if (papel == null ||
              nome is! String ||
              ciclo is! int ||
              !barreirasDoCiclo.contains(nome) ||
              ciclo < 0) {
            return await _responder(req, HttpStatus.badRequest, {
              'erro': 'campos',
            });
          }
          final dados = corpo['dados'];
          if (dados != null && dados is! Map<String, Object?>) {
            return await _responder(req, HttpStatus.badRequest, {
              'erro': 'campos',
            });
          }
          final r = await nucleo.chegar(
            nome,
            ciclo,
            papel,
            dados: dados as Map<String, Object?>?,
          );
          return await switch (r.resultado) {
            ResultadoBarreira.liberada => _responder(req, HttpStatus.ok, {
              'liberada': true,
              if (r.outro != null) 'outro': r.outro,
            }),
            ResultadoBarreira.abortado => _responder(req, HttpStatus.ok, {
              'abortado': true,
            }),
            ResultadoBarreira.expirada => _responder(
              req,
              HttpStatus.requestTimeout,
              {'erro': 'expirada'},
            ),
          };
        case 'POST /abortar':
          final ciclo = corpo['ciclo'];
          final motivo = corpo['motivo'];
          if (_papel(corpo['papel']) == null ||
              ciclo is! int ||
              ciclo < 0 ||
              motivo is! String) {
            return await _responder(req, HttpStatus.badRequest, {
              'erro': 'campos',
            });
          }
          nucleo.abortar(
            ciclo,
            motivo.length > 200 ? motivo.substring(0, 200) : motivo,
          );
          return await _responder(req, HttpStatus.ok, {'abortado': true});
        case 'POST /falha':
          final ciclo = corpo['ciclo'];
          final etapa = corpo['etapa'];
          final papel = _papel(corpo['papel']);
          if (papel == null ||
              ciclo is! int ||
              ciclo < 0 ||
              etapa is! String ||
              !RegExp(r'^(E\d{2}|R)$').hasMatch(etapa)) {
            return await _responder(req, HttpStatus.badRequest, {
              'erro': 'campos',
            });
          }
          nucleo.registrarFalha(ciclo, papel, etapa);
          return await _responder(req, HttpStatus.ok, {'registrada': true});
        case 'POST /relogio':
          final t0 = corpo['t0'];
          if (t0 is! String || DateTime.tryParse(t0) == null) {
            return await _responder(req, HttpStatus.badRequest, {
              'erro': 'campos',
            });
          }
          return await _responder(req, HttpStatus.ok, nucleo.relogio(t0));
        default:
          return await _responder(req, HttpStatus.notFound, {'erro': 'rota'});
      }
    } on Object {
      try {
        await _responder(req, HttpStatus.internalServerError, {
          'erro': 'interno',
        });
      } on Object {
        // Conexão já fechada.
      }
    }
  }

  Papel? _papel(Object? v) =>
      v is String ? Papel.values.where((p) => p.name == v).firstOrNull : null;

  Future<Map<String, Object?>?> _lerCorpo(HttpRequest req) async {
    final bytes = <int>[];
    await for (final parte in req) {
      bytes.addAll(parte);
      if (bytes.length > _maxCorpoBytes) return null;
    }
    try {
      final json = jsonDecode(utf8.decode(bytes));
      return json is Map<String, Object?> ? json : null;
    } on FormatException {
      return null;
    }
  }

  Future<void> _responder(HttpRequest req, int status, Object corpo) async {
    req.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(corpo));
    await req.response.close();
  }
}

/// Lado do motorista: fala com o servidor do coordenador.
class ClienteCoordenacao implements Coordenacao {
  ClienteCoordenacao({
    required this.papel,
    required this.host,
    required this.porta,
    required this.token,
    this.esperaBarreira = const Duration(minutes: 10),
    DateTime Function()? agora,
  }) : _agora = agora ?? (() => DateTime.now().toUtc());

  final Papel papel;
  final String host;
  final int porta;
  final String token;

  /// Prazo de uma barreira; a requisição aguarda um pouco mais que o servidor.
  final Duration esperaBarreira;
  final DateTime Function() _agora;

  factory ClienteCoordenacao.deOpcoes(Opcoes o) {
    final partes = o.coordenador!.split(':');
    return ClienteCoordenacao(
      papel: o.papel!,
      host: partes.first,
      porta: int.parse(partes.last),
      token: o.token!,
    );
  }

  Future<(int, Map<String, Object?>)> _chamar(
    String metodo,
    String caminho, {
    Map<String, Object?>? corpo,
    Duration? prazo,
  }) async {
    final http = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await http.openUrl(
        metodo,
        Uri(
          scheme: 'http',
          host: host,
          port: porta,
          path: caminho.split('?').first,
          query: caminho.contains('?') ? caminho.split('?').last : null,
        ),
      );
      req.headers.set('X-E2E-Token', token);
      if (corpo != null) {
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode(corpo));
      }
      final resposta = await req.close().timeout(
        prazo ?? const Duration(seconds: 30),
      );
      final texto = await utf8
          .decodeStream(resposta)
          .timeout(const Duration(seconds: 10));
      final json = jsonDecode(texto);
      return (
        resposta.statusCode,
        json is Map<String, Object?> ? json : <String, Object?>{},
      );
    } on SocketException catch (e) {
      throw CoordenadorInalcancavel(e.message);
    } on TimeoutException {
      throw CoordenadorInalcancavel('sem resposta');
    } on HttpException catch (e) {
      throw CoordenadorInalcancavel(e.message);
    } on FormatException {
      throw CoordenadorInalcancavel('resposta inválida');
    } finally {
      http.close(force: true);
    }
  }

  @override
  Future<RespostaBarreira> barreira(
    String nome,
    int ciclo, {
    Map<String, Object?>? dados,
  }) async {
    final (status, json) = await _chamar(
      'POST',
      '/barreira',
      corpo: {
        'nome': nome,
        'ciclo': ciclo,
        'papel': papel.name,
        'dados': ?dados,
      },
      prazo: esperaBarreira + const Duration(seconds: 15),
    );
    if (status == HttpStatus.requestTimeout) {
      return const RespostaBarreira(ResultadoBarreira.expirada);
    }
    if (status != HttpStatus.ok) {
      throw CoordenadorInalcancavel('barreira respondeu $status');
    }
    if (json['abortado'] == true) {
      return const RespostaBarreira(ResultadoBarreira.abortado);
    }
    if (json['liberada'] == true) {
      final outro = json['outro'];
      return RespostaBarreira(
        ResultadoBarreira.liberada,
        outro is Map<String, Object?> ? outro : null,
      );
    }
    throw CoordenadorInalcancavel('resposta de barreira inesperada');
  }

  @override
  Future<void> abortar(int ciclo, String motivo) async {
    final (status, _) = await _chamar(
      'POST',
      '/abortar',
      corpo: {'ciclo': ciclo, 'papel': papel.name, 'motivo': motivo},
    );
    if (status != HttpStatus.ok) {
      throw CoordenadorInalcancavel('abortar respondeu $status');
    }
  }

  @override
  Future<void> sinalizarFalha(int ciclo, String etapa) async {
    final (status, _) = await _chamar(
      'POST',
      '/falha',
      corpo: {'ciclo': ciclo, 'papel': papel.name, 'etapa': etapa},
    );
    if (status != HttpStatus.ok) {
      throw CoordenadorInalcancavel('falha respondeu $status');
    }
  }

  @override
  Future<String?> falhaDoOutro(int ciclo) async {
    final (status, json) = await _chamar(
      'GET',
      '/falha?ciclo=$ciclo&papel=${papel.name}',
    );
    if (status != HttpStatus.ok) {
      throw CoordenadorInalcancavel('falha respondeu $status');
    }
    final etapa = json['etapa'];
    return etapa is String ? etapa : null;
  }

  @override
  Future<void> publicarSituacao(SituacaoExecucao situacao) =>
      throw StateError('só o coordenador publica a situação');

  @override
  Future<SituacaoExecucao> estado() async {
    final (status, json) = await _chamar('GET', '/estado');
    final e = status == HttpStatus.ok ? SituacaoExecucao.fromJson(json) : null;
    if (e == null) throw CoordenadorInalcancavel('estado inválido ($status)');
    return e;
  }

  @override
  Future<Duration> deslocamentoDeRelogio() async {
    final t0 = _agora();
    final (status, json) = await _chamar(
      'POST',
      '/relogio',
      corpo: {'t0': t0.toIso8601String()},
    );
    final t3 = _agora();
    final t1 = DateTime.tryParse('${json['t1']}');
    final t2 = DateTime.tryParse('${json['t2']}');
    if (status != HttpStatus.ok || t1 == null || t2 == null) {
      throw CoordenadorInalcancavel('relógio inválido ($status)');
    }
    return deslocamentoNtp(t0: t0, t1: t1, t2: t2, t3: t3);
  }
}
