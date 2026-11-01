import 'dart:async';
import 'dart:convert';

import 'package:driver/services/event_verifier.dart';
import 'package:driver/services/prototype_marker.dart';
import 'package:driver/services/relay_protocol.dart';
import 'package:driver/services/relay_transport.dart';

import 'config.dart';
import 'relogio.dart';

/// As duas identidades do período, só chaves **públicas** (hex).
class Identidades {
  const Identidades({required this.motorista, required this.passageiro});

  final String motorista;
  final String passageiro;

  /// `motorista`, `passageiro` ou `null` se [pub] não é de nenhuma.
  String? papelDe(String? pub) {
    if (pub == null) return null;
    if (pub == motorista) return 'motorista';
    if (pub == passageiro) return 'passageiro';
    return null;
  }
}

/// Metadados de um evento visto num relay. **Não existe campo `content`** nem
/// `sig` nem `tags`: o conteúdo nunca sai do payload verificado (FR-022).
class EventoObservado {
  EventoObservado({
    required this.relay,
    required this.kind,
    required this.id,
    required this.createdAt,
    required this.recebidoUtc,
    required this.autor,
    required this.destinatario,
  });

  final String relay;
  final int kind;
  final String id;
  final int createdAt;
  final DateTime recebidoUtc;

  /// Papel (`motorista`/`passageiro`) do autor, se for do período.
  final String? autor;

  /// Papel do destinatário (tag `p`), se for do período.
  final String? destinatario;

  factory EventoObservado.fromJson(Map<String, dynamic> j) => EventoObservado(
    relay: j['relay'] as String,
    kind: j['kind'] as int,
    id: j['id'] as String,
    createdAt: j['created_at'] as int,
    recebidoUtc: DateTime.parse(j['recebido_utc'] as String),
    autor: j['autor'] as String?,
    destinatario: j['destinatario'] as String?,
  );

  Map<String, Object?> toJson({int? ciclo}) => {
    'relay': relay,
    'kind': kind,
    'id': id,
    'created_at': createdAt,
    'recebido_utc': recebidoUtc.toUtc().toIso8601String(),
    'autor': autor,
    'destinatario': destinatario,
    'ciclo': ciclo,
  };
}

/// Cliente observador, independente dos aplicativos (FR-022 a FR-024, D4): abre
/// as mesmas URLs, só **lê** (`REQ`/`CLOSE`, nunca `EVENT`), verifica a
/// assinatura e grava metadados de eventos das duas identidades do período.
///
/// O observador aproxima, mas não mede, a chegada do evento ao aplicativo
/// destinatário.
class Observador {
  Observador({
    required this.transport,
    required this.verifier,
    required this.identidades,
    required this.relogio,
    this.relays = relaysDoRoteiro,
    this.aoRegistrar,
  });

  static const String idInscricao = 'e2e-obs';

  final RelayTransport transport;
  final EventVerifier verifier;
  final Identidades identidades;
  final Relogio relogio;
  final List<String> relays;

  /// Chamado a cada evento registrado (gravação em `eventos.jsonl`).
  final void Function(EventoObservado evento)? aoRegistrar;

  /// Número do ciclo em andamento, gravado junto de cada evento (informativo;
  /// a associação oficial é por janela de tempo e papéis, FR-024).
  int? cicloAtual;

  final Map<String, RelaySocket> _sockets = {};
  final Map<String, StreamSubscription<String>> _assinaturas = {};
  final Set<String> _prontos = {};
  final Set<String> _vistos = {};
  final List<EventoObservado> _eventos = [];
  final Map<String, int> invalidosPorRelay = {};
  int ignorados = 0;
  late final int _since;

  List<EventoObservado> get eventos => List.unmodifiable(_eventos);

  /// Relays conectados **e** com a inscrição confirmada por `EOSE`.
  List<String> get relaysProntos => [
    for (final r in relays)
      if (_sockets.containsKey(r) && _prontos.contains(r)) r,
  ];

  /// Verdadeiro se nenhum relay está conectado (rede do hospedeiro, D9).
  bool get todosCaidos => _sockets.isEmpty;

  Future<void> iniciar() async {
    _since =
        relogio
            .agora()
            .subtract(margemSinceObservador)
            .millisecondsSinceEpoch ~/
        1000;
    await garantirConexoes();
  }

  /// Reabre os relays que não estão conectados e reenvia a inscrição.
  Future<void> garantirConexoes() async {
    await Future.wait([
      for (final url in relays)
        if (!_sockets.containsKey(url)) _conectar(url),
    ]);
  }

