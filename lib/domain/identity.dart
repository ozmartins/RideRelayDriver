/// Identidade criptográfica do motorista na rede Nostr.
///
/// A chave privada **nunca** deve ser exibida, registrada em log ou enviada a um
/// relay (Princípio I da constituição). Por isso esta classe não implementa
/// `toString` com o conteúdo das chaves nem expõe igualdade baseada nelas.
class Identity {
  Identity({required this.publicKey, required this.privateKey}) {
    if (!isValidHexKey(publicKey)) {
      throw ArgumentError(
        'Chave pública fora do formato hexadecimal de 64 caracteres.',
      );
    }
    if (!isValidHexKey(privateKey)) {
      throw ArgumentError(
        'Chave privada fora do formato hexadecimal de 64 caracteres.',
      );
    }
  }

  /// Chave pública em hexadecimal (64 caracteres). Identifica o motorista na rede.
  final String publicKey;

  /// Chave privada em hexadecimal (64 caracteres). Assina os eventos.
  final String privateKey;

  static final RegExp _hex64 = RegExp(r'^[0-9a-f]{64}$');

  /// Valida o formato de uma chave hexadecimal de 64 caracteres, em minúsculas.
  static bool isValidHexKey(String? key) => key != null && _hex64.hasMatch(key);

  /// Chave pública encurtada, para exibição em espaço reduzido.
  String get shortPublicKey =>
      '${publicKey.substring(0, 8)}…${publicKey.substring(publicKey.length - 8)}';

  /// Deliberadamente omite as chaves: evita vazamento por log ou depuração.
  @override
  String toString() => 'Identity(publicKey: $shortPublicKey)';
}
