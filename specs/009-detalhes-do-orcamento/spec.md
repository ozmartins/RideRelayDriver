# Feature Specification: Detalhes do motorista e tempo estimado no orçamento

**Feature Branch**: `009-detalhes-do-orcamento`

**Created**: 2026-09-20

**Status**: Draft

**Input**: User description: decisão tomada na conversa que originou a feature de recebimento de
orçamentos do passageiro — a modal de orçamentos do passageiro precisa exibir nome do motorista,
marca/modelo/ano do carro e o tempo estimado até a origem; nada disso está no orçamento (`kind:
20002`) hoje, que só tem `pricePerKm` e `total`. Decisão: "motorista inclui no orçamento", usando
`open_route_service` (já usado pela feature 007 para calcular a distância motorista→origem) também
para o tempo estimado.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Orçamento publicado com os dados que o passageiro precisa (Priority: P1)

Como motorista que envia um orçamento, quero que ele já leve meu nome, os dados do meu veículo e o
tempo estimado até o passageiro, para que quem decidir não precise de nenhuma informação além do
que eu publiquei.

**Why this priority**: sem isso, a modal de orçamentos do passageiro (feature seguinte) não tem de
onde tirar nome/marca/modelo/ano/tempo estimado — é pré-requisito direto.

**Independent Test**: com uma solicitação recebida e um orçamento enviado, inspecionar o evento
publicado e verificar que `content` traz `driverName`, `carBrand`, `carModel`, `carYear` e
`etaMinutes`, coerentes com o cadastro do motorista e com a distância até a origem.

**Acceptance Scenarios**:

1. **Given** uma modal de solicitação aberta, com o cadastro do motorista já carregado, **When** o
   motorista toca em "Enviar orçamento", **Then** o evento publicado (`kind: 20002`) traz, além de
   `pricePerKm` e `total` já existentes, `driverName` (nome do cadastro), `carBrand` (marca),
   `carModel` (modelo) e `carYear` (ano) do veículo.
2. **Given** a mesma modal, **When** a distância motorista→origem terminou de ser calculada antes do
   envio, **Then** o orçamento publicado traz `etaMinutes`, um tempo estimado em minutos derivado da
   duração do trajeto motorista→origem (mesma chamada de rota já usada para a distância exibida).
3. **Given** a distância motorista→origem falhou ao calcular, **When** o motorista ainda assim envia
   o orçamento, **Then** o orçamento é publicado sem `etaMinutes` (campo omitido, não um valor
   inventado) — mesma postura de "nunca calcular o que falhou" já adotada pela feature 007.

### Edge Cases

- Motorista sem cadastro (não deveria ser alcançável, pois cadastro é obrigatório antes de qualquer
  tela — feature 003): fora de escopo, mesma garantia estrutural já existente.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: O evento de orçamento (`kind: 20002`) MUST incluir `driverName`, `carBrand`,
  `carModel` e `carYear`, obtidos do cadastro do motorista no momento do envio.
- **FR-002**: O evento de orçamento MUST incluir `etaMinutes` quando a duração do trajeto
  motorista→origem estiver disponível no momento do envio, derivado dessa mesma chamada de rota (D1
  de `research.md`) — sem chamada de rede adicional.
- **FR-003**: O evento de orçamento MUST NOT incluir `etaMinutes` quando essa duração não estiver
  disponível (falha de cálculo) — campo omitido, nunca um valor estimado por outro meio.
- **FR-004**: Este contrato ampliado MUST ser definido antes do código (Princípio IV) e replicado de
  forma idêntica na app do passageiro, na mesma alteração.

### Key Entities

- **`RideQuote`** (existente, feature 007): ganha `driverName`, `carBrand`, `carModel`, `carYear`
  (sempre presentes) e `etaMinutes` (opcional).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% dos orçamentos publicados com sucesso trazem `driverName`/`carBrand`/`carModel`/
  `carYear` coerentes com o cadastro do motorista no momento do envio.
- **SC-002**: `etaMinutes` nunca aparece no orçamento quando a distância motorista→origem não pôde
  ser calculada — verificado nos casos de falha simulada.

## Assumptions

- `etaMinutes` é derivado da `duration` já devolvida pela mesma chamada de rota que calcula a
  distância motorista→origem (resposta do OpenRouteService já traz os dois valores) — não é uma
  segunda chamada de rede.
- Não há requisito de atualizar o orçamento já publicado se a posição do motorista mudar depois do
  envio — é um retrato do momento da publicação, como o preço e o total já são.
