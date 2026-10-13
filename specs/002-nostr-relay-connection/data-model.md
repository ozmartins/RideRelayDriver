# Phase 1 — Data Model: Conexão do Motorista com Relays Nostr

Diferente da feature 001, esta introduz entidades reais. Todas vivem em `lib/domain/` com **tipos
próprios**, sem expor tipos de `dart_nostr` à UI (mitigação do risco de acoplamento, decisão D1).

## Identidade do motorista (`Identity`)

| Campo | Tipo | Regras |
|-------|------|--------|
| `publicKey` | `String` (hex, 64 caracteres) | Derivada da chave privada; exibida ao usuário; identifica o motorista na rede |
| `privateKey` | `String` (hex, 64 caracteres) | **Nunca** exibida por padrão, registrada em log ou enviada a relay (FR-005/SC-007); vive apenas em memória e no armazenamento seguro |

- **Identidade e unicidade**: a chave pública é o identificador do motorista na rede. Uma única
  identidade por instalação.
- **Ciclo de vida**: criada na primeira execução → persistida no armazenamento seguro → recuperada nas
  execuções seguintes → destruída apenas com a desinstalação do aplicativo (FR-004, cenário 4 da US2).
- **Validação**: ambas as chaves devem ter 64 caracteres hexadecimais; uma chave recuperada fora desse
  formato é tratada como armazenamento corrompido, não como identidade válida.

## Relay (`Relay`)

| Campo | Tipo | Regras |
|-------|------|--------|
| `url` | `String` | Endereço `wss://` ou `ws://`; único na lista (FR-011); é a chave da entidade |
| `status` | `RelayStatus` | `connecting` \| `connected` \| `unavailable` |
| `lastError` | `String?` | Motivo resumido quando `unavailable`, para exibição (US1 cenário 2) |
| `isDefault` | `bool` | Distingue relay da lista padrão de relay adicionado pelo motorista |

**Transições de estado**:

```text
                  falha / timeout
        ┌──────────────────────────────┐
        ▼                              │
  [unavailable] ──── retentativa ──> [connecting] ──── handshake ok ──> [connected]
        ▲                                                                   │
        └───────────────── queda de conexão / perda de rede ────────────────┘
```

- Entrada: todo relay adicionado ou carregado da lista entra em `connecting`.
- `unavailable` não remove o relay da lista: ele permanece visível com o motivo (FR-002/FR-003).
- Retorno de rede dispara nova tentativa automática para todos em `unavailable` (FR-014).
- Remoção pelo motorista encerra a conexão e retira a entidade da lista (FR-011).

## Evento (`NostrEvent`)

| Campo | Tipo | Regras |
|-------|------|--------|
| `id` | `String` (hex) | Hash canônico definido pelo protocolo; **chave de deduplicação** (FR-010, D4) |
| `authorPublicKey` | `String` (hex, 64) | Autor do evento |
| `createdAt` | `DateTime` | Horário declarado pelo autor — dado de terceiro, não confiável para ordenação absoluta |
| `kind` | `int` | Tipo do evento conforme o protocolo |
| `tags` | `List<List<String>>` | Marcadores do evento. Entram no cálculo do `id`, logo são protegidos pela assinatura. O evento de teste carrega exatamente `["t", "tcc-ufsc-caronas"]` (emenda 01 do contrato) |
| `content` | `String` | Conteúdo textual; público nesta etapa (sem criptografia entre pares) |
| `isSignatureValid` | `bool` | Resultado da verificação; eventos inválidos são **descartados**, não exibidos (FR-009) |

Nota de implementação: `tags` é verificado no payload recebido, **antes** da conversão para o domínio —
o tipo de domínio carrega só o que a interface exibe. Quem decide é `hasPrototypeMarker` em
`lib/services/prototype_marker.dart`.

- **Origem**: eventos são recebidos de relays (dados de terceiros) ou criados localmente para publicação.
- **Regra de confiança**: nenhum campo de evento recebido é tratado como confiável antes da verificação
  de assinatura. Conteúdo recebido é **dado**, nunca instrução ou marcação renderizável.
- **Regra do marcador** (emenda 01): evento sem a tag `["t", "tcc-ufsc-caronas"]` é descartado, mesmo
  que o relay o entregue — o filtro `#t` pedido na inscrição não é garantia de bom comportamento do
  relay. O marcador **não** é mecanismo de segurança: qualquer pessoa pode publicar com a mesma tag, e
  por isso ele nunca substitui a verificação de assinatura nem a checagem de autoria.
- **Ordem de descarte**: assinatura inválida → kind não aceito → marcador ausente → duplicata. Os três
  primeiros nem chegam a ocupar a janela de memória.
- **Retenção**: apenas em memória, durante a sessão. Não há persistência de eventos nesta feature.
- **Limite**: o conjunto exibido é limitado (janela das entradas mais recentes) para sustentar SC-006 sob
  rajada de eventos.

## Relações

```text
Identity (1) ──assina──> NostrEvent (N) ──trafega por──> Relay (N)
```

- Uma identidade assina muitos eventos.
- Um evento pode chegar por vários relays; a deduplicação por `id` garante exibição única.
- Relays são independentes entre si: o estado de um não afeta o de outro (FR-003).

## Persistência

| Dado | Onde | Justificativa |
|------|------|---------------|
| Chave privada e pública | Armazenamento seguro (Keystore) | Material criptográfico (D2) |
| Lista de relays (`url` + `isDefault`) | Preferências locais, como JSON | Dado público e de baixo volume (D3) |
| `status` / `lastError` dos relays | Apenas memória | Estado de runtime; não faz sentido restaurar conexão "conectado" de uma sessão anterior |
| Eventos | Apenas memória | Escopo da feature (sem histórico offline) |
