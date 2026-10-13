import 'dart:convert';

import 'package:dart_nostr/dart_nostr.dart' as nostr;
import 'package:driver/domain/identity.dart';
import 'package:driver/services/message_cipher.dart';
import 'package:driver/services/nip44.dart';
import 'package:flutter_test/flutter_test.dart';

Identity _novaIdentidade() {
  final par = nostr.Nostr.instance.services.keys.generateKeyPair();
  return Identity(publicKey: par.public, privateKey: par.private);
}

void main() {
  late Identity motorista;
  late Identity passageiro;
  late Identity terceiro;
  late MessageCipher cifra;

  setUp(() {
    motorista = _novaIdentidade();
    passageiro = _novaIdentidade();
    terceiro = _novaIdentidade();
    cifra = MessageCipher();
  });

  test('ida e volta: o destinatário decifra o que o remetente cifrou', () {
    const texto = '{"lat":-28.93,"lon":-49.48}';
    final payload = cifra.encryptFor(motorista, passageiro.publicKey, texto);

    expect(payload, isNot(contains('lat')));
    expect(
      MessageCipher().decryptFrom(passageiro, motorista.publicKey, payload),
      texto,
    );
  });

  test('um terceiro não decifra', () {
    final payload = cifra.encryptFor(motorista, passageiro.publicKey, 'oi');

    expect(cifra.decryptFrom(terceiro, motorista.publicKey, payload), isNull);
    expect(cifra.decryptFrom(terceiro, passageiro.publicKey, payload), isNull);
  });

  test('conteúdo em claro vira null', () {
    expect(
      cifra.decryptFrom(passageiro, motorista.publicKey, '{"lat":1,"lon":2}'),
      isNull,
    );
    expect(cifra.decryptFrom(passageiro, motorista.publicKey, ''), isNull);
  });

  test('payload adulterado em um byte vira null', () {
    final payload = cifra.encryptFor(motorista, passageiro.publicKey, 'texto');
    final bytes = base64.decode(payload)..[50] ^= 0x01;

    expect(
      cifra.decryptFrom(passageiro, motorista.publicKey, base64.encode(bytes)),
      isNull,
    );
  });

  test('texto vazio é cifrado como {} e exige {} com emptyMarker', () {
    final vazio = cifra.encryptFor(motorista, passageiro.publicKey, '');
    expect(
      cifra.decryptFrom(passageiro, motorista.publicKey, vazio),
      emptyContentMarker,
    );
    expect(
      cifra.decryptFrom(
        passageiro,
        motorista.publicKey,
        vazio,
        emptyMarker: true,
      ),
      emptyContentMarker,
    );

    // outro texto, mesmo bem cifrado, não vale onde só `{}` é válido
    final outro = cifra.encryptFor(motorista, passageiro.publicKey, '{"a":1}');
    expect(
      cifra.decryptFrom(
        passageiro,
        motorista.publicKey,
        outro,
        emptyMarker: true,
      ),
      isNull,
    );
  });

  test('a chave de conversa é calculada uma vez por par e é simétrica', () {
    final a = MessageCipher();
    final b = MessageCipher();
    final p1 = a.encryptFor(motorista, passageiro.publicKey, 'um');
    final p2 = a.encryptFor(motorista, passageiro.publicKey, 'dois');
    expect(a.derivationCount, 1);

    expect(b.decryptFrom(passageiro, motorista.publicKey, p1), 'um');
    expect(b.decryptFrom(passageiro, motorista.publicKey, p2), 'dois');
    expect(b.derivationCount, 1);

    a.encryptFor(motorista, terceiro.publicKey, 'outro par');
    expect(a.derivationCount, 2);
  });

  test('chave de destinatário malformada: cifrar lança e decifrar é null', () {
    expect(
      () => cifra.encryptFor(motorista, 'não é chave', 'oi'),
      throwsA(isA<Nip44Exception>()),
    );
    expect(cifra.decryptFrom(motorista, 'não é chave', 'qualquer'), isNull);
  });

  test('FR-009: decryptFrom não lança nem ecoa chave ou texto', () {
    const segredo = 'texto-que-nao-pode-vazar';
    final payload = cifra.encryptFor(motorista, passageiro.publicKey, segredo);

    expect(
      () => cifra.decryptFrom(terceiro, motorista.publicKey, payload),
      returnsNormally,
    );
    try {
      cifra.encryptFor(motorista, 'x' * 64, segredo);
    } on Nip44Exception catch (e) {
      expect(e.toString(), isNot(contains(segredo)));
      expect(e.toString(), isNot(contains(motorista.privateKey)));
    }
  });
}
