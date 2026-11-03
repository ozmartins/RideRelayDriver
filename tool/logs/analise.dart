import 'linhas.dart';

/// Kinds que, vistos numa corrida, indicam desvio do caminho feliz (FR-005).
const Set<int> kindsAnomalia = {20004, 20006, 20012, 20013};

class CicloLog {
  CicloLog({
    required this.numero,
    required this.guid,
    required this.inicio,
    required this.fim,
    required this.estadosMotorista,
    required this.reciboMotorista,
    required this.reciboPassageiro,
    required this.fontePassageiro,
    required this.sucesso,
    required this.origem,
    this.servicoExterno,
    this.origemBruta,
    this.anomalias = const [],
  });

  final int numero;
  final String guid;
  final int inicio, fim;
  final List<String> estadosMotorista;
  final bool reciboMotorista, reciboPassageiro, fontePassageiro, sucesso;

  /// `null` se sucesso; senão aplicativo | relays | servico_externo.
  final String? origem;
  final String? servicoExterno;

  /// `indeterminada` quando nenhum sinal do log atribui a falha (FR-026).
  final String? origemBruta;
  final List<int> anomalias;

  /// Falha por serviço externo não conta como válida (FR-016).
  bool get valido => origem != 'servico_externo';
  bool get falha => !sucesso && valido;
  String get ultimoEstado =>
      estadosMotorista.isEmpty ? '—' : estadosMotorista.last;
}

class AmostraLatencia {
  AmostraLatencia(this.tipo, this.kind, this.id, this.ms, this.relayPrimeiro);
  final String tipo;
  final int kind;
  final String id;
  final int ms;
  final String? relayPrimeiro;
}

class Analise {
  Analise({
    required this.ciclos,
    required this.latencias,
    required this.latenciasDescartadas,
    required this.semRecepcao,
    required this.entregaPorRelay,
    required this.primeiroPorRelay,
    required this.solicitacoes,
    required this.temPassageiro,
    required this.temMotorista,
    required this.execs,
    required this.chamadasExternas,
  });

  final List<CicloLog> ciclos;
  final List<AmostraLatencia> latencias;
  final int latenciasDescartadas;

  /// Eventos publicados por um lado e nunca vistos pelo outro, por kind.
  final Map<int, int> semRecepcao;

  /// (relay, kind) → entregas ao receptor (recebeu + duplicado).
  final Map<(String, int), int> entregaPorRelay;
  final Map<(String, int), int> primeiroPorRelay;

  /// Solicitações do passageiro (entradas em `aguardandoorcamentos`).
  final int solicitacoes;
  final bool temPassageiro, temMotorista;
  final Set<String> execs;

  /// (serviço, componente) → duração (ms) de cada `externo.chamada` e se falhou.
  final Map<(String, String), List<({int ms, bool falhou})>> chamadasExternas;

  int get validos => ciclos.where((c) => c.valido).length;
  int get falhas => ciclos.where((c) => c.falha).length;
  int get externos => ciclos.where((c) => !c.valido).length;
}

