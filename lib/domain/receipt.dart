import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;

/// Recibo de avaliação de uma corrida concluída (emenda 25 do contrato de
/// eventos, seção 1.2 de "Reputação por recibos"; feature 026).
///
/// Imutável. Um recibo é assinado pelo avaliador e entregue ao avaliado, que o
/// guarda e o apresenta depois. Esta classe só descreve os dados e a forma
/// canônica: **não** verifica `idRecibo` nem assinatura (isso é de
/// `ReceiptSignature` e do `ReputationVerifier`).
class Receipt {
  const Receipt({
    required this.v,
    required this.guidCorrida,
    required this.pubkeyAvaliador,
    required this.pubkeyAvaliado,
    this.nota,
    required this.criadoEm,
    required this.seq,
    this.hashAnterior,
    required this.idRecibo,
    required this.assinatura,
  });

  /// Recibo ainda sem assinatura: `v = 1` e `idRecibo` calculado da forma
  /// canônica; `assinatura` vazia até [withSignature].
  factory Receipt.unsigned({
    required String guidCorrida,
    required String pubkeyAvaliador,
    required String pubkeyAvaliado,
    int? nota,
    required int criadoEm,
    required int seq,
    String? hashAnterior,
  }) => Receipt(
    v: 1,
    guidCorrida: guidCorrida,
    pubkeyAvaliador: pubkeyAvaliador,
    pubkeyAvaliado: pubkeyAvaliado,
    nota: nota,
    criadoEm: criadoEm,
    seq: seq,
    hashAnterior: hashAnterior,
    idRecibo: computeId(
      guidCorrida: guidCorrida,
      pubkeyAvaliador: pubkeyAvaliador,
      pubkeyAvaliado: pubkeyAvaliado,
      nota: nota,
      criadoEm: criadoEm,
      seq: seq,
      hashAnterior: hashAnterior,
    ),
    assinatura: '',
  );

