import 'checkpoint.dart';
import 'estatistica.dart';
import 'observador.dart';

/// Latência descritiva (FR-004, FR-028, FR-034): intervalo entre a ação do
/// roteiro no emulador e o recebimento do evento correspondente pelo
/// observador, pelo relógio do hospedeiro. Sem limite de aceitação.

class TipoLatencia {
  const TipoLatencia({
    required this.id,
    required this.rotulo,
    required this.kind,
    required this.autor,
    required this.categoria,
  });

  /// Identificador da ação gravada em `Etapa.acoes`.
  final String id;
  final String rotulo;
  final int kind;

  /// Papel do autor do evento esperado.
  final String autor;

  /// `toque` ou `posicionamento` (20007 e 20009 são disparados por posição).
  final String categoria;
}

/// Tabela "ação → evento esperado" do `spec.md` (FR-028).
const List<TipoLatencia> tiposDeLatencia = <TipoLatencia>[
  TipoLatencia(
    id: 'solicitar',
    rotulo: '20001 Solicitação de corrida',
    kind: 20001,
    autor: 'passageiro',
    categoria: 'toque',
  ),
  TipoLatencia(
    id: 'orcamento',
    rotulo: '20002 Orçamento de corrida',
    kind: 20002,
    autor: 'motorista',
    categoria: 'toque',
  ),
  TipoLatencia(
    id: 'aceitar',
    rotulo: '20003 Aceitação de orçamento',
    kind: 20003,
    autor: 'passageiro',
    categoria: 'toque',
  ),
  TipoLatencia(
    id: 'chegada-origem',
    rotulo: '20007 Chegada do motorista',
    kind: 20007,
    autor: 'motorista',
    categoria: 'posicionamento',
  ),
  TipoLatencia(
    id: 'confirmar-encontro',
    rotulo: '20008 Encontro confirmado',
    kind: 20008,
    autor: 'passageiro',
    categoria: 'toque',
  ),
  TipoLatencia(
    id: 'chegada-destino',
    rotulo: '20009 Chegada ao destino',
    kind: 20009,
    autor: 'motorista',
    categoria: 'posicionamento',
  ),
  TipoLatencia(
    id: 'confirmar-destino',
    rotulo: '20010 Destino confirmado',
    kind: 20010,
    autor: 'passageiro',
    categoria: 'toque',
  ),
  TipoLatencia(
    id: 'avaliacao-motorista',
    rotulo: '20014 Recibo (motorista→passageiro)',
    kind: 20014,
    autor: 'motorista',
    categoria: 'toque',
  ),
  TipoLatencia(
    id: 'avaliacao-passageiro',
    rotulo: '20014 Recibo (passageiro→motorista)',
    kind: 20014,
    autor: 'passageiro',
    categoria: 'toque',
  ),
];

class AmostraLatencia {
  const AmostraLatencia({
    required this.tipo,
    required this.ciclo,
    required this.latenciaMs,
    required this.relay,
  });

  final TipoLatencia tipo;
  final int ciclo;
  final double latenciaMs;

  /// Relay que entregou o evento primeiro ao observador.
  final String relay;
}

class ResultadoLatencia {
  ResultadoLatencia(this.amostras, this.desvios);

  final List<AmostraLatencia> amostras;
  final List<String> desvios;
}

/// Calcula as amostras de um [ciclo] a partir dos [eventos] associados a ele.
/// Evento não encontrado → sem amostra (nunca zero); latência negativa →
/// descartada com desvio (relógio).
ResultadoLatencia calcularLatencias(
  Ciclo ciclo,
  List<EventoObservado> eventos,
) {
  final amostras = <AmostraLatencia>[];
  final desvios = <String>[];
  for (final etapa in ciclo.etapas) {
    for (final acao in etapa.acoes) {
      final tipo = _tipoPorId(acao.id);
      if (tipo == null) continue;
      EventoObservado? primeiro;
      for (final e in eventos) {
        if (e.kind != tipo.kind || e.autor != tipo.autor) continue;
        if (e.recebidoUtc.isBefore(acao.inicioUtc)) continue;
        if (primeiro == null || e.recebidoUtc.isBefore(primeiro.recebidoUtc)) {
          primeiro = e;
        }
      }
      if (primeiro == null) continue;
      final ms =
          primeiro.recebidoUtc.difference(acao.fimUtc).inMicroseconds / 1000;
      if (ms < 0) {
        desvios.add(
          'ciclo ${ciclo.ciclo}: latência negativa descartada em ${tipo.id} '
          '(${ms.toStringAsFixed(1)} ms)',
        );
        continue;
      }
      amostras.add(
        AmostraLatencia(
          tipo: tipo,
          ciclo: ciclo.ciclo,
          latenciaMs: ms,
          relay: primeiro.relay,
        ),
      );
    }
  }
  return ResultadoLatencia(amostras, desvios);
}

TipoLatencia? _tipoPorId(String id) {
  for (final t in tiposDeLatencia) {
    if (t.id == id) return t;
  }
  return null;
}

class ResumoLatencia {
  const ResumoLatencia({required this.n, this.mediana, this.p95});

  final int n;
  final double? mediana;
  final double? p95;
}

ResumoLatencia resumir(Iterable<AmostraLatencia> amostras) {
  final valores = [for (final a in amostras) a.latenciaMs];
  return ResumoLatencia(
    n: valores.length,
    mediana: mediana(valores),
    p95: postoMaisProximo(valores, 95),
  );
}

/// Linhas do relatório: uma por tipo, mais "geral (todas)", "geral (toque)" e
/// "geral (posicionamento)" (F8 da análise).
Map<String, ResumoLatencia> resumoPorTipo(List<AmostraLatencia> amostras) {
  final m = <String, ResumoLatencia>{
    for (final t in tiposDeLatencia)
      t.rotulo: resumir(amostras.where((a) => a.tipo.id == t.id)),
  };
  m['geral (todas)'] = resumir(amostras);
  m['geral (toque)'] = resumir(
    amostras.where((a) => a.tipo.categoria == 'toque'),
  );
  m['geral (posicionamento)'] = resumir(
    amostras.where((a) => a.tipo.categoria == 'posicionamento'),
  );
  return m;
}
