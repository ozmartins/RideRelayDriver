# Quickstart — Reconexão manual com os relays (motorista)

Pré-requisito: o app do motorista instalado num emulador, com o cadastro concluído (o mapa e a aba Relays só
aparecem depois dele). Os comandos usam `emulator-5554`; ajuste o serial.

1. Abrir o app: sem faixa no mapa; aba "Relays" com os relays "conectado" e o botão "Reconectar" no topo.
2. Cortar a rede: `adb -s emulator-5554 shell svc wifi disable; adb -s emulator-5554 shell svc data disable`.
   Em até ~40 s os relays viram "indisponível" e o mapa mostra "Sem conexão com os relays.".
3. Religar: `adb -s emulator-5554 shell svc wifi enable; adb -s emulator-5554 shell svc data enable`.
4. Tocar "Reconectar" na faixa do mapa: o botão mostra "Reconectando…" e, ao fim, os relays voltam a
   "conectado" e a faixa some (antes do ciclo de 15 s).
5. Repetir os passos 2–3 e tocar "Reconectar" na aba Relays: mesmo resultado.
6. Com o passageiro no outro emulador, publicar uma solicitação e confirmar que ela chega ao motorista
   (inscrição reenviada).

**Estado da validação**: testes automatizados passando; validação em aparelho **pendente**.
