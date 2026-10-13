import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart' as pc;

/// Falha ao cifrar ou decifrar no padrão NIP-44.
///
/// A mensagem descreve só a categoria do defeito: nunca inclui chave, texto
/// de entrada nem o conteúdo recebido (Princípio I da constituição).
class Nip44Exception implements Exception {
  const Nip44Exception(this.reason);
  final String reason;

  @override
  String toString() => 'Nip44Exception: $reason';
}

/// NIP-44 v2: ECDH secp256k1 + HKDF-SHA256 + ChaCha20 + HMAC-SHA256.
///
/// Implementação própria, verificada contra os vetores oficiais do padrão
/// (`test/fixtures/nip44.vectors.json`) — decisão D1 de
/// `specs/019-mensagens-cifradas/research.md` (Princípio III): nenhum pacote
/// com NIP-44 resolve junto do `dart_nostr` usado pelo app. Não conhece o
/// domínio do app; a política de uso fica em `message_cipher.dart`.
class Nip44 {
  const Nip44._();

  static const int _minPlaintext = 1;
  static const int _maxPlaintext = 65535;

  static final pc.ECDomainParameters _curve = pc.ECDomainParameters(
    'secp256k1',
  );
  static final Random _random = Random.secure();

  /// Chave de conversa (32 bytes) entre a chave privada de um lado e a
  /// pública do outro, ambas em hexadecimal (pública x-only, 32 bytes).
  /// É a mesma nos dois sentidos.
  static Uint8List conversationKey(String privateKeyHex, String publicKeyHex) {
    final BigInt d;
    final BigInt x;
    try {
      d = _hexToBigInt(privateKeyHex);
      x = _hexToBigInt(publicKeyHex);
    } on FormatException {
      throw const Nip44Exception('chave fora do formato hexadecimal');
    }
    if (d <= BigInt.zero || d >= _curve.n) {
      throw const Nip44Exception('chave privada fora do intervalo da curva');
    }
    final pc.ECPoint ponto;
    try {
      // yTilde 0: a chave x-only do Nostr assume y par.
      ponto = _curve.curve.decompressPoint(0, x);
    } on Object {
      throw const Nip44Exception('chave pública fora da curva');
    }
    final compartilhado = (ponto * d)!;
    final shared = _bigIntTo32Bytes(compartilhado.x!.toBigInteger()!);
    return _hkdfExtract(salt: utf8.encode('nip44-v2'), ikm: shared);
  }

  /// Cifra [plaintext] com a [conversationKey]; devolve o payload em base64.
  /// [nonce] só existe para os testes com vetores fixos.
  static String encrypt(
    String plaintext,
    Uint8List conversationKey, {
    Uint8List? nonce,
  }) {
    final bytes = utf8.encode(plaintext);
    if (bytes.length < _minPlaintext || bytes.length > _maxPlaintext) {
      throw const Nip44Exception('tamanho do texto fora do permitido');
    }
    final n = nonce ?? _randomBytes(32);
    if (n.length != 32) throw const Nip44Exception('nonce inválido');

    final keys = messageKeys(conversationKey, n);
    final cifrado = _chacha20(keys.chachaKey, keys.chachaNonce, _pad(bytes));
    final mac = _hmac(keys.hmacKey, [...n, ...cifrado]);
    return base64.encode([0x02, ...n, ...cifrado, ...mac]);
  }

  /// Decifra [payload] (base64) com a [conversationKey]. Lança
  /// [Nip44Exception] em qualquer defeito: versão, tamanho, base64, MAC,
  /// padding ou UTF-8.
  static String decrypt(String payload, Uint8List conversationKey) {
    if (payload.isEmpty || payload.startsWith('#')) {
      throw const Nip44Exception('versão de payload não suportada');
    }
    if (payload.length < 132 || payload.length > 87472) {
      throw const Nip44Exception('tamanho de payload inválido');
    }
    final Uint8List dados;
    try {
      dados = base64.decode(payload);
    } on FormatException {
      throw const Nip44Exception('payload não é base64');
    }
    if (dados.length < 99 || dados.length > 65603) {
      throw const Nip44Exception('tamanho de payload inválido');
    }
    if (dados[0] != 0x02) {
      throw const Nip44Exception('versão de payload não suportada');
    }
    final n = Uint8List.sublistView(dados, 1, 33);
    final cifrado = Uint8List.sublistView(dados, 33, dados.length - 32);
    final mac = Uint8List.sublistView(dados, dados.length - 32);

    final keys = messageKeys(conversationKey, n);
    final esperado = _hmac(keys.hmacKey, [...n, ...cifrado]);
    if (!_constantTimeEquals(esperado, mac)) {
      throw const Nip44Exception('MAC inválido');
    }
    final bytes = _unpad(_chacha20(keys.chachaKey, keys.chachaNonce, cifrado));
    try {
      return utf8.decode(bytes);
    } on FormatException {
      throw const Nip44Exception('texto decifrado não é UTF-8');
    }
  }

