/// Status de disponibilidade do motorista para corridas.
///
/// Não é persistido entre execuções: toda abertura do aplicativo começa em
/// [offline] (FR-010) — é decisão deliberada, não um detalhe de
/// implementação a corrigir depois.
enum AvailabilityStatus {
  /// Disponível: o aplicativo está em condições de notificar solicitações de
  /// corrida (mecanismo definido em feature futura, FR-011).
  online,

  /// Indisponível: nenhuma notificação de solicitação de corrida deve
  /// ocorrer.
  offline,
}

/// Regra de transição do status de disponibilidade (FR-008, FR-009).
///
/// Fica em uma função pura, própria do domínio, para que a decisão "pode
/// ficar online?" tenha teste único e sem depender de nenhum sensor real —
/// por analogia ao Princípio II, que exige teste do caso permitido e do
/// impedido para código que decide aceitar ou rejeitar algo.
abstract final class AvailabilityRules {
  /// Verdadeiro somente se houver uma posição válida no momento da
  /// transição — o motorista nunca fica online sem que o aplicativo saiba
  /// onde ele está (FR-008).
  static bool canGoOnline({required bool hasValidPosition}) => hasValidPosition;
}
