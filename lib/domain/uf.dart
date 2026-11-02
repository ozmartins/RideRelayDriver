/// Unidade da Federação (UF) brasileira.
///
/// Lista fixa e embutida no aplicativo — as 26 unidades da federação mais o
/// Distrito Federal nunca mudam durante a vida do protótipo, então não há
/// fonte externa nem validação de rede (FR-003).
class UF {
  const UF({required this.sigla, required this.nome});

  /// Sigla de 2 letras, em caixa alta — chave da entidade.
  final String sigla;

  /// Nome completo, para exibição (ex.: "Distrito Federal").
  final String nome;

  /// Verdadeiro se [sigla] for uma das 27 UFs válidas.
  static bool isValida(String sigla) =>
      brazilianStates.any((uf) => uf.sigla == sigla);

  @override
  bool operator ==(Object other) => other is UF && other.sigla == sigla;

  @override
  int get hashCode => sigla.hashCode;

  @override
  String toString() => 'UF($sigla)';
}

/// As 26 unidades da federação e o Distrito Federal, em ordem alfabética pela
/// sigla. Fonte: divisão político-administrativa vigente do IBGE.
const List<UF> brazilianStates = [
  UF(sigla: 'AC', nome: 'Acre'),
  UF(sigla: 'AL', nome: 'Alagoas'),
  UF(sigla: 'AP', nome: 'Amapá'),
  UF(sigla: 'AM', nome: 'Amazonas'),
  UF(sigla: 'BA', nome: 'Bahia'),
  UF(sigla: 'CE', nome: 'Ceará'),
  UF(sigla: 'DF', nome: 'Distrito Federal'),
  UF(sigla: 'ES', nome: 'Espírito Santo'),
  UF(sigla: 'GO', nome: 'Goiás'),
  UF(sigla: 'MA', nome: 'Maranhão'),
  UF(sigla: 'MT', nome: 'Mato Grosso'),
  UF(sigla: 'MS', nome: 'Mato Grosso do Sul'),
  UF(sigla: 'MG', nome: 'Minas Gerais'),
  UF(sigla: 'PA', nome: 'Pará'),
  UF(sigla: 'PB', nome: 'Paraíba'),
  UF(sigla: 'PR', nome: 'Paraná'),
  UF(sigla: 'PE', nome: 'Pernambuco'),
  UF(sigla: 'PI', nome: 'Piauí'),
  UF(sigla: 'RJ', nome: 'Rio de Janeiro'),
  UF(sigla: 'RN', nome: 'Rio Grande do Norte'),
  UF(sigla: 'RS', nome: 'Rio Grande do Sul'),
  UF(sigla: 'RO', nome: 'Rondônia'),
  UF(sigla: 'RR', nome: 'Roraima'),
  UF(sigla: 'SC', nome: 'Santa Catarina'),
  UF(sigla: 'SP', nome: 'São Paulo'),
  UF(sigla: 'SE', nome: 'Sergipe'),
  UF(sigla: 'TO', nome: 'Tocantins'),
];
