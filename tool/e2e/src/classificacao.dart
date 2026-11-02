import 'telas.dart';

/// Origem da falha (FR-026, FR-021a, D9): regras determinísticas, em ordem de
/// precedência — ambiente de teste, serviço externo, relays, aplicativo.

enum OrigemFalha {
  aplicativo('aplicativo'),
  relays('relays'),
  servicoExterno('servico_externo'),
  ambienteTeste('ambiente_teste');

  const OrigemFalha(this.codigo);

  final String codigo;
}

/// Sinal que o próprio app deu de que um serviço externo falhou. Guarda só a
/// classificação, nunca a linha do `logcat` (FR-029).
class SinalExterno {
  const SinalExterno({required this.fonte, required this.servico, this.http});

  /// `ui` ou `logcat`.
  final String fonte;

  /// `Photon`, `OpenFreeMap` ou `OpenRouteService`.
  final String servico;
  final int? http;

  Map<String, Object?> toJson() => {
    'fonte': fonte,
    'servico': servico,
    'http': http,
  };
}

class Evidencias {
  const Evidencias({
    this.adbIndisponivel = false,
    this.observadorSemRelays = false,
    this.sinalExterno,
    this.acaoExecutada = false,
    this.eventoEsperado = false,
    this.eventoObservado = false,
    this.efeitoRemotoAusente = false,
    this.processoAppAusente = false,
  });

  /// `adb` sem resposta ou dispositivo offline.
  final bool adbIndisponivel;

  /// O observador não está conectado a nenhum relay (rede do hospedeiro).
  final bool observadorSemRelays;
  final SinalExterno? sinalExterno;

  /// A ação da etapa (toque ou posicionamento) foi executada.
  final bool acaoExecutada;

  /// A etapa tem evento esperado pelo observador.
  final bool eventoEsperado;

  /// O evento esperado foi visto em pelo menos um relay.
  final bool eventoObservado;

  /// A condição que falhou é o efeito no outro app (a espera estourou).
  final bool efeitoRemotoAusente;

  /// O processo do app envolvido não existe mais.
  final bool processoAppAusente;
}

class Classificacao {
  const Classificacao({
    required this.origem,
    required this.origemBruta,
    this.servicoExterno,
    this.sinal,
  });

  final OrigemFalha origem;

  /// `indeterminada` ou igual ao código da [origem].
  final String origemBruta;
  final String? servicoExterno;
  final SinalExterno? sinal;
}

/// Classifica a falha. Dúvida entre duas regras resolve-se pela de menor número.
Classificacao classificar(Evidencias e) {
  // 1. Ambiente de teste.
  if (e.adbIndisponivel || e.observadorSemRelays) {
    return const Classificacao(
      origem: OrigemFalha.ambienteTeste,
      origemBruta: 'ambiente_teste',
    );
  }
  // 2. Serviço externo: só com sinal do app (FR-021a).
  final sinal = e.sinalExterno;
  if (sinal != null) {
    return Classificacao(
      origem: OrigemFalha.servicoExterno,
      origemBruta: 'servico_externo',
      servicoExterno: sinal.servico,
      sinal: sinal,
    );
  }
  // 3. Relays: o evento chegou a algum relay e, mesmo assim, o app não avançou.
  if (e.acaoExecutada &&
      e.eventoEsperado &&
      e.eventoObservado &&
      e.efeitoRemotoAusente) {
    return const Classificacao(
      origem: OrigemFalha.relays,
      origemBruta: 'relays',
    );
  }
  // 4. Aplicativo. Ação feita e evento em nenhum relay: não se sabe se o app
  // não publicou ou se os relays não entregaram (FR-026).
  if (e.acaoExecutada &&
      e.eventoEsperado &&
      !e.eventoObservado &&
      !e.processoAppAusente) {
    return const Classificacao(
      origem: OrigemFalha.aplicativo,
      origemBruta: 'indeterminada',
    );
  }
  return const Classificacao(
    origem: OrigemFalha.aplicativo,
    origemBruta: 'aplicativo',
  );
}

/// Procura, na tela atual e nas linhas do `logcat` do ciclo, um sinal de que o
/// app registrou falha de um serviço externo. Devolve só a classificação.
SinalExterno? detectarSinalExterno({
  String? textoTela,
  List<String> linhasLogcat = const [],
}) {
  final http429 = RegExp(r'\b429\b');
  if (textoTela != null) {
    if (textoTela.contains(SinaisDeInterface.photon)) {
      return SinalExterno(
        fonte: 'ui',
        servico: 'Photon',
        http: http429.hasMatch(textoTela) ? 429 : null,
      );
    }
    if (textoTela.contains(SinaisDeInterface.rotaOrs1) ||
        textoTela.contains(SinaisDeInterface.rotaOrs2)) {
      return SinalExterno(
        fonte: 'ui',
        servico: 'OpenRouteService',
        http: http429.hasMatch(textoTela) ? 429 : null,
      );
    }
  }
  final rotas = RegExp(r'(Dist[âa]ncia|rota).*falhou', caseSensitive: false);
  final enderecos = RegExp(r'Endere[çc]o.*falhou', caseSensitive: false);
  final tiles = RegExp(
    r'(tile|openfreemap).*(erro|error|failed|falhou|exception)',
    caseSensitive: false,
  );
  for (final linha in linhasLogcat) {
    final http = http429.hasMatch(linha) ? 429 : null;
    if (rotas.hasMatch(linha)) {
      return SinalExterno(
        fonte: 'logcat',
        servico: 'OpenRouteService',
        http: http,
      );
    }
    if (enderecos.hasMatch(linha)) {
      return SinalExterno(fonte: 'logcat', servico: 'Photon', http: http);
    }
    if (tiles.hasMatch(linha)) {
      return SinalExterno(fonte: 'logcat', servico: 'OpenFreeMap', http: http);
    }
  }
  return null;
}

/// O limite diário da OpenRouteService esgotou (FR-021): resposta 429 do serviço.
bool limiteDiarioOrsEsgotado(SinalExterno? sinal) =>
    sinal != null && sinal.servico == 'OpenRouteService' && sinal.http == 429;
