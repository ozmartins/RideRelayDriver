# Phase 1 — Quickstart / Validação: Formas de pagamento aceitas

Comandos executados a partir de `Prototipo/driver`. O cenário 1 é automatizado; os demais exigem
emulador/aparelho, porque validam o formulário e a persistência real em SQLite (incluindo a migração
de esquema).

## Pré-requisitos

- Ambiente das features 001–003 funcionando (ver `README.md`)
- Dependências instaladas: `flutter pub get`
- Não é necessária conectividade de rede — esta feature funciona inteiramente offline, como a 003
- Para o Cenário 4 (migração): um APK/instalação já rodando a versão anterior a esta feature, com um
  cadastro já preenchido (ex.: o estado deixado pela validação da feature 003)

## Cenário 1 — Gates automatizados

```bash
flutter analyze   # esperado: No issues found!
flutter test      # esperado: todos os testes passam
```

Cobre, com dublê de `CadastroStore` e sem SQLite real (Princípio II): seleção independente das três
formas de pagamento, envio bloqueado com nenhuma marcada, `DriverProfile.isValido` exigindo o conjunto
não vazio, serialização/deserialização de `payment_methods` (`toMap`/`fromMap`), e um cadastro sem
nenhuma forma de pagamento sendo tratado como corrompido (mesma regra da FR-010 da feature 003).

## Cenário 2 — Marcar formas de pagamento no cadastro inicial (US1, SC-001, SC-002)

```bash
flutter run
```

1. Preencha o formulário de cadastro pela primeira vez, incluindo nome, UF, cidade e dados do veículo.
2. Marque "Dinheiro" e "PIX", sem marcar "Cartão".
3. Envie o formulário.

**Esperado**: o envio é aceito; abrindo a tela de edição em seguida, "Dinheiro" e "PIX" aparecem
marcados, "Cartão" desmarcado.

## Cenário 3 — Envio bloqueado sem nenhuma forma marcada (US1 cenário 2, SC-001)

1. No formulário de cadastro, preencha todos os demais campos com dados válidos.
2. Não marque nenhuma forma de pagamento.

**Esperado**: o botão de envio permanece desabilitado (ou o envio é recusado, se disparado por outro
caminho), com uma mensagem indicando que ao menos uma forma de pagamento precisa ser marcada.

## Cenário 4 — Cadastro de uma instalação anterior a esta feature (FR-006, Edge Case)

Com um aparelho/emulador já rodando uma versão anterior a esta feature, com cadastro já preenchido
(ex.: o estado da validação da feature 003):

1. Atualize o aplicativo instalado para a versão que inclui esta feature (reinstale por cima, sem
   limpar dados: `flutter run` sobre a instalação existente, ou `adb install -r`).
2. Abra o aplicativo.

**Esperado**: como o cadastro existente não tem nenhuma forma de pagamento registrada, ele é tratado
como corrompido pela mesma regra já usada para qualquer outro campo obrigatório ausente (FR-010 da
feature 003) — o formulário completo é exibido de novo, pedindo todos os campos, não apenas as formas
de pagamento. Este é o comportamento esperado e deliberado (FR-006, Assumptions do `spec.md`), não um
defeito a corrigir.

## Cenário 5 — Corrigir as formas de pagamento depois do cadastro (US2, SC-004)

Com um cadastro já preenchido (Cenário 2):

1. Abra a tela de edição do cadastro.
2. Marque "Cartão" também, mantendo "Dinheiro" e "PIX" marcados.
3. Salve.
4. Feche e reabra o aplicativo; abra a edição de novo.

**Esperado**: as três formas aparecem marcadas na consulta seguinte.

## Verificação de não vazamento (Princípio I, por não aplicabilidade)

Esta feature não toca chave privada, semente nem material de assinatura — não há verificação de
vazamento criptográfico a executar.
