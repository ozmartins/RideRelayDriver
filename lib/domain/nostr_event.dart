/// Evento assinado trafegado pelos relays.
///
/// Nenhum campo de um evento recebido é confiável antes da verificação de
/// assinatura, e `content` é sempre tratado como **dado** — nunca como
/// instrução ou marcação renderizável (contrato de eventos, regra 3).
class NostrEvent {
  const NostrEvent({
    required this.id,
    required this.authorPublicKey,
    required this.createdAt,
    required this.kind,
    required this.content,
    required this.isSignatureValid,
    this.tags = const [],
  });

  /// Converte o payload de um evento **já verificado** (assinatura e `id`
  /// conferidos por `EventVerifier`) no tipo de domínio. Não verifica nada: é
  /// só a tradução, compartilhada pelo `EventFeed` e pelo serviço em segundo
  /// plano. Lança se faltar campo — quem chama já validou o payload.
  factory NostrEvent.fromVerifiedPayload(Map<String, dynamic> payload) =>
      NostrEvent(
        id: payload['id'] as String,
        authorPublicKey: payload['pubkey'] as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          (payload['created_at'] as int) * 1000,
        ),
        kind: payload['kind'] as int,
        content: payload['content'] as String,
        isSignatureValid: true,
        tags: (payload['tags'] as List<dynamic>? ?? const [])
            .map((t) => (t as List<dynamic>).map((e) => e.toString()).toList())
            .toList(),
      );

  /// Hash canônico do evento. É a chave de deduplicação entre relays (FR-010).
  final String id;

  /// Chave pública do autor, em hexadecimal.
  final String authorPublicKey;

  /// Horário declarado pelo autor. Dado de terceiro: não confiável como
  /// ordenação absoluta.
  final DateTime createdAt;

  /// Tipo do evento conforme o protocolo.
  final int kind;

  /// Conteúdo textual do evento.
  final String content;

  /// Resultado da verificação de assinatura. Eventos inválidos são descartados
  /// pelo `EventFeed` e nunca chegam à interface (FR-009).
  final bool isSignatureValid;

  /// Tags do evento, cada uma como `[chave, valor, ...]` — usadas para
  /// correlacionar um evento a outro (ex.: `["e", "<id>"]`) ou a um
  /// destinatário (`["p", "<pubkey>"]`). Lista vazia por padrão: até a
  /// feature 010, nenhum evento recebido pelo motorista precisava delas.
  final List<List<String>> tags;

  /// Kind da solicitação de carona, publicada pelo passageiro (emenda 04 do
  /// contrato de eventos, feature 006 do passageiro).
  static const int kindRideRequest = 20001;

  /// Kind do orçamento de carona, publicado pelo motorista em resposta a uma
  /// solicitação (emenda 05 do contrato de eventos, feature 007).
  static const int kindRideQuote = 20002;

  /// Kind da aceitação de orçamento, publicada pelo passageiro (emenda 07 do
  /// contrato de eventos, feature 008 do passageiro) — consumida pelo
  /// motorista pela primeira vez na feature 010 (emenda 08).
  static const int kindQuoteAccepted = 20003;

  /// Kind da localização do motorista, publicada enquanto ele estiver
  /// "Deslocando-se até o passageiro" (emenda 08 do contrato de eventos,
  /// feature 010).
  static const int kindDriverLocation = 20005;

  /// Kind do aviso de que uma corrida não pode mais ser atendida, publicado
  /// pelo motorista quando uma segunda aceitação chega enquanto ele já está
  /// comprometido com outra corrida (emenda 08 do contrato de eventos,
  /// feature 010).
  static const int kindRideNoLongerAvailable = 20006;

  /// Kind da chegada do motorista, publicado uma única vez por corrida
  /// quando a posição do motorista entra num raio de 30 m do ponto de
  /// origem da corrida ativa (emenda 09 do contrato de eventos, feature
  /// 011).
  static const int kindArrivalNotice = 20007;

  /// Kind do encontro confirmado, publicado pelo passageiro e consumido
  /// pelo motorista — transiciona de "Deslocando-se até o passageiro" para
  /// "Em corrida" (emenda 11 do contrato de eventos, feature 012).
  static const int kindMeetingConfirmed = 20008;

  /// Kind da chegada ao destino, publicado pelo motorista uma única vez
  /// por corrida quando sua posição entra num raio de 1 km do destino,
  /// durante "Em corrida" (emenda 11 do contrato de eventos, feature 012).
  static const int kindDestinationArrival = 20009;

  /// Kind do destino confirmado, publicado pelo passageiro e consumido
  /// pelo motorista — volta de "Em corrida" para "Aguardando solicitação
  /// de corrida" (emenda 11 do contrato de eventos, feature 012).
  static const int kindDestinationConfirmed = 20010;

  /// Kind da rota da corrida, publicado pelo motorista ao passageiro a cada
  /// cálculo ou recálculo bem-sucedido do trajeto até o destino, só em "Em
  /// corrida" (emenda 13 do contrato de eventos, feature 017).
  static const int kindRideRoute = 20011;

  /// Kind do cancelamento da corrida, publicado pelo motorista ao passageiro
  /// uma única vez por corrida cancelada em "Deslocando-se até o passageiro"
  /// ou "Em corrida" (emenda 14 do contrato de eventos, feature 018).
  static const int kindRideCancelled = 20012;

  /// Kind do cancelamento da corrida pelo passageiro, publicado por ele ao
  /// motorista depois de aceitar um orçamento e consumido aqui em
  /// "Deslocando-se até o passageiro" ou "Em corrida" (emenda 19 do contrato
  /// de eventos, feature 020).
  static const int kindRideCancelledByPassenger = 20013;

  /// O valor da primeira tag `["e", "<valor>"]`, ou `null` se ausente —
  /// referência a outro evento (ex.: o orçamento respondido por uma
  /// confirmação). Mesmo padrão já usado pelo `NostrEvent` do passageiro;
  /// aqui só a partir da feature 012, que passa a comparar diretamente
  /// contra `ActiveRide.quoteId` em vez de criar uma entidade de domínio
  /// dedicada para cada tipo de confirmação (D3 de
  /// `specs/012-confirmar-encontro-destino/research.md`).
  String? get referencedEventId {
    for (final tag in tags) {
      if (tag.length >= 2 && tag[0] == 'e') return tag[1];
    }
    return null;
  }

  /// O valor da primeira tag `["p", "<valor>"]`, ou `null` se ausente — o
  /// destinatário do evento (emenda 17: é com a chave dele que o `content`
  /// foi cifrado, e só ele o decifra).
  String? get recipientPublicKey {
    for (final tag in tags) {
      if (tag.length >= 2 && tag[0] == 'p') return tag[1];
    }
    return null;
  }

  @override
  bool operator ==(Object other) => other is NostrEvent && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
