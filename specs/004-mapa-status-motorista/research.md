# Phase 0 — Research: Mapa e Status de Disponibilidade do Motorista

## D1 — Biblioteca de geolocalização (atende FR-001 a FR-005, FR-008, FR-009)

**Decision**: adotar **`geolocator` versão `^14.0.3`**.

**Contexto da decisão**: levantamento no pub.dev (busca por pacotes de geolocalização para Flutter) e
metadados publicados de cada pacote em 17/09/2026.

### Alternativas avaliadas

| Pacote | Versão | Última publicação | Observações |
|--------|--------|-------------------|-------------|
| **`geolocator`** | 14.0.3 | 2026-06-12 | 160/160 pontos, 6.127 likes — o pacote de geolocalização mais adotado do ecossistema Flutter. Expõe permissão, posição atual e stream de posições em uma única API, sem dependência de pacote adicional de permissões. |
| `location` | 10.0.2 | 2026-07-23 | 150/160 pontos, 3.211 likes. Cobre o mesmo essencial, mas com adoção bem menor e histórico de instabilidade de API entre versões maiores documentado em issues do próprio repositório. |

### Critérios aplicados

1. **Cobertura do caso de uso com a menor superfície** — a feature precisa de três coisas: checar/pedir
   permissão, ler a posição atual uma vez e assinar um fluxo contínuo de posições. `geolocator` resolve
   as três sem depender de `permission_handler` à parte, o que uma alternativa como `location` também
   faz, mas com adoção bem menor.
2. **Manutenção e adoção** — `geolocator` tem quase o dobro de likes do concorrente e é o pacote citado
   pela documentação e por tutoriais oficiais do Flutter para geolocalização.
3. **Confinamento de tipos (Princípio III)** — a API de `geolocator` (streams de `Position`, exceções
   próprias de permissão) fica inteiramente atrás de uma interface própria do projeto
   (`LocationService`), do mesmo jeito que `dart_nostr` e `sqflite` já ficam confinados a `services/`.

### Riscos assumidos e mitigação

- **Risco de acoplamento**: se `geolocator` se mostrar limitante, a troca não deve contaminar a UI.
  **Mitigação**: `lib/domain/` usa um tipo próprio (`DriverPosition`), nunca o `Position` da biblioteca;
  só `lib/services/geolocator_location_service.dart` importa `package:geolocator`.
- **Permissão de localização**: é dado sensível pela constituição (Restrições de Segurança e
  Privacidade). O pedido de permissão só acontece quando a tela de mapa é aberta, nunca antes, e a
  justificativa por escrito está nas Assumptions do `spec.md`.

## D2 — Biblioteca de mapa (atende FR-001 a FR-003)

**Decision**: adotar **`flutter_map` versão `^8.3.2`** com **`latlong2` versão `^0.10.1`**, usando
o serviço público de mapas do OpenStreetMap como fonte de imagem do mapa.

**Contexto da decisão**: levantamento no pub.dev (busca por pacotes de mapa para Flutter) e metadados
publicados de cada pacote em 17/09/2026.

### Alternativas avaliadas

| Pacote | Versão | Última publicação | Observações |
|--------|--------|-------------------|-------------|
| **`flutter_map`** | 8.3.2 | 2026-08-27 | 160/160 pontos, 2.177 likes. Não depende de conta nem chave de API — usa provedores de mapa configuráveis, com o OpenStreetMap funcionando de imediato. Widget 100% Flutter, sem código nativo de mapa embutido por uma SDK de terceiro. |
| `google_maps_flutter` | 2.18.1 | 2026-09-16 | Pacote oficial do Google, 4.628 likes, mas **exige uma chave de API do Google Cloud com faturamento habilitado** para funcionar, mesmo dentro da cota gratuita. Isso tornaria o protótipo impossível de rodar por um avaliador sem que ele próprio crie e configure essa credencial. |
| `mapbox_maps_flutter` | 2.30.1 | 2026-09-11 | 140/160 pontos, 381 likes. Mesma exigência de conta e token de terceiro que `google_maps_flutter`, com adoção bem menor. |

### Critérios aplicados

1. **Reprodutibilidade acadêmica sem credencial externa** — critério decisivo. Um protótipo de TCC
   precisa ser executável por quem avalia o trabalho sem que essa pessoa precise abrir conta em um
   provedor de mapas e cadastrar um cartão de crédito só para ver a tela inicial abrir. `flutter_map`
   com o provedor padrão do OpenStreetMap não exige nada disso; as duas alternativas exigem.
2. **Manutenção ativa** — as três alternativas publicaram nas últimas semanas; nenhuma foi descartada
   por abandono.
3. **Simplicidade proporcional (Princípio V)** — a feature pede um mapa com um indicador de posição,
   nada além disso (sem rotas, sem múltiplas camadas, sem estilização de terceiros). `flutter_map`
   entrega exatamente isso; os concorrentes trariam SDKs nativos inteiros para uma necessidade pequena.

### Riscos assumidos e mitigação

- **Uso do serviço público de mosaicos do OpenStreetMap**: a política de uso deles pede um identificador
  de aplicação no cabeçalho das requisições e limita a taxa de pedidos — adequado ao volume de uso de
  um protótipo acadêmico, não de um produto em produção. **Mitigação**: o `userAgentPackageName` da
  aplicação é configurado nas opções do `TileLayer`, conforme a própria documentação do `flutter_map`
  pede.
- **Atribuição obrigatória**: o uso de mosaicos do OpenStreetMap exige exibir a atribuição "©
  OpenStreetMap contributors" visível no mapa — tratado como requisito de implementação (widget de
  atribuição do próprio `flutter_map`), não da especificação.
- **Dependência de rede para carregar os mosaicos do mapa**: coerente com o restante do aplicativo, que
  já depende de rede para os relays; a ausência de rede é tratada como o mapa não carregando as
  imagens, sem travar o aplicativo (mesmo padrão de mensagem compreensível já usado nas features
  anteriores).

## Resumo das decisões

| # | Decisão | Tipo |
|---|---------|------|
| D1 | `geolocator ^14.0.3` para permissão, posição atual e fluxo contínuo de posições | Dependência de terceiros adicionada |
| D2 | `flutter_map ^8.3.2` + `latlong2 ^0.10.1`, com mosaicos do OpenStreetMap, para o mapa | Dependência de terceiros adicionada |
