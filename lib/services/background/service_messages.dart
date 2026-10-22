import '../../domain/driver_coverage.dart';
import '../../domain/relay.dart';
import '../../domain/service_state.dart';
import '../relay_gateway.dart';

/// Mensagens entre a interface e o serviço em segundo plano — contrato interno
/// em `specs/025-conexao-em-segundo-plano/contracts/service-channel.md`.
///
/// Cada mensagem vira um `Map<String, dynamic>` só de tipos primitivos (é o que
/// o canal entre isolates aceita), com o tipo em `t` e a versão em `v`.
/// **Nenhuma mensagem carrega chave privada, semente ou texto decifrado**
/// (Princípio I): quem assina e cifra é a interface, e o serviço só repassa o
/// evento pronto.
sealed class ServiceMessage {
  const ServiceMessage();

  static const int version = 1;

  /// Tipo da mensagem, o valor do campo `t`.
  String get type;

  Map<String, dynamic> toMap() => {'t': type, 'v': version, ...body()};

  /// Campos próprios de cada mensagem.
  Map<String, dynamic> body();

  /// Lê uma mensagem recebida do canal. Devolve `null` — nunca lança — para
  /// dado que não é mapa, de outra versão, de tipo desconhecido ou
  /// malformado: o que chega pelo canal é entrada, não instrução.
  static ServiceMessage? fromMap(Object? raw) {
    if (raw is! Map || raw['v'] != version) return null;
    final map = Map<String, dynamic>.from(raw);
    try {
      return switch (map['t']) {
        'ready' => const ServiceReady(),
        'hello' => ServiceHello(foreground: map['foreground'] as bool),
        'helloAck' => ServiceHelloAck(
          online: map['online'] as bool,
          relays: _relays(map['relays']),
          pending: _payloads(map['pending']),
        ),
        'state' => ServiceStateUpdate(
          ServiceState.fromJson(Map<String, dynamic>.from(map['state'] as Map)),
        ),
        'connectAll' => ServiceConnectAll(_relays(map['relays'])),
        'addRelay' => ServiceAddRelay(map['url'] as String),
        'removeRelay' => ServiceRemoveRelay(map['url'] as String),
        'reconnectNow' => const ServiceReconnectNow(),
        'publish' => ServicePublish(
          reqId: map['reqId'] as int,
          id: map['id'] as String,
          payload: Map<String, dynamic>.from(map['payload'] as Map),
        ),
        'publishResult' => ServicePublishResult(
          reqId: map['reqId'] as int,
          outcomes: ((map['outcomes'] as List?) ?? const [])
              .map(
                (o) => PublishOutcome(
                  relayUrl: (o as Map)['relayUrl'] as String,
                  accepted: o['accepted'] as bool,
                  message: o['message'] as String?,
                ),
              )
              .toList(),
          done: map['done'] as bool,
          error: map['error'] as String?,
        ),
        'relaysChanged' => ServiceRelaysChanged(_relays(map['relays'])),
        'incoming' => ServiceIncoming(
          relayUrl: map['relayUrl'] as String,
          payload: Map<String, dynamic>.from(map['payload'] as Map),
        ),
        'coverage' => ServiceSetCoverage(
          map['coverage'] == null
              ? null
              : DriverCoverage.fromJson(map['coverage']),
        ),
        'stop' => const ServiceStop(),
        _ => null,
      };
    } on Object {
      return null;
    }
  }

  static List<Relay> _relays(Object? raw) => ((raw as List?) ?? const [])
      .map(
        (r) => Relay(
          url: (r as Map)['url'] as String,
          status: r['status'] == null
              ? RelayStatus.connecting
              : RelayStatus.values.byName(r['status'] as String),
          lastError: r['error'] as String?,
          isDefault: r['isDefault'] == true,
        ),
      )
      .toList();

  static List<Map<String, dynamic>> _payloads(Object? raw) =>
      ((raw as List?) ?? const [])
          .map((p) => Map<String, dynamic>.from(p as Map))
          .toList();

  static List<Map<String, dynamic>> relaysToMaps(List<Relay> relays) => [
    for (final r in relays)
      {
        'url': r.url,
        'status': r.status.name,
        'error': r.lastError,
        'isDefault': r.isDefault,
      },
  ];
}

/// S→UI: o isolate do serviço está de pé; até recebê-la a interface enfileira
/// os comandos.
class ServiceReady extends ServiceMessage {
  const ServiceReady();
  @override
  String get type => 'ready';
  @override
  Map<String, dynamic> body() => {};
}

/// UI→S: handshake ao abrir o app ou voltar ao primeiro plano.
class ServiceHello extends ServiceMessage {
  const ServiceHello({required this.foreground});
  final bool foreground;
  @override
  String get type => 'hello';
  @override
  Map<String, dynamic> body() => {'foreground': foreground};
}

