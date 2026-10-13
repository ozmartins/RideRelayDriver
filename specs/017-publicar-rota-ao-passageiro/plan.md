# Implementation Plan: Publicar ao passageiro a rota da corrida

**Branch**: `master` (commits diretos, sem branch de feature — Padrão de Commits da constituição) | **Date**: 2026-10-03 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/017-publicar-rota-ao-passageiro/spec.md`

## Summary

Em "Em corrida", cada vez que `MapScreen._calcularRota` (feature 016) obtém com sucesso o trajeto
da posição do motorista até o destino, o app também publica esse trajeto ao passageiro da corrida
ativa num evento novo, `kind: 20011` ("Rota da corrida"), definido pela emenda 13 do contrato e
replicado no passageiro na mesma alteração. Nenhuma consulta nova ao serviço de rotas: o
`RouteTrace` já calculado para o mapa é reaproveitado. O `content` leva os pontos arredondados a
5 casas decimais e limitados a 1000 pontos (decimação uniforme preservando início e fim), o que
mantém o evento em ~23 KB contra os 128 KiB do relay mais restritivo medido. Falha de cálculo, outro
estado ou resposta tardia: nada é publicado. Estritamente do lado do motorista; o desenho no mapa
do passageiro é a feature `018` dele.

## Technical Context

**Language/Version**: Dart 3 / Flutter (versão já fixada no `pubspec.yaml`)

**Primary Dependencies**: `dart_nostr` (assinatura, já em uso), `latlong2` (já em uso) — **nenhuma
dependência nova**.

**Storage**: N/A — a rota publicada é efêmera; nada é persistido.

**Testing**: `flutter_test`, com dublês de `RouteDistanceService`, `LocationService` e
`RelayService`; nenhum teste toca rede (Princípio II). Codificação/redução dos pontos é lógica pura
em `domain/`, testada diretamente; assinatura do novo kind tem teste próprio (Princípio II).

**Target Platform**: Android (sem mudança)

**Project Type**: mobile-app (Flutter, Android apenas)

**Performance Goals**: publicação disparada no mesmo instante em que o trajeto é desenhado no mapa
do motorista (sem espera adicional além da assinatura local).

**Constraints**: zero consultas extras ao serviço de rotas (SC-003); evento ≤ ~24 KB, ≤ 1000 pontos
(D3); sem criptografia, sem dado além do trajeto e dos identificadores de correlação (D6).

**Scale/Scope**: uma corrida ativa; no máximo uma publicação por cálculo bem-sucedido (≤ 1 por
50 m percorridos, mais 1 ao entrar em "Em corrida").

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Princípio / restrição | Avaliação |
|---|---|
| I. Segredo criptográfico não vaza | PASS. Mesma assinatura por `Identity.privateKey` dos demais kinds; nenhum novo caminho de log nem persistência de segredo. |
| II. Assinatura/verificação nascem com teste | PASS (obrigação). `IdentityService.signRideRoute` (novo) MUST ter teste de assinatura, no padrão de `signArrivalNotice`; a lógica de redução/codificação é pura e testada diretamente. |
| III. Dependência exige decisão registrada | PASS por vacuidade — nenhuma dependência nova. |
| IV. Contrato antes do código, replicado | **GATE ATIVO.** A emenda 13 (kind `20011`) MUST ser escrita nas duas cópias do contrato **antes** do código, na mesma alteração; ver `contracts/README.md`. A cópia do passageiro ganha a nova seção e o cabeçalho de procedência atualizado. |
| V. Simplicidade e medição | PASS. Reuso do `RouteTrace`; decimação uniforme em vez de algoritmo de simplificação; limite de tamanho decidido com medição real do `max_message_length` dos relays padrão (D3). |
| Restrições de Segurança e Privacidade | PASS sem emenda — a exceção de roteamento cobre a chamada ao serviço de rotas, que não muda; o evento vai só a relays Nostr, para o passageiro da própria corrida, e não revela mais que o `kind: 20005` já revela (D6). |
| Identidade Visual e Design | N/A — nenhuma tela alterada. |

Pós-design (Phase 1): inalterado; o gate IV é cumprido pelo primeiro item de `tasks.md`.

## Project Structure

### Documentation (this feature)

```text
specs/017-publicar-rota-ao-passageiro/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/README.md   # texto da emenda 13 a inserir nas duas cópias do contrato
├── checklists/requirements.md
└── tasks.md              # /speckit-tasks
```

### Source Code

```text
lib/
├── domain/
│   └── ride_route_content.dart      # NOVO: reduz (≤ 1000 pontos) e codifica os pontos em JSON
├── domain/nostr_event.dart          # + kindRideRoute = 20011
├── services/identity_service.dart   # + signRideRoute (usa _signCorrelatedEvent)
└── screens/map_screen.dart          # _calcularRota: publica após sucesso, só em "Em corrida"

test/
├── domain/ride_route_content_test.dart        # NOVO
├── services/identity_service_test.dart        # + signRideRoute
└── screens/map_screen_test.dart               # + publicação em Em corrida / não publica nos demais casos

specs/002-nostr-relay-connection/contracts/nostr-events.md   # + emenda 13 (e a cópia do passageiro)
```

**Structure Decision**: mesma divisão `domain/` + `services/` + `screens/` do restante do app; sem
serviço novo. A inscrição do motorista (`kinds`) não muda — ele só publica este kind.

## Complexity Tracking

Sem violações a justificar.
