# Tasks: Chegada periódica à origem (motorista)

**Input**: `specs/021-chegada-periodica/` (spec, plan, research, data-model, quickstart)
**Tests**: incluídos — o padrão do projeto.
**Convenção**: `[P]` = arquivos diferentes, sem dependência; `[USn]` = história de `spec.md`.

## Phase 1: Setup

- [x] T001 Conferir a emenda 20 nas duas cópias do contrato (idênticas por `diff`, commit `7c77d9a` antes de qualquer código desta feature) — Princípio IV, `contracts/README.md`.

## Phase 2: Foundational

- [x] T002 [P] Remover `arrivalNotified` de `lib/domain/active_ride.dart` (campo, `copyWith`, `==`, `hashCode`, `toString`, docs) e ajustar `test/domain/active_ride_test.dart` (casos de `arrivalNotified` removidos; os de `destinationArrivalNotified` ficam).
- [x] T003 [P] Remover a leitura e a escrita da chave `arrivalNotified` em `lib/services/ride_state_store.dart`; ajustar `test/services/ride_state_store_test.dart` (remover o caso de persistência da marca; acrescentar: JSON antigo com `"arrivalNotified": true` carrega sem erro e a corrida volta sem a marca).

## Phase 3: US1 — Avisar repetidamente (P1) 🎯 MVP

**Teste independente**: posições dentro do raio com `capturedAt` espaçado → um aviso na primeira e um a cada 5 s.

- [x] T004 [US1] Em `lib/screens/map_screen.dart`, reescrever `_talvezNotificarChegada` (D1 de `research.md`): guardas de estado e de corrida, distância ≤ `_raioDeChegadaMetros`, throttle por `_ultimaChegadaEm` e `_intervaloLocalizacao`, sem `setState` nem `save`; novo campo `DateTime? _ultimaChegadaEm`; atualizar os comentários de `_raioDeChegadaMetros` e `_publicarChegada`.
- [x] T005 [US1] Reescrever o grupo da feature 011 em `test/screens/map_screen_test.dart` (≈ `:1185-1400`; ajustar os usos de `arrivalNotified` em ≈ `:1772` e `:1937`): primeira posição no raio publica na hora; 4 s depois não, 5 s depois sim; parado por 30 s ≈ um por 5 s; instante repetido ou anterior não publica; cada evento com tags `e`/`p` e `content` que decifra para `{}`.

## Phase 4: US2 — Parar quando deixa de valer (P1)

- [x] T006 [US2] Em `lib/screens/map_screen.dart`, zerar `_ultimaChegadaEm` onde `_ultimaPublicacaoEm` é zerado (conclusão, cancelamento pelo motorista, cancelamento pelo passageiro) e ao iniciar a corrida (D3).
- [x] T007 [US2] Testes em `test/screens/map_screen_test.dart`: fora do raio não publica e ao voltar respeita os 5 s desde o último; em "Aguardando" e em "Em corrida" não publica; após `20008` (encontro) e após cancelamento (pelo motorista e pelo passageiro) para; uma corrida nova não herda o intervalo.

## Phase 5: US3 — Reinício e falhas (P2)

- [x] T008 [US3] Testes em `test/screens/map_screen_test.dart`: reinício dentro do raio publica na primeira posição; sem relay conectado, sem identidade ou com cifra que falha, nada é publicado nem lança, e o próximo intervalo ainda tenta.

## Phase 6: Polish

- [x] T009 `flutter analyze` ("No issues found!") e `flutter test` do motorista; `grep -rn arrivalNotified lib test` só deve achar `destinationArrivalNotified`; anotar a contagem em `quickstart.md` e marcar a validação em aparelho como **pendente**.

## Dependências

- T002/T003 em paralelo, antes de T004 (o código novo não pode mais ler a marca). T005 depende de T004; T006 e T007 de T004; T008 de T004. MVP = T001–T005.
