/// Relógio injetável do roteiro E2E: o teste avança o tempo sem esperar de verdade.
abstract interface class Relogio {
  /// Instante atual em UTC, relógio do hospedeiro (o mesmo do observador).
  DateTime agora();

  /// Espera [duracao]. Nenhuma espera do roteiro é fixa e longa: isto só serve
  /// ao intervalo curto entre duas leituras de uma espera por condição.
  Future<void> dormir(Duration duracao);
}

class RelogioReal implements Relogio {
  const RelogioReal();

  @override
  DateTime agora() => DateTime.now().toUtc();

  @override
  Future<void> dormir(Duration duracao) => Future<void>.delayed(duracao);
}
