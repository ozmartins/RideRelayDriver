# Feature 015 — Endereço legível na modal de solicitação (motorista)

**Pedido**: a modal de solicitação de corrida (feature 007) mostrava origem e destino como latitude e
longitude; deve mostrar um endereço legível.

## Requisitos
- **FR-001**: a modal exibe o endereço de origem e o de destino, obtidos por geocodificação reversa das
  coordenadas do `kind: 20001`.
- **FR-002**: enquanto o endereço não chega, a linha mostra "buscando endereço…".
- **FR-003**: se a busca falhar (rede, timeout, HTTP ≠ 200, resposta sem endereço), a linha volta a
  mostrar `lat, lon` com 4 casas — o motorista nunca fica sem a informação.
- **FR-004**: a busca nunca bloqueia "Enviar orçamento" nem "Recusar corrida".
- **FR-005**: nenhum contrato de evento muda; nenhuma alteração no passageiro.
- **FR-006**: a chamada usa HTTPS, envia só a coordenada, e a resposta fica só em memória (sessão).
