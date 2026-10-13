# Contrato — emenda 14: `kind: 20012` "Corrida cancelada"

Este diretório não guarda um contrato próprio: o contrato único do protótipo está em
`specs/002-nostr-relay-connection/contracts/nostr-events.md` (e na cópia do passageiro, com
cabeçalho de procedência). Esta feature **acrescenta a emenda 14 às duas cópias, na mesma alteração
e antes do código** (Princípio IV). O texto a inserir:

## 1. Linha na tabela de kinds (depois de `20011`)

```
| `20012` | Corrida cancelada | feature 018 (motorista) | motorista → relays → passageiro | Ver *Conteúdo do kind 20012* abaixo |
```

## 2. Linha no *Histórico de emendas*

```
| 14 | 2026-10-04 | Define `kind: 20012` para "Corrida cancelada" (seção *Conteúdo do kind 20012*); o passageiro passa a se inscrever também em `20012` (Forma da inscrição atualizada) | Feature 018 do motorista (cancelar corrida): depois de aceito o orçamento, o motorista passa a poder cancelar a corrida em "Deslocando-se até o passageiro" ou "Em corrida", e o passageiro precisa saber para avisar o usuário e encerrar a corrida dele. Definido pelo motorista, que o publica; o consumo é da feature dele (019) |
```

## 3. Parágrafo na seção *Forma da inscrição*

Acrescentar a `20012` à lista de kinds a que o passageiro se inscreve ("desde a emenda 14, `20012`
(recebe o cancelamento da corrida pelo motorista, feature 019 do passageiro)"), no mesmo estilo do
que a emenda 13 fez para `20011`. A inscrição do motorista não muda.

## 4. Seção nova (depois de *Conteúdo do kind 20011*)

```
## Conteúdo do kind 20012 — Corrida cancelada (emenda 14)

Evento **efêmero** (mesma faixa 20000–29999). Publicado pelo motorista **uma única vez por corrida**,
quando ele cancela a corrida ativa enquanto está no estado local "Deslocando-se até o passageiro" ou
"Em corrida" (features 010 e 012). Nunca é publicado em "Aguardando solicitação de corrida".

**Tags**: a tag de marcador do protótipo, `["t", "tcc-ufsc-caronas"]`; uma tag de referência ao
orçamento aceito daquela corrida, `["e", "<id-do-orçamento>"]`; e uma tag de destinatário,
`["p", "<pubkey-do-passageiro>"]` — mesmo formato dos `kind: 20007` e `20009`.

**`content`**: string vazia (`""`) — não há motivo nem posição; mesma convenção dos demais kinds
efêmeros sem dado próprio.

**Privacidade**: mesma dos demais kinds efêmeros deste contrato — sem criptografia, sem dado além
dos identificadores de correlação já usados pelos kinds anteriores.

**Consumo pelo passageiro**: implementado pela feature 019 dele. Só vale evento **assinado pelo
motorista cujo orçamento o passageiro aceitou** (autor = autor do `kind: 20002` aceito) e que
referencia o `quoteId` da corrida aceita, com o passageiro em "orçamento aceito", "motorista a
caminho" ou "em corrida": exibe uma modal informando o cancelamento e encerra a corrida no app dele.
Fora dessas condições (outra corrida, outro autor, corrida já encerrada ou concluída), é ignorado
sem erro. Um evento duplicado ou reentregue não tem efeito além do primeiro.
```
