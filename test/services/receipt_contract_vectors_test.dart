import 'dart:convert';
import 'dart:io';

import 'package:driver/domain/receipt.dart';
import 'package:driver/domain/reputation.dart';
import 'package:driver/services/receipt_signature.dart';
import 'package:driver/services/reputation_verifier.dart';
import 'package:flutter_test/flutter_test.dart';

/// Teste de contrato (FR-022): os vetores de `test/fixtures/receipt_vectors.json`
/// são idênticos, byte a byte, nos dois apps. Um recibo gerado por um deles
/// MUST ser aceito (ou recusado, pelo mesmo motivo) pelo verificador do outro.
void main() {
  final arquivo = File('test/fixtures/receipt_vectors.json');
  final dados = jsonDecode(arquivo.readAsStringSync()) as Map<String, dynamic>;
  final vetores = (dados['vetores'] as List<dynamic>)
      .cast<Map<String, dynamic>>();

  test('o arquivo traz os casos mínimos do contrato', () {
    expect(
      vetores.map((v) => v['nome']),
      containsAll([
        'valido_seq0_sem_nota',
        'valido_com_nota_e_hash_anterior',
        'id_recibo_adulterado',
        'assinatura_de_outra_chave',
        'versao_2',
        'nota_6',
        'avaliador_igual_ao_avaliado',
      ]),
    );
  });

  for (final v in vetores) {
    final nome = v['nome'] as String;
    group('vetor $nome', () {
      final recibo = Receipt.fromJson(v['recibo']);
      final autor = v['autor_do_evento'] as String;
      final valido = v['valido'] as bool;

      test('a forma canônica bate com a esperada', () {
        expect(recibo.canonical, v['canonico']);
      });

      test('o veredito do verificador é o esperado', () {
        final rep = Reputation(
          corridas: 1,
          avaliacoes: recibo.nota == null ? 0 : 1,
          seqProximo: recibo.seq + 1,
          head: recibo.idRecibo,
          recibos: [recibo],
        );
        final view = verifyReputation(rep, authorPubkey: autor);
        expect(view.verifiedCount, valido ? 1 : 0);
        expect(view.invalidDiscarded, valido ? 0 : 1);
      });

      if (valido) {
        test('o id_recibo é o do arquivo e a assinatura verifica', () {
          expect(recibo.hasConsistentId, isTrue);
          expect(ReceiptSignature.verify(recibo), isTrue);
        });
      }
    });
  }
}
