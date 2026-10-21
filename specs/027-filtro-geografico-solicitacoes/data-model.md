# Modelo de dados: 027-filtro-geografico-solicitacoes

## Domínio (`lib/domain/`, sem importar terceiros)

### `Geohash` (funções puras, `geohash.dart`)

| Função | Contrato |
|---|---|
| `encode(lat, lon, precisao)` | `String` de `precisao` caracteres no alfabeto `0123456789bcdefghjkmnpqrstuvwxyz`. `precisao` ∈ 1–12. Lat fora de −90..90 ou lon fora de −180..180 ⇒ `ArgumentError` |
| `neighbors(cell)` | as 8 vizinhas da célula; longitude dá a volta no antimeridiano; sem vizinha além dos polos (menos de 8 nesse caso); sem repetição |
| `cellWithNeighbors(cell)` | `[cell, ...neighbors(cell)]`, sem repetição |
| `isValid(String)` | comprimento 3–5 e só caracteres do alfabeto |
| `cellHeightKm(p)`, `cellWidthKm(p, lat)` | altura `180/2^⌊5p/2⌋ · 111,195`; largura `360/2^⌈5p/2⌉ · 111,195 · cos(lat)` |
| `kPrecisoesDaTag = [5, 4, 3]` | precisões que o passageiro publica |

### `DriverCoverage` (imutável, `driver_coverage.dart`)

| Campo | Tipo | Regra |
|---|---|---|
| `referenceLat`, `referenceLon` | double | posição ao ficar online; só em memória |
| `radiusKm` | int | 1–100; **instantâneo** do raio no momento de ficar online |
| `precision` | int | 5, 4 ou 3, derivada (R3 do research) |
| `cells` | `List<String>` | `cellWithNeighbors(encode(ref, precision))`, ≤ 9, derivada |

- `DriverCoverage.around({lat, lon, radiusKm})` calcula `precision` e `cells`; `radiusKm` fora de 1–100 ⇒
  `ArgumentError` (quem chama já validou o cadastro).
- `static int precisionFor(radiusKm, lat)`: maior de 5, 4, 3 com `radiusKm ≤ min(altura, largura·cos φ')`; senão 3.
- `bool matchesCells(List<List<String>> tags)`: alguma tag `["g", v]` com `v` válido e `∈ cells`.
- `bool withinRadius(lat, lon)`: `metersBetween(ref, ponto) ≤ radiusKm·1000` (inclusivo).
- `CoverageDecision evaluateRideRequest({tags, content})`: pura; `aceita` ou motivo (`semTagG`, `foraDasCelulas`,
  `origemIlegivel`, `alemDoRaio`). É a **única** implementação da regra 8; `RideRequestFilter`, `EventFeed` e
  `RelayHostCore` a chamam.
- `toJson`/`fromJson` estritos: só `lat`, `lon`, `raio_km`; `precision` e `cells` são recalculados em `fromJson`.
  `fromJson` lança `FormatException` para campo faltando, tipo errado ou raio fora de 1–100. É o corpo da mensagem
  `ServiceSetCoverage`; **nunca** vai para `ServiceStateStore` nem para evento.
- Igualdade por valor (lat, lon, raio).

### `RideRequestFilter` (alterado)

`evaluate(event, state, {required DriverCoverage? coverage})`. Ordem: `offline → emCorrida → malformada →
(geográfica) → pagamentoNaoAceito`. Geográfica: `coverage == null` ⇒ recusa `semReferencia`; senão
`coverage.evaluateRideRequest` recusando com `foraDaCobertura`. `RideRequestRefusal` ganha `semReferencia` e
`foraDaCobertura`. Nenhuma outra regra muda.

### Cadastro

- `DriverPersonalData` ganha `raioAtendimentoKm` (`int`, padrão `kRaioPadraoKm`); entra em `isValido`
  (`kRaioMinKm ≤ x ≤ kRaioMaxKm`), `toMap` (`raio_atendimento_km`), `fromMap` (ausente ⇒ padrão), `==`, `hashCode`.
- `DriverProfile` ganha `raioAtendimentoKm` (padrão `kRaioPadraoKm` no construtor), em `isValido`, `copyWith`,
  `toMap`, `fromMap`.
- `DriverProfile.parseRaioKm(String)`: inteiro de 1–100; recusa vazio, não numérico, decimal, ≤ 0, > 100.
- Constantes: `kRaioMinKm = 1`, `kRaioMaxKm = 100`, `kRaioPadraoKm = 10`.
- `CadastroProgress.toProfile()` e `ensureValid` seguem a validade acima: raio persistido inválido ⇒ etapa
  corrompida ⇒ formulário reaparece, como já ocorre com qualquer campo. (A migração põe 10, nunca inválido.)

## Armazenamento

`cadastro_motorista.db` sobe de versão 5 para 6: `ALTER TABLE driver_personal ADD COLUMN raio_atendimento_km
INTEGER NOT NULL DEFAULT 10`; `onCreate` já cria a coluna. Sem migração de dado além do `DEFAULT`. A cobertura **não**
é armazenada em lugar algum.

## Serviços e mensagens

| Item | Mudança |
|---|---|
| `RelayGateway` | `subscribe({kinds, List<String>? rideRequestCells})` e `setRideRequestCells(List<String>?)`. O filtro de `20001` só existe com células não nulas; os demais kinds vão num filtro à parte, sempre |
| `RelayConnection` | `DriverCoverage? get coverage`; `Future<void> applyCoverage(DriverCoverage?)` |
| `RelayService` | guarda `_coverage`, repassa `cells` ao gateway |
| `RemoteRelayConnection` | guarda `_coverage`, manda `ServiceSetCoverage` e o reenvia ao receber `ServiceHelloAck` (serviço reiniciado) |
| `ServiceMessage` | `ServiceSetCoverage(DriverCoverage? coverage)` UI→S, `type: 'coverage'`, corpo `{ 'coverage': {…} \| null }` |
| `RelayHostCore` | guarda `_coverage` **só em memória**; ao receber `ServiceSetCoverage` chama `relays.applyCoverage`; em `_onIncoming`, para `20001`, aplica `coverage.evaluateRideRequest` **antes** da deduplicação quando há cobertura, e passa `coverage` a `RideRequestFilter.evaluate` |
| `EventFeed` | parâmetro `DriverCoverage? Function()? coverage`; para `20001` com cobertura não nula, descarta antes da deduplicação e conta em `discardedOutOfCoverageCount`. Sem o parâmetro (ou com cobertura nula) não há recorte geográfico: a recusa por falta de referência é do `RideRequestFilter` |
| `NostrRelayGateway` | monta `NostrFilter` com `additionalFilters: {'#g': cells}` para `20001`; refaz a inscrição por relay ao mudar células |
| `ServiceState`, `ServiceStateStore` | **sem mudança** (a cobertura não é estado persistido) |

## Máquina de estados da cobertura (`MapScreen`)

| Evento | Efeito |
|---|---|
| ficar online com posição | `coverage = around(posição, perfil.raioAtendimentoKm)`; `applyCoverage(coverage)` |
| ficar offline (toque) | `coverage = null`; `applyCoverage(null)` |
| localização perdida online | offline forçado ⇒ idem |
| retomada online (FR-012 da 025) | online sem cobertura; primeira posição válida **e** cadastro carregado ⇒ cria a cobertura; solicitações recebidas antes ficam estacionadas e são reavaliadas contra ela |
| posição muda online | nada (referência fixa) |
| raio alterado no cadastro online | nada até o próximo "ficar online" |
