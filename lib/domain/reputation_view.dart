/// O que o usuário declarou sobre si (`corridas`, `avaliacoes`, `media`) — não
/// verificável além da janela de recibos apresentada.
class DeclaredReputation {
  const DeclaredReputation({
    required this.corridas,
    required this.avaliacoes,
    this.media,
  });

  final int corridas;
  final int avaliacoes;
  final double? media;
}

/// Resultado da verificação de uma `Reputation` (1.6 do contrato, emenda 25).
///
/// Mantém **separados** o que foi verificado (só recibos válidos) e o que foi
/// declarado: os dois nunca são misturados numa nota única.
class ReputationView {
  const ReputationView({
    required this.verifiedCount,
    this.verifiedAverage,
    required this.declared,
    required this.invalidDiscarded,
    required this.gaps,
    required this.inconsistent,
  });

  /// Quantos recibos passaram em todas as regras (a–g).
  final int verifiedCount;

  /// Média das notas dos recibos válidos que trazem nota; `null` se nenhum.
  final double? verifiedAverage;

  /// Valores declarados, exibidos à parte.
  final DeclaredReputation declared;

  /// Recibos descartados por falharem em alguma regra (a–g).
  final int invalidDiscarded;

  /// Recibos não apresentados: soma dos saltos de `seq` entre recibos válidos
  /// consecutivos na lista ("N recibos não apresentados").
  final int gaps;

  /// `head` não confere com o recibo de `seqProximo − 1`, ou `hash_anterior`
  /// quebrado entre recibos presentes (h, i).
  final bool inconsistent;
}
