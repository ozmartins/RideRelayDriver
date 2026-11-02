# Research — feature 015

## D1 — Geocodificação reversa no motorista, Photon `/reverse`
Alternativa descartada: o passageiro incluir o endereço no `kind: 20001`. Mudaria o contrato e a
origem (posição GPS) não tem endereço no passageiro. Escolhida a chamada no motorista.

**Exceção de privacidade**: usa a exceção de geocodificação reversa da constituição 2.9.0 (Restrições
de Segurança e Privacidade) — coordenada de origem/destino de solicitação recebida, HTTPS, sem
identificador, sem persistência além da sessão (cache em memória em `PhotonReverseGeocodingService`).

**Dependência**: nenhuma nova. `package:http` já estava no `pubspec.yaml` (Princípio III); serviço
Photon já adotado pelo passageiro (feature 005 dele). Mesmo `User-Agent` próprio, pois o padrão do Dart
recebe 403. Endereço formatado como `_paraSugestao` do passageiro, sem o país e com `district`.
