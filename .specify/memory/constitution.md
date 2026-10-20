<!--
SYNC IMPACT REPORT

--- Emenda 2.16.0 (2026-10-13) ---
Version change: 2.15.0 → 2.16.0
Bump rationale: MINOR. A exceção de geocodificação às Restrições de Segurança e Privacidade proibia persistir o
  texto de busca e a resposta do serviço além da sessão; passa a admitir guardar, só no aparelho, o endereço de
  destino que o próprio usuário selecionou. Nenhum Princípio foi alterado; nenhuma obrigação foi removida.
Motivador: pedido do autor — o destino do passageiro precisa sobreviver a um reinício do app (o botão de confirmar a
  chegada ao destino depende dele, e hoje sumia ao reabrir o app em "Em corrida"). Condições: texto exibido e
  coordenadas do destino selecionado, nada mais; só no aparelho (nunca enviado a relay nem a terceiros além do já
  previsto); apagado quando o usuário limpa o campo de destino. O texto de busca digitado e as sugestões continuam
  sem persistir.
Custo aceito: o último destino escolhido fica gravado em claro no armazenamento local do aparelho (dado de
  baixo volume, não é segredo criptográfico).
Emendada em conjunto com a constituição espelho, na mesma alteração e com texto idêntico salvo nome, escopo
  e perspectiva. A constituição de `Prototipo/` não repete esta seção e não precisa de emenda.

Princípios modificados: nenhum. Seções adicionadas/removidas: nenhuma.
Seções modificadas: Restrições de Segurança e Privacidade — exceção de geocodificação.

Propagação:
  ✅ Constituição espelho — emendada na mesma alteração; corpos conferidos por diff.
  ◻ Prototipo/.specify/memory/constitution.md — não contém esta seção; sem alteração necessária.
  ⚠ Código do passageiro e `CLAUDE.md`, em commits separados (posteriores).

--- Emenda 2.15.0 (2026-10-12) ---
Version change: 2.14.0 → 2.15.0
Bump rationale: MINOR. A exceção às Restrições de Segurança e Privacidade criada na 2.14.0 para o app do
  motorista passa a valer também para o app do passageiro, com condições próprias. Nenhum Princípio foi
  alterado; nenhuma obrigação anterior foi removida.
Motivador: pedido do autor — o app do passageiro precisa manter a conexão com o relay mesmo fechado, para
  notificar a chegada de uma mensagem do motorista (orçamento, chegada, cancelamento), que são eventos
  efêmeros que o relay não guarda. Diferente do motorista, essas mensagens chegam cifradas (NIP-44) e o
  serviço não pode ter a chave privada; por isso a decisão de notificar usa só dados públicos do evento
  (kind, autor, tags `p` e `e`). Descartados: FCM/UnifiedPush/servidor próprio (intermediário, contra a tese)
  e levar a chave ao serviço para decifrar (viola o Princípio I). Feature `026-conexao-em-segundo-plano` do
  passageiro; as dependências `flutter_foreground_task` e `flutter_local_notifications` já foram decididas na
  025 do motorista e são registradas no `research.md` da 026 (Princípio III).
Custo aceito: notificação permanente enquanto há solicitação ou corrida ativa, consumo de bateria, possibilidade
  de o sistema ou o fabricante encerrar o serviço, e de uma notificação ser disparada por conteúdo ilegível
  ou forjado por quem tem a chave de assinatura do motorista da corrida (a interface o descarta ao abrir).
Emendada em conjunto com a constituição espelho, na mesma alteração e com texto idêntico salvo nome, escopo
  e perspectiva. A constituição de `Prototipo/` não repete esta seção e não precisa de emenda.

Princípios modificados: nenhum. Seções adicionadas/removidas: nenhuma.
Seções modificadas: Restrições de Segurança e Privacidade — exceção de execução em segundo plano.

Propagação:
  ✅ Constituição espelho — emendada na mesma alteração; corpos conferidos por diff.
  ◻ Prototipo/.specify/memory/constitution.md — não contém esta seção; sem alteração necessária.
  ⚠ Código do passageiro (feature 026) e `CLAUDE.md`, em commits separados (posteriores).

--- Emenda 2.14.0 (2026-10-11) ---
Version change: 2.13.0 → 2.14.0
Bump rationale: MINOR. Nova exceção às Restrições de Segurança e Privacidade: o app do motorista passa a
  poder manter um serviço em primeiro plano do Android que hospeda a conexão com os relays e mostra
  notificações locais, para receber solicitações de corrida com o app fora de primeiro plano ou fechado.
  Nenhum Princípio foi alterado; nenhuma obrigação anterior foi removida.
Motivador: pedido do autor — o app do motorista precisa manter a conexão com o relay mesmo fechado, para
  notificar a chegada de uma solicitação (`kind: 20001`, evento efêmero que o relay não guarda). Sem isso o
  motorista "online" perde corridas sem saber. Descartados: FCM/Firebase e UnifiedPush/servidor próprio
  (reintroduzem um intermediário, contra a tese do TCC) e tarefa periódica do WorkManager (intervalo mínimo
  de 15 min, sem conexão contínua). Feature `025-conexao-em-segundo-plano` do motorista; dependências
  `flutter_foreground_task` e `flutter_local_notifications` (Princípio III, `research.md` da feature).
Custo aceito: notificação permanente enquanto o serviço roda, consumo de bateria e possibilidade de o sistema
  ou o fabricante encerrar o serviço; o serviço não substitui o app aberto durante uma corrida.
Emendada em conjunto com a constituição espelho (`Prototipo/passenger`), na mesma alteração e com texto
  idêntico — o passageiro não usa o serviço, mas o texto é espelho. A constituição de `Prototipo/` não
  repete esta seção e não precisa de emenda.

Princípios modificados: nenhum. Seções adicionadas/removidas: nenhuma.
Seções modificadas: Restrições de Segurança e Privacidade — exceção de execução em segundo plano.

Propagação:
  ✅ Constituição espelho (`Prototipo/passenger`) — emendada na mesma alteração; corpos conferidos por diff.
  ◻ Prototipo/.specify/memory/constitution.md — não contém esta seção; sem alteração necessária.
  ⚠ Código do motorista (feature 025) e `CLAUDE.md`, em commits separados (posteriores).

--- Emenda 2.13.0 (2026-10-08) ---
Version change: 2.12.0 → 2.13.0
Bump rationale: MINOR. Nova exceção às Restrições de Segurança e Privacidade: os tiles do mapa passam a
  ser pedidos a um serviço de tiles vetoriais de terceiros (OpenFreeMap), no lugar dos tiles raster
  do OpenStreetMap. Nenhum Princípio foi alterado; nenhuma obrigação anterior foi removida.
Motivador: pedido do autor de melhorar a aparência do mapa. Descartados com evidência: tiles raster do
  Carto (`basemaps.cartocdn.com` devolve tile "API KEY REQUIRED" sem chave, verificado em 2026-10-08) e
  Google Maps (exige chave e faturamento). O OpenFreeMap não exige chave nem cadastro (confirmado em
  openfreemap.org, 2026-10-08). Nova dependência: `vector_map_tiles` (Princípio III; decisão de
  dependência no `research.md` da feature de cada app).
Custo aceito: quem serve os tiles (e a Cloudflare, que opera a CDN) vê o IP do aparelho e as
  coordenadas z/x/y pedidas, que revelam a região consultada — dado que o OpenStreetMap já via. Sem SLA;
  o serviço pode ser descontinuado sem aviso. Sem provedor de reserva: sem estilo, o mapa fica só com o
  fundo `mapa-base`.
Emendada em conjunto com a constituição espelho (`Prototipo/passenger`), na mesma alteração e com texto
  idêntico. A constituição de `Prototipo/` não repete esta seção e não precisa de emenda.

