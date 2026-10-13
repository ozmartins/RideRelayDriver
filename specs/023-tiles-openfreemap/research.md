# Research — Tiles vetoriais do OpenFreeMap

## D1 — Provedor de tiles (exceção 2.13.0 das Restrições de Segurança e Privacidade)

**Decision**: OpenFreeMap, instância pública, estilo `positron`.

| Opção | Resultado (consultado em 2026-10-08) |
|---|---|
| Carto Voyager raster | **Descartada.** O repositório `CartoDB/basemap-styles` exige `?key=` no raster; sem chave, o servidor responde 200 com tile "API KEY REQUIRED" (verificado por `curl`). |
| Google Maps (`google_maps_flutter`) | Descartada: chave, faturamento, reescrita da camada de mapa, Google vê a região. |
| MapTiler / Stadia / Thunderforest | Descartadas: exigem chave. |
| OpenFreeMap (escolhida) | `openfreemap.org`: "completely free: there are no limits on the number of map views or requests"; "no registration, no user database, no API keys, and no cookies"; uso comercial permitido; MIT. |
| Manter OSM e refinar o filtro | Alternativa sem emenda, mas não muda o desenho dos tiles. |

**Riscos assumidos**: sem SLA ("may discontinue it at any time without notice", `/tos/`); a Cloudflare
processa as requisições; o serviço vê IP e região (z/x/y). Atribuição obrigatória. Sem provedor de
reserva, de propósito: a exceção da constituição cobre um único serviço.

## D2 — Dependência: `vector_map_tiles` (Princípio III)

**Decision**: adotar `vector_map_tiles ^9.0.0-beta.13`, confinada a `lib/screens/camada_mapa_base.dart`.

- É o único renderizador de tiles vetoriais para `flutter_map`; a versão 9 é a que aceita
  `flutter_map ^8` (`pub add --dry-run` resolveu sem conflito em 2026-10-08).
- **É uma versão beta**: a API pode mudar e há risco de defeito. Mitigação: uso restrito a um widget de
  30 linhas; se falhar, o mapa fica só com o fundo.
- Traz transitivas novas: `vector_tile`, `vector_tile_renderer`, `protobuf`, `executor_lib`,
  `idb_shim`, `sembast`. Cache em disco padrão: 30 dias, 50 MB.
- **Não medido**: desempenho de renderização em aparelho real (Princípio V). Tiles vetoriais custam mais
  CPU/memória que raster. Ver `quickstart.md`.

## D3 — Falha e carregamento

O estilo é lido uma vez em `initState`; falha é absorvida e o mapa fica só com o fundo. Sem retentativa:
um `Timer` pendente quebra os testes de widget, e o app pode ser reaberto. Limitação registrada.
