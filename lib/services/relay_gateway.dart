import '../domain/nostr_event.dart';

/// Resultado da tentativa de publicar um evento em **um** relay.
class PublishOutcome {
  const PublishOutcome({
    required this.relayUrl,
    required this.accepted,
    this.message,
  });

  final String relayUrl;
  final bool accepted;

  /// Motivo informado pelo relay quando recusa (ex.: exige pagamento ou
  /// autenticação). Exibido ao usuário sem interpretação (FR-007).
  final String? message;
}

/// Evento bruto recebido de um relay, antes de qualquer verificação.
///
/// Carrega o payload como veio do relay: **dado não confiável de terceiro**. A
/// conversão para o domínio só acontece depois da verificação de assinatura,
/// no `EventFeed` (contrato de eventos, regra 1).
class IncomingEvent {
  const IncomingEvent({required this.relayUrl, required this.payload});

  final String relayUrl;
  final Map<String, dynamic> payload;

  String? get id => payload['id'] as String?;
}

/// Transporte de relay: conecta, publica e entrega eventos recebidos.
///
/// Abstração do projeto (Princípio III). A implementação real usa `dart_nostr`;
/// os testes usam dublê em memória, para que nenhum teste dependa de rede ou de
/// relay público (decisão D5).
abstract class RelayGateway {
  /// Conecta a um relay. Completa quando o handshake termina; lança em falha.
  Future<void> connect(String relayUrl);

  /// Encerra a conexão com um relay, se houver.
  Future<void> disconnect(String relayUrl);

  /// Sonda de vivacidade: completa quando [relayUrl] responde a uma consulta
  /// inócua; lança se não houver conexão registrada.
  ///
  /// Quem impõe o prazo é o chamador. Existe porque uma conexão pode morrer sem
  /// erro nem fechamento — TCP meio aberto após troca de rede — e só uma
  /// pergunta sem resposta revela isso.
  Future<void> probe(String relayUrl);

  /// Url de cada relay cuja conexão **já estabelecida** caiu — relay fechou o
  /// socket, a rede sumiu, o aparelho trocou de Wi-Fi para dados móveis.
  ///
  /// Sem este sinal o relay continuaria "conectado" e surdo. Quando emite, o
  /// transporte já descartou a conexão; encerramento pedido por [disconnect]
  /// não emite.
  Stream<String> get connectionLost;

  /// Inscreve-se para receber eventos dos relays conectados (*subscription*).
  Stream<IncomingEvent> subscribe({required List<int> kinds});

  /// Publica um evento já assinado, reportando o resultado por relay.
  ///
  /// `payload` é o evento serializado como o protocolo espera, incluindo `id` e
  /// `sig` — é o que vai para os relays, sem reassinatura.
  Stream<PublishOutcome> publish(
    NostrEvent event, {
    required Map<String, dynamic> payload,
  });
}
