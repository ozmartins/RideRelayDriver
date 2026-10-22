// Publica uma solicitação de corrida (`kind: 20001`, emenda 27) de teste, para
// exercitar o motorista sem o app do passageiro: a origem e a tag `g` são
// escolhidas na linha de comando (feature 027, roteiro do quickstart).
//
// ignore_for_file: avoid_print — é uma ferramenta de linha de comando, em que a
// saída padrão é a própria interface; não faz parte do aplicativo.
//
// Uso:
//   dart run tool/publish_ride_request.dart --lat=-28.9298 --lon=-49.4753
//   dart run tool/publish_ride_request.dart --lat=-28.9298 --lon=-49.4753 --sem-g
//   dart run tool/publish_ride_request.dart --lat=-28.9298 --lon=-49.4753 --g-de=-23.5505,-46.6333
//   Opções: --relay=URL (repetível; padrão: relays do app), --pagamento=pix|dinheiro|cartao
//
// --sem-g          publica só com o marcador, como uma solicitação anterior à emenda 27.
// --g-de=LAT,LON   calcula as três tags `g` de outro ponto, deixando a origem do `content`
//                  onde está (tag incoerente com a origem).
//
// O evento é efêmero e assinado por uma chave descartável, mas vai a relays
// públicos de verdade: **qualquer app do motorista online na região, conectado
// ao mesmo relay, pode mostrá-lo.**
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_nostr/dart_nostr.dart' as nostr;
import 'package:driver/domain/geohash.dart';
import 'package:driver/domain/nostr_event.dart';
import 'package:driver/services/default_relays.dart';
import 'package:driver/services/prototype_marker.dart';

String? _opcao(List<String> args, String nome) {
  for (final a in args) {
    if (a.startsWith('--$nome=')) return a.substring(nome.length + 3);
  }
  return null;
}

Future<void> main(List<String> args) async {
  final lat = double.tryParse(_opcao(args, 'lat') ?? '');
  final lon = double.tryParse(_opcao(args, 'lon') ?? '');
  if (lat == null || lon == null) {
    print('Informe --lat=… e --lon=… (veja o cabeçalho do arquivo).');
    exitCode = 64;
    return;
  }
  final pagamento = _opcao(args, 'pagamento') ?? 'pix';
  final relays = [
    for (final a in args)
      if (a.startsWith('--relay=')) a.substring('--relay='.length),
  ];

  var gLat = lat, gLon = lon;
  final gDe = _opcao(args, 'g-de');
  if (gDe != null) {
    final partes = gDe.split(',');
    gLat = double.parse(partes[0]);
    gLon = double.parse(partes[1]);
  }
  final semG = args.contains('--sem-g');

  final chaves = nostr.Nostr.instance.services.keys.generateKeyPair();
  final evento = nostr.NostrEvent.fromPartialData(
    kind: NostrEvent.kindRideRequest,
    content: jsonEncode({
      'origin': {'lat': lat, 'lon': lon},
      'destination': {'lat': lat + 0.01, 'lon': lon + 0.01},
      'payment': pagamento,
    }),
    keyPairs: chaves,
    tags: [
      prototypeMarkerTag,
      if (!semG)
        for (final p in kPrecisoesDaTag) ['g', Geohash.encode(gLat, gLon, p)],
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
  print('origem ($lat, $lon), pagamento $pagamento, tags: ${evento.tags}');

  for (final url in relays.isEmpty ? defaultRelayUrls : relays) {
    WebSocket? ws;
    try {
      ws = await WebSocket.connect(url).timeout(const Duration(seconds: 10));
      final ok = Completer<String>();
      ws.listen((dado) {
        final m = jsonDecode(dado as String) as List<dynamic>;
        if (m.first == 'OK' && m[1] == evento.id && !ok.isCompleted) {
          ok.complete('aceito=${m[2]}${m.length > 3 ? ' ${m[3]}' : ''}');
        }
      });
      ws.add(mensagem);
      final resposta = await ok.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => 'sem OK em 5 s',
      );
      print('$url: $resposta');
    } on Object catch (erro) {
      print('$url: falha ($erro)');
    } finally {
      await ws?.close();
    }
  }
}
