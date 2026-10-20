# Quickstart — Integridade das avaliações (Row Signing, motorista)

Guia de validação manual desta feature, em `Prototipo/driver/`. Pressupõe acesso ao arquivo do
banco `ride_ratings.db` do aparelho/emulador (via `adb shell run-as br.ufsc.tcc.corridas.driver` +
`sqlite3`, ou extraindo o arquivo) para inspecionar/alterar linhas diretamente, simulando uma
adulteração fora do app.

## Cenários de validação (referem os FR/SC de `spec.md`)

### 1. Avaliação gravada carrega assinatura válida (US1, SC-001)

1. Avaliar uma corrida normalmente (feature 013 — tela de avaliação, confirmar uma nota).
2. **Esperado**: `SELECT * FROM ride_ratings WHERE ride_id = '<id-da-corrida>'` mostra a linha com
   a coluna `signature` preenchida (não nula) e `tampered = 0`.
3. Ler a mesma avaliação pelo app (`RideRatingStore.forRide`, via teste manual ou tela de
   depuração, se existir). **Esperado**: a avaliação é devolvida normalmente, com a mesma nota.

### 2. Adulteração é detectada e a linha passa a ser ignorada (US2, SC-002)

1. Repetir o passo 1 do cenário anterior.
2. Fora do app, alterar diretamente o valor de `stars` daquela linha no banco (ex.: `UPDATE
   ride_ratings SET stars = 1 WHERE ride_id = '<id-da-corrida>'`, para um valor diferente do
   originalmente avaliado).
3. Ler a mesma avaliação pelo app. **Esperado**: `forRide` devolve `null`.
4. **Esperado**: `SELECT tampered FROM ride_ratings WHERE ride_id = '<id-da-corrida>'` mostra `1`.
5. Ler de novo. **Esperado**: continua devolvendo `null`, sem alterar mais nada no banco.

### 3. Avaliação anterior a esta feature é tratada como violada (US3, SC-003)

1. Antes de instalar esta feature (ou simulando manualmente): `INSERT INTO ride_ratings (ride_id,
   stars, rated_at) VALUES ('quote-legado', 4, '2026-09-22T10:00:00.000')` — sem `signature`
   (coluna ausente na v1, ou `NULL` após a migração).
2. Ler essa avaliação pelo app. **Esperado**: `forRide` devolve `null`.
3. **Esperado**: a linha correspondente tem `tampered = 1` depois dessa leitura.

### 4. Nenhum vazamento de chave privada (SC-004, Princípio I)

1. Avaliar uma corrida (cenário 1) com logging habilitado (`flutter run` em modo debug,
   observando o console).
2. **Esperado**: a chave privada da identidade não aparece em nenhuma linha de log, nem na
   assinatura resultante.
