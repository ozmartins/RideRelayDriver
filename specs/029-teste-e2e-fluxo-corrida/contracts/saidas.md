# Contrato: arquivos gerados

Raiz: `e2e_saida/` (ignorada pelo Git; `/e2e_saida/` em `.gitignore`).

```text
e2e_saida/
├── periodo-1/
│   ├── checkpoint.json        # ver data-model.md (Periodo)
│   ├── ciclos.jsonl           # uma linha por ciclo (Ciclo)
│   ├── eventos.jsonl          # uma linha por (evento, relay) (EventoObservado)
│   ├── desvios.md             # FR-040: desvios, ajustes de timeout, conferências manuais
│   ├── execucao.log           # log do roteiro (sem chaves, content, linhas brutas de logcat)
│   └── capturas/
│       ├── c001-solicitacao-enviada-motorista.png   # primeiros ciclos: 6 telas × 2 emuladores
│       ├── c017-E05-falha-passageiro.png            # falhas: png + dump XML dos dois
│       └── c017-E05-falha-passageiro.xml
├── periodo-2/ …
├── ensaio-AAAAMMDD-HHMM/ …    # mesmo formato, rotulado
├── relatorio.md               # combina os períodos
└── dados/
    ├── ciclos.csv             # 1 linha por ciclo
    ├── latencias.csv          # 1 linha por amostra de latência
    ├── falhas.csv             # 1 linha por falha
    └── relays.csv             # (período, relay, kind, eventos entregues)
```

## `relatorio.md` — seções (fixas, nesta ordem)

1. Metadados — data(s), período(s), commits dos dois apps (e se havia alterações locais),
   configuração dos emuladores, relays, ciclos executados/válidos por período, **parcial: sim/não e
   motivo**, tempo ativo, timeouts usados (rotulados "limites escolhidos, não medidos").
2. Critério de sucesso — n = ciclos válidos, falhas sem as externas, veredito: `ATENDIDO` (0),
   `PARCIALMENTE ATENDIDO` (1–3), `NÃO ATENDIDO` (>3). Veredito **só no total**; por período,
   apenas falhas, n e taxa. Período único: "não aplicável (período único)".
3. Taxa de falha total (inclui externas) — separada, "informativo, sem critério".
4. Taxas de sucesso e de falha com IC de Clopper-Pearson 95% bilateral, por período e total.
5. Latência — mediana e P95 (posto mais próximo), por período e total, por tipo e geral; linhas "geral (todas)", "geral (toque)" e "geral (posicionamento)"; n de amostras por linha. Sem IC nem limite.
6. Falhas por origem — contagem (aplicativo [com sublista de `indeterminada`], relays, serviço
   externo por serviço, ambiente de teste) e lista: ciclo, etapa, origem, referência às capturas.
7. Comportamento por relay — por período, eventos entregues ao observador por relay e por kind e
   quantos eventos foram vistos primeiro em cada relay. Descritivo.
8. Limitações — ciclos repostos, interrompidos, teto/orçamento/cota atingidos, períodos ausentes,
   telas não capturadas por serem sensíveis, desvios de `desvios.md`, ressalva do observador
   (FR-024), ressalva do rótulo "posicionamento".

O relatório **não** contém: chaves privadas, `content`, linhas brutas de logcat, a chave da ORS, nem
critério de aceitação de latência.

## Proibições aplicadas a todos os arquivos de texto (varredura)

`nsec1…`; hex de 64 caracteres que não seja id de evento observado nem chave pública do período;
hex de 128 caracteres; `"content"` como chave JSON; o valor da chave da ORS.
