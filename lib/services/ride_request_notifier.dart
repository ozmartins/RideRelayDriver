/// Avisa o motorista, fora do app, de que chegou uma solicitação de corrida.
///
/// Abstração do projeto (Princípio III): a implementação real usa
/// `flutter_local_notifications`; os testes usam um dublê. O texto é sempre
/// genérico — nunca endereço, coordenada, nome nem chave de terceiros
/// (constituição 2.14.0, SC-003).
abstract class RideRequestNotifier {
  /// Mostra o aviso da solicitação [eventId]. O mesmo id substitui o aviso
  /// anterior em vez de duplicá-lo.
  Future<void> notifyRideRequest(String eventId);

  /// Remove os avisos de solicitação ainda na bandeja (o app voltou à tela).
  Future<void> cancelAll();
}

/// O conteúdo do aviso de uma solicitação, sem nada que venha do evento além do
/// id usado só para não duplicar (constituição 2.14.0: nem endereço, nem
/// coordenada, nem nome, nem chave de terceiros — SC-003). Vive fora do plugin
/// para poder ser testado.
class RideRequestNotificationContent {
  const RideRequestNotificationContent._(this.id, this.title, this.body);

  /// Identificador numérico do aviso, estável para o mesmo evento e sempre
  /// positivo (o Android o exige como `int` de 32 bits).
  final int id;
  final String title;
  final String body;

  static const String fixedTitle = 'Nova solicitação de corrida';
  static const String fixedBody = 'Toque para ver';

  factory RideRequestNotificationContent.forEvent(String eventId) =>
      RideRequestNotificationContent._(
        eventId.hashCode & 0x7fffffff,
        fixedTitle,
        fixedBody,
      );
}