  /// Decodificação estrita: lança [FormatException] para campo faltando, de
  /// tipo errado ou hexadecimal de tamanho errado. Os valores (`v`, faixa da
  /// `nota`, `seq`) **não** são julgados aqui — recibo de `v` desconhecido ou
  /// com nota fora de 1–5 é descartado e contado pelo verificador (1.6 d).
  factory Receipt.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      throw const FormatException('recibo não é um objeto JSON');
    }
    return Receipt(
      v: _int(json, 'v'),
      guidCorrida: _hex(json, 'guid_corrida', 64),
      pubkeyAvaliador: _hex(json, 'pubkey_avaliador', 64),
      pubkeyAvaliado: _hex(json, 'pubkey_avaliado', 64),
      nota: json.containsKey('nota') ? _int(json, 'nota') : null,
      criadoEm: _int(json, 'criado_em'),
      seq: _nonNegativeInt(json, 'seq'),
      hashAnterior: json.containsKey('hash_anterior')
          ? _hex(json, 'hash_anterior', 64)
          : null,
      idRecibo: _hex(json, 'id_recibo', 64),
      assinatura: _hex(json, 'assinatura', 128),
    );
  }

  /// Versão do formato: `1`.
  final int v;

  /// `id` do `kind: 20002` aceito (`quoteId`).
  final String guidCorrida;

  /// Autor do recibo.
  final String pubkeyAvaliador;

  /// Quem recebe o recibo.
  final String pubkeyAvaliado;

  /// Nota de 1 a 5; `null` quando o avaliador não avaliou (conta como corrida,
  /// não como avaliação).
  final int? nota;

  /// Epoch em segundos. Só informativo: nunca usado para ordenar com
  /// segurança (regra 5 de recepção).
  final int criadoEm;

  /// Posição na cadeia **do avaliado**, a partir de 0.
  final int seq;

  /// `idRecibo` do recibo `seq − 1`; `null` quando `seq = 0`.
  final String? hashAnterior;

  /// SHA-256 de [canonical], em hexadecimal minúsculo.
  final String idRecibo;

  /// Schnorr (BIP-340) do avaliador sobre [idRecibo], em hexadecimal.
  final String assinatura;

  /// Forma canônica (1.2): campos separados por `|`, ausente = `-`.
  String get canonical => _canonical(
    guidCorrida: guidCorrida,
    pubkeyAvaliador: pubkeyAvaliador,
    pubkeyAvaliado: pubkeyAvaliado,
    nota: nota,
    criadoEm: criadoEm,
    seq: seq,
    hashAnterior: hashAnterior,
  );

  /// Verdadeiro se [idRecibo] é o SHA-256 da forma canônica atual.
  bool get hasConsistentId =>
      idRecibo ==
      computeId(
        guidCorrida: guidCorrida,
        pubkeyAvaliador: pubkeyAvaliador,
        pubkeyAvaliado: pubkeyAvaliado,
        nota: nota,
        criadoEm: criadoEm,
        seq: seq,
        hashAnterior: hashAnterior,
      );

  /// `id_recibo` = SHA-256 (UTF-8) da forma canônica, em hexadecimal minúsculo.
  static String computeId({
    required String guidCorrida,
    required String pubkeyAvaliador,
    required String pubkeyAvaliado,
    int? nota,
    required int criadoEm,
    required int seq,
    String? hashAnterior,
  }) => crypto.sha256
      .convert(
        utf8.encode(
          _canonical(
            guidCorrida: guidCorrida,
            pubkeyAvaliador: pubkeyAvaliador,
            pubkeyAvaliado: pubkeyAvaliado,
            nota: nota,
            criadoEm: criadoEm,
            seq: seq,
            hashAnterior: hashAnterior,
          ),
        ),
      )
      .toString();

  /// Cópia com [assinatura] preenchida.
  Receipt withSignature(String assinatura) => Receipt(
    v: v,
    guidCorrida: guidCorrida,
    pubkeyAvaliador: pubkeyAvaliador,
    pubkeyAvaliado: pubkeyAvaliado,
    nota: nota,
    criadoEm: criadoEm,
    seq: seq,
    hashAnterior: hashAnterior,
    idRecibo: idRecibo,
    assinatura: assinatura,
  );

  /// JSON do contrato (snake_case); `nota` e `hash_anterior` são omitidos
  /// quando ausentes, nunca `null`.
  Map<String, dynamic> toJson() => {
    'v': v,
    'guid_corrida': guidCorrida,
    'pubkey_avaliador': pubkeyAvaliador,
    'pubkey_avaliado': pubkeyAvaliado,
    'nota': ?nota,
    'criado_em': criadoEm,
    'seq': seq,
    'hash_anterior': ?hashAnterior,
    'id_recibo': idRecibo,
    'assinatura': assinatura,
  };

  @override
  bool operator ==(Object other) =>
      other is Receipt &&
      other.v == v &&
      other.guidCorrida == guidCorrida &&
      other.pubkeyAvaliador == pubkeyAvaliador &&
      other.pubkeyAvaliado == pubkeyAvaliado &&
      other.nota == nota &&
      other.criadoEm == criadoEm &&
      other.seq == seq &&
      other.hashAnterior == hashAnterior &&
      other.idRecibo == idRecibo &&
      other.assinatura == assinatura;

  @override
  int get hashCode => Object.hash(
    v,
    guidCorrida,
    pubkeyAvaliador,
    pubkeyAvaliado,
    nota,
    criadoEm,
    seq,
    hashAnterior,
    idRecibo,
    assinatura,
  );

  /// Sem chaves nem assinatura: o recibo pode ir parar em log de erro.
  @override
  String toString() => 'Receipt(seq: $seq, nota: ${nota ?? "—"})';

  static String _canonical({
    required String guidCorrida,
    required String pubkeyAvaliador,
    required String pubkeyAvaliado,
    required int? nota,
    required int criadoEm,
    required int seq,
    required String? hashAnterior,
  }) =>
      'tcc-recibo-v1|$guidCorrida|$pubkeyAvaliador|$pubkeyAvaliado|'
      '${nota ?? '-'}|$criadoEm|$seq|${hashAnterior ?? '-'}';

  static int _int(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! int) {
      throw FormatException('campo "$key" ausente ou não inteiro');
    }
    return value;
  }

  static int _nonNegativeInt(Map<String, dynamic> json, String key) {
    final value = _int(json, key);
    if (value < 0) throw FormatException('campo "$key" negativo');
    return value;
  }

  static String _hex(Map<String, dynamic> json, String key, int length) {
    final value = json[key];
    if (value is! String || !RegExp('^[0-9a-f]{$length}\$').hasMatch(value)) {
      throw FormatException(
        'campo "$key" ausente ou não é hexadecimal de $length caracteres',
      );
    }
    return value;
  }
}
