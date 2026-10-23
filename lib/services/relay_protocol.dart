import 'dart:convert';

import '../domain/nostr_event.dart' as domain;
import 'prototype_marker.dart';

/// Frames do protocolo de relay (NIP-01) que o motorista monta e interpreta.
///
/// Tudo aqui é função pura, sem socket: o que chega do relay é entrada não
/// confiável de terceiros, então o interpretador devolve `null` para qualquer
/// coisa que não seja um frame bem formado, em vez de lançar. A assinatura do
/// evento **não** é verificada aqui: o frame entrega o payload bruto e quem
/// verifica é o `EventFeed` (contrato de eventos, regra 1).

/// Limite de tamanho de um frame recebido, em caracteres. O `content` vai até
/// 65 535 bytes (contrato, NIP-44); com tags, escape JSON e a moldura do frame
/// isso cabe em quatro vezes esse valor. Acima disso o texto nem é decodificado.
/// `dart:io` não deixa limitar antes de receber: isto poupa o trabalho de
/// decodificar, não o recebimento.
const int kMaxRelayMessageChars = 262144;

/// Inscrição com os kinds consumidos, exceto o `20001`. Sempre presente.
const String generalSubscriptionId = 'tcc-geral';

/// Inscrição do `20001`, com `#g`. Só existe com o motorista online.
const String rideRequestSubscriptionId = 'tcc-solicitacoes';

/// Inscrição efêmera da sonda de vivacidade.
const String probeSubscriptionId = 'vivacidade';

const String _nonexistentId =
    '0000000000000000000000000000000000000000000000000000000000000000';

/// Os filtros do `REQ` (emenda 27 do contrato): os kinds consumidos, exceto o
/// `20001`, num filtro sempre presente; o `20001` num filtro à parte, com o
/// `#g` das [cells], só quando há células (motorista online). Todos com o
/// marcador `#t` e `limit: 50`. Vazio se não há nada a pedir.
///
/// Sem `since`: a inscrição é refeita a cada conexão, e um `since` calculado
/// uma vez ficaria cada vez mais velho (emenda 02).
List<Map<String, dynamic>> buildFilters(List<int> kinds, List<String>? cells) {
  final outros = [
    for (final k in kinds)
      if (k != domain.NostrEvent.kindRideRequest) k,
  ];
  final querSolicitacoes = kinds.contains(domain.NostrEvent.kindRideRequest);
  return [
    if (outros.isNotEmpty)
      {
        'kinds': outros,
        '#t': const [prototypeMarker],
        'limit': 50,
      },
    if (querSolicitacoes && cells != null && cells.isNotEmpty)
      {
        'kinds': const [domain.NostrEvent.kindRideRequest],
        '#t': const [prototypeMarker],
        '#g': cells,
        'limit': 50,
      },
  ];
}

/// `["REQ", <id>, <filtro>, …]`.
String reqFrame(String subscriptionId, List<Map<String, dynamic>> filters) =>
    jsonEncode(['REQ', subscriptionId, ...filters]);

/// `["CLOSE", <id>]`.
String closeFrame(String subscriptionId) =>
    jsonEncode(['CLOSE', subscriptionId]);

/// `["EVENT", <evento>]`: o payload já assinado, sem reassinatura.
String eventFrame(Map<String, dynamic> payload) =>
    jsonEncode(['EVENT', payload]);

/// Consulta por um id inexistente: o relay responde `EOSE` sem entregar nada e
/// sem depender de kind nem de marcador.
String probeReqFrame() => jsonEncode([
  'REQ',
  probeSubscriptionId,
  {
    'ids': [_nonexistentId],
    'limit': 1,
  },
]);

sealed class RelayFrame {
  const RelayFrame();
}

/// `["EVENT", <inscrição>, <evento>]`: evento bruto, ainda não verificado.
class EventFrame extends RelayFrame {
  const EventFrame(this.subscriptionId, this.payload);

  final String subscriptionId;
  final Map<String, dynamic> payload;
}

/// `["OK", <id>, <aceito>, <mensagem>]`: resposta a uma publicação.
class OkFrame extends RelayFrame {
  const OkFrame(this.eventId, this.accepted, this.message);

  final String eventId;
  final bool accepted;

  /// Motivo informado pelo relay; nulo quando vazio ou ausente.
  final String? message;
}

/// `["NOTICE", <texto>]`: aviso livre do relay.
class NoticeFrame extends RelayFrame {
  const NoticeFrame(this.message);

  final String message;
}

/// `["EOSE", <inscrição>]`: fim do histórico guardado.
class EoseFrame extends RelayFrame {
  const EoseFrame(this.subscriptionId);

  final String subscriptionId;
}

/// `["CLOSED", <inscrição>, <mensagem>]`: o relay encerrou a inscrição.
class ClosedFrame extends RelayFrame {
  const ClosedFrame(this.subscriptionId, this.message);

  final String subscriptionId;
  final String? message;
}

/// Interpreta um frame recebido do relay. Devolve `null` — nunca lança — para
/// texto grande demais, JSON inválido ou truncado, tipo desconhecido e campos
/// ausentes ou de tipo errado.
RelayFrame? parseRelayFrame(String raw) {
  if (raw.length > kMaxRelayMessageChars) return null;
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    return null;
  }
  if (decoded is! List<dynamic> || decoded.isEmpty) return null;
  final List<dynamic> frame = decoded;

  String? textoEm(int i) =>
      frame.length > i && frame[i] is String ? frame[i] as String : null;

  switch (frame[0]) {
    case 'EVENT':
      final inscricao = textoEm(1);
      final evento = frame.length > 2 ? frame[2] : null;
      if (inscricao == null || evento is! Map) return null;
      return EventFrame(inscricao, Map<String, dynamic>.from(evento));
    case 'OK':
      final id = textoEm(1);
      final aceito = frame.length > 2 ? frame[2] : null;
      if (id == null || aceito is! bool) return null;
      final mensagem = textoEm(3);
      return OkFrame(
        id,
        aceito,
        mensagem == null || mensagem.isEmpty ? null : mensagem,
      );
    case 'NOTICE':
      final texto = textoEm(1);
      return texto == null ? null : NoticeFrame(texto);
    case 'EOSE':
      final inscricao = textoEm(1);
      return inscricao == null ? null : EoseFrame(inscricao);
    case 'CLOSED':
      final inscricao = textoEm(1);
      if (inscricao == null) return null;
      final mensagem = textoEm(2);
      return ClosedFrame(
        inscricao,
        mensagem == null || mensagem.isEmpty ? null : mensagem,
      );
    default:
      return null;
  }
}
