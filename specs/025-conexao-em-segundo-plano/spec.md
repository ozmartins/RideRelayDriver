# Especificação: Conexão com os relays em segundo plano e notificação de solicitação (motorista)

**Feature**: `025-conexao-em-segundo-plano` · **App**: `driver/` · **Data**: 2026-10-11 · **Status**: Draft
**Contrato de eventos**: não muda (nenhum kind, tag ou formato novo). Sem contrapartida no passageiro.
**Entrada**: "o app do motorista precisa manter a conexão com o relay mesmo se o usuário fechar o app, para
gerar uma notificação push caso uma solicitação de corrida chegue e o app não esteja em primeiro plano ou
esteja efetivamente fechado".

## Clarificações

### Sessão 2026-10-11
- Q: Ao reabrir o app com o serviço ainda ativo, qual o estado do motorista? → A: retoma **online** (se houver
  posição válida; sem ela vai a offline e o serviço para). A regra "sempre offline ao abrir" da 004 vale só
  quando não há serviço ativo.
- Q: Por quanto tempo uma solicitação recebida com o app fechado continua válida? → A: **5 minutos**.

## Problema

Hoje a conexão com os relays vive dentro do app. Com o app em segundo plano ou fechado o Android suspende ou
encerra o processo, o WebSocket morre e a solicitação de corrida (`kind: 20001`, evento efêmero — o relay não o
guarda) se perde para sempre: o motorista que está "online" deixa de receber corridas sem saber. Um app de corridas
só é usável se o motorista puder deixar o celular no bolso e ser avisado. O desenho do protótipo não tem backend
nem serviço de push de terceiros (Princípio IV/V, tese do TCC), logo o aviso tem de ser gerado no próprio aparelho.

## Cenários de usuário

### US1 — Ser avisado de uma solicitação com o app fechado (P1)
O motorista fica online, sai do app (ou o remove da lista de recentes) e guarda o celular. Um passageiro
solicita uma corrida; o aparelho mostra uma notificação de alta importância; ao tocar nela o app abre e a
solicitação aparece na modal de sempre.

**Teste independente**: com o motorista online e o app removido dos recentes, publicar um `kind: 20001` válido
por outro cliente e observar a notificação e a modal ao tocá-la.

1. **Dado** motorista online, "Aguardando solicitação de corrida", app fora de primeiro plano, **quando** chega
   uma solicitação válida com forma de pagamento aceita, **então** uma notificação é exibida.
2. **Dado** a notificação exibida, **quando** o motorista a toca, **então** o app abre e a modal da solicitação
   é apresentada (a solicitação não se perde por ter chegado com o app fechado).
3. **Dado** o app em primeiro plano, **quando** chega a solicitação, **então** só a modal abre (sem notificação).

### US2 — Saber que o app está ouvindo, e poder parar (P1)
Enquanto online, uma notificação fixa "Você está online" mostra que o app mantém conexão em segundo plano. Ficar
offline e sair do app interrompe a conexão em segundo plano e todo aviso.

1. **Dado** o motorista que fica online, **então** a notificação fixa aparece e a conexão em segundo plano começa.
2. **Dado** o motorista que fica offline e sai do app, **então** a notificação fixa some, o serviço encerra e nada
   mais é notificado nem mantido.

### US3 — Conexão sobrevive a quedas de rede em segundo plano (P2)
Com o app fechado, a reconexão automática (retentativa a cada 15 s, sonda de vivacidade a cada 30 s) e o reenvio
da inscrição continuam funcionando; trocar Wi-Fi por dados móveis não deixa o motorista surdo.

## Casos de borda

- Solicitação sem forma de pagamento aceita, com `content` malformado, com assinatura inválida, duplicada (mesmo
  `id` vindo de três relays) ou fora de "Aguardando solicitação de corrida": **nenhuma notificação**, como hoje
  não há modal.
- Motorista offline: nada é notificado; sem o app aberto, não há conexão em segundo plano.
- Várias solicitações com o app fechado: uma notificação por solicitação; ao abrir, as ainda pendentes entram na
  fila sequencial existente (nunca duas modais ao mesmo tempo).
- Solicitação que chegou com o app fechado há mais de 5 minutos ao abrir: não entra na fila.
- Permissão de notificação negada: o motorista é avisado ao ficar online de que não será avisado com o app fechado;
  o serviço roda só com o app visível (a interface não tem outra conexão) e encerra ao sair dele, mesmo online
  (sem aviso possível, manter a conexão com o app fechado seria só gasto de bateria).
- Processo morto pelo sistema ou "Forçar parada": o serviço para; ao reabrir, o app abre offline (regra da 004).
- Corrida em andamento com o app fechado: **fora de escopo** — a publicação de localização (`20005`) e dos avisos
  de chegada (`20007`, `20009`) continua dependendo do app aberto; eventos cifrados (`20003`, `20008`, `20010`,
  `20013`) que chegarem ao serviço sem a interface aberta não são notificados nem guardados.

