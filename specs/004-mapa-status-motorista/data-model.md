# Phase 1 — Data Model: Mapa e Status de Disponibilidade do Motorista

Entidades vivem em `lib/domain/` com tipos próprios; `geolocator` e `flutter_map` ficam confinados à
camada de serviços e à tela (D1/D2 de `research.md`) — o domínio nunca importa esses pacotes.

## Posição do motorista (`DriverPosition`)

| Campo | Tipo | Regras |
|-------|------|--------|
| `latitude` | `double` | Coordenada geográfica atual |
| `longitude` | `double` | Coordenada geográfica atual |
| `capturedAt` | `DateTime` | Instante em que a posição foi obtida, para decidir se está "atual" |

- **Origem**: leitura contínua do sensor de localização do aparelho (D1). Nunca inventada nem
  aproximada pelo aplicativo.
- **Ciclo de vida**: existe apenas em memória, atualizada a cada nova leitura recebida enquanto a tela
  de mapa está em primeiro plano. Não é persistida entre execuções nem enviada a nenhum relay ou
  servidor (Assumptions do `spec.md`).
- **Ausência**: representada por `null` — sem uma leitura de posição válida, a tela de mapa mostra a
  mensagem de indisponibilidade (FR-005) em vez de uma posição inventada.

## Status de disponibilidade (`AvailabilityStatus`)

| Valor | Significado |
|-------|-------------|
| `online` | O motorista está disponível; o aplicativo está em condições de notificar solicitações de corrida (mecanismo de feature futura) |
| `offline` | O motorista não está disponível; nenhuma notificação de solicitação de corrida deve ocorrer |

- **Estado inicial**: sempre `offline` a cada abertura do aplicativo (FR-010) — não é lido de nenhum
  armazenamento persistente.
- **Transições permitidas**:

```text
  [offline] ──── motorista liga, com posição válida disponível ────> [online]
     ▲                                                                  │
     └──── motorista desliga, OU localização deixa de estar disponível ─┘
```

  - `offline → online` só é permitida com uma `DriverPosition` não nula presente (FR-008); a tentativa
    sem posição válida não muda o estado e produz a explicação de FR-008.
  - `online → offline` acontece por ação do motorista (US2 cenário 2) ou automaticamente quando a
    posição deixa de estar disponível enquanto online (FR-009, US2 cenário 4) — os dois casos levam ao
    mesmo estado final, `offline`, distintos apenas pela mensagem exibida.
- **Persistência**: nenhuma. É recalculado como `offline` a cada início do aplicativo.

## Relações

```text
AvailabilityStatus (online) ──requer──> DriverPosition (não nula)
```

- `online` não existe como estado sem uma `DriverPosition` presente no momento da transição; a perda
  subsequente da posição força a volta a `offline` (FR-009).
- `DriverPosition` existe independentemente do `AvailabilityStatus` — a posição é exibida no mapa esteja
  o motorista online ou offline (US1 não depende de US2).

## Persistência

| Dado | Onde | Justificativa |
|------|------|----------------|
| `DriverPosition` | Apenas memória | Dado de sensor, sempre relido; não há requisito de histórico (Assumptions do `spec.md`) |
| `AvailabilityStatus` | Apenas memória, sempre `offline` na inicialização | FR-010: decisão de segurança/UX de exigir ação deliberada a cada sessão |