  /// Chaves de uma mensagem derivadas da chave de conversa e do nonce
  /// (HKDF-expand, 76 bytes). Exposto para os testes com vetores.
  static ({Uint8List chachaKey, Uint8List chachaNonce, Uint8List hmacKey})
  messageKeys(Uint8List conversationKey, Uint8List nonce) {
    if (conversationKey.length != 32) {
      throw const Nip44Exception('chave de conversa inválida');
    }
    if (nonce.length != 32) throw const Nip44Exception('nonce inválido');
    final saida = _hkdfExpand(conversationKey, nonce, 76);
    return (
      chachaKey: Uint8List.sublistView(saida, 0, 32),
      chachaNonce: Uint8List.sublistView(saida, 32, 44),
      hmacKey: Uint8List.sublistView(saida, 44, 76),
    );
  }

  /// Tamanho com padding de uma mensagem de [unpaddedLen] bytes.
  static int paddedLength(int unpaddedLen) {
    if (unpaddedLen < 1) throw const Nip44Exception('tamanho inválido');
    if (unpaddedLen <= 32) return 32;
    final proximaPotencia = 1 << ((unpaddedLen - 1).bitLength);
    final bloco = proximaPotencia <= 256 ? 32 : proximaPotencia ~/ 8;
    return bloco * (((unpaddedLen - 1) ~/ bloco) + 1);
  }

  static Uint8List _pad(List<int> bytes) {
    final saida = Uint8List(2 + paddedLength(bytes.length));
    saida[0] = bytes.length >> 8;
    saida[1] = bytes.length & 0xff;
    saida.setRange(2, 2 + bytes.length, bytes);
    return saida;
  }

  static Uint8List _unpad(Uint8List padded) {
    if (padded.length < 2) throw const Nip44Exception('padding inválido');
    final tamanho = (padded[0] << 8) | padded[1];
    if (tamanho < _minPlaintext ||
        padded.length != 2 + paddedLength(tamanho) ||
        2 + tamanho > padded.length) {
      throw const Nip44Exception('padding inválido');
    }
    return Uint8List.sublistView(padded, 2, 2 + tamanho);
  }

  static Uint8List _chacha20(Uint8List key, Uint8List nonce, Uint8List data) {
    final motor = pc.ChaCha7539Engine()
      ..init(true, pc.ParametersWithIV(pc.KeyParameter(key), nonce));
    return motor.process(data);
  }

  static Uint8List _hmac(List<int> key, List<int> data) =>
      Uint8List.fromList(Hmac(sha256, key).convert(data).bytes);

  static Uint8List _hkdfExtract({
    required List<int> salt,
    required List<int> ikm,
  }) => _hmac(salt, ikm);

  static Uint8List _hkdfExpand(List<int> prk, List<int> info, int length) {
    final saida = BytesBuilder();
    var anterior = Uint8List(0);
    for (var i = 1; saida.length < length; i++) {
      anterior = _hmac(prk, [...anterior, ...info, i]);
      saida.add(anterior);
    }
    return Uint8List.sublistView(saida.toBytes(), 0, length);
  }

  /// Comparação sem saída antecipada, para o MAC não vazar a posição do
  /// primeiro byte diferente.
  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diferenca = 0;
    for (var i = 0; i < a.length; i++) {
      diferenca |= a[i] ^ b[i];
    }
    return diferenca == 0;
  }

  static Uint8List _randomBytes(int n) =>
      Uint8List.fromList(List<int>.generate(n, (_) => _random.nextInt(256)));

  static BigInt _hexToBigInt(String hex) {
    if (hex.length != 64) throw const FormatException('tamanho');
    return BigInt.parse(hex, radix: 16);
  }

  static Uint8List _bigIntTo32Bytes(BigInt valor) {
    final saida = Uint8List(32);
    var resto = valor;
    for (var i = 31; i >= 0; i--) {
      saida[i] = (resto & BigInt.from(0xff)).toInt();
      resto = resto >> 8;
    }
    return saida;
  }
}