/// Junta os logs dos dois apps e deriva ciclos, latências e comportamento por
/// relay. Função pura. Ciclo = uma corrida (`guid_corrida`) que chegou à
/// aceitação no log do motorista; sucesso = recibo emitido pelos dois lados.
Analise analisar(List<Linha> motorista, List<Linha> passageiro) {
  final todas = [...motorista, ...passageiro]..sort((a, b) => a.t - b.t);

  // ---- ciclos
  final porGuid = <String, List<Linha>>{};
  for (final l in motorista) {
    if (l.op == 'corrida.estado' && l.guid != null) {
      porGuid.putIfAbsent(l.guid!, () => []).add(l);
    }
  }
  final guids = porGuid.keys.toList()
    ..sort((a, b) => porGuid[a]!.first.t - porGuid[b]!.first.t);

  bool recibo(List<Linha> ls, String g) =>
      ls.any((l) => l.op == 'recibo.emitiu' && l.guid == g);

  int fimDe(String g) => [
    for (final l in motorista)
      if (l.guid == g) l.t,
    for (final l in passageiro)
      if (l.guid == g) l.t,
  ].reduce((a, b) => a > b ? a : b);

  // Janela de cada ciclo: do ponto médio entre o fim do anterior e o início
  // dele até o ponto médio seguinte. Disjuntas, e cobrem tudo (inclusive o
  // que o app registra pouco depois da última mudança de estado).
  final inicios = [for (final g in guids) porGuid[g]!.first.t];
  final fins = [for (final g in guids) fimDe(g)];
  int limite(int i) => fins[i] + (inicios[i + 1] - fins[i]) ~/ 2;

  final ciclos = <CicloLog>[];
  for (var i = 0; i < guids.length; i++) {
    final g = guids[i];
    final estados = porGuid[g]!;
    final rm = recibo(motorista, g);
    final rp = recibo(passageiro, g);
    final fim = fins[i];
    final de = i == 0 ? -1 : limite(i - 1);
    final ate = i == guids.length - 1 ? 1 << 62 : limite(i);
    final janela = todas.where((l) => l.t > de && l.t <= ate).toList();
    final sucesso = rm && (passageiro.isEmpty || rp);

    String? origem, externo, bruta;
    if (!sucesso) {
      final ext = janela.where((l) => l.op == 'externo.falha' && l.ext != null);
      if (ext.isNotEmpty) {
        origem = bruta = 'servico_externo';
        externo = ext.first.ext;
      } else if (_relaysFalharam(janela)) {
        origem = bruta = 'relays';
      } else {
        origem = 'aplicativo';
        bruta = 'indeterminada';
      }
    }
    ciclos.add(
      CicloLog(
        numero: i + 1,
        guid: g,
        inicio: estados.first.t,
        fim: fim,
        estadosMotorista: [for (final e in estados) e.motivo ?? '?'],
        reciboMotorista: rm,
        reciboPassageiro: rp,
        fontePassageiro: passageiro.isNotEmpty,
        sucesso: sucesso,
        origem: origem,
        servicoExterno: externo,
        origemBruta: bruta,
        anomalias: {
          for (final l in janela)
            if (l.kind != null &&
                kindsAnomalia.contains(l.kind) &&
                (l.op == 'evento.publicou' || l.op == 'evento.recebeu'))
              l.kind!,
        }.toList()..sort(),
      ),
    );
  }

  // ---- latência: publicou (um lado) → primeira recepção (outro lado)
  final publicados = <String, Linha>{};
  for (final l in todas) {
    if (l.op == 'evento.publicou' && l.id != null) {
      publicados.putIfAbsent(l.id!, () => l);
    }
  }
  final primeiraRecepcao = <String, Linha>{};
  for (final l in todas) {
    if (l.op != 'evento.recebeu' || l.id == null) continue;
    final pub = publicados[l.id];
    if (pub == null || pub.papel == l.papel) continue; // eco do próprio
    primeiraRecepcao.putIfAbsent(l.id!, () => l);
  }
  final amostras = <AmostraLatencia>[];
  var descartadas = 0;
  final sem = <int, int>{};
  publicados.forEach((id, pub) {
    final rec = primeiraRecepcao[id];
    if (rec == null) {
      sem[pub.kind ?? -1] = (sem[pub.kind ?? -1] ?? 0) + 1;
      return;
    }
    final ms = rec.t - pub.t;
    if (ms < 0) {
      descartadas++;
      return;
    }
    final k = pub.kind ?? -1;
    amostras.add(
      AmostraLatencia('$k ${pub.papel}→${rec.papel}', k, id, ms, rec.relay),
    );
  });

  // ---- relays: o que cada relay entregou ao receptor
  final entrega = <(String, int), int>{};
  final primeiro = <(String, int), int>{};
  for (final l in todas) {
    if (l.relay == null || l.kind == null || l.comp == 'relay') continue;
    final entregue =
        l.op == 'evento.recebeu' ||
        (l.op == 'evento.descartou' && l.motivo == 'duplicado');
    if (!entregue) continue;
    final k = (l.relay!, l.kind!);
    entrega[k] = (entrega[k] ?? 0) + 1;
    if (l.op == 'evento.recebeu') primeiro[k] = (primeiro[k] ?? 0) + 1;
  }

  final chamadas = <(String, String), List<({int ms, bool falhou})>>{};
  for (final l in todas) {
    if (l.op != 'externo.chamada' || l.ext == null) continue;
    chamadas.putIfAbsent((l.ext!, l.comp), () => []).add((
      ms: l.ms ?? 0,
      falhou: l.res == 'falha',
    ));
  }

  return Analise(
    ciclos: ciclos,
    latencias: amostras,
    latenciasDescartadas: descartadas,
    semRecepcao: sem,
    entregaPorRelay: entrega,
    primeiroPorRelay: primeiro,
    solicitacoes: passageiro
        .where(
          (l) => l.op == 'corrida.estado' && l.motivo == 'aguardandoorcamentos',
        )
        .length,
    temPassageiro: passageiro.isNotEmpty,
    temMotorista: motorista.isNotEmpty,
    execs: {for (final l in todas) l.exec},
    chamadasExternas: chamadas,
  );
}

/// Algum evento da janela sem aceite em nenhum relay (ou sem relay conectado).
bool _relaysFalharam(List<Linha> janela) {
  final porId = <String, List<Linha>>{};
  for (final l in janela) {
    if (l.op == 'relay.ok' && l.id != null) {
      porId.putIfAbsent(l.id!, () => []).add(l);
    }
  }
  if (porId.values.any((ls) => ls.every((l) => l.res != 'ok'))) return true;
  return janela.any(
    (l) => l.op == 'evento.publicou' && l.motivo == 'sem_relay',
  );
}
