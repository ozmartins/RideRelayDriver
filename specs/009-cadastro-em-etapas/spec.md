# Feature 009 — Cadastro do motorista em etapas (wizard)

**Escopo**: só o `driver/`. Não toca o contrato de eventos (sem contrapartida no passageiro).

## Requisitos

- **FR-001** O cadastro é um wizard de 3 etapas: "Dados do motorista" (nome, UF, cidade),
  "Dados do veículo" (marca, modelo, ano, cor, placa) e "Financeiro" (formas de pagamento
  aceitas, preço por quilômetro).
- **FR-002** O botão das etapas 1 e 2 é "Salvar e continuar"; o da etapa 3 é "Concluir cadastro".
  Cada botão só habilita quando os campos da própria etapa são válidos.
- **FR-003** Cada etapa é persistida ao ser confirmada, em tabela própria do SQLite
  (`driver_personal`, `driver_vehicle`, `driver_financial`), antes de a seguinte ser exibida.
- **FR-004** Ao reabrir o aplicativo com o cadastro incompleto, o wizard abre na primeira etapa
  ainda não salva (etapa 2 após salvar a 1; etapa 3 após salvar a 2).
- **FR-005** Com as três etapas salvas o cadastro está completo e a tela principal substitui o
  wizard; nenhum consumidor de `DriverProfile` muda.
- **FR-006** Na aba "Cadastro" (edição), o mesmo wizard abre na etapa 1 pré-preenchido, cada
  etapa regrava a própria tabela e "Concluir cadastro" confirma e volta à etapa 1.
- **FR-007** Etapa salva ilegível ou inválida é tratada como progresso vazio (mesma regra de
  cadastro corrompido, FR-010 da feature 003).

## Decisões

- **Esquema SQLite v5**: a tabela única `driver_profile` (v1–v4) é descartada no `onUpgrade`
  (`DROP TABLE`) — o app está em desenvolvimento, sem migração de dado (Princípio V).
- `DriverProfile` continua sendo o cadastro completo; `CadastroProgress` (novo, em
  `lib/domain/cadastro_progress.dart`) guarda as três etapas e calcula `nextStep`.
- `CadastroStore` troca `save(DriverProfile)` por `savePersonal`/`saveVehicle`/`saveFinancial`
  e ganha `loadProgress()`; `load()` permanece, derivado do progresso.

## Validação

Testes automatizados passando (298). **Validação em aparelho pendente**: instalação limpa →
salvar etapa 1, fechar o app, reabrir (etapa 2) → salvar etapa 2, fechar, reabrir (etapa 3) →
concluir (mapa). Instalação anterior (v4) deve abrir o wizard do zero.
