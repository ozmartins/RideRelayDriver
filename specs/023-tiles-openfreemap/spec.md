# Feature Specification: Tiles vetoriais do OpenFreeMap no mapa

**Feature Branch**: `023-tiles-openfreemap` (trabalho direto na `master`)
**Created**: 2026-10-08
**Status**: Implemented — validação em aparelho pendente
**Input**: pedido do autor: "melhorar a aparência dos tiles" do mapa.

## Escopo

Trocar os tiles raster do OpenStreetMap (`tile.openstreetmap.org`) por tiles vetoriais do OpenFreeMap
(estilo `positron`), nas duas apps, na mesma alteração. Só a camada de base do mapa muda: posição,
marcadores, rota, botão "Centralizar" e todo o comportamento de corrida ficam intactos. Sem contrato de
eventos, sem contrapartida de lógica (a outra app recebe a mesma troca por simetria visual).

## Requisitos

- **FR-001**: o mapa MUST desenhar o fundo com `CamadaMapaBase` (`vector_map_tiles`), estilo
  `https://tiles.openfreemap.org/styles/positron`, tingido com o lilás `mapa-base`.
- **FR-002**: enquanto o estilo não chega, ou se a leitura falhar, o mapa MUST mostrar só o fundo
  `mapa-base` — sem tile de outro provedor e sem bloquear marcadores, rota ou a corrida.
- **FR-003**: o mapa MUST exibir a atribuição "OpenFreeMap, OpenMapTiles, OpenStreetMap contributors" (em duas linhas, para caber no canto).
- **FR-004**: nenhum identificador do usuário MUST ser enviado ao serviço (constituição 2.13.0).

## Fora de escopo

Provedor de reserva, nova tentativa automática de leitura do estilo, estilo próprio, hospedagem própria
dos tiles.
