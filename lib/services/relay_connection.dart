import '../domain/nostr_event.dart';
import '../domain/relay.dart';
import 'relay_gateway.dart';

/// O que a interface e o `EventFeed` do app precisam da conexão com os relays.
///
/// Existe porque a conexão pode viver em dois lugares (feature 025): no
/// próprio isolate da interface — `RelayService`, usado pelo serviço em
/// segundo plano e pelos testes — ou no isolate de um serviço em primeiro
/// plano do Android, acessado por mensagens (`RemoteRelayConnection`). Quem
/// consome só vê esta interface.
abstract class RelayConnection {
  /// Estado atual de cada relay, em ordem de inclusão.
  List<Relay> get relays;

  /// Verdadeiro se ao menos um relay está conectado.
  bool get hasConnectedRelay;

  /// Eventos brutos recebidos dos relays, sem verificação nem deduplicação.
  Stream<IncomingEvent> get incoming;

  /// Emite sempre que o estado de algum relay muda.
  Stream<void> get statusChanges;

  /// Conecta a todos os relays da lista, de forma independente.
  Future<void> connectAll(List<Relay> relays);

  /// Acrescenta um relay à lista e tenta conectar.
  Future<void> addRelay(String url);

  /// Remove um relay da lista e encerra sua conexão.
  Future<void> removeRelay(String url);

  /// Sonda os relays conectados e reconecta os indisponíveis, sem esperar o
  /// ciclo automático.
  Future<void> reconnectNow();

  /// Publica um evento já assinado, reportando o resultado por relay. Lança
  /// [NoConnectedRelay] se nenhum relay estiver conectado.
  Stream<PublishOutcome> publish(
    NostrEvent event, {
    required Map<String, dynamic> payload,
  });

  /// Liga a retentativa dos indisponíveis e a sonda de vivacidade. Idempotente.
  void enableAutoRetry();

  /// Libera os recursos. Idempotente.
  Future<void> dispose();
}

/// Tentativa de publicar sem nenhum relay conectado.
class NoConnectedRelay implements Exception {
  @override
  String toString() => 'Nenhum relay conectado: não há como publicar o evento.';
}
