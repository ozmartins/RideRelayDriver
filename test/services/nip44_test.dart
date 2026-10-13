import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dart_nostr/dart_nostr.dart' as nostr;
import 'package:driver/services/nip44.dart';
import 'package:flutter_test/flutter_test.dart';

// Vetores oficiais do NIP-44 v2 (https://github.com/paulmillr/nip44, MIT),
// copiados sem alteração para test/fixtures/nip44.vectors.json.
Uint8List _hex(String s) => Uint8List.fromList([
  for (var i = 0; i < s.length; i += 2)
    int.parse(s.substring(i, i + 2), radix: 16),
]);

String _toHex(List<int> b) =>
    b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();

void main() {
  final vetores =
      (jsonDecode(File('test/fixtures/nip44.vectors.json').readAsStringSync())
              as Map<String, dynamic>)['v2']
          as Map<String, dynamic>;
  final validos = vetores['valid'] as Map<String, dynamic>;
  final invalidos = vetores['invalid'] as Map<String, dynamic>;

  group('vetores válidos', () {
    test('get_conversation_key', () {
      for (final v in validos['get_conversation_key'] as List) {
        final chave = Nip44.conversationKey(
          v['sec1'] as String,
          v['pub2'] as String,
        );
        expect(_toHex(chave), v['conversation_key']);
      }
    });

    test('get_message_keys', () {
      final grupo = validos['get_message_keys'] as Map<String, dynamic>;
      final conversa = _hex(grupo['conversation_key'] as String);
      for (final v in grupo['keys'] as List) {
        final k = Nip44.messageKeys(conversa, _hex(v['nonce'] as String));
        expect(_toHex(k.chachaKey), v['chacha_key']);
        expect(_toHex(k.chachaNonce), v['chacha_nonce']);
        expect(_toHex(k.hmacKey), v['hmac_key']);
      }
    });

    test('calc_padded_len', () {
      for (final v in validos['calc_padded_len'] as List) {
        expect(Nip44.paddedLength(v[0] as int), v[1] as int);
      }
    });

    test('encrypt_decrypt: nonce fixo gera o payload exato e decifra', () {
      for (final v in validos['encrypt_decrypt'] as List) {
        final conversa = Nip44.conversationKey(
          v['sec1'] as String,
          // a pública de sec2 vem do vetor de conversa; confere a chave
          _publicDe(v['sec2'] as String),
        );
        expect(_toHex(conversa), v['conversation_key']);
        final payload = Nip44.encrypt(
          v['plaintext'] as String,
          conversa,
          nonce: _hex(v['nonce'] as String),
        );
        expect(payload, v['payload']);
        expect(Nip44.decrypt(v['payload'] as String, conversa), v['plaintext']);
      }
    });

    test('encrypt_decrypt_long_msg', () {
      for (final v in validos['encrypt_decrypt_long_msg'] as List) {
        final conversa = _hex(v['conversation_key'] as String);
        final texto = (v['pattern'] as String) * (v['repeat'] as int);
        expect(
          sha256.convert(utf8.encode(texto)).toString(),
          v['plaintext_sha256'],
        );
        final payload = Nip44.encrypt(
          texto,
          conversa,
          nonce: _hex(v['nonce'] as String),
        );
        expect(
          sha256.convert(utf8.encode(payload)).toString(),
          v['payload_sha256'],
        );
        expect(Nip44.decrypt(payload, conversa), texto);
      }
    });
  });

  group('vetores inválidos', () {
    test('encrypt_msg_lengths: 0 e acima de 65535 lançam', () {
      final conversa = Uint8List(32)..fillRange(0, 32, 1);
      for (final n in invalidos['encrypt_msg_lengths'] as List) {
        expect(
          () => Nip44.encrypt('a' * (n as int), conversa),
          throwsA(isA<Nip44Exception>()),
          reason: 'tamanho $n',
        );
      }
    });

    test('get_conversation_key lança', () {
      for (final v in invalidos['get_conversation_key'] as List) {
        expect(
          () => Nip44.conversationKey(v['sec1'] as String, v['pub2'] as String),
          throwsA(isA<Nip44Exception>()),
          reason: v['note'] as String,
        );
      }
    });

    test('decrypt lança', () {
      for (final v in invalidos['decrypt'] as List) {
        expect(
          () => Nip44.decrypt(
            v['payload'] as String,
            _hex(v['conversation_key'] as String),
          ),
          throwsA(isA<Nip44Exception>()),
          reason: v['note'] as String,
        );
      }
    });
  });

  group('FR-009: a exceção não vaza segredo', () {
    test('mensagem não contém chave nem texto', () {
      const privada =
          '315e59ff51cb9209768cf7da80791ddcaae56ac9775eb25b6dee1234bc5d2268';
      const texto = 'segredo-que-nao-pode-aparecer';
      final conversa = Nip44.conversationKey(
        privada,
        _publicDe(
          '0000000000000000000000000000000000000000000000000000000000000002',
        ),
      );
      final payload = Nip44.encrypt(texto, conversa);
      final adulterado = base64.encode(base64.decode(payload)..[40] ^= 0x01);
      try {
        Nip44.decrypt(adulterado, conversa);
        fail('deveria lançar');
      } on Nip44Exception catch (e) {
        final msg = e.toString();
        expect(msg, isNot(contains(texto)));
        expect(msg, isNot(contains(privada)));
        expect(msg, isNot(contains(_toHex(conversa))));
      }
    });
  });
}

/// Chave pública x-only de uma privada, via a mesma biblioteca de chaves já
/// usada no app (só em teste).
String _publicDe(String privada) =>
    nostr.Nostr.instance.services.keys.derivePublicKey(privateKey: privada);
