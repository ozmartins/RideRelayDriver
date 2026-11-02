// Sonda manual (feature 027, T034): mede, relay por relay, se o filtro `#g` do
// `kind: 20001` é respeitado e se o `CLOSE` ao trocar a inscrição é honrado
// (R7 de `specs/027-filtro-geografico-solicitacoes/research.md`).
//
// Para cada relay, com duas conexões (uma assina, outra publica) e chaves
// descartáveis geradas na hora:
//   A. inscreve-se com `#g` = 9 células de Araranguá; publica uma solicitação de
//      teste com origem em Araranguá (dentro) e outra em São Paulo (fora).
//   B. envia `CLOSE` da inscrição A e publica de novo uma de Araranguá: se ela
//      chegar à conexão que assina, o `CLOSE` não foi honrado.
//   C. abre outra inscrição com as 9 células de São Paulo e publica uma de cada
//      cidade: só a de São Paulo deve chegar (a troca de células funciona).
//
// O `20001` é efêmero (faixa 20000–29999 do NIP-01): os relays não o retêm. Mesmo
// assim os eventos vão a relays públicos de verdade, com o marcador do protótipo
// e o `content` no formato da emenda 04 — **um app do motorista online em
// Araranguá ou em São Paulo, conectado ao mesmo relay, pode mostrar a solicitação
// de teste.** Rode com os apps fechados ou fora dessas regiões.
//
// ignore_for_file: avoid_print — é uma ferramenta de linha de comando, em que a
// saída padrão é a própria interface; não faz parte do aplicativo.
//
// Uso:
//   dart run tool/probe_geohash_filter.dart                  # relays padrão do app
//   dart run tool/probe_geohash_filter.dart --relay=ws://localhost:7777 [--relay=...]
//
// Cada resposta é lida do que o relay devolve nesta execução; nada é suposto. O
// resultado só vale para o relay e o instante medidos: registre-o no research.md
// com a data e este método.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_nostr/dart_nostr.dart' as nostr;
import 'package:driver/domain/driver_coverage.dart';
import 'package:driver/domain/geohash.dart';
import 'package:driver/domain/nostr_event.dart';
import 'package:driver/services/default_relays.dart';
import 'package:driver/services/prototype_marker.dart';

const _araranguaLat = -28.9298, _araranguaLon = -49.4753;
const _saoPauloLat = -23.5505, _saoPauloLon = -46.6333;
const _espera = Duration(seconds: 5);
const _esperaDoClose = Duration(seconds: 3);
const _conexao = Duration(seconds: 10);

/// Uma conexão WebSocket que guarda o que o relay devolve.
class _Conexao {
  _Conexao(this._socket) {
    _socket.listen(_aoReceber, onError: (_) {}, onDone: () => fechada = true);
  }

  static Future<_Conexao> abrir(String url) async =>
      _Conexao(await WebSocket.connect(url).timeout(_conexao));

  final WebSocket _socket;
  bool fechada = false;

  /// Ids entregues por inscrição.
  final Map<String, Set<String>> entregues = {};
  final Map<String, Completer<void>> _eose = {};
  final Map<String, Completer<String>> _ok = {};
  final List<String> avisos = [];

  void _aoReceber(dynamic dado) {
    if (dado is! String) return;
    final List<dynamic> m;
    try {
      m = jsonDecode(dado) as List<dynamic>;
    } on Object {
      return;
    }
    switch (m.first) {
      case 'EVENT':
        final id = (m[2] as Map<String, dynamic>)['id'] as String;
        (entregues[m[1] as String] ??= {}).add(id);
      case 'EOSE':
        _eose[m[1] as String]?.complete();
      case 'OK':
        _ok[m[1] as String]?.complete(
          'aceito=${m[2]}${m.length > 3 && '${m[3]}'.isNotEmpty ? ' (${m[3]})' : ''}',
        );
      case 'NOTICE' || 'CLOSED':
        avisos.add(m.join(' '));
    }
  }

