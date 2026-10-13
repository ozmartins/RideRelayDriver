# Especificação: Reconexão manual com os relays (motorista)

**Feature**: `024-reconectar-relays` · **App**: `driver/` · **Data**: 2026-10-11
**Contrato de eventos**: não muda. Sem contrapartida no passageiro (que já tem "Tentar reconectar").

## Problema

O `RelayService` reconecta sozinho (retentativa dos indisponíveis a cada 15 s, sonda de vivacidade a cada
30 s), mas o motorista não tem como acionar a reconexão nem sabe, olhando o mapa, que perdeu a conexão. A tela
de diagnóstico que tinha o botão de atualizar saiu na feature `010-remover-aba-eventos`. Sem relay conectado o
app não recebe solicitações nem publica orçamentos, localização ou avisos.

## Requisitos

- **FR-001** A aba "Relays" MUST ter o botão "Reconectar" quando a lista não está vazia.
- **FR-002** O mapa MUST mostrar a faixa "Sem conexão com os relays." com o botão "Reconectar" enquanto
  nenhum relay estiver conectado, e MUST escondê-la assim que um conectar.
- **FR-003** "Reconectar" MUST sondar na hora os relays conectados (conexão meio aberta continua "conectada"
  até a sonda falhar) e reconectar todos os indisponíveis, sem esperar o ciclo automático.
- **FR-004** Relay que responde à sonda MUST NOT ser reconectado; relay em `connecting` MUST NOT ganhar uma
  segunda conexão.
- **FR-005** O botão MUST ficar desabilitado ("Reconectando…") durante a chamada: toque duplo não sobrepõe
  rodadas.
- **FR-006** A inscrição (REQ) é reenviada pelo gateway a toda conexão estabelecida; nada a acrescentar.
- **FR-007** A faixa de rota indisponível (feature 016) MUST descer quando as duas faixas aparecem juntas.

## Fora de escopo

Reconexão do passageiro; mudança de intervalos automáticos; fila de reenvio de eventos publicados offline.

## Critérios de sucesso

- **SC-001** Com a rede de volta, um toque em "Reconectar" leva todos os relays a "conectado" sem esperar o
  próximo ciclo de 15 s.
- **SC-002** Testes automatizados: `reconnectNow` (5), botão da aba Relays (3), faixa do mapa (2); suíte do
  motorista passa (454) e `flutter analyze` sem avisos.
