// Relay local mínimo para o roteiro da feature 027: guarda nada, entrega os
// eventos às inscrições abertas e **imprime cada quadro recebido** (REQ, CLOSE,
// EVENT), o que permite ver o que o app realmente pede ao relay — inclusive o
// `#g` — sem expor solicitações de teste a relays públicos.
//
// ignore_for_file: avoid_print — é uma ferramenta de linha de comando, em que a
// saída padrão é a própria interface; não faz parte do aplicativo.
//
// Uso: dart run tool/relay_local.dart [--porta=7777] [--ignora-g]
//   --ignora-g   entrega tudo, como um relay que não respeita o filtro `#g`.
//
// No emulador Android o computador é `10.0.2.2`: no app, em Mais → Relays,
// acrescente `ws://10.0.2.2:7777`. Dos scripts do computador, `ws://127.0.0.1:7777`.
// Só filtra por `kinds` e `#g` (o suficiente para esta feature) e responde `OK`.
import 'dart:convert';
import 'dart:io';

String _resumo(String dado) =>
    dado.length > 300 ? '${dado.substring(0, 300)}…' : dado;

Future<void> main(List<String> args) async {
  var porta = 7777;
  for (final a in args) {
    if (a.startsWith('--porta=')) porta = int.parse(a.substring(8));
  }
  final ignoraG = args.contains('--ignora-g');
  final servidor = await HttpServer.bind(InternetAddress.anyIPv4, porta);
  print('Relay local em ws://0.0.0.0:$porta${ignoraG ? ' (ignora #g)' : ''}');

  final inscricoes = <WebSocket, Map<String, Map<String, dynamic>>>{};
  var cliente = 0;
  await for (final req in servidor) {
    final ws = await WebSocketTransformer.upgrade(req);
    final n = ++cliente;
    final subs = inscricoes[ws] = {};
    print('[$n] conectou');
    ws.listen(
      (dado) {
        print('[$n] <- ${_resumo('$dado')}');
        final List<dynamic> m;
        try {
          m = jsonDecode(dado as String) as List<dynamic>;
        } on Object {
          return;
        }
        switch (m.first) {
          case 'REQ':
            // Um REQ com o mesmo id substitui o anterior (NIP-01); cada filtro
            // adicional do REQ vale por si (OU).
            subs[m[1] as String] = {'filtros': m.skip(2).toList()};
            ws.add(jsonEncode(['EOSE', m[1]]));
          case 'CLOSE':
            subs.remove(m[1]);
          case 'EVENT':
            final e = m[1] as Map<String, dynamic>;
            ws.add(jsonEncode(['OK', e['id'], true, '']));
            final gs = [
              for (final t in e['tags'] as List)
                if ((t as List)[0] == 'g') t[1] as String,
            ];
            for (final entry in inscricoes.entries) {
              for (final sub in entry.value.entries) {
                final filtros = sub.value['filtros'] as List;
                final casa = filtros.any((f) {
                  final filtro = f as Map<String, dynamic>;
                  if (!(filtro['kinds'] as List).contains(e['kind'])) {
                    return false;
                  }
                  final g = filtro['#g'] as List?;
                  return ignoraG || g == null || g.any(gs.contains);
                });
                if (casa) {
                  entry.key.add(jsonEncode(['EVENT', sub.key, e]));
                }
              }
            }
        }
      },
      onDone: () {
        inscricoes.remove(ws);
        print('[$n] desconectou');
      },
    );
  }
}
