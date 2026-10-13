# Quickstart — feature 015 (validação em aparelho PENDENTE)

1. Dois aparelhos/emuladores com relay em comum; passageiro escolhe um destino e solicita a corrida.
2. Motorista online: a modal mostra endereços em Origem e Destino (pode aparecer "buscando endereço…"
   por instantes).
3. Repita com a internet do motorista só alcançando os relays (bloqueie photon.komoot.io): a modal mostra
   `lat, lon` e "Enviar orçamento" continua funcionando.

Automatizado: `flutter analyze` sem problemas; `flutter test` — 305 testes.