  void enviar(Object mensagem) => _socket.add(jsonEncode(mensagem));

  /// Abre a inscrição [id] e espera o EOSE (ou [_espera]); devolve o tempo.
  Future<Duration> assinar(String id, Map<String, Object?> filtro) async {
    final sw = Stopwatch()..start();
    final eose = _eose[id] = Completer<void>();
    enviar(['REQ', id, filtro]);
    await eose.future.timeout(_espera, onTimeout: () {});
    return sw.elapsed;
  }

  /// Publica o evento e devolve a resposta `OK` do relay (ou o motivo de não ter).
  Future<String> publicar(Map<String, Object?> evento) async {
    final id = evento['id'] as String;
    final ok = _ok[id] = Completer<String>();
    enviar(['EVENT', evento]);
    return ok.future.timeout(_espera, onTimeout: () => 'sem OK em 5 s');
  }

  Future<void> fechar() async {
    try {
      await _socket.close();
    } on Object {
      // Melhor-esforço.
    }
  }
}

/// Solicitação de teste (emenda 04) com as três tags `g` da emenda 27.
Map<String, Object?> _solicitacao(
  nostr.NostrKeyPairs chaves,
  double lat,
  double lon,
  String rotulo,
) {
  final evento = nostr.NostrEvent.fromPartialData(
    kind: NostrEvent.kindRideRequest,
    content: jsonEncode({
      'origin': {'lat': lat, 'lon': lon},
      'destination': {'lat': lat + 0.01, 'lon': lon + 0.01},
      'payment': 'pix',
      // Aviso humano; campo fora do contrato, ignorado por quem o lê.
      'sonda': 'teste de filtro #g da feature 027 ($rotulo): ignore',
    }),
    keyPairs: chaves,
    tags: [
      prototypeMarkerTag,
      for (final p in kPrecisoesDaTag) ['g', Geohash.encode(lat, lon, p)],
    ],
  );
  return {
    'id': evento.id,
    'pubkey': evento.pubkey,
    'created_at': evento.createdAt!.millisecondsSinceEpoch ~/ 1000,
    'kind': evento.kind,
    'tags': evento.tags,
    'content': evento.content,
    'sig': evento.sig,
  };
}

Map<String, Object?> _filtro(List<String> celulas) => {
  'kinds': [NostrEvent.kindRideRequest],
  '#t': [prototypeMarker],
  '#g': celulas,
};

String _sim(bool v) => v ? 'sim' : 'não';

/// Resultado de um relay, para o resumo final.
class _Resultado {
  _Resultado(this.url);
  final String url;
  String? falha;
  bool? respeitaG;
  bool? closeHonrado;
  Duration? eoseA;
}

