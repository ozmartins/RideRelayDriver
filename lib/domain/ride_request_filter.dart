import 'driver_coverage.dart';
import 'driver_ride_status.dart';
import 'nostr_event.dart';
import 'payment_method.dart';
import 'ride_request_received.dart';
import 'service_state.dart';

/// Por que uma solicitação de corrida não deve ser mostrada nem notificada.
enum RideRequestRefusal {
  offline,
  emCorrida,
  malformada,

  /// Online, mas sem posição de referência (feature 027): só ocorre na
  /// retomada, antes da primeira posição válida.
  semReferencia,

  /// Sem tag `g` bem formada numa das células da inscrição, ou origem além do
  /// raio (regra de recepção 8 do contrato, emenda 27).
  foraDaCobertura,
  pagamentoNaoAceito,
}

/// Resultado de [RideRequestFilter.evaluate]: ou a solicitação decodificada,
/// ou o motivo da recusa.
class RideRequestDecision {
  const RideRequestDecision.accepted(RideRequestReceived this.request)
    : refusal = null;
  const RideRequestDecision.refused(RideRequestRefusal this.refusal)
    : request = null;

  final RideRequestReceived? request;
  final RideRequestRefusal? refusal;

  bool get accepted => request != null;
}

/// A regra única de aceitação de uma solicitação de corrida (`kind: 20001`),
/// FR-005 da feature 025: a mesma na interface (que abre a modal) e no serviço
/// (que decide notificar). Função pura, sem I/O.
///
/// Ordem, herdada de `MapScreen._processarSolicitacaoRecebida`: offline,
/// corrida em andamento, `content` malformado, cobertura geográfica (feature
/// 027), pagamento não aceito. A
/// assinatura, o marcador e a deduplicação já foram tratados antes, no
/// `EventFeed` ou no serviço (Princípio IV).
abstract final class RideRequestFilter {
  /// [coverage] é a cobertura do motorista online (posição de referência e
  /// raio), `null` enquanto ele não tem referência. Fica de fora de
  /// [ServiceState] de propósito: o estado é persistido, a cobertura não.
  static RideRequestDecision evaluate(
    NostrEvent event,
    ServiceState state, {
    required DriverCoverage? coverage,
  }) {
    // FR-002 da feature 007: offline é ignorado, verificado na chegada.
    if (!state.online) {
      return const RideRequestDecision.refused(RideRequestRefusal.offline);
    }

    // FR-004 da feature 010: só em "Aguardando solicitação de corrida".
    if (state.rideStatus != DriverRideStatus.aguardandoSolicitacao) {
      return const RideRequestDecision.refused(RideRequestRefusal.emCorrida);
    }

    final RideRequestReceived solicitacao;
    try {
      solicitacao = RideRequestReceived.fromNostrEvent(event);
    } on FormatException {
      // content é dado, nunca instrução (regra 3 de recepção).
      return const RideRequestDecision.refused(RideRequestRefusal.malformada);
    }

    // Feature 027: sem referência não há como medir o raio; com ela, vale a
    // regra 8 do contrato (célula e distância sobre a origem do `content`).
    if (coverage == null) {
      return const RideRequestDecision.refused(
        RideRequestRefusal.semReferencia,
      );
    }
    if (!coverage
        .evaluateRideRequest(tags: event.tags, content: event.content)
        .accepted) {
      return const RideRequestDecision.refused(
        RideRequestRefusal.foraDaCobertura,
      );
    }

    if (!acceptsPayment(state.acceptedPayments, solicitacao.payment)) {
      return const RideRequestDecision.refused(
        RideRequestRefusal.pagamentoNaoAceito,
      );
    }
    return RideRequestDecision.accepted(solicitacao);
  }

  /// Mesma regra de `DriverProfile.acceptsPayment`: o valor tem de ser um dos
  /// três do contrato **e** estar entre os [aceitos]. Sem cadastro carregado
  /// ([aceitos] nulo) não há o que comparar e nada é descartado.
  static bool acceptsPayment(Set<String>? aceitos, String wireValue) =>
      aceitos == null ||
      (PaymentMethod.fromWire(wireValue) != null &&
          aceitos.contains(wireValue));
}