Princípios modificados: nenhum. Seções adicionadas/removidas: nenhuma.
Seções modificadas: Restrições de Segurança e Privacidade — exceção de tiles de mapa.

Propagação:
  ✅ Constituição espelho (`Prototipo/passenger`) — emendada na mesma alteração; corpos conferidos por diff.
  ⚠ Código das duas apps (`CamadaMapaBase`) e `CLAUDE.md`, em commits separados (posteriores).

--- Emenda 2.12.0 (2026-10-07) ---
Version change: 2.11.0 → 2.12.0
Bump rationale: MINOR. O componente "Botão de ação destrutiva" da seção "Identidade Visual e Design"
  (introduzido na 2.10.0, fundo `ColorScheme.error`) é substituído por "Botão de cancelamento de
  corrida", com a aparência da ação primária (fundo `roxo`, ícone e texto brancos). Nenhum Princípio
  foi alterado; a regra de que cor de erro vem do `ColorScheme.error` continua valendo para erros.
Motivador: pedido do autor de unificar os botões que cancelam uma corrida em roxo, o que substitui o
  componente em vermelho que ele próprio havia aprovado na 2.10.0 (features 022 do motorista e a
  equivalente do passageiro). Razão de contraste do branco sobre `roxo`: cerca de 6:1, acima dos 4,5:1
  exigidos para texto.
Emendada em conjunto com a constituição espelho, na mesma alteração e com texto idêntico.

Princípios modificados: nenhum. Seções adicionadas/removidas: nenhuma.
Seções modificadas: Identidade Visual e Design — Componentes (botão de ação destrutiva).

Propagação:
  ✅ Constituição espelho — emendada na mesma alteração; corpos conferidos por diff.
  ◻ Prototipo/.specify/memory/constitution.md — não contém esta seção; sem alteração necessária.
  ⚠ Código do motorista (feature 022) e do passageiro (feature própria), em commits separados
     (posteriores).

--- Emenda 2.11.0 (2026-10-06) ---
Version change: 2.10.0 → 2.11.0
Bump rationale: MINOR. Ampliação material das Restrições de Segurança e Privacidade: a regra
  anterior só exigia justificativa escrita para dado pessoal trafegando sem cifra; passa a exigir que
  toda mensagem de domínio com destinatário conhecido seja cifrada ao destinatário (NIP-44) e
  assinada, com o `kind: 20001` (Solicitação de corrida — anúncio sem destinatário) como única
  exceção registrada. Nenhuma obrigação anterior foi removida.
Motivador: pedido de que toda mensagem enviada de um app ao outro seja criptografada e assinada com
  o par de chaves assimétricas (features 019 do motorista e 022 do passageiro; contrato, emenda 17).
Emendada em conjunto com a constituição espelho (`Prototipo/passenger`), na mesma alteração e com
  texto idêntico. A constituição de `Prototipo/` não repete esta seção e não precisa de emenda.

Princípios modificados: nenhum. Seções adicionadas/removidas: nenhuma.
Seções modificadas: Restrições de Segurança e Privacidade — nova regra de cifragem entre pares.

Propagação:
  ✅ Constituição espelho (`Prototipo/passenger`) — emendada na mesma alteração; corpos conferidos por
     diff.
  ✅ .specify/templates/ — nenhum template cita a regra anterior; sem alteração necessária.
  ✅ Specs anteriores que declaram "sem criptografia" (`specs/006-solicitar-corrida`,
     `007`, `010`, `011`, `012`, `017`, `018` e o contrato) — são registros históricos das decisões da
     época; a mudança é registrada no contrato (emenda 17), não reescrevendo-as.
  ⚠ Código das duas apps, em commits separados (posteriores): feature 019 do motorista e 022 do
     passageiro.

--- Emenda 2.10.0 (2026-10-06) ---
Version change: 2.9.0 → 2.10.0
Bump rationale: MINOR. A seção "Identidade Visual e Design" ganha dois componentes — o bloco
  "corrida em andamento" dentro do cartão de status do mapa e o botão de ação destrutiva —,
  medidos no mockup do cancelamento de corrida (Screenshot From 2026-10-06 21-24-08.png). O
  componente anterior para o cancelamento (faixa de estado em alerta, sobre o mapa) deixa de ser o
  usado nesse caso. Só usa tokens já existentes; nenhuma obrigação anterior foi alterada.
Motivador: pedido de mover o "Cancelar corrida" do motorista para dentro do cartão de status, como
  botão vermelho cheio; a própria seção exige registrar aqui todo componente novo antes de usá-lo.
Emendada em conjunto com a constituição espelho, na mesma alteração e com texto idêntico.

Princípios modificados: nenhum. Seções adicionadas/removidas: nenhuma.
Seções modificadas: Identidade Visual e Design — Componentes.

Propagação:
  ✅ Constituição espelho — emendada na mesma alteração; corpos conferidos por diff.
  ⚠ Código do motorista: cartão de status e botão "Cancelar corrida", em commit separado (posterior).

--- Emenda 2.9.0 (2026-09-26) ---
Version change: 2.8.0 → 2.9.0
Bump rationale: MINOR. Nova exceção às Restrições de Segurança e Privacidade: geocodificação
  reversa de uma coordenada de origem ou destino de solicitação recebida, para exibi-la como
  endereço legível. A exceção de geocodificação só cobria texto digitado pelo próprio usuário e a
  de roteamento só cobria o cálculo de distância e trajeto; nenhuma das duas autoriza enviar uma
  coordenada isolada de terceiro a um geocodificador. Nenhuma proibição anterior foi afrouxada.
Motivador: pedido de que a modal de solicitação de corrida do motorista exiba endereços legíveis
  em vez de latitude e longitude (feature 015 do motorista).
Emendada em conjunto com a constituição espelho, na mesma alteração e com texto idêntico.

Princípios modificados: nenhum. Seções adicionadas/removidas: nenhuma.
Seções modificadas: Restrições de Segurança e Privacidade — nova exceção de geocodificação reversa.

Propagação:
  ✅ Constituição espelho — emendada na mesma alteração; corpos conferidos por diff.
  ◻ Prototipo/.specify/memory/constitution.md — não contém esta seção; sem alteração necessária.
  ⚠ Código e feature 015 do motorista, em commits separados (posteriores).

--- Emenda 2.8.0 (2026-09-24) ---
Version change: 2.7.0 → 2.8.0
Bump rationale: MINOR. A seção "Identidade Visual e Design" ganha componentes usados pelo app do
  passageiro e ainda não previstos: ações no cabeçalho e botão de voltar, painel de ação sobre o
  mapa, seleção segmentada, faixa de estado, marcador do passageiro, rota e botão flutuante
  estendido. Só usa tokens já existentes; nenhuma obrigação anterior foi alterada.
Motivador: pedido de aplicar a identidade às telas do passageiro; a própria seção exige registrar
  aqui todo componente novo antes de usá-lo no código.
Emendada em conjunto com a constituição espelho, na mesma alteração e com texto idêntico.

Princípios modificados: nenhum. Seções adicionadas/removidas: nenhuma.
Seções modificadas: Identidade Visual e Design — Componentes.

Propagação:
  ✅ Constituição espelho — emendada na mesma alteração; corpos conferidos por diff.
  ⚠ Código do passageiro: todas as telas e modais, em commit separado (posterior).
  ⚠ Fonte DM Sans ainda não empacotada (mantido).

--- Emenda 2.7.0 (2026-09-24) ---
Version change: 2.6.0 → 2.7.0
Bump rationale: MINOR. A seção "Identidade Visual e Design" ganha componentes para telas de conteúdo
  sem etapas (lista de relays, identidade), cartões de lista e modais, para permitir migrar as telas
  que ainda usavam o visual padrão do Material. Só usa tokens já existentes; nenhuma obrigação
  anterior foi alterada.
