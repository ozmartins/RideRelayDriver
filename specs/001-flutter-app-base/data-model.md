# Phase 1 — Data Model: Aplicativo Mobile Base (Motorista)

## Entidades de domínio

**Nenhuma.** O spec declara explicitamente que esta feature não modela nem persiste dados de domínio
(seção *Key Entities*) e FR-005 proíbe persistência, rede e permissões nesta etapa. Não há tabelas,
esquemas, modelos Dart de domínio, DTOs ou serialização a definir.

## Estado da aplicação

| Elemento | Tipo | Persistência | Observações |
|----------|------|--------------|-------------|
| Título do app | constante de compilação (`String`) | nenhuma | "Caronas Motorista"; usado no `MaterialApp.title`, na `AppBar` e no `android:label` |
| Tema | derivado do sistema | nenhuma | `ThemeMode.system` com os esquemas padrão do Material; nada é escolhido ou salvo pelo usuário (SC-004) |

A tela inicial é **stateless**: não há `setState`, nenhum estado mutável, nenhum ciclo de vida a modelar.
Ao ir para segundo plano e voltar, o sistema operacional restaura a mesma árvore de widgets — o cenário de
aceitação 2 da User Story 1 é satisfeito sem código de persistência de estado.

## Transições de estado

Não aplicável — não existe máquina de estados nesta feature.

## Identidade

O único identificador estável introduzido é o do **aplicativo**, não de dados:

- `applicationId` / namespace Android: `br.ufsc.tcc.caronas.driver`
- nome de pacote Dart: `driver`
- nome de exibição: `Caronas Motorista`
- identificador irmão reservado (fora desta feature): `br.ufsc.tcc.caronas.passenger`

## O que vem depois (fora desta feature)

Registrado apenas para deixar claro por que este documento está vazio, sem comprometer decisão alguma:
as entidades reais do protótipo (identidade de chave pública/privada Nostr, oferta de carona, solicitação,
mensagem entre pares) nascem junto das features de comunicação via relays, onde cada uma será um **formato
de evento Nostr** replicado de forma idêntica nas apps do motorista e do passageiro.
