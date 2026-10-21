// Gera `test/fixtures/receipt_vectors.json`: vetores de teste do recibo de
// reputação (emenda 25 do contrato; feature 026), compartilhados byte a byte
// com o app do passageiro. Chaves de teste fixas, nunca chaves de usuário.
//
// ignore_for_file: avoid_print — é uma ferramenta de linha de comando, em que a
// saída padrão é a própria interface; não faz parte do aplicativo.
// Uso: dart run tool/gen_receipt_vectors.dart
//
// O `id_recibo` e a forma canônica são determinísticos. A assinatura Schnorr
// (BIP-340) pode usar aleatoriedade auxiliar: rodar de novo troca as
// assinaturas, e os testes só as **verificam**, não as comparam por igualdade.
import 'dart:convert';
import 'dart:io';

import 'package:dart_nostr/dart_nostr.dart' as nostr;
import 'package:driver/domain/identity.dart';
import 'package:driver/domain/receipt.dart';
import 'package:driver/services/receipt_signature.dart';

Identity _identidade(String privada) => Identity(
  publicKey: nostr.Nostr.instance.services.keys.derivePublicKey(
    privateKey: privada,
  ),
  privateKey: privada,
);

String _guid(int n) => n.toRadixString(16).padLeft(64, '0');

Receipt _assinado(Receipt base, Identity quem) =>
    base.withSignature(ReceiptSignature.sign(base, quem));

Map<String, dynamic> _vetor(
  String nome,
  String autorDoEvento,
  Receipt recibo, {
  required bool valido,
  String? motivo,
}) => {
  'nome': nome,
  'autor_do_evento': autorDoEvento,
  'recibo': recibo.toJson(),
  'canonico': recibo.canonical,
  'valido': valido,
  'motivo': ?motivo,
};

void main() {
  final avaliador = _identidade('11' * 32);
  final avaliado = _identidade('22' * 32);
  final outro = _identidade('33' * 32);

  Receipt base({
    required int n,
    int? nota,
    int seq = 0,
    String? hashAnterior,
    Identity? de,
    Identity? para,
  }) => Receipt.unsigned(
    guidCorrida: _guid(n),
    pubkeyAvaliador: (de ?? avaliador).publicKey,
    pubkeyAvaliado: (para ?? avaliado).publicKey,
    nota: nota,
    criadoEm: 1760000000,
    seq: seq,
    hashAnterior: hashAnterior,
  );

  final r0 = _assinado(base(n: 1), avaliador);
  final r1 = _assinado(
    base(n: 2, nota: 5, seq: 1, hashAnterior: r0.idRecibo),
    avaliador,
  );

  // id_recibo adulterado: nota trocada de 5 para 4, com id e assinatura antigos.
  final adulterado = Receipt(
    v: r1.v,
    guidCorrida: r1.guidCorrida,
    pubkeyAvaliador: r1.pubkeyAvaliador,
    pubkeyAvaliado: r1.pubkeyAvaliado,
    nota: 4,
    criadoEm: r1.criadoEm,
    seq: r1.seq,
    hashAnterior: r1.hashAnterior,
    idRecibo: r1.idRecibo,
    assinatura: r1.assinatura,
  );

  final outraChave = _assinado(base(n: 3), outro);

  final v2Base = _assinado(base(n: 4), avaliador);
  final v2 = Receipt(
    v: 2,
    guidCorrida: v2Base.guidCorrida,
    pubkeyAvaliador: v2Base.pubkeyAvaliador,
    pubkeyAvaliado: v2Base.pubkeyAvaliado,
    nota: v2Base.nota,
    criadoEm: v2Base.criadoEm,
    seq: v2Base.seq,
    hashAnterior: v2Base.hashAnterior,
    idRecibo: v2Base.idRecibo,
    assinatura: v2Base.assinatura,
  );

  final nota6 = _assinado(base(n: 5, nota: 6), avaliador);
  final autoAvaliacao = _assinado(
    base(n: 6, nota: 5, de: avaliado, para: avaliado),
    avaliado,
  );

  final conteudo = {
    'descricao':
        'Vetores do recibo de reputação (emenda 25). O verificador recebe o '
        'recibo e o autor do evento e decide se vale. Idêntico nos dois apps.',
    'chaves_publicas_de_teste': {
      'avaliador': avaliador.publicKey,
      'avaliado': avaliado.publicKey,
      'outro': outro.publicKey,
    },
    'vetores': [
      _vetor('valido_seq0_sem_nota', avaliado.publicKey, r0, valido: true),
      _vetor(
        'valido_com_nota_e_hash_anterior',
        avaliado.publicKey,
        r1,
        valido: true,
      ),
      _vetor(
        'id_recibo_adulterado',
        avaliado.publicKey,
        adulterado,
        valido: false,
        motivo: 'a',
      ),
      _vetor(
        'assinatura_de_outra_chave',
        avaliado.publicKey,
        outraChave,
        valido: false,
        motivo: 'b',
      ),
      _vetor('versao_2', avaliado.publicKey, v2, valido: false, motivo: 'd'),
      _vetor('nota_6', avaliado.publicKey, nota6, valido: false, motivo: 'd'),
      _vetor(
        'avaliador_igual_ao_avaliado',
        avaliado.publicKey,
        autoAvaliacao,
        valido: false,
        motivo: 'g',
      ),
    ],
  };

  File('test/fixtures/receipt_vectors.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(conteudo)}\n',
  );
  print('test/fixtures/receipt_vectors.json gerado.');
}
