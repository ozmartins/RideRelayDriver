# Research — Botões de cancelar corrida em roxo (motorista)

## D1. A constituição manda o vermelho; o pedido manda o roxo

- **Decision**: emendar o componente "Botão de ação destrutiva" (Identidade Visual e Design, introduzido na
  2.10.0) nas duas constituições, versão 2.12.0 (MINOR: componente muda de aparência), em commit separado e
  anterior ao código. O componente passa a descrever o botão de cancelamento de corrida com a aparência da
  ação primária (fundo `roxo`, ícone e texto brancos 16 px / 700, largura total, 48 px, raio 16 px).
- **Rationale**: a seção exige registrar o componente antes de usá-lo; a Governance exige emenda separada e
  conjunta com a constituição espelho. A regra "Cor de erro MUST vir do `ColorScheme.error`" continua valendo
  para erros reais.
- **Alternatives**: usar o roxo sem emendar (viola Governance); manter o vermelho (contradiz o pedido).

## D2. Como obter o roxo: o estilo que já existe

- **Decision**: `IdentidadeVisual.estiloAcaoPrimaria(altura: 48)` no botão do mapa, igual ao da modal.
- **Rationale**: o pedido diz que já há botões com essa aparência; é exatamente esse estilo (`roxo`, branco,
  16 px / 700, raio 16). Uma única fonte impede divergência futura (SC-003).
- **Alternatives**: copiar as cores para um `styleFrom` próprio (duplica e pode divergir).

## D3. Contraste

- **Decision**: nenhuma cor nova; branco sobre `#6B3FE0` tem razão ≈ 6,2:1 (> 4,5:1) pela fórmula WCAG;
  o teste da T004 calcula a razão sobre as cores resolvidas e exige ≥ 4,5:1.

## D4. Tamanho do botão

- **Decision**: `estiloAcaoPrimaria` define `minimumSize: Size.fromHeight(48)`; o botão do mapa já está num
  `SizedBox` de largura total e altura 48, então a geometria não muda. Os testes existentes por chave
  (`botao-cancelar-corrida`) continuam válidos.

## D5. Passageiro

- **Decision**: fora desta feature; terá feature própria em `passenger/` (botão do mapa, modal e, a confirmar,
  "Cancelar" da lista de orçamentos, que cancela a solicitação, não uma corrida aceita). A emenda 2.12.0 é
  única para as duas apps.
