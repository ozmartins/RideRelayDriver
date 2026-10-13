import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Armazenamento de material criptográfico.
///
/// Abstração do projeto (Princípio III): o `IdentityService` depende desta
/// interface, não do plugin, o que permite dublê em memória nos testes e troca
/// de plugin sem tocar a interface do aplicativo.
abstract class KeyStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Erro de acesso ao armazenamento protegido do sistema.
///
/// Propagado em vez de silenciado: gerar uma identidade nova a cada abertura
/// por falha de leitura seria pior que falhar de forma visível (edge case do
/// spec, Princípio I).
class KeyStoreUnavailable implements Exception {
  KeyStoreUnavailable(this.cause);
  final Object cause;

  @override
  String toString() => 'Armazenamento seguro indisponível: $cause';
}

/// Implementação sobre o Android Keystore, via `flutter_secure_storage`.
class SecureKeyStore implements KeyStore {
  SecureKeyStore([FlutterSecureStorage? storage])
    : _storage =
          storage ?? const FlutterSecureStorage(aOptions: androidOptions);

  /// Opções do armazenamento no Android.
  ///
  /// v11 já usa AES/GCM com chave no Android Keystore por padrão;
  /// `storageNamespace` isola os dados deste app dos de outros.
  ///
  /// `resetOnError: false` é obrigatório. O padrão do plugin é `true`: quando a
  /// decifração falha — backup restaurado em outro aparelho, chave do Keystore
  /// invalidada —, ele **apaga todos os dados**, a leitura devolve nulo e o
  /// `IdentityService` gera uma identidade nova sem ninguém saber. Com `false`,
  /// a falha chega aqui como exceção e vira [KeyStoreUnavailable], visível ao
  /// motorista (Princípio I).
  static const AndroidOptions androidOptions = AndroidOptions(
    storageNamespace: 'br.ufsc.tcc.caronas.driver',
    resetOnError: false,
  );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (error) {
      throw KeyStoreUnavailable(error);
    }
  }

  @override
  Future<void> write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (error) {
      throw KeyStoreUnavailable(error);
    }
  }

  @override
  Future<void> delete(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (error) {
      throw KeyStoreUnavailable(error);
    }
  }
}
