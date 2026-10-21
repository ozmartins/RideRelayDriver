# Pesquisa e decisões: 026-recibos-de-reputacao

Nenhuma dependência nova é adicionada, então não há entrada de dependência (Princípio III). As decisões abaixo são
as que não são óbvias no código (Princípio V). Nenhuma medição é citada aqui; as que entram são feitas no quickstart.

## R1 — Numeração da feature e pasta

`especificacao-motorista.md` sugere `027-recibos-de-reputacao` ou reaproveitar `026-avaliacao-enviada-ao-passageiro`,
"já existente e vazia". Verificado em 2026-10-20: `specs/` termina em `025-conexao-em-segundo-plano` e não há pasta
`026*`. **Decisão**: `026-recibos-de-reputacao` (próximo número sequencial, `feature_numbering: sequential`). A
emenda de contrato continua sendo a **25**, a próxima depois da 24.

## R2 — Reenvio reassina um evento novo

Alternativas: (a) guardar o evento `20014` já assinado/cifrado e republicar o mesmo `payload`; (b) guardar só o
recibo e, a cada reenvio, assinar e cifrar um evento novo. **Decisão: (b).** O recibo é o artefato de longa vida
(assinado pelo avaliador, identificador estável); o evento é transporte. (a) guardaria um payload cifrado no banco
(texto cifrado longevo sem utilidade) e, com a mesma `created_at`, relays podem tratar como duplicata. (b) custa
uma cifragem por reenvio, desprezível. O receptor deduplica por `guid_corrida` (1.8), então reenvios com ids
diferentes são seguros. Consequência: o reenvio exige a identidade em memória, que só existe na interface (R3).

## R3 — Onde roda o reenvio periódico

O contrato (antes da emenda 25 ser escrita) pedia reenvio "a cada 60 s com a app em primeiro plano/serviço ativo (reaproveitar o temporizador já
usado pelas publicações periódicas)". Verificado: as publicações periódicas existentes (localização, a cada 5 s,
`_intervaloLocalizacao` em `map_screen.dart`) vivem no isolate da interface; não há temporizador de 60 s a
reaproveitar, e o serviço em segundo plano (025) não tem a chave nem decifra (restrição da constituição), logo não
pode assinar. **Decisão**: `ReceiptService` é dono de um `Timer.periodic(60 s)` no isolate da interface, enquanto a
interface existir; além dele, reenvio ao abrir o app e a cada reconexão de relay. **Limite aceito e documentado**:
com o processo da interface morto, nada é reenviado até o app reabrir (o recibo pendente sobrevive em disco). Mover o
reenvio para o serviço exigiria que a interface entregasse ao serviço o `payload` já assinado (alternativa (a)
de R2), o que é viável mas fora do escopo do contrato (critério de aceite cobre "matar e reabrir").

## R4 — Linha de `reputacao_declarada` sempre gravada

Se o passageiro não declarou reputação, `saveDeclared` grava uma `Reputation` vazia (`corridas 0`, `seqProximo 0`,
sem `head`). Assim, "linha ausente" significa que a corrida foi orçada antes desta feature ou que a gravação falhou,
e nesses casos **não** se emite recibo (não se sabe o `seq`; chutar `seq = 0` poderia forjar um ramo). "Linha vazia"
significa passageiro sem histórico e emite `seq = 0`. A spec (caso de borda) cobre esse segundo caso.

## R5 — Reputação própria é calculada, não guardada

`myReputation()` agrega `recibos_recebidos` a cada chamada (poucas linhas; cada leitura revalida assinatura).
Alternativa — tabela de resumo — duplicaria a fonte da verdade e abriria divergência. Sem cache.

## R6 — `ReputationVerifier` puro e reutilizado

A mesma função serve a exibição (autor = passageiro do `20001`) e à emissão (autor = passageiro da corrida). O
resultado `ReputationView` carrega tudo que a tela precisa; a tela não recalcula nada. A assinatura de cada recibo é
verificada dentro do verificador chamando `ReceiptSignature.verify` — função pura em relação a I/O (a verificação
Schnorr não toca disco nem rede), mas depende da biblioteca de chaves, então o teste usa chaves de teste reais.

## R7 — Reputação malformada não derruba a solicitação

`RideRequestReceived.fromNostrEvent` envolve apenas a leitura de `reputacao` em tentativa própria; falha de campo
obrigatório da solicitação continua lançando `FormatException` como hoje. Teste cobre os três casos (presente,
ausente, malformada).

## R8 — Vetores de teste compartilhados

Gerados por script reproduzível com chaves de teste fixas (nunca chaves de usuário) e copiados byte a byte para o
passageiro. Os valores de `id_recibo` e `assinatura` nos vetores vêm da execução do código, não de cálculo à mão.
Assinatura Schnorr BIP-340 com `keys.sign` pode usar aleatoriedade auxiliar: o teste de vetor **verifica** a
assinatura, não a compara por igualdade; a igualdade vale para `id_recibo` e forma canônica.

## R9 — Decisões de implementação da fundação (Fase 2)

- **`crypto` no domínio**: `Receipt.computeId` (exigido em 2.2 de `especificacao-motorista.md`) usa `package:crypto`
  em `lib/domain/receipt.dart`. É a única importação de terceiros no domínio de recibos; nenhum tipo da biblioteca
  aparece na API pública (só `String`), e `crypto` já estava no `pubspec.yaml`. Alternativa descartada: calcular o
  hash num serviço e injetá-lo em `Receipt`, o que tiraria do tipo a garantia de que o id bate com a forma canônica.
- **Verificador como função**: `verifyReputation(Reputation, {authorPubkey})` em `reputation_verifier.dart`, não
  `ReputationVerifier.verify`. Uma classe só com método estático não teria segunda implementação (Princípio V).
- **Mais de 5 recibos**: `Reputation.fromJson` rejeita listas com mais de `kReputacaoJanela` recibos (reputação
  malformada → ausente), para não verificar assinaturas de uma lista de tamanho arbitrário vinda de um relay. O
  contrato diz "os N mais recentes (N = 5)" sem dizer o que fazer com mais de N; **pendência**: esclarecer no
  contrato nas duas apps.
- **(h) literal**: com `seq_proximo = 0` nada é conferido (o contrato só exige o `head` quando há recibo `seq − 1`).
  Uma reputação `seq_proximo = 0` com recibos na lista passa. Mantido literal para não divergir do passageiro;
  endurecer exigiria emenda.
- **Janela com ramo**: `aggregateReputation` apresenta um só recibo por `seq` (vence o de `criadoEm` maior, depois o
  de `idRecibo` maior), porque (e) descartaria o segundo da contraparte; os dois contam em `corridas`.
- **Recibo emitido**: `saveIssued` ignora segunda gravação da mesma corrida (o primeiro `seq` vale).
