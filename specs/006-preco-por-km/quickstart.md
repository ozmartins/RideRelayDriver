# Phase 1 — Quickstart / Validação: Preço padrão por quilômetro

Comandos executados a partir de `Prototipo/driver`. O cenário 1 é automatizado; os demais exigem
emulador/aparelho, porque validam o formulário e a persistência real em SQLite (incluindo a migração
de esquema).

## Pré-requisitos

- Ambiente das features 001–005 funcionando (ver `README.md`)
- Dependências instaladas: `flutter pub get`
- Não é necessária conectividade de rede — esta feature funciona inteiramente offline
- Para o Cenário 4 (migração): um APK/instalação já rodando uma versão anterior a esta feature, com um
  cadastro já preenchido

## Cenário 1 — Gates automatizados

```bash
flutter analyze   # esperado: No issues found!
flutter test      # esperado: todos os testes passam
```

Cobre, com dublê de `CadastroStore` e sem SQLite real (Princípio II por analogia): `parsePrecoPorKm`
aceitando vírgula e ponto, recusando texto vazio/zero/negativo/mais de duas casas decimais,
`DriverProfile.isValido` exigindo `precoPorKm > 0`, `toMap`/`fromMap`, e um cadastro com preço zerado
sendo tratado como corrompido (mesma regra da feature 005).

## Cenário 2 — Informar o preço no cadastro inicial (US1, SC-001, SC-002)

```bash
flutter run
```

1. Preencha o formulário de cadastro pela primeira vez, incluindo nome, UF, cidade, veículo e formas
   de pagamento.
2. Informe "2,50" no campo de preço por quilômetro.
3. Envie o formulário.

**Esperado**: o envio é aceito; abrindo a tela de edição em seguida, o campo mostra o valor
informado. O texto explicativo junto ao campo (FR-003) está visível antes do envio.

## Cenário 3 — Envio bloqueado com preço inválido (US1 cenário 2, SC-001)

No formulário de cadastro, com todos os demais campos válidos, teste cada um destes valores no campo
de preço por quilômetro: vazio, `0`, `-1`, `2,555` (três casas decimais), `abc`.

**Esperado**: em todos os casos, o botão de envio permanece desabilitado, com uma mensagem indicando
o motivo junto ao campo.

## Cenário 4 — Cadastro de uma instalação anterior a esta feature (FR-006, Edge Case)

Com um aparelho/emulador já rodando uma versão anterior a esta feature, com cadastro já preenchido:

1. Atualize o aplicativo instalado para a versão que inclui esta feature, sem limpar dados.
2. Abra o aplicativo.

**Esperado**: como o cadastro existente não tem preço por quilômetro registrado (a coluna nova assume
`0` pelo `DEFAULT`), ele é tratado como corrompido pela mesma regra já usada para qualquer outro campo
obrigatório ausente — o formulário completo é exibido de novo. Comportamento esperado e deliberado
(FR-006), não um defeito.

## Cenário 5 — Corrigir o preço depois do cadastro (US2, SC-004)

Com um cadastro já preenchido (Cenário 2):

1. Abra a tela de edição do cadastro.
2. Altere o preço por quilômetro para "3,00".
3. Salve.
4. Feche e reabra o aplicativo; abra a edição de novo.

**Esperado**: o novo valor ("3,00" ou "3,0", conforme a formatação de exibição) aparece na consulta
seguinte.

## Verificação de não vazamento (Princípio I, por não aplicabilidade)

Esta feature não toca chave privada, semente nem material de assinatura — não há verificação de
vazamento criptográfico a executar.
