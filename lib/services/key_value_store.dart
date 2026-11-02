import 'package:shared_preferences/shared_preferences.dart';

/// Armazenamento simples de chave-valor para dados **não sensíveis**.
///
/// Separado do [KeyStore] de propósito: misturar a lista de relays (dado
/// público) com a chave privada dificultaria auditar depois o que é segredo.
abstract class KeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

/// Implementação sobre `shared_preferences`.
class PreferencesStore implements KeyValueStore {
  @override
  Future<String?> read(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(key);
  }

  @override
  Future<void> write(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }
}

/// Como [PreferencesStore], mas relê o arquivo antes de cada leitura.
///
/// O serviço em segundo plano roda em outro isolate, com o seu próprio cache do
/// `shared_preferences`: sem o `reload`, ele não veria a lista de relays que a
/// interface gravou depois de o isolate existir (feature 025).
class FreshPreferencesStore implements KeyValueStore {
  @override
  Future<String?> read(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return prefs.getString(key);
  }

  @override
  Future<void> write(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }
}
