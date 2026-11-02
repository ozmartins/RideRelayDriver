/// Estado do motorista em relação a uma corrida, introduzido pela feature 010.
///
/// Ao contrário de [AvailabilityStatus] (status online/offline, que nunca
/// sobrevive a um reinício do app — `availability_status.dart`), este estado
/// MUST ser persistido: o motorista pode fechar o app a caminho do passageiro
/// e reabri-lo sem perder esse compromisso (FR-003).
enum DriverRideStatus {
  /// Default. O motorista pode ver e responder solicitações de corrida
  /// (`kind: 20001`) e reage normalmente a uma aceitação de orçamento
  /// (FR-001).
  aguardandoSolicitacao,

  /// Assumido só após o motorista confirmar o início de uma corrida aceita
  /// (FR-002). Bloqueia a exibição de novas solicitações (FR-004, FR-005) e
  /// ativa a publicação de localização (FR-007).
  deslocandoAtePassageiro,

  /// Assumido só depois que o passageiro confirma o encontro com o
  /// motorista (feature 012, FR-001). Continua bloqueando novas
  /// solicitações (mesma regra de [deslocandoAtePassageiro]) e ativa a
  /// checagem de proximidade do destino (FR-003 da feature 012).
  emCorrida,
}

/// Regras de transição de [DriverRideStatus] (FR-002 da feature 010; FR-001,
/// FR-007 da feature 012).
///
/// Funções puras, testáveis sem I/O, por analogia a `AvailabilityRules`.
abstract final class DriverRideRules {
  /// A transição para [DriverRideStatus.deslocandoAtePassageiro] só é válida
  /// a partir de [DriverRideStatus.aguardandoSolicitacao] — nunca automática,
  /// sempre por ação explícita do motorista (toque em "Iniciar corrida").
  static bool canStartRide(DriverRideStatus current) =>
      current == DriverRideStatus.aguardandoSolicitacao;

  /// A transição para [DriverRideStatus.emCorrida] só é válida a partir de
  /// [DriverRideStatus.deslocandoAtePassageiro] — uma confirmação de
  /// encontro chegando em qualquer outro estado é ignorada (FR-001, FR-002
  /// da feature 012).
  static bool canConfirmMeeting(DriverRideStatus current) =>
      current == DriverRideStatus.deslocandoAtePassageiro;

  /// A transição de volta a [DriverRideStatus.aguardandoSolicitacao] a
  /// partir de uma confirmação de destino só é válida a partir de
  /// [DriverRideStatus.emCorrida] (FR-007, FR-008 da feature 012).
  static bool canConfirmDestinationArrival(DriverRideStatus current) =>
      current == DriverRideStatus.emCorrida;

  /// O cancelamento pelo motorista só é válido em
  /// [DriverRideStatus.deslocandoAtePassageiro] e [DriverRideStatus.emCorrida]
  /// — nos dois, volta a [DriverRideStatus.aguardandoSolicitacao] e descarta a
  /// corrida ativa (FR-001, FR-003 da feature 018).
  static bool canCancelRide(DriverRideStatus current) =>
      current == DriverRideStatus.deslocandoAtePassageiro ||
      current == DriverRideStatus.emCorrida;

  /// O aviso de cancelamento do passageiro (`kind: 20013`, emenda 19) só
  /// vale nas mesmas duas fases do cancelamento pelo motorista — nelas,
  /// volta a [DriverRideStatus.aguardandoSolicitacao] e descarta a corrida
  /// ativa (FR-002, FR-003 da feature 020). Em
  /// [DriverRideStatus.aguardandoSolicitacao] não há corrida a encerrar.
  static bool canBeCancelledByPassenger(DriverRideStatus current) =>
      current == DriverRideStatus.deslocandoAtePassageiro ||
      current == DriverRideStatus.emCorrida;
}