  Future<void> _conectar(String url) async {
    final RelaySocket socket;
    try {
      socket = await transport.connect(url);
    } on Object {
      return; // relay fora do ar: o chamador vê em relaysProntos
    }
    _sockets[url] = socket;
    _assinaturas[url] = socket.messages.listen(
      (texto) => _aoReceber(url, texto),
      onError: (Object _) => _cair(url),
      onDone: () => _cair(url),
    );
    try {
      socket.send(_req());
    } on Object {
      _cair(url);
    }
  }

  String _req() {
    final ids = [identidades.motorista, identidades.passageiro];
    final kinds = [for (var k = 20001; k <= 20015; k++) k];
    return reqFrame(idInscricao, [
      {
        'authors': ids,
        'kinds': kinds,
        '#t': const [prototypeMarker],
        'since': _since,
      },
      {
        '#p': ids,
        'kinds': kinds,
        '#t': const [prototypeMarker],
        'since': _since,
      },
    ]);
  }

  void _cair(String url) {
    _prontos.remove(url);
    final socket = _sockets.remove(url);
    unawaited(_assinaturas.remove(url)?.cancel());
    if (socket != null) unawaited(socket.close());
  }

  void _aoReceber(String url, String texto) {
    final frame = parseRelayFrame(texto);
    if (frame is EoseFrame && frame.subscriptionId == idInscricao) {
      _prontos.add(url);
      return;
    }
    if (frame is! EventFrame || frame.subscriptionId != idInscricao) return;
    final payload = frame.payload;
    if (!hasPrototypeMarker(payload['tags'] as List<dynamic>?)) return;
    if (!verifier.isValid(payload)) {
      invalidosPorRelay.update(url, (v) => v + 1, ifAbsent: () => 1);
      return;
    }
    final id = payload['id'] as String;
    final kind = payload['kind'] as int;
    final autor = identidades.papelDe(payload['pubkey'] as String?);
    String? destinatario;
    for (final tag in (payload['tags'] as List<dynamic>? ?? const [])) {
      if (tag is List && tag.length >= 2 && tag[0] == 'p') {
        destinatario ??= identidades.papelDe(tag[1]?.toString());
      }
    }
    if (autor == null && destinatario == null) {
      ignorados++;
      return;
    }
    if (!_vistos.add('$url|$id')) return;
    final evento = EventoObservado(
      relay: url,
      kind: kind,
      id: id,
      createdAt: payload['created_at'] as int,
      recebidoUtc: relogio.agora(),
      autor: autor,
      destinatario: destinatario,
    );
    _eventos.add(evento);
    aoRegistrar?.call(evento);
  }

  /// O evento de [kind] do [autor] recebido em [apos] ou depois, no relay que o
  /// entregou primeiro.
  EventoObservado? primeiroEvento({
    required int kind,
    required String autor,
    required DateTime apos,
  }) {
    EventoObservado? melhor;
    for (final e in _eventos) {
      if (e.kind != kind || e.autor != autor) continue;
      if (e.recebidoUtc.isBefore(apos)) continue;
      if (melhor == null || e.recebidoUtc.isBefore(melhor.recebidoUtc)) {
        melhor = e;
      }
    }
    return melhor;
  }

  bool vistoEmAlgumRelay({
    required int kind,
    required String autor,
    required DateTime apos,
  }) => primeiroEvento(kind: kind, autor: autor, apos: apos) != null;

  /// Eventos recebidos no intervalo [de, ate] (associação a ciclo por janela
  /// de tempo e papéis, FR-024).
  List<EventoObservado> naJanela(DateTime de, DateTime ate) => [
    for (final e in _eventos)
      if (!e.recebidoUtc.isBefore(de) && !e.recebidoUtc.isAfter(ate)) e,
  ];

  /// Contagem de eventos entregues por relay.
  Map<String, int> contagemPorRelay() {
    final m = <String, int>{for (final r in relays) r: 0};
    for (final e in _eventos) {
      m.update(e.relay, (v) => v + 1, ifAbsent: () => 1);
    }
    return m;
  }

  Future<void> parar() async {
    for (final url in _sockets.keys.toList()) {
      try {
        _sockets[url]?.send(jsonEncode(['CLOSE', idInscricao]));
      } on Object {
        // já caiu
      }
      _cair(url);
    }
  }
}
