import 'package:driver/services/key_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SecureKeyStore — opções do Android', () {
    test(
      'não apaga os dados quando a decifração falha (resetOnError desligado)',
      () {
        // Com o padrão do plugin (true), uma falha de decifração apaga a chave
        // privada, a leitura devolve nulo e o IdentityService cria outra
        // identidade sem avisar. Desligado, a falha vira KeyStoreUnavailable.
        expect(SecureKeyStore.androidOptions.toMap()['resetOnError'], 'false');
      },
    );

    test('isola os dados no namespace do aplicativo do motorista', () {
      expect(
        SecureKeyStore.androidOptions.toMap()['storageNamespace'],
        'br.ufsc.tcc.corridas.driver',
      );
    });
  });
}
