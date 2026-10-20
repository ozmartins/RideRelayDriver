import 'municipio.dart';
import 'payment_method.dart';
import 'uf.dart';

/// Cadastro do motorista: dados pessoais e do veículo.
///
/// Não é segredo criptográfico (diferente de [Identity]) — corrupção ou perda
/// leva a solicitar o preenchimento de novo (FR-010), nunca ao tratamento de
/// vazamento irreversível do Princípio I.
class DriverProfile {
  const DriverProfile({
    required this.nome,
    required this.uf,
    required this.cidade,
    required this.marcaVeiculo,
    required this.modeloVeiculo,
    required this.corVeiculo,
    required this.placaVeiculo,
    required this.paymentMethods,
    required this.precoPorKm,
    required this.anoVeiculo,
  });

  final String nome;
  final String uf;
  final String cidade;
  final String marcaVeiculo;
  final String modeloVeiculo;
  final String corVeiculo;
  final String placaVeiculo;

  /// Formas de pagamento aceitas (feature 005). `isValido` exige que não
  /// esteja vazio (FR-002, FR-003 do `spec.md` da feature 005).
  final Set<PaymentMethod> paymentMethods;

  /// Preço padrão por quilômetro (feature 006), sugerido e ajustável por
  /// corrida (FR-003). `isValido` exige `> 0` (FR-001, FR-002).
  final double precoPorKm;

  /// Ano-modelo do veículo (feature 008). `isValido` exige uma faixa
  /// razoável (FR-001, FR-002).
  final int anoVeiculo;

  static final RegExp _placaValida = RegExp(r'^[A-Z]{3}[0-9][A-Z0-9][0-9]{2}$');

  /// Normaliza um campo de texto livre (nome, marca, modelo, cor): descarta
  /// espaços das pontas.
  static String normalizeTexto(String raw) => raw.trim();

  /// Verdadeiro se o texto normalizado não ficar vazio — regra dos campos
  /// obrigatórios de texto livre (FR-002, FR-006).
  static bool isTextoValido(String raw) => normalizeTexto(raw).isNotEmpty;

  /// Normaliza a placa para caixa alta e sem separadores, antes de validar e
  /// de persistir — `abc1d23`, `ABC-1D23` e `ABC1D23` resultam no mesmo valor
  /// (D3 de `specs/003-cadastro-motorista/research.md`).
  static String normalizePlaca(String raw) =>
      raw.trim().toUpperCase().replaceAll(RegExp(r'[\s-]'), '');

  /// Verdadeiro se a placa, já normalizada, estiver no formato antigo (3
  /// letras + 4 dígitos) ou Mercosul (3 letras + 1 dígito + 1 letra + 2
  /// dígitos) — os dois formatos vigentes no Brasil (FR-005, D3).
  static bool isValidPlaca(String raw) =>
      _placaValida.hasMatch(normalizePlaca(raw));

  /// Converte o texto digitado do preço por quilômetro para `double`, ou
  /// `null` se inválido (D1 de `specs/006-preco-por-km/research.md`).
  ///
  /// Aceita vírgula ou ponto como separador decimal. Recusa (devolve `null`)
  /// texto vazio, não numérico, `<= 0` ou com mais de duas casas decimais no
  /// texto original — essa última checagem é textual, antes da conversão,
  /// para não depender de arredondamento de ponto flutuante para *validar* a
  /// entrada.
  static double? parsePrecoPorKm(String raw) {
    final normalizado = raw.trim().replaceAll(',', '.');
    if (normalizado.isEmpty) return null;

    final partes = normalizado.split('.');
    if (partes.length == 2 && partes[1].length > 2) return null;

    final valor = double.tryParse(normalizado);
    if (valor == null || valor <= 0) return null;
    return valor;
  }

  /// Converte o texto digitado do ano do veículo para `int`, ou `null` se
  /// inválido (D1 de `specs/008-ano-do-veiculo/research.md`).
  ///
  /// Exige exatamente 4 dígitos, dentro da faixa 1900 até o ano corrente + 1
  /// (admite o ano-modelo do lançamento seguinte).
  static int? parseAnoVeiculo(String raw) {
    final texto = raw.trim();
    if (!RegExp(r'^\d{4}$').hasMatch(texto)) return null;

    final ano = int.parse(texto);
    final limiteSuperior = DateTime.now().year + 1;
    if (ano < 1900 || ano > limiteSuperior) return null;
    return ano;
  }

  /// Verdadeiro somente se **todos** os campos deste cadastro passarem pelas
  /// próprias regras de validação — nome, marca, modelo e cor não vazios,
  /// placa em um dos dois formatos, UF entre as 27 válidas, cidade
  /// pertencente àquela UF (FR-003, FR-004, FR-005, FR-006, FR-009 da feature
  /// 003), e ao menos uma forma de pagamento marcada (FR-002, FR-003 da
  /// feature 005).
  ///
  /// Usado tanto para habilitar o envio do formulário quanto para decidir se
  /// um cadastro lido do armazenamento está corrompido (FR-010 da feature
  /// 003) — inclusive um cadastro de uma instalação anterior à feature 005,
  /// sem nenhuma forma de pagamento registrada (FR-006 da feature 005).
  bool get isValido =>
      isTextoValido(nome) &&
      isTextoValido(marcaVeiculo) &&
      isTextoValido(modeloVeiculo) &&
      isTextoValido(corVeiculo) &&
      isValidPlaca(placaVeiculo) &&
      UF.isValida(uf) &&
      Municipio.isValido(nome: cidade, uf: uf) &&
      paymentMethods.isNotEmpty &&
      precoPorKm > 0 &&
      anoVeiculo >= 1900 &&
      anoVeiculo <= DateTime.now().year + 1;

