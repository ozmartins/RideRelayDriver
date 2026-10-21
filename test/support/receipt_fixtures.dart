import 'package:dart_nostr/dart_nostr.dart' as nostr;
import 'package:driver/domain/identity.dart';
import 'package:driver/domain/receipt.dart';
import 'package:driver/services/receipt_signature.dart';

/// Identidade de teste com par de chaves real (sem tocar Keystore).
Identity newTestIdentity() {
  final par = nostr.Nostr.instance.services.keys.generateKeyPair();
  return Identity(publicKey: par.public, privateKey: par.private);
}

/// Hexadecimal de 64 caracteres determinístico a partir de [n], para
/// `guid_corrida` de teste.
String fakeGuid(int n) => n.toRadixString(16).padLeft(64, '0');

/// Recibo realmente assinado por [avaliador] para [avaliado].
Receipt signedReceipt({
  required Identity avaliador,
  required String avaliado,
  required int seq,
  String? guid,
  int? nota,
  String? hashAnterior,
  int criadoEm = 1760000000,
}) {
  final base = Receipt.unsigned(
    guidCorrida: guid ?? fakeGuid(seq + 1),
    pubkeyAvaliador: avaliador.publicKey,
    pubkeyAvaliado: avaliado,
    nota: nota,
    criadoEm: criadoEm,
    seq: seq,
    hashAnterior: hashAnterior,
  );
  return base.withSignature(ReceiptSignature.sign(base, avaliador));
}

/// Cadeia consecutiva de [notas.length] recibos para [avaliado], do `seq` 0 em
/// diante, cada um apontando para o anterior. Devolve do mais antigo ao mais
/// novo; [notas] com `null` gera recibo sem nota.
List<Receipt> signedChain({
  required String avaliado,
  required List<int?> notas,
  Identity? avaliador,
}) {
  final out = <Receipt>[];
  for (var i = 0; i < notas.length; i++) {
    out.add(
      signedReceipt(
        avaliador: avaliador ?? newTestIdentity(),
        avaliado: avaliado,
        seq: i,
        nota: notas[i],
        hashAnterior: i == 0 ? null : out[i - 1].idRecibo,
      ),
    );
  }
  return out;
}
