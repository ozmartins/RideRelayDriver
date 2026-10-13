# Quickstart — Ano do veículo no cadastro

## Cenários de validação

1. Preencher o cadastro inicial com ano "2018": envio aceito, ano persistido.
2. Tentar enviar com ano vazio, "18" (2 dígitos), "20199" (5 dígitos), "abcd", "1899" ou
   ano corrente + 2: envio recusado, motivo indicado.
3. Editar um cadastro existente, trocar o ano para um valor válido: novo valor persiste.
4. Cadastro de instalação anterior a esta feature (sem `ano_veiculo`): tratado como corrompido,
   formulário reaberto — mesmo comportamento das features 005/006.

## Verificação automatizada

```bash
flutter analyze
flutter test test/domain/driver_profile_test.dart
flutter test test/services/cadastro_store_test.dart
flutter test test/screens/cadastro_screen_test.dart
flutter test
```
