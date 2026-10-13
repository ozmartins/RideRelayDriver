# Quickstart — Avaliar corrida (motorista)

Guia de validação manual desta feature, em `Prototipo/driver/`. Pressupõe uma corrida no estado
"Em corrida" prestes a ser encerrada pela confirmação de destino do passageiro (feature
`012-confirmar-encontro-destino`) — um único aparelho/emulador do motorista basta, já que esta
feature é inteiramente local (a confirmação de destino em si pode ser simulada publicando
`kind: 20010` diretamente, sem precisar do app do passageiro).

## Cenários de validação (referem os FR/SC de `spec.md`)

### 1. Avaliar a corrida ao final (US1, SC-001, SC-002)

1. Com uma corrida no estado "Em corrida", receber a confirmação de destino do passageiro
   (`kind: 20010`, encerra a corrida e volta o app a "Aguardando solicitação de corrida").
2. **Esperado**: em seguida (até 2 s), a tela de avaliação da corrida aparece, com cinco estrelas
   e nenhuma pré-selecionada.
3. Tocar na quarta estrela. **Esperado**: as estrelas 1 a 4 aparecem selecionadas; 5, não.
4. Tocar "Confirmar". **Esperado**: a tela fecha; inspecionar o banco local (`ride_ratings.db`,
   tabela `ride_ratings`) e confirmar uma linha com `ride_id` igual ao `quoteId` da corrida e
   `stars = 4`.

### 2. Pular a avaliação (US1, cenário 4)

1. Repetir o passo 1 do cenário anterior para uma nova corrida.
2. Na tela de avaliação, tocar em pular/fechar sem selecionar nenhuma estrela.
3. **Esperado**: a tela fecha; nenhuma linha nova aparece em `ride_ratings` para aquela corrida.

### 3. Nunca reavaliar a mesma corrida (FR-006)

1. Depois do cenário 1 (corrida já avaliada com 4 estrelas), verificar que não há nenhuma ação no
   app que reabra a tela de avaliação para a mesma corrida.

### 4. Oportunidade se perde ao fechar o app (Edge Case, FR-009)

1. Repetir o passo 1 do cenário 1 para uma nova corrida, mas fechar o app (encerrar o processo)
   assim que a tela de avaliação aparecer, sem tocar em nada.
2. Reabrir o app. **Esperado**: a tela de avaliação não reaparece; nenhuma linha é criada em
   `ride_ratings` para aquela corrida.
