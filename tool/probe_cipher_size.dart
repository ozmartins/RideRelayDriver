// Sonda offline (sem rede): mede o custo da cifra NIP-44 do motorista —
// tempo do primeiro ECDH de um par, tempo médio de cifrar e decifrar depois
// dele, e o tamanho da mensagem `EVENT` do kind 20011 com 1000 pontos já
// cifrado (feature 019, SC-004 e SC-005; D4 e D6 de
// `specs/019-mensagens-cifradas/research.md`).
//
// ignore_for_file: avoid_print — é uma ferramenta de linha de comando, em que a
// saída padrão é a própria interface; não faz parte do aplicativo.
// Uso: dart run tool/probe_cipher_size.dart
//
// Roda na VM do Dart do computador: serve de referência relativa, não de
// medida do aparelho. O valor que vale para SC-004 é o do emulador/aparelho
// (rodar a mesma conta dentro do app em modo release).
import 'dart:convert';

import 'package:dart_nostr/dart_nostr.dart' as nostr;
import 'package:driver/domain/identity.dart';
import 'package:driver/domain/nostr_event.dart';
import 'package:driver/domain/ride_route_content.dart';
import 'package:driver/services/message_cipher.dart';
import 'package:driver/services/prototype_marker.dart';
import 'package:latlong2/latlong.dart';

Identity _nova() {
  final par = nostr.Nostr.instance.services.keys.generateKeyPair();
  return Identity(publicKey: par.public, privateKey: par.private);
}

double _ms(Stopwatch sw) => sw.elapsedMicroseconds / 1000;

void main() {
  const repeticoes = 200;
  final motorista = _nova();
  final passageiro = _nova();

  // 1. Primeiro ECDH de um par (o passo caro, que roda na thread de UI).
  final primeiros = <double>[];
  for (var i = 0; i < 10; i++) {
    final par = _nova();
    final c = MessageCipher();
    final sw = Stopwatch()..start();
    c.encryptFor(motorista, par.publicKey, '{"lat":-28.93,"lon":-49.48}');
    primeiros.add(_ms(sw));
  }
  primeiros.sort();
  print(
    'primeiro ECDH + cifrar (10 pares novos): '
    'mediana ${primeiros[5].toStringAsFixed(1)} ms, '
    'máximo ${primeiros.last.toStringAsFixed(1)} ms',
  );

  // 2. Cifrar/decifrar uma localização depois do primeiro ECDH.
  final cifraM = MessageCipher();
  final cifraP = MessageCipher();
  const localizacao = '{"lat":-28.93123,"lon":-49.48891}';
  cifraM.encryptFor(motorista, passageiro.publicKey, localizacao);
  final swC = Stopwatch()..start();
  late String payload;
  for (var i = 0; i < repeticoes; i++) {
    payload = cifraM.encryptFor(motorista, passageiro.publicKey, localizacao);
  }
  final cifrar = _ms(swC) / repeticoes;
  cifraP.decryptFrom(passageiro, motorista.publicKey, payload);
  final swD = Stopwatch()..start();
  for (var i = 0; i < repeticoes; i++) {
    cifraP.decryptFrom(passageiro, motorista.publicKey, payload);
  }
  final decifrar = _ms(swD) / repeticoes;
  print(
    'localização (${utf8.encode(localizacao).length} B, '
    'payload ${payload.length} B): cifrar ${cifrar.toStringAsFixed(2)} ms, '
    'decifrar ${decifrar.toStringAsFixed(2)} ms (média de $repeticoes)',
  );

  // 3. Rota de 1000 pontos: tempo e tamanho da mensagem EVENT cifrada.
  final pontos = [
    for (var i = 0; i < 2500; i++)
      LatLng(-28.9 + i * 0.0001, -49.4 + i * 0.00008),
  ];
  final rota = RideRouteContent.encode(pontos);
  final swR = Stopwatch()..start();
  final rotaCifrada = cifraM.encryptFor(motorista, passageiro.publicKey, rota);
  final tCifrarRota = _ms(swR);
  swR
    ..reset()
    ..start();
  cifraP.decryptFrom(passageiro, motorista.publicKey, rotaCifrada);
  final tDecifrarRota = _ms(swR);

  final evento = nostr.NostrEvent.fromPartialData(
    kind: NostrEvent.kindRideRoute,
    content: rotaCifrada,
    keyPairs: nostr.NostrKeyPairs(private: motorista.privateKey),
    tags: [
      prototypeMarkerTag,
      ['e', '0' * 64],
      ['p', passageiro.publicKey],
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
  const menorLimite = 131072; // menor max_message_length anunciado (D6)
  final bytes = utf8.encode(mensagem).length;
  print(
    'rota de 1000 pontos: texto ${utf8.encode(rota).length} B, '
    'cifrar ${tCifrarRota.toStringAsFixed(1)} ms, '
    'decifrar ${tDecifrarRota.toStringAsFixed(1)} ms',
  );
  print(
    'mensagem EVENT cifrada: $bytes B = '
    '${(100 * bytes / menorLimite).toStringAsFixed(1)} % de $menorLimite B '
    '(em claro eram 21 237 B)',
  );
  print(
    bytes < menorLimite / 2
        ? 'SC-005: ok (abaixo de 50 % do menor limite)'
        : 'SC-005: ACIMA de 50 % — revisar o teto de pontos',
  );
}
