# Quickstart — Detalhes do motorista e tempo estimado no orçamento

1. Com uma solicitação recebida e orçamento enviado, inspecionar o evento publicado
   (`dart run tool/verify_published.dart <pubkey>`): `content` traz `driverName`, `carBrand`,
   `carModel`, `carYear` e `etaMinutes`, coerentes com o cadastro e a distância exibida na modal.
2. Simular falha na distância motorista→origem antes de enviar: `content` publicado não traz a
   chave `etaMinutes`.

## Verificação automatizada

```bash
flutter analyze
flutter test
```
