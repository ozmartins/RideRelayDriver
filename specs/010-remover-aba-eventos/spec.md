# Feature 010 — Remover a aba "Eventos" do motorista

**Escopo**: só o `driver/`; não toca o contrato de eventos.

- **FR-001** A navegação inferior tem quatro destinos: Mapa, Relays, Identidade e Cadastro.
- **FR-002** Nenhuma função do app depende da aba: conexão aos relays, reconexão automática,
  `EventFeed` e o consumo dos eventos de corrida ficam em `_CorridasDriverAppState` e em `MapScreen`.
- **FR-003** O estado dos relays segue visível na aba "Relays".

## Consequências

- Saem `HomeScreen`, a publicação da nota de teste pela UI (`_publish`), a medição de ida e volta
  (`[medicao] ida e volta`) e o estado `_loading`.
- Ficam `IdentityService.signTextNote`, sua verificação por teste (Princípio II) e a inscrição em
  `kind: 1` com o marcador `tcc-ufsc-caronas`, por serem contrato compartilhado com o passageiro.
- Os cenários do `quickstart.md` da feature 002 que publicam a nota de teste pela aba deixam de ser
  executáveis no aparelho do motorista; a interoperabilidade se verifica com
  `dart run tool/verify_published.dart <pubkey>` ou pelo passageiro, e o histórico do git guarda a tela.

**Validação**: testes automatizados passando (294) e conferido no emulador `Pixel_6_API34_1`.
