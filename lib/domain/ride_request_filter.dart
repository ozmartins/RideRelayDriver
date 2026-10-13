import 'driver_ride_status.dart';
import 'nostr_event.dart';
import 'payment_method.dart';
import 'ride_request_received.dart';
import 'service_state.dart';

/// Por que uma solicitação de corrida não deve ser mostrada nem notificada.
enum RideRequestRefusal { offline, emCorrida, malformada, pagamentoNaoAceito }

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
/// corrida em andamento, `content` malformado, pagamento não aceito. A
/// assinatura, o marcador e a deduplicação já foram tratados antes, no
/// `EventFeed` ou no serviço (Princípio IV).
abstract final class RideRequestFilter {
  static RideRequestDecision evaluate(NostrEvent event, ServiceState state) {
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
