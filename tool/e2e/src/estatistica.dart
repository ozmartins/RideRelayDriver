import 'dart:math' as math;

/// Estatística do relatório (FR-033, FR-034, D5, D6): código próprio, conferido
/// por testes de valores conhecidos e por um fixture gerado com scipy.

class Intervalo {
  const Intervalo(this.inferior, this.superior);

  final double inferior;
  final double superior;
}

double _lgamma(double x) {
  // Aproximação de Lanczos (g = 7, n = 9).
  const coef = <double>[
    0.99999999999980993,
    676.5203681218851,
    -1259.1392167224028,
    771.32342877765313,
    -176.61502916214059,
    12.507343278686905,
    -0.13857109526572012,
    9.9843695780195716e-6,
    1.5056327351493116e-7,
  ];
  if (x < 0.5) {
    return math.log(math.pi / math.sin(math.pi * x).abs()) - _lgamma(1 - x);
  }
  x -= 1;
  var a = coef[0];
  final t = x + 7.5;
  for (var i = 1; i < 9; i++) {
    a += coef[i] / (x + i);
  }
  return 0.5 * math.log(2 * math.pi) +
      (x + 0.5) * math.log(t) -
      t +
      math.log(a);
}

double _fracaoContinua(double x, double a, double b) {
  const maxIter = 500;
  const eps = 1e-16;
  const tiny = 1e-300;
  final qab = a + b, qap = a + 1, qam = a - 1;
  var c = 1.0;
  var d = 1 - qab * x / qap;
  if (d.abs() < tiny) d = tiny;
  d = 1 / d;
  var h = d;
  for (var m = 1; m <= maxIter; m++) {
    final m2 = 2 * m;
    var aa = m * (b - m) * x / ((qam + m2) * (a + m2));
    d = 1 + aa * d;
    if (d.abs() < tiny) d = tiny;
    c = 1 + aa / c;
    if (c.abs() < tiny) c = tiny;
    d = 1 / d;
    h *= d * c;
    aa = -(a + m) * (qab + m) * x / ((a + m2) * (qap + m2));
    d = 1 + aa * d;
    if (d.abs() < tiny) d = tiny;
    c = 1 + aa / c;
    if (c.abs() < tiny) c = tiny;
    d = 1 / d;
    final delta = d * c;
    h *= delta;
    if ((delta - 1).abs() < eps) break;
  }
  return h;
}

/// Beta incompleta regularizada I_x(a, b).
double betaIncompletaRegularizada(double x, double a, double b) {
  if (x <= 0) return 0;
  if (x >= 1) return 1;
  final lbeta = _lgamma(a + b) - _lgamma(a) - _lgamma(b);
  final frente = math.exp(lbeta + a * math.log(x) + b * math.log(1 - x));
  if (x < (a + 1) / (a + b + 2)) {
    return frente * _fracaoContinua(x, a, b) / a;
  }
  return 1 - frente * _fracaoContinua(1 - x, b, a) / b;
}

/// Quantil [q] da distribuição Beta(a, b), por bisecção.
double quantilBeta(double q, double a, double b) {
  var baixo = 0.0, alto = 1.0;
  for (var i = 0; i < 200; i++) {
    final meio = (baixo + alto) / 2;
    if (betaIncompletaRegularizada(meio, a, b) < q) {
      baixo = meio;
    } else {
      alto = meio;
    }
    if (alto - baixo < 1e-15) break;
  }
  return (baixo + alto) / 2;
}

/// Intervalo de Clopper-Pearson bilateral para [x] ocorrências em [n] ensaios.
Intervalo clopperPearson(int x, int n, {double confianca = 0.95}) {
  if (n <= 0 || x < 0 || x > n) {
    throw ArgumentError('x=$x n=$n inválidos');
  }
  final alfa = 1 - confianca;
  final inferior = x == 0
      ? 0.0
      : quantilBeta(alfa / 2, x.toDouble(), (n - x + 1).toDouble());
  final superior = x == n
      ? 1.0
      : quantilBeta(1 - alfa / 2, (x + 1).toDouble(), (n - x).toDouble());
  return Intervalo(inferior, superior);
}

/// Percentil [p] (0–100) pelo método do posto mais próximo: valor ordenado na
/// posição ⌈p·N/100⌉ (1-indexada). Sem amostras devolve `null`, nunca zero.
double? postoMaisProximo(List<num> valores, double p) {
  if (valores.isEmpty) return null;
  final ordenados = [for (final v in valores) v.toDouble()]..sort();
  var posto = (p / 100 * ordenados.length).ceil();
  if (posto < 1) posto = 1;
  if (posto > ordenados.length) posto = ordenados.length;
  return ordenados[posto - 1];
}

/// Mediana pelo mesmo método (percentil 50 por posto mais próximo, D6).
double? mediana(List<num> valores) => postoMaisProximo(valores, 50);
