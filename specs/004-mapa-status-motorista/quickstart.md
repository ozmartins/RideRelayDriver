# Phase 1 — Quickstart / Validação: Mapa e Status de Disponibilidade do Motorista

Comandos executados a partir de `Prototipo/driver`. O cenário 1 é automatizado; os demais exigem
emulador/aparelho com localização simulável e, para carregar os mosaicos do mapa, conectividade de
rede (D2 de `research.md`).

## Pré-requisitos

- Ambiente das features 001–003 funcionando (ver `README.md`)
- Dependências instaladas: `flutter pub get`
- No emulador: localização simulada disponível (Android Studio → Extended Controls → Location, ou
  `adb emu geo fix <longitude> <latitude>`)

## Cenário 1 — Gates automatizados

```bash
flutter analyze   # esperado: No issues found!
flutter test      # esperado: todos os testes passam
```

Cobre, com dublê de `LocationService` e sem sensor real (Princípio II por analogia): posição exibida
quando disponível, mensagem quando indisponível, transição para online exigindo posição válida,
transição automática para offline quando a posição some, e status sempre offline ao iniciar.

## Cenário 2 — Mapa na posição real (US1, SC-001)

```bash
flutter run
```

1. Com localização simulada configurada no emulador, abra o aplicativo.

**Esperado**: a tela inicial é um mapa centrado na posição simulada, com um indicador visível naquele
ponto, em até 5 segundos.

## Cenário 3 — Indicador acompanha o deslocamento (US1 cenário 2, SC-002)

Com o aplicativo aberto na tela de mapa:

```bash
adb emu geo fix -49.4900 -28.9350   # primeira posição
# aguardar o indicador aparecer, depois:
adb emu geo fix -49.4950 -28.9400   # posição deslocada
```

**Esperado**: o indicador se move para a nova posição sem nenhuma ação manual, em até 10 segundos.

## Cenário 4 — Permissão de localização (US1 cenários 3 e 4)

1. Instale o aplicativo do zero (ou revogue a permissão de localização pelas configurações do sistema)
   e abra-o.

**Esperado**: o aplicativo solicita a permissão de localização, explicando o motivo. Ao negar, a tela
de mapa mostra uma mensagem compreensível em vez de travar ou mostrar erro técnico.

## Cenário 5 — Ficar online exige posição válida (US2 cenários 1 e 5, SC-004)

1. Sem localização disponível (permissão negada, ou emulador sem localização simulada configurada),
   toque no botão de status para tentar ficar online.

**Esperado**: o aplicativo impede a mudança e explica que precisa da localização primeiro; o status
permanece offline.

## Cenário 6 — Alternar online/offline (US2 cenários 1 e 2, SC-003)

Com localização disponível:

1. Toque no botão de status para ficar online.
2. Toque novamente para voltar a offline.

**Esperado**: o status exibido muda em até 1 segundo em cada toque, sempre visível na tela.

## Cenário 7 — Perda de localização estando online (US2 cenário 4, SC-006)

1. Com o motorista online (cenário 6), revogue a permissão de localização pelas configurações do
   sistema (ou desligue a localização simulada do emulador).

**Esperado**: o aplicativo coloca o motorista offline automaticamente e explica o motivo, sem travar.

## Cenário 8 — Status sempre offline ao reabrir (US2 cenário 3, SC-005)

1. Com o motorista online, encerre o aplicativo completamente (não apenas segundo plano) e reabra-o.
   Repita 5 vezes.

**Esperado**: em todas as 5 reaberturas, o status exibido é offline, exigindo ação deliberada para
ficar online de novo.

## Resultados da execução de 17/09/2026

**Cenários 2–8 (emulador/aparelho): não executados nesta rodada.** A sessão que implementou esta
feature não conseguiu manter o emulador `Pixel_6_API34_1` de pé entre chamadas de ferramenta neste
ambiente — o processo do emulador foi encerrado três vezes seguidas assim que a chamada que o lançava
terminava, mesmo isolado com `nohup`/`disown` e como tarefa em segundo plano rastreada pelo próprio
ambiente. Registrar um resultado desses cenários sem tê-los executado de fato seria medição fabricada
(Princípio V) — por isso ficam **pendentes de execução manual**, num ambiente com emulador ou aparelho
físico disponível de forma persistente, antes de declarar a feature concluída em produção.

O que **foi** verificado nesta rodada, sem depender do emulador:

| Cenário | Resultado |
|---------|-----------|
| 1 — `flutter analyze` / `flutter test` | ✅ `No issues found!` e **120 testes** aprovados, nenhum ignorado — cobrindo, com dublê de `LocationService`, todos os comportamentos de US1 e US2: posição exibida e indicador atualizado, mensagem de indisponibilidade sem travar (permissão negada, negada permanentemente, sinal perdido), bloqueio de ficar online sem posição válida, offline automático ao perder a posição estando online, estado inicial sempre offline, e dois toques rápidos no controle de status resultando em estado final único |
| 2–8 (medições em aparelho: SC-001, SC-002, SC-003, e as demais verificações visuais) | ⚠️ pendentes — ver acima |

**Pendência explícita para antes da entrega final**: rodar os cenários 2 a 8 em um emulador ou
aparelho físico controlado interativamente (não em processo desacoplado), medindo de fato SC-001,
SC-002 e SC-003, nos mesmos moldes já feitos para as features 002 e 003.
