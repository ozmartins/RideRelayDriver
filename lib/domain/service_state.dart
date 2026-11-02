import 'driver_ride_status.dart';

/// O que o serviço em segundo plano precisa saber do app para decidir se uma
/// solicitação de corrida merece notificação (feature 025, `data-model.md`).
///
/// A interface é a dona destes quatro valores e os envia ao serviço a cada
/// mudança; o serviço os guarda em `KeyValueStore` para relê-los ao ser
/// reiniciado pelo sistema. Nada aqui é segredo: nem chave, nem posição.
class ServiceState {
  const ServiceState({
    this.online = false,
    this.acceptedPayments,
    this.rideStatus = DriverRideStatus.aguardandoSolicitacao,
    this.appInForeground = false,
  });

  /// Espelha `AvailabilityStatus.online`.
  final bool online;

  /// Formas de pagamento aceitas no cadastro, pelos valores do contrato
  /// (`DriverProfile.paymentMethods.map(wireValue)`). `null` enquanto o
  /// cadastro ainda não foi carregado: sem o que comparar, a solicitação não
  /// é descartada por pagamento (mesma regra de `MapScreen._aceitaPagamento`).
  final Set<String>? acceptedPayments;

  /// Só `aguardandoSolicitacao` permite notificar.
  final DriverRideStatus rideStatus;

  /// Com o app visível quem trata a solicitação é a modal, não a notificação.
  final bool appInForeground;

  ServiceState copyWith({
    bool? online,
    Set<String>? acceptedPayments,
    DriverRideStatus? rideStatus,
    bool? appInForeground,
  }) => ServiceState(
    online: online ?? this.online,
    acceptedPayments: acceptedPayments ?? this.acceptedPayments,
    rideStatus: rideStatus ?? this.rideStatus,
    appInForeground: appInForeground ?? this.appInForeground,
  );

  Map<String, dynamic> toJson() => {
    'online': online,
    'acceptedPayments': acceptedPayments?.toList()?..sort(),
    'rideStatus': rideStatus.name,
    'appInForeground': appInForeground,
  };

  /// Sem o primeiro plano: ao reiniciar, o serviço assume que o app não está
  /// visível até a interface dizer o contrário.
  Map<String, dynamic> toStorageJson() => toJson()..remove('appInForeground');

  /// Tolerante: campo ausente ou de tipo inesperado cai no padrão, nunca
  /// lança — o JSON pode ter sido gravado por uma versão anterior.
  factory ServiceState.fromJson(Map<String, dynamic> json) {
    final pagamentos = json['acceptedPayments'];
    final estado = json['rideStatus'];
    return ServiceState(
      online: json['online'] == true,
      acceptedPayments: pagamentos is List
          ? pagamentos.whereType<String>().toSet()
          : null,
      rideStatus:
          DriverRideStatus.values.asNameMap()[estado] ??
          DriverRideStatus.aguardandoSolicitacao,
      appInForeground: json['appInForeground'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ServiceState &&
      other.online == online &&
      _mesmoConjunto(other.acceptedPayments, acceptedPayments) &&
      other.rideStatus == rideStatus &&
      other.appInForeground == appInForeground;

  @override
  int get hashCode => Object.hash(
    online,
    acceptedPayments == null
        ? null
        : Object.hashAllUnordered(acceptedPayments!),
    rideStatus,
    appInForeground,
  );

  static bool _mesmoConjunto(Set<String>? a, Set<String>? b) {
    if (a == null || b == null) return a == b;
    return a.length == b.length && a.containsAll(b);
  }

  @override
  String toString() =>
      'ServiceState(online: $online, pagamentos: $acceptedPayments, '
      'corrida: ${rideStatus.name}, primeiroPlano: $appInForeground)';
}