Motivador: pedido de aplicar a identidade às telas restantes do motorista; a própria seção exige
  registrar aqui todo componente novo antes de usá-lo no código.
Emendada em conjunto com a constituição espelho, na mesma alteração e com texto idêntico.

Princípios modificados: nenhum. Seções adicionadas/removidas: nenhuma.
Seções modificadas: Identidade Visual e Design — Componentes.

Propagação:
  ✅ Constituição espelho — emendada na mesma alteração; corpos conferidos por diff.
  ⚠ Código do motorista: telas Relays e Identidade, modais de solicitação, aceitação e avaliação,
     aviso de indisponibilidade do mapa — em commit separado (posterior). Tokens extraídos para um
     arquivo único, como a seção já exige.
  ⚠ Passageiro: nenhuma tela segue a identidade ainda (mantido das emendas anteriores).

--- Emenda 2.6.0 (2026-09-24) ---
Version change: 2.5.1 → 2.6.0
Bump rationale: MINOR. A seção "Identidade Visual e Design" ganha tokens e componentes para telas
  de mapa e para a navegação inferior (`fundo-profundo`, `mapa-*`, barra de navegação, cartão de
  status, marcador de posição, botão de centralizar), medidos no mockup da tela principal do
  motorista (Screenshot From 2026-09-24 22-56-12.png). Nenhuma obrigação anterior foi alterada.
Motivador: a tela do mapa do motorista usa cores e componentes que a 2.5.1 não previa, e a própria
  seção exige registrar aqui qualquer valor novo antes de usá-lo no código.
Emendada em conjunto com a constituição espelho, na mesma alteração e com texto idêntico.

Princípios modificados: nenhum. Seções adicionadas/removidas: nenhuma.
Seções modificadas: Identidade Visual e Design — tabela de paleta (novas linhas) e Componentes.

Propagação:
  ✅ Constituição espelho — emendada na mesma alteração; corpos conferidos por diff.
  ⚠ Código: tela do mapa e barra de navegação do motorista, em commit separado (posterior).
  ⚠ Os tiles do mapa vêm do OpenStreetMap padrão; a paleta `mapa-*` é aproximada por filtro de
     cor, não por estilo de tiles próprio (exigiria serviço de terceiros; Restrições de Privacidade).
  ⚠ Fonte DM Sans ainda não empacotada (mantido).

--- Emenda 2.5.1 (2026-09-24) ---
Version change: 2.5.0 → 2.5.1
Bump rationale: PATCH. Os valores da paleta da 2.5.0 foram estimados a olho; esta emenda os
  substitui pelos medidos, pixel a pixel, no próprio arquivo do mockup de referência
  (Screenshot From 2026-09-24 22-20-59.png), e separa `texto-suave` (legível, ≥ 4,5:1) de
  `desabilitado` (esmaecido). Nenhuma obrigação nova; só valores de token e a regra de contraste.
Emendada em conjunto com a constituição espelho, na mesma alteração e com texto idêntico.

Princípios modificados: nenhum. Seções adicionadas/removidas: nenhuma.
Seções modificadas: Identidade Visual e Design — tabela de paleta e parágrafo de contraste.

Propagação:
  ✅ Constituição espelho — emendada na mesma alteração; corpos conferidos por diff.
  ✅ Código: `lib/screens/cadastro_screen.dart` (motorista) atualizado para os valores desta emenda,
     em commit separado; a divergência de contraste anotada na 2.5.0 fica resolvida.
  ⚠ Fonte DM Sans ainda não empacotada (mantido da 2.5.0).

--- Emenda 2.5.0 (2026-09-24) ---
Version change: 2.4.0 → 2.5.0
Bump rationale: MINOR. Nova seção "Identidade Visual e Design" (paleta, tipografia, forma,
  espaçamento e componentes), mais um item no gate de conclusão de feature. Nenhum Princípio foi
  removido ou redefinido; nenhuma obrigação anterior foi afrouxada.
Motivador: redesenho da etapa 1 do cadastro do motorista a partir de um mockup fornecido pelo autor
  (feature 009 do motorista). Sem regra escrita, cada tela nova reinterpretaria o mockup.
Emendada em conjunto com a constituição espelho, na mesma alteração e com texto idêntico. A
  constituição de `Prototipo/` não repete esta seção e não precisa de emenda.

Princípios modificados: nenhum.
Seções modificadas: Fluxo de Desenvolvimento e Gates — novo item 6 (telas novas ou redesenhadas
  seguem a identidade visual).
Seções adicionadas: Identidade Visual e Design. Seções removidas: nenhuma.

