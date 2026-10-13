import '../services/ibge_municipios.dart';

/// Município brasileiro, pertencente a uma [UF].
///
/// Os dados vêm da lista embutida do IBGE (`municipiosPorUf`, decisão D2 de
/// `specs/003-cadastro-motorista/research.md`) — sem chamada de rede em tempo
/// de execução. Só o nome e a UF interessam a este protótipo; o código IBGE do
/// município não é usado.
class Municipio {
  const Municipio({required this.nome, required this.uf});

  /// Nome do município, conforme o IBGE.
  final String nome;

  /// Sigla da UF à qual o município pertence.
  final String uf;

  /// Municípios da [uf] informada, em ordem alfabética. Lista vazia se a UF
  /// não constar da lista embutida (por exemplo, sigla inválida).
  static List<Municipio> doEstado(String uf) =>
      (municipiosPorUf[uf] ?? const <String>[])
          .map((nome) => Municipio(nome: nome, uf: uf))
          .toList();

  /// Verdadeiro se [nome] for um município válido da [uf] informada — a
  /// combinação que FR-004 e FR-009 exigem nunca ficar inconsistente.
  static bool isValido({required String nome, required String uf}) =>
      (municipiosPorUf[uf] ?? const <String>[]).contains(nome);

  @override
  bool operator ==(Object other) =>
      other is Municipio && other.nome == nome && other.uf == uf;

  @override
  int get hashCode => Object.hash(nome, uf);

  @override
  String toString() => 'Municipio($nome, $uf)';
}