Future<_Resultado> _medir(String url) async {
  final r = _Resultado(url);
  print('\n== $url');
  _Conexao? assina;
  _Conexao? publica;
  try {
    assina = await _Conexao.abrir(url);
    publica = await _Conexao.abrir(url);
    final chaves = nostr.Nostr.instance.services.keys.generateKeyPair();

    final celulasAra = DriverCoverage.around(
      lat: _araranguaLat,
      lon: _araranguaLon,
      radiusKm: 10,
    ).cells;
    final celulasSp = DriverCoverage.around(
      lat: _saoPauloLat,
      lon: _saoPauloLon,
      radiusKm: 10,
    ).cells;

    // --- A: células de Araranguá; uma de cada cidade.
    r.eoseA = await assina.assinar('g-a', _filtro(celulasAra));
    print(
      '   A: EOSE em ${r.eoseA!.inMilliseconds} ms (${celulasAra.length} células)',
    );
    final dentroA = _solicitacao(
      chaves,
      _araranguaLat + 0.027,
      _araranguaLon,
      'A dentro',
    );
    final foraA = _solicitacao(chaves, _saoPauloLat, _saoPauloLon, 'A fora');
    final okDentroA = await publica.publicar(dentroA);
    final okForaA = await publica.publicar(foraA);
    await Future<void>.delayed(_espera);
    final chegouDentroA =
        assina.entregues['g-a']?.contains(dentroA['id']) ?? false;
    final chegouForaA = assina.entregues['g-a']?.contains(foraA['id']) ?? false;
    print('      publicou dentro: $okDentroA | fora: $okForaA');
    print(
      '      chegou: dentro=${_sim(chegouDentroA)} fora=${_sim(chegouForaA)}',
    );

    // --- B: CLOSE e nova publicação em Araranguá.
    assina.enviar(['CLOSE', 'g-a']);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final dentroB = _solicitacao(
      chaves,
      _araranguaLat + 0.027,
      _araranguaLon,
      'B depois do CLOSE',
    );
    final okB = await publica.publicar(dentroB);
    await Future<void>.delayed(_esperaDoClose);
    final chegouB = assina.entregues['g-a']?.contains(dentroB['id']) ?? false;
    print(
      '   B: depois do CLOSE publicou: $okB | chegou à inscrição fechada: ${_sim(chegouB)}',
    );

    // --- C: outra inscrição com as células de São Paulo.
    await assina.assinar('g-c', _filtro(celulasSp));
    final dentroC = _solicitacao(
      chaves,
      _araranguaLat + 0.027,
      _araranguaLon,
      'C Araranguá',
    );
    final foraC = _solicitacao(
      chaves,
      _saoPauloLat,
      _saoPauloLon,
      'C São Paulo',
    );
    final okDentroC = await publica.publicar(dentroC);
    final okForaC = await publica.publicar(foraC);
    await Future<void>.delayed(_espera);
    final chegouAraC =
        assina.entregues['g-c']?.contains(dentroC['id']) ?? false;
    final chegouSpC = assina.entregues['g-c']?.contains(foraC['id']) ?? false;
    print('   C: publicou Araranguá: $okDentroC | São Paulo: $okForaC');
    print(
      '      chegou: Araranguá=${_sim(chegouAraC)} São Paulo=${_sim(chegouSpC)}',
    );

    for (final aviso in [...assina.avisos, ...publica.avisos]) {
      print('   aviso do relay: $aviso');
    }

    // Conclusões: só afirma o que a medição sustenta.
    if (chegouDentroA && !chegouForaA && chegouSpC && !chegouAraC) {
      r.respeitaG = true;
    } else if (chegouDentroA && chegouForaA) {
      r.respeitaG = false; // entregou o que o filtro excluía
    } // senão: inconclusivo (o relay nem entregou o de dentro, ou recusou publicar)
    if (chegouDentroA) r.closeHonrado = !chegouB;
  } on Object catch (erro) {
    r.falha = '$erro';
    print('   falha: $erro');
  } finally {
    await assina?.fechar();
    await publica?.fechar();
  }
  return r;
}

Future<void> main(List<String> args) async {
  final relays = [
    for (final a in args)
      if (a.startsWith('--relay=')) a.substring('--relay='.length),
  ];
  final alvos = relays.isEmpty ? defaultRelayUrls : relays;
  print(
    'Sonda do filtro #g (feature 027) — ${DateTime.now().toUtc().toIso8601String()}',
  );
  print('Relays: ${alvos.join(', ')}');

  final resultados = <_Resultado>[];
  for (final url in alvos) {
    resultados.add(await _medir(url));
  }

  print('\n== Resumo (vale só para estes relays e este instante)');
  for (final r in resultados) {
    final g = switch (r.respeitaG) {
      true => 'respeita #g',
      false => 'IGNORA #g (entregou o que o filtro excluía)',
      null => 'inconclusivo',
    };
    final close = switch (r.closeHonrado) {
      true => 'CLOSE honrado',
      false => 'CLOSE NÃO honrado',
      null => 'CLOSE inconclusivo',
    };
    print('${r.url}: ${r.falha != null ? 'falha (${r.falha})' : '$g; $close'}');
  }
}