Propagação:
  ✅ Constituição espelho — emendada na mesma alteração; corpos conferidos por diff.
  ✅ .specify/templates/* — nenhuma seção obrigatória de spec/plan/tasks muda; nada a alterar.
  ⚠ Código: `lib/screens/cadastro_screen.dart` (motorista) define os tokens como constantes
     locais e usa `#8A80A8` também no texto de ajuda, o que esta seção restringe a placeholder e
     estado desabilitado (contraste 4,5:1). Ajustar quando a tela for tocada de novo.
  ⚠ Fonte DM Sans ainda não empacotada; a tela usa a fonte padrão do Material até haver decisão de
     asset no `research.md` (Princípio III).
  ⚠ Passageiro: nenhuma tela segue a identidade ainda; migram quando tocadas.

Follow-ups pendentes:
  ⚠ Pela Governance, esta emenda MUST ser commitada separadamente das mudanças de código.

--- Emenda 2.4.0 (2026-09-20) ---
Version change: 2.3.0 → 2.4.0
Bump rationale: MINOR. A exceção de roteamento aberta pela emenda 2.3.0 só cobria, ao pé da letra, o
  par "posição atual do usuário + destino escolhido por ele". A feature 007 do motorista (modal de
  solicitação de corrida recebida) precisa enviar também o par origem→destino de uma solicitação
  recebida de outro usuário — nenhum dos dois pontos é a posição do próprio motorista. Esta emenda
  generaliza a exceção para "duas coordenadas relevantes para uma decisão do usuário", cobrindo os
  dois casos sob as mesmas condições (HTTPS, sem identificador, sem persistência). Nenhum Princípio
  foi removido ou redefinido de forma incompatível — ampliação de escopo, não afrouxamento da
  proibição padrão.
Motivador: `/speckit-plan` da feature 007 do motorista encontrou a lacuna de redação durante o
  Constitution Check, antes de qualquer código ser escrito — o mesmo gate que motivou a 2.2.0 e a
  2.3.0.
Emendada em conjunto com a constituição espelho (`Prototipo/passenger`), na mesma alteração e com
  texto idêntico.

Princípios modificados: nenhum.
Seções modificadas:
  Restrições de Segurança e Privacidade — generaliza a exceção de roteamento da 2.3.0, sem alterar
  suas condições (HTTPS, sem identificador, sem persistência, decisão registrada no research.md).
Seções adicionadas: nenhuma. Seções removidas: nenhuma.

Propagação:
  ✅ Constituição espelho (`Prototipo/passenger`) — emendada na mesma alteração; corpos conferidos
     por diff.
  ◻ `Prototipo/.specify/memory/constitution.md` — não contém esta seção; sem alteração necessária.
  ✅ specs/007-receber-solicitacao-corrida/plan.md (motorista) — Constitution Check avaliado já
     contra esta versão.

Follow-ups pendentes:
  ⚠ Pela Governance, esta emenda MUST ser commitada separadamente das mudanças de código.

--- Emenda 2.3.0 (2026-09-20) ---
Version change: 2.2.0 → 2.3.0
Bump rationale: MINOR. A seção "Restrições de Segurança e Privacidade" ganha uma segunda exceção
  estreita e explícita à proibição de enviar dado de usuário a serviço que não seja relay Nostr
  configurado, para permitir a chamada a um serviço de roteamento de terceiros (OpenRouteService).
  Nenhum Princípio (I a V) foi removido ou redefinido de forma incompatível; a regra padrão continua
  proibindo o resto — é ampliação material de escopo, delimitada por condições, mesmo padrão da
  emenda 2.2.0 que abriu a exceção do Photon.
Motivador: `/speckit-plan` da feature 007-rota-ate-destino do passageiro (cálculo de distância real
  de rota e traçado no mapa) encontrou a proibição vigente durante o Constitution Check, antes de
  qualquer código ser escrito — exatamente o gate que a Governance prevê para isso. O motorista não
  implementa esta feature ainda, mas a Restrições de Segurança e Privacidade é espelhada nas duas
  apps e MUST ser emendada junto, por construção (Governance / Escopo). Diferente da exceção do
  Photon, o cálculo de rota exige enviar a posição atual do usuário (origem) além do destino, o que a
  exceção existente proibia explicitamente; por isso não bastava reenquadrar o uso na 2.2.0.
Emendada em conjunto com a constituição espelho (`Prototipo/passenger`), na mesma alteração e com
  texto idêntico. A constituição de `Prototipo/` não repete esta seção (só compartilha Padrão de
  Commits) e por isso não precisa de emenda.

Princípios modificados: nenhum.
Seções modificadas:
  Restrições de Segurança e Privacidade — acrescenta a exceção de roteamento, com condições (HTTPS,
  sem identificador de usuário além das coordenadas de origem/destino, sem persistência além da
  sessão, decisão registrada no research.md conforme o Princípio III).
Seções adicionadas: nenhuma. Seções removidas: nenhuma.

Propagação:
  ✅ Constituição espelho (`Prototipo/passenger`) — emendada na mesma alteração; corpos conferidos
     por diff.
  ◻ `Prototipo/.specify/memory/constitution.md` — não contém esta seção; sem alteração necessária.
  ✅ .specify/templates/*.md — nenhum menciona a lista de serviços permitidos; sem alteração.
  ◻ Nenhuma feature do motorista usa esta exceção até o momento; nada a reavaliar neste diretório.

Follow-ups pendentes:
  ⚠ Pela Governance, esta emenda MUST ser commitada separadamente das mudanças de código.

--- Emenda 2.2.0 (2026-09-17) ---
Version change: 2.1.0 → 2.2.0
Bump rationale: MINOR. A seção "Restrições de Segurança e Privacidade" ganha uma exceção estreita e
  explícita à proibição de enviar dado de usuário a serviço que não seja relay Nostr configurado,
  para permitir a chamada a um serviço de geocodificação de terceiros (Photon). Nenhum Princípio (I a
  V) foi removido ou redefinido de forma incompatível; a regra padrão continua proibindo o resto —
  é ampliação material de escopo, delimitada por condições, não afrouxamento geral.
Motivador: `/speckit-plan` da feature 005-busca-endereco-photon do passageiro (busca de endereço com
  sugestões da API Photon) encontrou a proibição vigente durante o Constitution Check, antes de
  qualquer código ser escrito — exatamente o gate que a Governance prevê para isso. O motorista não
  implementa esta feature, mas a Restrições de Segurança e Privacidade é espelhada nas duas apps e
  MUST ser emendada junto, por construção (Governance / Escopo).
Emendada em conjunto com a constituição espelho (`Prototipo/passenger`), na mesma alteração e com
  texto idêntico. A constituição de `Prototipo/` não repete esta seção (só compartilha Padrão de
  Commits) e por isso não precisa de emenda.

Princípios modificados: nenhum.
Seções modificadas:
  Restrições de Segurança e Privacidade — acrescenta a exceção de geocodificação, com condições
  (HTTPS, sem identificador de usuário, sem persistência além da sessão, decisão registrada no
  research.md conforme o Princípio III).
Seções adicionadas: nenhuma. Seções removidas: nenhuma.

Propagação:
  ✅ Constituição espelho (`Prototipo/passenger`) — emendada na mesma alteração; corpos conferidos
     por diff.
  ◻ `Prototipo/.specify/memory/constitution.md` — não contém esta seção; sem alteração necessária.
  ✅ .specify/templates/*.md — nenhum menciona a lista de serviços permitidos; sem alteração.
  ◻ Nenhuma feature do motorista usa esta exceção até o momento; nada a reavaliar neste diretório.

Follow-ups pendentes:
  ⚠ Pela Governance, esta emenda MUST ser commitada separadamente das mudanças de código.

--- Emenda 2.1.0 (2026-09-16) ---
Version change: 2.0.0 → 2.1.0
Bump rationale: MINOR. Nova seção "Padrão de Commits", que torna obrigatório o padrão extraído dos
  commits do repositório desde 2026-09-15. O gate 5 do Fluxo de Desenvolvimento, que já exigia
  commit em português descrevendo o comportamento, passa a remeter à seção — ampliação material da
  mesma obrigação, sem revogar nada. Nenhum princípio foi removido ou redefinido.
Emendada em conjunto com a constituição espelho e com a constituição de Prototipo/ (1.0.0), na
  mesma alteração; a seção Padrão de Commits tem texto idêntico nas três.

Princípios modificados: nenhum.
Seções adicionadas: Padrão de Commits.
Seções modificadas:
  Fluxo de Desenvolvimento e Gates — gate 5 remete ao Padrão de Commits.
  Governance / Escopo — registra que o Padrão de Commits é compartilhado com Prototipo/.
Seções removidas: nenhuma.

Propagação:
  ✅ Constituição espelho — emendada na mesma alteração; corpos conferidos por diff.
  ✅ Prototipo/.specify/memory/constitution.md — ratificada 1.0.0 com a mesma seção.
  ✅ .specify/templates/tasks-template.md — "Commit after each task or logical group" passa a
     remeter ao Padrão de Commits (uma mudança lógica por commit).
  ✅ .specify/templates/plan-template.md, spec-template.md, checklist-template.md — não tratam de
     commit; sem alteração.
  ✅ README.md da aplicação — não descreve commits; sem alteração.
  ◻ Commits anteriores a 2026-09-15 não são reescritos: histórico publicado não se altera.

Follow-ups pendentes:
  ⚠ Pela Governance, esta emenda MUST ser commitada separadamente das mudanças de código.

--- Emenda 2.0.0 (2026-09-16) ---
Version change: 1.1.0 → 2.0.0
Bump rationale: MAJOR. O Princípio IV volta a exigir replicação direta como única forma de cumprimento
  e passa a cobrir também a lista padrão de relays e o marcador do protótipo; a Governance deixa de
  admitir divergência entre as constituições como risco administrável. Trabalho que cumpria a versão
  anterior pode não cumprir esta — redefinição incompatível, logo MAJOR pela regra de versionamento.
  Motivador: a sessão dedicada ao motorista foi encerrada em 2026-09-16 e uma única sessão passou a
  manter as duas aplicações, eliminando o impedimento que justificara o afrouxamento da 1.1.0.
Emendada em conjunto com a constituição espelho, na mesma alteração e com texto idêntico.

Princípios modificados:
  IV. O contrato de evento vem antes do código
      - REVOGADO: a alternativa "relato explícito ao autor", introduzida na 1.1.0. Replicação direta volta a ser a única forma de cumprimento.
      - AMPLIADO: a obrigação de replicação passa a cobrir a lista padrão de relays e o marcador
        `tcc-ufsc-caronas`. Evidência: as listas padrão divergiram entre as apps durante a vigência
        da 1.1.0 (uma incluía relay.damus.io, a outra offchain.pub) — a divergência que o achado F1
        do /speckit-analyze do passageiro havia previsto.
      - Racional reescrito para registrar a exceção da 1.1.0, seu motivo, seu custo e sua revogação.
Princípios inalterados: I, II, III, V.

Seções modificadas:
  Governance / Escopo — as constituições são espelhos, MUST ter o mesmo texto salvo nome, escopo e
  perspectiva, e MUST ser emendadas juntas. Divergência é defeito, não risco.
Seções adicionadas: nenhuma. Seções removidas: nenhuma.

Propagação:
  ✅ Constituição espelho — emendada na mesma alteração; corpos conferidos por diff.
  ✅ .specify/templates/*.md — nenhum cita a forma de cumprimento do Princípio IV; sem alteração.
  ✅ Prototipo/passenger/specs/002-nostr-relay-connection/spec.md — premissa "não edita o diretório do
     motorista" recebeu nota datada de superação, sem reescrita.
  ◻ Mantidos como registro histórico, sem alteração: driver/specs/002-nostr-relay-connection/plan.md
     (avaliação sob v1.1.0) e driver/specs/002-nostr-relay-connection/tasks.md T034 (entrega por
     relato sob v1.1.0). Eram verdadeiros quando escritos; reescrevê-los apagaria a história.

Follow-ups pendentes:
  ⚠ Pela Governance, esta emenda MUST ser commitada separadamente das mudanças de código.

--- Emenda 1.1.0 (2026-09-15) ---
Version change: 1.0.0 → 1.1.0
Bump rationale: MINOR. O Princípio IV teve a forma de cumprimento materialmente ampliada (replicação
  direta OU relato ao autor); a obrigação em si não foi removida nem enfraquecida, e nenhum outro
  princípio mudou. Motivador: achado D1 de /speckit-analyze em 002-nostr-relay-connection — a redação
  original era inexequível no modo de trabalho com uma sessão de Claude Code por aplicação.
Propagação da emenda:
  ✅ specs/002-nostr-relay-connection/tasks.md — T033 reescrita como "preparar e relatar".
  ✅ specs/002-nostr-relay-connection/plan.md — linha do Princípio IV na tabela de avaliação.
  ✅ .specify/templates/*.md — nenhuma alteração necessária (não referenciam o Princípio IV).

--- Ratificação 1.0.0 (2026-09-15) ---
Version change: (template não preenchido) → 1.0.0
Bump rationale: primeira ratificação. Todos os princípios são novos, logo não há
  incompatibilidade com versão anterior; MAJOR inicial conforme versionamento semântico.

Princípios definidos (todos novos):
  I.   Segredo criptográfico não vaza (NÃO NEGOCIÁVEL)
  II.  Assinatura e verificação nascem com teste (NÃO NEGOCIÁVEL)
  III. Dependência de terceiros exige decisão registrada
  IV.  O contrato de evento vem antes do código
  V.   Simplicidade proporcional e rastreabilidade acadêmica

Seções adicionadas:
  - Restrições de Segurança e Privacidade
  - Fluxo de Desenvolvimento e Gates
  - Governance

Seções removidas: nenhuma (o arquivo era o template não preenchido).

Propagação em templates:
  ✅ .specify/templates/plan-template.md — a seção "Constitution Check" já delega os gates ao
     arquivo de constituição; nenhuma alteração necessária.
  ✅ .specify/templates/spec-template.md — nenhuma seção obrigatória foi adicionada ou removida
     por esta constituição; nenhuma alteração necessária.
  ✅ .specify/templates/tasks-template.md — ajustado: a nota "Tests are OPTIONAL" passa a
     registrar a exceção do Princípio II.
  ✅ Prototipo/driver/README.md — documenta os comandos que os gates exigem
     (flutter analyze / flutter test); nenhuma alteração necessária.

Follow-ups pendentes:
  ⚠ Prototipo/passenger/.specify/memory/constitution.md continua sendo o template não
    preenchido. As duas aplicações compartilham contratos de evento e material criptográfico;
    esta constituição deve ser espelhada lá para que os gates valham dos dois lados.
  ⚠ specs/001-flutter-app-base e specs/002-nostr-relay-connection registram o gate de
    constituição como "PASS por vacuidade". A feature 002 precisa ser reavaliada contra esta
    constituição antes de /speckit-implement.
-->

# Corridas Motorista Constitution

Constituição do aplicativo do motorista (`Prototipo/driver`), protótipo de corridas P2P sobre o
protocolo Nostr, prova de conceito do TCC em Tecnologias da Informação e Comunicação (UFSC —
Araranguá). Ela existe porque este protótipo manipula material criptográfico do usuário e produz
resultados que sustentam afirmações de uma monografia: ambos exigem regras que não dependam da
disposição de quem estiver escrevendo o código naquele dia.

## Core Principles

### I. Segredo criptográfico não vaza (NÃO NEGOCIÁVEL)

Chave privada, semente ou qualquer material que permita assinar em nome do usuário MUST ser gravado
apenas no armazenamento protegido do sistema operacional. Esse material MUST NOT aparecer em log,
em mensagem de erro, em tela por padrão, em arquivo de configuração, em captura de tela de
documentação, no histórico do git ou em qualquer dado enviado a um relay.

Toda feature que toque nesse material MUST incluir uma verificação explícita de não vazamento entre
seus critérios de aceitação — inspeção de log e do tráfego enviado, no mínimo.

*Racional*: em um sistema sem intermediário, a chave privada **é** o usuário. Vazá-la não é um bug de
protótipo: é a perda irreversível da identidade e a possibilidade de terceiros publicarem corridas em
nome dele. Nenhum prazo de TCC justifica relaxar isso.

### II. Assinatura e verificação nascem com teste (NÃO NEGOCIÁVEL)

Código que assina eventos, verifica assinaturas, deriva chaves ou decide descartar uma mensagem
recebida MUST ter teste automatizado escrito junto da implementação, cobrindo o caso válido **e** o
caso inválido (assinatura adulterada, autor divergente, campo ausente).

Esses testes MUST rodar sem rede e sem relay real, usando dublês. Uma feature que dependa de relay
público para provar que funciona não pode ser considerada verificada.

*Racional*: erro em verificação de assinatura falha em silêncio — o app continua funcionando e
aceitando eventos forjados. É a classe de defeito que nenhum teste manual pega e que invalidaria a
conclusão do trabalho sobre viabilidade.

### III. Dependência de terceiros exige decisão registrada

Adicionar dependência de terceiros ao `pubspec.yaml` MUST ser acompanhado de uma entrada no
`research.md` da feature correspondente contendo: alternativas efetivamente avaliadas com suas
versões e datas de publicação, critérios aplicados, riscos assumidos e a mitigação de acoplamento.

Tipos de bibliotecas de terceiros MUST ficar confinados à camada de serviços; a camada de domínio e
as telas usam tipos próprios do projeto.

*Racional*: o ecossistema Dart para Nostr é pequeno e desigual — qual biblioteca existe, quão viva
ela está e o que ela cobre **é resultado de pesquisa**, não detalhe de implementação. Registrar a
decisão alimenta a monografia e mantém possível trocar de biblioteca sem reescrever a interface.

### IV. O contrato de evento vem antes do código

Não existe backend neste sistema: o único acoplamento entre a app do motorista e a do passageiro é o
formato dos eventos Nostr. Todo novo tipo de evento MUST ser especificado em
`specs/<feature>/contracts/` antes de ser implementado, e MUST ser replicado de forma idêntica na
outra aplicação na mesma alteração. A mesma exigência vale para os demais artefatos dos quais a
interoperabilidade depende: a lista padrão de relays e o marcador que identifica o tráfego do
protótipo. Divergência em qualquer um deles entre as duas aplicações é defeito, não trabalho em
andamento.

Todo evento recebido MUST ter a assinatura verificada antes de qualquer outro processamento, MUST ser
deduplicado por identificador e MUST ser tratado como dado — nunca como instrução ou marcação
renderizável. Kinds desconhecidos MUST ser ignorados sem erro.

*Racional*: contrato divergente entre as duas apps produz falha que só aparece em teste ponta a
ponta, quando o custo de corrigir já é alto. E conteúdo vindo de relay é entrada não confiável de
terceiros por definição.

A exigência de replicação direta foi afrouxada na versão 1.1.0, quando cada aplicação era mantida por
uma sessão de trabalho distinta e nenhuma podia editar o diretório da outra — regra impossível de
cumprir ensina a ignorar a constituição. Foi restaurada na 2.0.0, quando uma única sessão passou a
manter as duas aplicações. O período de exceção deixou evidência do custo: as listas padrão de relays
divergiram entre as apps, e a cópia do contrato ficou defasada da emenda já aplicada do outro lado —
as duas divergências só foram detectadas por verificação cruzada, não evitadas por construção. Se o
modo de trabalho voltar a impedir a replicação direta, a saída é emendar esta constituição, nunca
descumpri-la.

### V. Simplicidade proporcional e rastreabilidade acadêmica

Estrutura MUST ser introduzida apenas quando houver consumidor para ela: camada sem uso, abstração
sem segunda implementação e configuração sem requisito são proibidas. Quando uma decisão de projeto
não for óbvia, ela MUST estar registrada no `research.md` da feature, com as alternativas
descartadas e o porquê.

Resultado apresentado como medição MUST ter sido medido de fato, com o método descrito junto do
número. Estimativa apresentada como medição é falta grave de integridade acadêmica.

*Racional*: este é um protótipo para responder a uma pergunta de pesquisa, não um produto. O que
sobra de arquitetura atrapalha a leitura do avaliador; o que falta de registro impede que o trabalho
seja auditado ou reproduzido.

## Restrições de Segurança e Privacidade

- O aplicativo MUST declarar apenas as permissões do sistema que uma funcionalidade já implementada
  exige. Permissão "para o futuro" é proibida.
- Localização, contatos, câmera e armazenamento externo MUST NOT ser acessados sem feature própria
  que os justifique e que descreva o dado coletado, seu uso e seu tempo de vida.
- Conteúdo publicado em relay público MUST ser tratado como permanente e mundialmente legível:
  qualquer dado pessoal que trafegue sem criptografia entre pares MUST estar justificado por escrito
  na especificação da feature.
- Toda mensagem de domínio entre as duas apps que tenha destinatário conhecido MUST ser cifrada ao
  destinatário (NIP-44, entre a chave privada do remetente e a chave pública do destinatário) e
  assinada (NIP-01); só o `content` é cifrado — as tags de marcador, referência e destinatário ficam
  em claro para filtro e roteamento. A única exceção é o `kind: 20001` (Solicitação de corrida), um
  anúncio a qualquer motorista, sem destinatário: só assinado, com posição e destino públicos,
  justificado em `specs/006-solicitar-corrida/spec.md` do passageiro e no contrato. Toda exceção nova
  MUST ser registrada nesta seção, com justificativa, antes de ser implementada.
- Dados de usuário MUST NOT ser enviados a qualquer serviço que não seja um relay Nostr configurado,
  com uma única exceção: o texto de busca de endereço e o endereço resultante da seleção do usuário
  podem ser enviados a um serviço de geocodificação de terceiros, estritamente para obter endereços
  correspondentes ao texto. Essa exceção só vale sob todas estas condições: a chamada MUST ser feita
  por HTTPS; MUST NOT incluir qualquer identificador do usuário (chave pública, nome ou apelido de
  exibição, posição atual); e o app MUST NOT persistir o texto de busca digitado nem a resposta do
  serviço além da sessão em curso, salvo o endereço de destino que o próprio usuário selecionou (texto
  exibido e coordenadas), que pode ser guardado só no aparelho, sem identificador, para ser restaurado
  depois de um reinício do app, e que MUST ser apagado quando o usuário limpa o campo de destino. Toda feature que use esta exceção MUST registrar a decisão de dependência no
  `research.md` correspondente, conforme o Princípio III, citando esta exceção explicitamente.
  Telemetria, analytics e relatórios de erro para terceiros continuam proibidos neste protótipo.
- Duas coordenadas geográficas (latitude/longitude) relevantes para uma decisão do usuário — a
  posição atual do usuário e um destino, ou as coordenadas de origem e destino de uma solicitação
  que ele recebeu de outro usuário do protocolo — podem ser enviadas a um serviço de roteamento de
  terceiros, estritamente para calcular a distância e o trajeto entre os dois pontos. Essa exceção
  só vale sob todas estas condições: a chamada MUST ser feita por HTTPS; MUST NOT incluir qualquer
  identificador do usuário ou de terceiros além das coordenadas em si (chave pública, nome ou
  apelido de exibição); e o app MUST NOT persistir a resposta do serviço além da sessão em curso.
  Toda feature que use esta exceção MUST registrar a decisão de dependência no `research.md`
  correspondente, conforme o Princípio III, citando esta exceção explicitamente.
- Uma coordenada geográfica (latitude/longitude) de origem ou destino de uma solicitação que o
  usuário recebeu de outro usuário do protocolo pode ser enviada a um serviço de geocodificação
  reversa de terceiros, estritamente para obter um endereço legível a ser exibido a ele. Essa
  exceção só vale sob todas estas condições: a chamada MUST ser feita por HTTPS; MUST NOT incluir
  qualquer identificador do usuário ou de terceiros além da coordenada em si (chave pública, nome ou
  apelido de exibição, posição atual do usuário); e o app MUST NOT persistir a resposta do serviço
  além da sessão em curso. Toda feature que use esta exceção MUST registrar a decisão de dependência
  no `research.md` correspondente, conforme o Princípio III, citando esta exceção explicitamente.
- Os tiles do mapa podem ser pedidos a um serviço de tiles vetoriais de terceiros (OpenFreeMap),
  estritamente para desenhar o mapa. A requisição revela ao serviço o IP do aparelho e as
  coordenadas z/x/y dos tiles, isto é, a região exibida; isso MUST ser aceito como custo desta
  exceção. Ela só vale sob todas estas condições: a chamada MUST ser feita por HTTPS; MUST NOT
  incluir qualquer identificador do usuário (chave pública, nome ou apelido de exibição) nem a
  posição exata além dos tiles em si; e o app MUST NOT enviar a esse serviço nada além dos pedidos de
  estilo, de tiles, de fontes e de sprites. Os tiles são dado de mapa público: o cache em disco do
  pacote de tiles é permitido. Exibir a atribuição exigida pelo serviço ("OpenFreeMap",
  "OpenMapTiles" e "OpenStreetMap contributors") MUST ser feito no mapa. Toda feature que use esta
  exceção MUST registrar a decisão de dependência no `research.md` correspondente, conforme o
  Princípio III, citando esta exceção explicitamente.
- Os apps do motorista e do passageiro podem manter um serviço em primeiro plano do Android que hospeda
  a conexão com os relays configurados e mostra notificações locais (features `025-conexao-em-segundo-plano`
  do motorista e `026-conexao-em-segundo-plano` do passageiro). No motorista o serviço fica ativo enquanto o
  app está visível ou o motorista está online; no passageiro, enquanto o app está visível ou há solicitação ou
  corrida ativa. Essa exceção só vale sob todas estas condições: o serviço MUST NOT ler nem receber a chave
  privada ou a semente, MUST NOT decifrar mensagens e MUST NOT acessar a localização; ele só verifica
  assinatura, deduplica, repassa eventos e publica o que a interface já assinou e cifrou; a decisão de
  notificar MUST usar apenas dados públicos do evento (kind, autor, tags) e o estado persistido pela
  interface; a notificação MUST NOT conter endereço, coordenada, nome, placa nem chave pública de terceiros;
  o serviço MUST ser iniciado pela interface, com o app visível, nunca no boot do aparelho nem por receptor
  em segundo plano; e nenhum serviço de push de terceiros (FCM, UnifiedPush ou semelhante) é permitido. Toda
  feature que use esta exceção MUST registrar a decisão de dependência no `research.md` correspondente,
  conforme o Princípio III, citando esta exceção explicitamente.

## Identidade Visual e Design

As telas dos dois aplicativos MUST compartilhar uma mesma identidade visual, derivada do mockup de
referência do cadastro do motorista (etapa 1, aprovado em 2026-09-24). Os valores abaixo são a
fonte única: cor, tamanho ou raio que não conste aqui MUST ser acrescentado aqui antes de ser usado.

**Escopo de aplicação**: toda tela nova ou redesenhada MUST seguir esta seção. Telas existentes
migram quando forem tocadas por uma feature — não há reescrita em bloco só por esta emenda
(Princípio V). Quando uma segunda tela adotar a identidade, os tokens MUST ser extraídos para um
único arquivo por aplicativo e referenciados dali, nunca copiados entre telas.

**Paleta** (uma só; sem variante escura nesta versão — o cabeçalho escuro e a folha clara já fazem
parte da identidade, e o modo escuro do sistema MUST NOT inverti-la):

| Token | Valor | Uso |
|---|---|---|
| `fundo` | `#24124F` | cabeçalho e fundo da tela atrás da folha |
| `segmento-inativo` | `#382469` | segmentos de progresso ainda não alcançados |
| `destaque` | `#C8F169` | segmento de progresso atual/concluído; único uso do verde-limão |
| `folha` | `#FAF8FF` | superfície do conteúdo (folha de cantos superiores arredondados) |
| `campo` | `#F4F0FF` | preenchimento de campos de entrada |
| `roxo` | `#6B3FE0` | ação primária, setas de seleção, foco |
| `texto` | `#3D3358` | rótulos e valores digitados sobre `folha`/`campo` |
| `texto-suave` | `#6E6789` | placeholder e texto de ajuda |
| `fundo-profundo` | `#140A26` | barra de navegação inferior e cartão de status sobre o mapa |
| `mapa-base` | `#E5DFEF` | tom de fundo do mapa (aproximado por filtro sobre os tiles) |
| `mapa-via` | `#F1EEF6` | vias e edificações claras do mapa |
| `mapa-verde` | `#D5EDB5` | parques e áreas verdes do mapa |
| `mapa-agua` | `#BFE0F5` | corpos d'água do mapa |
| `desabilitado` | `#A6A1B8` | rótulo e dica de campo desabilitado |
| sobre `fundo` | branco (título grande, rótulo de etapa) e branco a 87% (`#DEDCE5`: subtítulo, título da barra) | texto no cabeçalho |
| botão desabilitado | fundo `#E7E1F7`, texto e ícone `#9C94B5` | ação primária indisponível |

Cor de erro MUST vir do `ColorScheme.error` do tema, não de um valor fixo. Texto informativo que o
usuário precisa ler (ajuda, erro, placeholder, valor digitado) MUST ter contraste mínimo de 4,5:1
com o fundo em que aparece; `desabilitado` e o texto do botão desabilitado ficam isentos, por
serem elementos inativos.

**Tipografia**: família **DM Sans**, com estes papéis — título da tela 32 px / peso 800, branco;
subtítulo 15 px / regular, branco a 87%; título da barra superior 15 px / 700; rótulo de etapa 13
px / 600; rótulo de campo 15 px / 600; valor de campo e botão 16 px / 700; texto de ajuda 12 px /
regular. Enquanto a fonte não estiver empacotada, o aplicativo MUST usar a fonte padrão do Material
com os mesmos tamanhos e pesos. A fonte MUST ser empacotada como asset local, com a decisão
registrada no `research.md` da feature conforme o Princípio III; carregá-la em tempo de execução de
um serviço externo (por exemplo, o pacote `google_fonts` com download) é proibido, porque enviaria
requisição a terceiro em desacordo com Restrições de Segurança e Privacidade.

**Forma e espaçamento**: folha com raio superior de 32 px; campos e botões com raio de 16 px;
margem lateral de 20 px; 12 px entre campos; barra de progresso com segmentos de 3 px de altura,
raio 2 px e 4 px entre eles, um segmento por etapa; botão primário com altura de 56 px.

**Componentes**:
- Cabeçalho: título da tela em texto pequeno, rótulo "Etapa N de M", barra segmentada, título
  grande e, quando útil, um subtítulo — nessa ordem, sobre `fundo`.
- Campo de entrada: preenchido (`campo`), sem borda nem traço, com o rótulo sempre visível **dentro**
  do campo, acima do valor, e placeholder em `texto-suave`. Seleção usa a mesma aparência, com seta
  `roxo`. Campo dependente de outro fica esmaecido, mostra "—" e uma ajuda explicando o pré-requisito.
- Ação primária: uma por tela, largura total, fixa no rodapé da folha, com ícone de seta à esquerda
  do texto quando avança; `roxo` com texto branco habilitada, estilo de desabilitado da paleta
  quando os campos da etapa ainda não são válidos.
- Tela de mapa: mapa em tela cheia, com tons de `mapa-*` obtidos por filtro de cor sobre os tiles;
  marcador de posição circular de 44 px em `fundo`, borda branca de 2 px e ícone em `destaque`;
  botão circular branco de 48 px com ícone `roxo` no canto inferior direito, acima do cartão de
  status, que recentraliza o mapa na posição do usuário.
- Cartão de status (disponibilidade): fundo `fundo-profundo`, raio 20 px, margem de 16 px, título 16
  px / 700 branco, subtítulo 12 px branco a 87%, e interruptor em pílula (trilho `segmento-inativo`
  desligado, `roxo` ligado, polegar branco).
- Barra de navegação inferior: fundo `fundo-profundo`; destino selecionado em pílula `roxo` com ícone
  e rótulo brancos em peso 700; demais destinos em branco a 70%; rótulos de 11 px.
- Tela de conteúdo (sem etapas): mesmo cabeçalho sobre `fundo` (título pequeno da barra e título
  grande 32 px / 800 branco, sem "Etapa N de M" nem barra segmentada) e folha de cantos superiores
  arredondados; MUST NOT usar o `AppBar` padrão do Material.
- Cartão de lista: fundo `campo`, raio 16 px, preenchimento de 12 px por 16 px, 8 px entre cartões e
  sem divisores; título 16 px / 700 `texto`, subtítulo 12 px `texto-suave`. Ícone de estado: ativo em
  `roxo`, em andamento em `texto-suave`, falha em `ColorScheme.error`.
- Modal: fundo `folha`, raio 24 px; título 20 px / 800 `texto`; corpo 15 px `texto`; ação primária
  `roxo` com texto branco 16 px / 700, altura 48 px e raio 16 px; ação secundária em texto `roxo`.
  Seleção de nota: ícone selecionado `roxo`, não selecionado `desabilitado`.
- Cabeçalho com ações: ícones de ação em branco a 87%, alinhados à direita da linha do título da
  barra; em tela empilhada na navegação, um ícone de voltar à esquerda dessa linha.
- Painel de ação sobre o mapa: fundo `folha`, raio 24 px, margem de 16 px e sombra suave, contendo
  campos preenchidos e a ação primária de 56 px; sugestões de busca em linhas de 44 px com ícone
  `roxo`, sem divisores pesados.
- Seleção segmentada: segmentos de raio 16 px em `campo`; o selecionado em `roxo` com texto branco,
  os demais com texto `texto`.
- Faixa de estado: cartão `campo`, raio 16 px, com ícone e texto 13 px; situação normal com ícone
  `roxo`, situação de alerta com ícone e texto em `ColorScheme.error`.
- Bloco "corrida em andamento": dentro do cartão de status do mapa, abaixo da linha do status e de
  um divisor de 1 px em branco a 12%; rótulo em caixa alta 11 px / 600 em branco a 70%, endereço do
  alvo do trecho 16 px / 700 branco e, à direita, o tempo estimado 13 px em branco a 87% (omitido
  quando indisponível); 12 px de espaço entre o bloco e o botão de cancelamento de corrida.
- Botão de cancelamento de corrida: largura total, altura 48 px, raio 16 px, mesma aparência da ação
  primária — fundo `roxo`, ícone e texto brancos 16 px / 700. Todo botão que efetiva o cancelamento
  de uma corrida MUST seguir este componente.
- Marcador do passageiro: mesmo círculo de 44 px do marcador do motorista, com ícone de pessoa em
  `destaque`. Rota traçada em `roxo`, 5 px. Botão flutuante estendido: `roxo`, texto branco 16 px /
  700, raio 16 px.
- Fluxos em etapas MUST mostrar a barra segmentada e persistir cada etapa conforme a feature que os
  define; a identidade visual não altera regra de validação nem contrato de evento.

*Racional*: as duas apps são a mesma experiência vista de lados opostos da corrida; aparência
divergente entre elas ou entre telas da mesma app reduz a clareza do protótipo na demonstração da
monografia. Fixar os valores aqui evita que cada sessão de implementação reinterprete o mockup.

## Fluxo de Desenvolvimento e Gates

Antes de considerar uma feature concluída, todos os itens abaixo MUST passar:

1. `flutter analyze` termina sem apontamentos.
2. `flutter test` passa integralmente, sem teste ignorado ou marcado como pendente.
3. Os cenários do `quickstart.md` da feature foram executados, e os que falharam estão relatados —
   não omitidos.
4. Features que tocam material criptográfico têm a verificação de não vazamento do Princípio I
   executada e registrada.
5. Os commits seguem a seção Padrão de Commits desta constituição.
6. Telas novas ou redesenhadas seguem a seção Identidade Visual e Design desta constituição.

Relatar conclusão com gate pendente MUST ser acompanhado da lista explícita do que ficou de fora e
por quê. Silenciar uma falha é violação desta constituição, não economia de tempo.

## Padrão de Commits

O padrão abaixo foi extraído dos commits do repositório a partir de 2026-09-15, que o seguem de forma
consistente. Commits anteriores ("download template", "Criação do arquivo contendo a introdução",
"Atualiza arquivo 1-TCC.v2.docx") são anteriores a esta regra e MUST NOT ser usados como exemplo.

1. **Idioma e formato**: a mensagem MUST ser escrita em português do Brasil. Conventional Commits
   (`feat:`, `fix:`, `docs:`, escopo entre parênteses) e emojis MUST NOT ser usados.
2. **Assunto**: uma única frase, iniciada por verbo no presente do indicativo, terceira pessoa do
   singular, com inicial maiúscula e sem ponto final — `Adiciona`, `Corrige`, `Conecta`, `Emenda`,
   `Registra`, `Sincroniza`, `Especifica e planeja`. Forma nominal ("Criação de…", "Atualização
   de…") e infinitivo ("Adicionar…") MUST NOT ser usados.
3. **O assunto nomeia o alvo e o efeito**: diz o que mudou no comportamento ou no conteúdo e onde —
   qual aplicação ("do motorista", "do passageiro", "nas duas apps"), qual feature, qual documento.
   Assunto que só nomeia o arquivo ("Atualiza arquivo X") MUST NOT ser usado. Quando o motivo cabe
   numa oração, ele SHOULD vir no próprio assunto ("Emenda as duas constituições para 2.0.0,
   restaurando a replicação direta do Princípio IV"). Especificidade prevalece sobre brevidade, mas o
   assunto SHOULD ficar abaixo de 120 caracteres, deixando o detalhe para o corpo.
4. **Corpo**: separado do assunto por uma linha em branco, em parágrafos de prosa, sem listas com
   marcadores, com linhas quebradas em torno de 80 colunas e nunca acima de 100. O corpo MUST existir
   quando o commit altera comportamento, corrige defeito, emenda contrato ou constituição, ou mexe
   em dependência; pode ser omitido só quando o assunto já diz tudo. Ele MUST explicar o que o diff
   não mostra: por que a mudança existe (motivação, causa do defeito, achado do `/speckit-analyze`
   que a originou), qual evidência a sustenta (defeito reproduzido por teste antes da correção,
   tamanho da suíte depois da mudança, medição com o método) e o que ficou de fora. Números citados
   no corpo seguem o Princípio V: medidos de fato, nunca estimados.
5. **Coautoria**: commit produzido com participação de agente de IA MUST terminar, após linha em
   branco, com o trailer `Co-Authored-By:` identificando o modelo, no formato
   `Co-Authored-By: <Modelo> <noreply@anthropic.com>`.
6. **Granularidade**: um commit MUST conter uma única mudança lógica, e a mensagem MUST cobri-la por
   inteiro. Em particular, são commits separados: a emenda de constituição e o código que ela
   autoriza; a proposta de emenda a um contrato e sua aplicação; a atualização do `CLAUDE.md` e a
   mudança que ela descreve. Em sentido inverso, o que o Princípio IV exige idêntico nas duas
   aplicações (contrato de eventos, lista padrão de relays, marcador) MUST mudar nas duas no mesmo
   commit. A tarefa de `tasks.md` que consiste no próprio commit fica desmarcada nele e é marcada
   num commit seguinte.
7. **Ramo**: commits MUST ir direto para a `master`, em histórico linear, sem ramos de feature nem
   merges — o trabalho é individual e o histórico é lido em ordem cronológica.

*Racional*: os binários do trabalho (`.docx`, `.pdf`) não têm diff legível, e o porquê de uma
correção nem sempre fica registrado em outro lugar. A mensagem de commit é, portanto, registro de
pesquisa citável na monografia: precisa ser lida sem o diff ao lado, por quem não acompanhou a
sessão.

## Governance

Esta constituição prevalece sobre preferências pessoais, sobre o hábito estabelecido no repositório e
sobre a pressa de prazo. Em conflito entre uma instrução pontual e um princípio marcado como NÃO
NEGOCIÁVEL, o princípio prevalece até ser formalmente emendado.

**Emendas**: qualquer alteração MUST ser feita neste arquivo, com Sync Impact Report atualizado no
topo, versão incrementada e propagação verificada nos templates de `.specify/templates/` e nas
especificações já escritas. Emenda MUST ser commitada separadamente das mudanças de código que ela
autoriza, para que o histórico mostre a regra mudando antes do código que se apoia nela.

**Versionamento**: MAJOR para remoção ou redefinição incompatível de princípio; MINOR para novo
princípio ou ampliação material de escopo; PATCH para esclarecimento sem mudança de obrigação.

**Conformidade**: toda execução de `/speckit-plan` MUST avaliar a feature contra estes princípios na
seção Constitution Check, e `/speckit-analyze` MUST tratar conflito com princípio como achado
CRITICAL. Exceção justificada MUST ser registrada na seção Complexity Tracking do plano, nomeando o
princípio, o motivo e a alternativa mais simples descartada — nunca deixada implícita.

**Escopo**: esta constituição vale para `Prototipo/driver`. Ela é espelho da constituição de
`Prototipo/passenger`: as duas MUST ter o mesmo texto — diferindo apenas no nome, no escopo e na
perspectiva de cada aplicação — e MUST ser emendadas em conjunto, na mesma alteração. Divergência
entre elas é defeito a corrigir, não risco a administrar.
A seção Padrão de Commits é, além disso, compartilhada com a constituição de `Prototipo/`, com
texto idêntico, e MUST ser emendada nas três ao mesmo tempo.

**Version**: 2.16.0 | **Ratified**: 2026-09-15 | **Last Amended**: 2026-10-13
