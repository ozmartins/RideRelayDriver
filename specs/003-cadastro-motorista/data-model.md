# Phase 1 — Data Model: Cadastro do Motorista

Entidades vivem em `lib/domain/` com tipos próprios; `sqflite` fica confinado à camada de serviços
(D1 de `research.md`), atrás de uma interface própria do projeto — a UI e o domínio nunca importam
`package:sqflite`.

## Cadastro do motorista (`DriverProfile`)

| Campo | Tipo | Regras |
|-------|------|--------|
| `nome` | `String` | Obrigatório; espaços nas pontas descartados; não pode ficar vazio após o corte (FR-002, FR-006) |
| `uf` | `String` (sigla, 2 letras) | Obrigatório; uma das 26 UFs ou `DF`, de uma lista fixa embutida (FR-003) |
| `cidade` | `String` | Obrigatória; precisa constar na lista de municípios do IBGE da `uf` selecionada (FR-004); limpa sempre que `uf` muda (FR-009) |
| `marcaVeiculo` | `String` | Obrigatório; texto livre — não há lista oficial equivalente à do IBGE para marcas (D2 de `research.md`, Assumptions do `spec.md`); espaços nas pontas descartados |
| `modeloVeiculo` | `String` | Obrigatório; texto livre, mesma regra de `marcaVeiculo` |
| `corVeiculo` | `String` | Obrigatório; texto livre, mesma regra de `marcaVeiculo` |
| `placaVeiculo` | `String` (7 caracteres, caixa alta, sem separador) | Obrigatória; formato antigo ou Mercosul (FR-005, D3 de `research.md`); normalizada antes de validar e de persistir |

- **Identidade e unicidade**: no máximo um cadastro por instalação do aplicativo — não há múltiplos
  motoristas no mesmo aparelho nesta feature. A tabela SQLite correspondente tem, na prática, no
  máximo uma linha.
- **Ciclo de vida**: ausente na instalação → criado quando o formulário é enviado com todos os campos
  válidos (US1) → lido na inicialização seguinte para decidir se o formulário aparece (US2) → pode ser
  atualizado por completo pela tela de edição (US3), sempre pelas mesmas regras de validação → some
  apenas com a desinstalação do aplicativo, igual à identidade Nostr (FR-004 da feature 002, Edge
  Cases desta feature).
- **Validação de `uf`**: contra a lista fixa das 26 unidades da federação e o Distrito Federal (`UF`,
  abaixo) — nunca texto livre, nunca aceita por regex.
- **Validação de `cidade`**: contra a lista de municípios do IBGE correspondente à `uf` já escolhida
  (`Municipio`, abaixo) — nunca texto livre. Uma `cidade` só é válida em combinação com a `uf` que a
  contém; trocar a `uf` sem trocar a `cidade` deixaria essa combinação inconsistente, por isso FR-009
  exige limpar `cidade` nesse momento.
- **Validação de `placaVeiculo`**: normalizar para caixa alta e remover espaços/hífen, depois conferir
  contra `^[A-Z]{3}[0-9][A-Z0-9][0-9]{2}$` (D3 de `research.md`). `abc1d23`, `ABC-1D23` e `ABC1D23`
  resultam no mesmo valor persistido.
- **Não é segredo criptográfico**: ao contrário da identidade Nostr, corrupção ou perda deste cadastro
  não tem o tratamento do Princípio I — a resposta é solicitar o preenchimento de novo (FR-010), não
  impedir o uso do aplicativo nem alertar sobre perda irreversível.

## Unidade da Federação (`UF`)

| Campo | Tipo | Regras |
|-------|------|--------|
| `sigla` | `String` (2 letras) | Chave da entidade — `AC`, `AL`, ..., `DF`, ..., `TO` |
| `nome` | `String` | Nome completo, para exibição (ex.: "Distrito Federal") |

- Lista **fixa**, com exatamente 27 entradas (26 estados + Distrito Federal), embutida como constante
  do projeto — não sujeita a atualização externa (D2 de `research.md`).

## Município (`Municipio`)

| Campo | Tipo | Regras |
|-------|------|--------|
| `nome` | `String` | Nome do município, conforme o IBGE |
| `uf` | `String` (sigla) | UF à qual o município pertence |

- Fonte: API de Localidades do IBGE, consultada uma única vez durante a implementação e embutida como
  dado estático do aplicativo (D2 de `research.md`) — sem chamada de rede em tempo de execução.
- O conjunto de municípios oferecido para seleção é sempre filtrado pela `uf` já escolhida no
  cadastro; não existe seleção de município sem uma `uf` definida antes (FR-004).

## Relações

```text
UF (1) ──contém──> Municipio (N)
UF (1) ──é a UF de──> DriverProfile (0..1)
Municipio (1) ──é a cidade de──> DriverProfile (0..1)
```

- Uma UF contém muitos municípios (dado fixo do IBGE, D2).
- O cadastro do motorista referencia exatamente uma UF e um município daquela UF — nunca uma
  combinação de UF e município que não correspondam entre si (FR-009).
- Há no máximo um `DriverProfile` por instalação.

## Persistência

| Dado | Onde | Justificativa |
|------|------|----------------|
| Cadastro do motorista (`DriverProfile`) | Banco de dados SQLite local, via `sqflite` (D1) | Exigência explícita da feature; dado estruturado, de baixo volume, sem necessidade de sincronização com rede |
| Lista de UFs | Constante embutida no código Dart | Dado fixo, nunca muda (D2) |
| Lista de municípios do IBGE | Arquivo de dados embutido no aplicativo, gerado a partir da API do IBGE | Precisa funcionar offline; muda apenas se o IBGE alterar a divisão municipal, o que é raro (D2) |

### Esquema SQLite

Uma única tabela, criada na primeira abertura do banco:

```sql
CREATE TABLE driver_profile (
  id             INTEGER PRIMARY KEY CHECK (id = 1), -- garante no máximo uma linha
  nome           TEXT NOT NULL,
  uf             TEXT NOT NULL,
  cidade         TEXT NOT NULL,
  marca_veiculo  TEXT NOT NULL,
  modelo_veiculo TEXT NOT NULL,
  cor_veiculo    TEXT NOT NULL,
  placa_veiculo  TEXT NOT NULL
);
```

A restrição `CHECK (id = 1)` é o que impede, no próprio banco, mais de um cadastro por instalação —
gravar substitui a única linha existente (`INSERT OR REPLACE`), em vez de acumular histórico.
