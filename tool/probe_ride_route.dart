// Sonda manual: publica um kind 20011 com o tamanho máximo do contrato
// (1000 pontos) em cada relay padrão e confere a aceitação (OK) e a entrega a
// uma segunda conexão inscrita — o kind é efêmero, então os relays não o
// guardam e "recuperar depois" não se aplica (feature 017, T013).
//
// ignore_for_file: avoid_print — é uma ferramenta de linha de comando, em que a
// saída padrão é a própria interface; não faz parte do aplicativo.
// Uso: dart run tool/probe_ride_route.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_nostr/dart_nostr.dart' as nostr;
import 'package:driver/domain/nostr_event.dart';
import 'package:driver/domain/ride_route_content.dart';
import 'package:driver/services/default_relays.dart';
import 'package:driver/services/prototype_marker.dart';
import 'package:latlong2/latlong.dart';

Future<void> main() async {
  // Rota sintética de ~30 km com 2500 pontos: exercita também a redução.
  final pontos = [
    for (var i = 0; i < 2500; i++)
      LatLng(-28.9 + i * 0.0001, -49.4 + i * 0.00008),
  ];
  final content = RideRouteContent.encode(pontos);
  print('content: ${utf8.encode(content).length} bytes');

  final par = nostr.Nostr.instance.services.keys.generateKeyPair();
  for (final url in defaultRelayUrls) {
    final evento = nostr.NostrEvent.fromPartialData(
      kind: NostrEvent.kindRideRoute,
      content: content,
      keyPairs: par,
      tags: [
        prototypeMarkerTag,
        // Os relays validam `e` e `p` como ids hex de 32 bytes.
        ['e', '0' * 64],
        ['p', '1' * 64],
      ],
    );
    final mensagem = jsonEncode([
      'EVENT',
      {
        'id': evento.id,
        'pubkey': evento.pubkey,
        'created_at': evento.createdAt!.millisecondsSinceEpoch ~/ 1000,
        'kind': evento.kind,
        'tags': evento.tags,
        'content': evento.content,
        'sig': evento.sig,
      },
    ]);
    print('$url -> mensagem de ${utf8.encode(mensagem).length} bytes');

    WebSocket? assinante;
    WebSocket? publicador;
    try {
      assinante = await WebSocket.connect(url)
          .timeout(const Duration(seconds: 10));
      publicador = await WebSocket.connect(url)
          .timeout(const Duration(seconds: 10));

      final entregue = Completer<bool>();
      assinante.listen((dado) {
        final m = jsonDecode(dado as String) as List<dynamic>;
        if (m.first == 'EVENT' &&
            (m[2] as Map<String, dynamic>)['id'] == evento.id &&
            !entregue.isCompleted) {
          entregue.complete(true);
        }
      });
      assinante.add(
        jsonEncode([
          'REQ',
          'sonda',
          {
            'kinds': [NostrEvent.kindRideRoute],
            '#t': ['tcc-ufsc-caronas'],
            'authors': [par.public],
          },
        ]),
      );
      await Future<void>.delayed(const Duration(seconds: 1));

      final ok = Completer<String>();
      publicador.listen((dado) {
        final m = jsonDecode(dado as String) as List<dynamic>;
        if (m.first == 'OK' && m[1] == evento.id && !ok.isCompleted) {
          ok.complete('aceito=${m[2]} ${m.length > 3 ? m[3] : ''}');
        } else if (m.first == 'NOTICE' && !ok.isCompleted) {
          ok.complete('NOTICE ${m.sublist(1)}');
        }
      });
      publicador.add(mensagem);

      final resposta = await ok.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => 'sem resposta em 10 s',
      );
      final chegou = await entregue.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => false,
      );
      print('   OK: $resposta | entregue à 2ª conexão: $chegou');
    } on Object catch (erro) {
      print('   falha: $erro');
    } finally {
      await assinante?.close();
      await publicador?.close();
    }
  }
}