  /// Se o motorista aceita a forma de pagamento [wireValue] de uma solicitação
  /// de corrida (valor do campo `payment` do `kind: 20001`). Um valor que não é
  /// um dos três do contrato não é aceito.
  bool acceptsPayment(String wireValue) {
    final metodo = PaymentMethod.fromWire(wireValue);
    return metodo != null && paymentMethods.contains(metodo);
  }

  /// Cópia com os campos informados substituídos — não normaliza nem valida;
  /// quem chama decide quando fazer isso (a tela, antes de salvar).
  DriverProfile copyWith({
    String? nome,
    String? uf,
    String? cidade,
    String? marcaVeiculo,
    String? modeloVeiculo,
    String? corVeiculo,
    String? placaVeiculo,
    Set<PaymentMethod>? paymentMethods,
    double? precoPorKm,
    int? anoVeiculo,
  }) {
    return DriverProfile(
      nome: nome ?? this.nome,
      uf: uf ?? this.uf,
      cidade: cidade ?? this.cidade,
      marcaVeiculo: marcaVeiculo ?? this.marcaVeiculo,
      modeloVeiculo: modeloVeiculo ?? this.modeloVeiculo,
      corVeiculo: corVeiculo ?? this.corVeiculo,
      placaVeiculo: placaVeiculo ?? this.placaVeiculo,
      paymentMethods: paymentMethods ?? this.paymentMethods,
      precoPorKm: precoPorKm ?? this.precoPorKm,
      anoVeiculo: anoVeiculo ?? this.anoVeiculo,
    );
  }

  /// Representação plana, usada pela camada de persistência (`toMap`/`fromMap`
  /// ficam no domínio porque `Map<String, dynamic>` não é um tipo de
  /// `sqflite` — só `SqfliteCadastroStore` importa o pacote, Princípio III).
  ///
  /// `paymentMethods` é serializado como os `storageValue` separados por
  /// vírgula (D2 de `specs/005-formas-pagamento/research.md`) — sem ordem
  /// significativa, já que o campo é um conjunto.
  Map<String, Object?> toMap() => {
    'nome': nome,
    'uf': uf,
    'cidade': cidade,
    'marca_veiculo': marcaVeiculo,
    'modelo_veiculo': modeloVeiculo,
    'cor_veiculo': corVeiculo,
    'placa_veiculo': placaVeiculo,
    'payment_methods': paymentMethods.map((p) => p.storageValue).join(','),
    'preco_por_km': precoPorKm,
    'ano_veiculo': anoVeiculo,
  };

  factory DriverProfile.fromMap(Map<String, Object?> map) => DriverProfile(
    nome: map['nome'] as String,
    uf: map['uf'] as String,
    cidade: map['cidade'] as String,
    marcaVeiculo: map['marca_veiculo'] as String,
    modeloVeiculo: map['modelo_veiculo'] as String,
    corVeiculo: map['cor_veiculo'] as String,
    placaVeiculo: map['placa_veiculo'] as String,
    paymentMethods: _paymentMethodsFromStorage(map['payment_methods']),
    precoPorKm: (map['preco_por_km'] as num).toDouble(),
    anoVeiculo: map['ano_veiculo'] as int,
  );

  /// Decodifica a coluna `payment_methods`. Um valor desconhecido (banco
  /// editado manualmente) é ignorado — nunca lança (D2 de `research.md`,
  /// Riscos assumidos): na pior hipótese o conjunto resultante fica vazio, o
  /// que `isValido` já trata como cadastro corrompido.
  static Set<PaymentMethod> _paymentMethodsFromStorage(Object? raw) {
    final texto = raw as String? ?? '';
    if (texto.isEmpty) return const {};
    return {
      for (final valor in texto.split(','))
        for (final forma in PaymentMethod.values)
          if (forma.storageValue == valor) forma,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is DriverProfile &&
      other.nome == nome &&
      other.uf == uf &&
      other.cidade == cidade &&
      other.marcaVeiculo == marcaVeiculo &&
      other.modeloVeiculo == modeloVeiculo &&
      other.corVeiculo == corVeiculo &&
      other.placaVeiculo == placaVeiculo &&
      other.paymentMethods.length == paymentMethods.length &&
      other.paymentMethods.containsAll(paymentMethods) &&
      other.precoPorKm == precoPorKm &&
      other.anoVeiculo == anoVeiculo;

  @override
  int get hashCode => Object.hash(
    nome,
    uf,
    cidade,
    marcaVeiculo,
    modeloVeiculo,
    corVeiculo,
    placaVeiculo,
    // Object.hashAllUnordered depende só do conteúdo, não da ordem de
    // iteração do Set — condição para == e hashCode continuarem
    // consistentes entre duas instâncias com o mesmo conjunto.
    Object.hashAllUnordered(paymentMethods),
    precoPorKm,
    anoVeiculo,
  );

  @override
  String toString() => 'DriverProfile($nome, $uf/$cidade, $placaVeiculo)';
}