/// S→UI: resposta ao `hello`, com o estado atual e as solicitações guardadas
/// (no máximo 5 minutos) enquanto a interface não estava aberta.
class ServiceHelloAck extends ServiceMessage {
  const ServiceHelloAck({
    required this.online,
    required this.relays,
    required this.pending,
  });
  final bool online;
  final List<Relay> relays;
  final List<Map<String, dynamic>> pending;
  @override
  String get type => 'helloAck';
  @override
  Map<String, dynamic> body() => {
    'online': online,
    'relays': ServiceMessage.relaysToMaps(relays),
    'pending': pending,
  };
}

/// UI→S: o estado de que o serviço precisa para decidir notificar.
class ServiceStateUpdate extends ServiceMessage {
  const ServiceStateUpdate(this.state);
  final ServiceState state;
  @override
  String get type => 'state';
  @override
  Map<String, dynamic> body() => {'state': state.toJson()};
}

/// UI→S: substitui a lista de relays e conecta a todos.
class ServiceConnectAll extends ServiceMessage {
  const ServiceConnectAll(this.relays);
  final List<Relay> relays;
  @override
  String get type => 'connectAll';
  @override
  Map<String, dynamic> body() => {
    'relays': ServiceMessage.relaysToMaps(relays),
  };
}

class ServiceAddRelay extends ServiceMessage {
  const ServiceAddRelay(this.url);
  final String url;
  @override
  String get type => 'addRelay';
  @override
  Map<String, dynamic> body() => {'url': url};
}

class ServiceRemoveRelay extends ServiceMessage {
  const ServiceRemoveRelay(this.url);
  final String url;
  @override
  String get type => 'removeRelay';
  @override
  Map<String, dynamic> body() => {'url': url};
}

class ServiceReconnectNow extends ServiceMessage {
  const ServiceReconnectNow();
  @override
  String get type => 'reconnectNow';
  @override
  Map<String, dynamic> body() => {};
}

/// UI→S: publica um evento **já assinado e cifrado** pela interface.
class ServicePublish extends ServiceMessage {
  const ServicePublish({
    required this.reqId,
    required this.id,
    required this.payload,
  });
  final int reqId;
  final String id;
  final Map<String, dynamic> payload;
  @override
  String get type => 'publish';
  @override
  Map<String, dynamic> body() => {'reqId': reqId, 'id': id, 'payload': payload};
}

/// S→UI: um [PublishOutcome] por mensagem; `done` fecha o fluxo. [error] só
/// vem junto de `done` — `no_relay` quando nenhum relay estava conectado.
class ServicePublishResult extends ServiceMessage {
  const ServicePublishResult({
    required this.reqId,
    required this.outcomes,
    required this.done,
    this.error,
  });
  final int reqId;
  final List<PublishOutcome> outcomes;
  final bool done;
  final String? error;
  @override
  String get type => 'publishResult';
  @override
  Map<String, dynamic> body() => {
    'reqId': reqId,
    'outcomes': [
      for (final o in outcomes)
        {'relayUrl': o.relayUrl, 'accepted': o.accepted, 'message': o.message},
    ],
    'done': done,
    'error': error,
  };
}

/// S→UI: o estado de algum relay mudou.
class ServiceRelaysChanged extends ServiceMessage {
  const ServiceRelaysChanged(this.relays);
  final List<Relay> relays;
  @override
  String get type => 'relaysChanged';
  @override
  Map<String, dynamic> body() => {
    'relays': ServiceMessage.relaysToMaps(relays),
  };
}

/// S→UI: evento recebido de um relay, **já verificado** (assinatura com o `id`
/// recalculado, marcador e deduplicação) pelo serviço.
class ServiceIncoming extends ServiceMessage {
  const ServiceIncoming({required this.relayUrl, required this.payload});
  final String relayUrl;
  final Map<String, dynamic> payload;
  @override
  String get type => 'incoming';
  @override
  Map<String, dynamic> body() => {'relayUrl': relayUrl, 'payload': payload};
}

/// UI→S: encerra o serviço.
class ServiceStop extends ServiceMessage {
  const ServiceStop();
  @override
  String get type => 'stop';
  @override
  Map<String, dynamic> body() => {};
}

/// UI→S: a cobertura geográfica do motorista online (feature 027), ou `null`
/// ao ficar offline. O serviço a guarda **só em memória** — nunca no
/// `ServiceStateStore`, em log ou em notificação (constituição 2.18.0) — e a usa
/// para pedir o `20001` das células certas e para decidir notificar com o
/// mesmo corte por raio da interface.
class ServiceSetCoverage extends ServiceMessage {
  const ServiceSetCoverage(this.coverage);
  final DriverCoverage? coverage;
  @override
  String get type => 'coverage';
  @override
  Map<String, dynamic> body() => {'coverage': coverage?.toJson()};
}