## Requisitos

- **FR-001** O serviço em segundo plano MUST rodar enquanto o app está em primeiro plano **ou** o motorista está
  online, e MUST encerrar quando o app sai de primeiro plano com o motorista offline. Enquanto online, a
  notificação fixa MUST dizer "Você está online"; com o app aberto e o motorista offline, o serviço segue
  (a interface não tem outra conexão) com notificação discreta de baixa importância. Sem a permissão de
  notificação, o serviço não sobrevive à saída do app (ver casos de borda).
- **FR-002** A conexão MUST permanecer ativa com o app em segundo plano e depois de removido da lista de recentes,
  mantendo a reconexão automática, a sonda de vivacidade e o reenvio da inscrição a cada conexão (FR-006 da 024).
- **FR-003** Exista uma única conexão por relay, mantida pelo serviço; a interface do app a usa como cliente
  (receber eventos, estado dos relays, publicar, adicionar/remover relay, reconectar). Nada que o app já faz com
  os relays pode regredir.
- **FR-004** A verificação de assinatura (com recálculo do `id`), do marcador e a deduplicação MUST ocorrer antes de
  qualquer outro processamento, também no serviço (regras 1/2/6 do contrato).
- **FR-005** Uma solicitação (`kind: 20001`) MUST gerar notificação se, e somente se, o app está fora de primeiro
  plano **e** as mesmas condições que hoje abrem a modal valem: motorista online, "Aguardando solicitação de
  corrida", `content` válido, forma de pagamento aceita pelo cadastro. A decisão MUST ser uma única regra
  compartilhada entre serviço e interface.
- **FR-006** A notificação MUST ter importância alta (som/aviso visual), MUST NOT conter endereços, coordenadas
  nem nome do passageiro (texto genérico "Nova solicitação de corrida"), e MUST abrir o app ao ser tocada.
- **FR-007** Solicitações recebidas pelo serviço com o app fechado MUST ser entregues à interface quando ela
  abrir, por até 5 minutos desde o recebimento; fora desse prazo são descartadas.
- **FR-012** Ao abrir com o serviço ainda ativo, o app MUST retomar o estado online (se a posição for válida;
  senão ficar offline e encerrar o serviço); sem serviço ativo, abre offline como na 004.
- **FR-008** Eventos publicados pelo app (assinados e cifrados na interface) MUST ser repassados ao serviço para
  envio; a chave privada MUST NOT atravessar o canal entre interface e serviço nem ser necessária no serviço.
- **FR-009** O app MUST pedir a permissão de notificação apenas ao ficar online pela primeira vez, nunca ao abrir.
- **FR-010** O serviço MUST informar à interface o estado dos relays para que a faixa "Sem conexão com os relays."
  e a aba "Relays" continuem corretas.
- **FR-011** O estado necessário ao serviço (online, formas de pagamento aceitas, estado da corrida, app em
  primeiro plano) MUST ser comunicado a ele pela interface e persistido o bastante para sobreviver a um reinício
  do processo do serviço.

## Fora de escopo

FCM/Firebase/UnifiedPush ou qualquer servidor; publicar `20005`/`20007`/`20009` com o app fechado; notificar
`20003`/`20013` com o app fechado; iniciar o serviço no boot do aparelho; contornar otimização de bateria de
fabricantes; qualquer mudança no passageiro ou no contrato.

## Critérios de sucesso

- **SC-001** Com o motorista online e o app removido dos recentes, uma solicitação válida gera notificação em até
  10 s depois de publicada, com os três relays padrão ativos (medido em aparelho; registrar a distribuição de 10
  tentativas).
- **SC-002** 0 notificações para solicitações que hoje não abrem modal (offline, pagamento recusado, malformada,
  assinatura inválida, duplicada, em corrida).
- **SC-003** A notificação nunca contém endereço, coordenada nem nome do passageiro (verificável por teste).
- **SC-004** Com a tela apagada por 10 min e uma troca de rede no meio, o motorista continua recebendo.
- **SC-005** Nenhum teste existente regride; a suíte do motorista passa e `flutter analyze` não tem avisos.
- **SC-006** Medir e registrar o consumo de bateria por hora online com a tela apagada (dado para o TCC).

## Suposições

- Android apenas; versões com serviço em primeiro plano tipado (14+) e permissão de notificação em tempo de
  execução (13+) são tratadas.
- O motorista aceita a notificação fixa enquanto online como custo da conexão contínua.
- Sem serviço ativo o app abre offline (004); a conexão em segundo plano não se retoma sozinha após morte do
  processo nem no boot do aparelho.
- Constituição: exige emenda **2.14.0** nas duas apps (execução em segundo plano e notificação), commitada antes
  do código, e dependências novas registradas no `research.md` (Princípio III).
- Risco registrado: fabricantes com economia de bateria agressiva podem matar o serviço; é limitação, não defeito.
