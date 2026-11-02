import 'package:driver/domain/receipt.dart';
import 'package:flutter_test/flutter_test.dart';

final _g = 'a' * 64;
final _avaliador = 'b' * 64;
final _avaliado = 'c' * 64;
final _hash = 'd' * 64;

Receipt _recibo({
  int? nota = 5,
  int seq = 3,
  String? hashAnterior,
  String? guid,
  int criadoEm = 1760000000,
}) => Receipt.unsigned(
  guidCorrida: guid ?? _g,
  pubkeyAvaliador: _avaliador,
  pubkeyAvaliado: _avaliado,
  nota: nota,
  criadoEm: criadoEm,
  seq: seq,
  hashAnterior: hashAnterior ?? _hash,
);

Map<String, dynamic> _json() => {
  'v': 1,
  'guid_corrida': _g,
  'pubkey_avaliador': _avaliador,
  'pubkey_avaliado': _avaliado,
  'nota': 5,
  'criado_em': 1760000000,
  'seq': 3,
  'hash_anterior': _hash,
  'id_recibo': 'e' * 64,
  'assinatura': 'f' * 128,
};

void main() {
  group('Receipt — forma canônica e identificador', () {
    // Os SHA-256 esperados foram calculados fora do Dart (hashlib), não pelo
    // próprio código sob teste.
    test('vetor fixo com nota e hash anterior', () {
      final r = _recibo();
      expect(
        r.canonical,
        'tcc-recibo-v1|$_g|$_avaliador|$_avaliado|5|1760000000|3|$_hash',
      );
      expect(
        r.idRecibo,
        '14b73850e54a91034ec9cfead2fd729765ffc99e1e56f056e9ed91c9e77d0c6e',
      );
    });

    test('vetor fixo sem nota e sem hash anterior usa "-"', () {
      final r = Receipt.unsigned(
        guidCorrida: _g,
        pubkeyAvaliador: _avaliador,
        pubkeyAvaliado: _avaliado,
        criadoEm: 1760000000,
        seq: 0,
      );
      expect(
        r.canonical,
        'tcc-recibo-v1|$_g|$_avaliador|$_avaliado|-|1760000000|0|-',
      );
      expect(
        r.idRecibo,
        'fab108e75c1f2e235b10f6fd06898f1a864ccf1d7de48c36410b1e3917ad91a2',
      );
    });

    test('o identificador muda ao alterar qualquer campo', () {
      final base = _recibo().idRecibo;
      expect(_recibo(guid: 'b' * 64).idRecibo, isNot(base));
      expect(_recibo(nota: 4).idRecibo, isNot(base));
      expect(_recibo(nota: null).idRecibo, isNot(base));
      expect(_recibo(criadoEm: 1760000001).idRecibo, isNot(base));
      expect(_recibo(seq: 4).idRecibo, isNot(base));
      expect(_recibo(hashAnterior: 'e' * 64).idRecibo, isNot(base));
      final outroAvaliador = Receipt.unsigned(
        guidCorrida: _g,
        pubkeyAvaliador: '9' * 64,
        pubkeyAvaliado: _avaliado,
        nota: 5,
        criadoEm: 1760000000,
        seq: 3,
        hashAnterior: _hash,
      );
      expect(outroAvaliador.idRecibo, isNot(base));
    });

    test('hasConsistentId acusa campo alterado com o id antigo', () {
      final r = _recibo();
      expect(r.hasConsistentId, isTrue);
      final adulterado = Receipt(
        v: r.v,
        guidCorrida: r.guidCorrida,
        pubkeyAvaliador: r.pubkeyAvaliador,
        pubkeyAvaliado: r.pubkeyAvaliado,
        nota: 1,
        criadoEm: r.criadoEm,
        seq: r.seq,
        hashAnterior: r.hashAnterior,
        idRecibo: r.idRecibo,
        assinatura: r.assinatura,
      );
      expect(adulterado.hasConsistentId, isFalse);
    });
  });

  group('Receipt — JSON', () {
    test('ida e volta preserva todos os campos', () {
      final original = Receipt.fromJson(_json());
      expect(Receipt.fromJson(original.toJson()), original);
    });

    test('nota e hash_anterior ausentes são omitidos, nunca null', () {
      final json = _json()
        ..remove('nota')
        ..remove('hash_anterior');
      final r = Receipt.fromJson(json);
      expect(r.nota, isNull);
      expect(r.hashAnterior, isNull);
      expect(r.toJson().containsKey('nota'), isFalse);
      expect(r.toJson().containsKey('hash_anterior'), isFalse);
    });

    test('não é objeto → FormatException', () {
      expect(() => Receipt.fromJson('x'), throwsFormatException);
      expect(() => Receipt.fromJson(null), throwsFormatException);
    });

    for (final chave in [
      'v',
      'guid_corrida',
      'pubkey_avaliador',
      'pubkey_avaliado',
      'criado_em',
      'seq',
      'id_recibo',
      'assinatura',
    ]) {
      test('campo "$chave" faltando → FormatException', () {
        final json = _json()..remove(chave);
        expect(() => Receipt.fromJson(json), throwsFormatException);
      });
    }

    test('tipo errado → FormatException', () {
      expect(
        () => Receipt.fromJson(_json()..['seq'] = '3'),
        throwsFormatException,
      );
      expect(
        () => Receipt.fromJson(_json()..['nota'] = 4.5),
        throwsFormatException,
      );
      expect(
        () => Receipt.fromJson(_json()..['nota'] = null),
        throwsFormatException,
      );
      expect(
        () => Receipt.fromJson(_json()..['criado_em'] = 1.5),
        throwsFormatException,
      );
    });

    test('hexadecimal de tamanho ou alfabeto errado → FormatException', () {
      expect(
        () => Receipt.fromJson(_json()..['guid_corrida'] = 'a' * 63),
        throwsFormatException,
      );
      expect(
        () => Receipt.fromJson(_json()..['assinatura'] = 'f' * 64),
        throwsFormatException,
      );
      expect(
        () => Receipt.fromJson(_json()..['pubkey_avaliado'] = 'Z' * 64),
        throwsFormatException,
      );
      expect(
        () => Receipt.fromJson(_json()..['id_recibo'] = 'E' * 64),
        throwsFormatException,
      );
    });

    test('seq negativo → FormatException', () {
      expect(
        () => Receipt.fromJson(_json()..['seq'] = -1),
        throwsFormatException,
      );
    });

    test(
      'v e nota fora da faixa são aceitos aqui (o verificador descarta)',
      () {
        final r = Receipt.fromJson(
          _json()
            ..['v'] = 2
            ..['nota'] = 6,
        );
        expect(r.v, 2);
        expect(r.nota, 6);
      },
    );

    test('toString não expõe chaves nem assinatura', () {
      final texto = Receipt.fromJson(_json()).toString();
      expect(texto, isNot(contains(_avaliador)));
      expect(texto, isNot(contains('f' * 128)));
    });
  });
}
