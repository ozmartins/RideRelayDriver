import 'driver_profile.dart';
import 'municipio.dart';
import 'payment_method.dart';
import 'uf.dart';

/// Etapa 1 do cadastro: dados do motorista (nome, UF, cidade de atuação e raio
/// de atendimento).
class DriverPersonalData {
  const DriverPersonalData({
    required this.nome,
    required this.uf,
    required this.cidade,
    this.raioAtendimentoKm = kRaioPadraoKm,
  });

  final String nome;
  final String uf;
  final String cidade;

  /// Raio de atendimento em km (feature 027), de [kRaioMinKm] a [kRaioMaxKm].
  final int raioAtendimentoKm;

  bool get isValido =>
      DriverProfile.isTextoValido(nome) &&
      UF.isValida(uf) &&
      Municipio.isValido(nome: cidade, uf: uf) &&
      DriverProfile.isRaioValido(raioAtendimentoKm);

  Map<String, Object?> toMap() => {
    'nome': nome,
    'uf': uf,
    'cidade': cidade,
    'raio_atendimento_km': raioAtendimentoKm,
  };

  factory DriverPersonalData.fromMap(Map<String, Object?> map) =>
      DriverPersonalData(
        nome: map['nome'] as String,
        uf: map['uf'] as String,
        cidade: map['cidade'] as String,
        raioAtendimentoKm: map['raio_atendimento_km'] as int? ?? kRaioPadraoKm,
      );

  @override
  bool operator ==(Object other) =>
      other is DriverPersonalData &&
      other.nome == nome &&
      other.uf == uf &&
      other.cidade == cidade &&
      other.raioAtendimentoKm == raioAtendimentoKm;

  @override
  int get hashCode => Object.hash(nome, uf, cidade, raioAtendimentoKm);
}

/// Etapa 2 do cadastro: dados do veículo.
class DriverVehicleData {
  const DriverVehicleData({
    required this.marca,
    required this.modelo,
    required this.ano,
    required this.cor,
    required this.placa,
  });

  final String marca;
  final String modelo;
  final int ano;
  final String cor;
  final String placa;

  bool get isValido =>
      DriverProfile.isTextoValido(marca) &&
      DriverProfile.isTextoValido(modelo) &&
      DriverProfile.isTextoValido(cor) &&
      DriverProfile.isValidPlaca(placa) &&
      ano >= 1900 &&
      ano <= DateTime.now().year + 1;

  Map<String, Object?> toMap() => {
    'marca_veiculo': marca,
    'modelo_veiculo': modelo,
    'ano_veiculo': ano,
    'cor_veiculo': cor,
    'placa_veiculo': placa,
  };

  factory DriverVehicleData.fromMap(Map<String, Object?> map) =>
      DriverVehicleData(
        marca: map['marca_veiculo'] as String,
        modelo: map['modelo_veiculo'] as String,
        ano: map['ano_veiculo'] as int,
        cor: map['cor_veiculo'] as String,
        placa: map['placa_veiculo'] as String,
      );

  @override
  bool operator ==(Object other) =>
      other is DriverVehicleData &&
      other.marca == marca &&
      other.modelo == modelo &&
      other.ano == ano &&
      other.cor == cor &&
      other.placa == placa;

  @override
  int get hashCode => Object.hash(marca, modelo, ano, cor, placa);
}

/// Etapa 3 do cadastro: formas de pagamento aceitas e preço por quilômetro.
class DriverFinancialData {
  const DriverFinancialData({
    required this.paymentMethods,
    required this.precoPorKm,
  });

  final Set<PaymentMethod> paymentMethods;
  final double precoPorKm;

  bool get isValido => paymentMethods.isNotEmpty && precoPorKm > 0;

  /// Mesma serialização de [DriverProfile.toMap]: `storageValue`s separados
  /// por vírgula.
  Map<String, Object?> toMap() => {
    'payment_methods': paymentMethods.map((p) => p.storageValue).join(','),
    'preco_por_km': precoPorKm,
  };

  factory DriverFinancialData.fromMap(Map<String, Object?> map) {
    final texto = map['payment_methods'] as String? ?? '';
    return DriverFinancialData(
      paymentMethods: {
        if (texto.isNotEmpty)
          for (final valor in texto.split(','))
            for (final forma in PaymentMethod.values)
              if (forma.storageValue == valor) forma,
      },
      precoPorKm: (map['preco_por_km'] as num).toDouble(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DriverFinancialData &&
      other.paymentMethods.length == paymentMethods.length &&
      other.paymentMethods.containsAll(paymentMethods) &&
      other.precoPorKm == precoPorKm;

  @override
  int get hashCode =>
      Object.hash(Object.hashAllUnordered(paymentMethods), precoPorKm);
}

/// O que já foi salvo do cadastro em etapas. Cada parte só existe depois de
/// a respectiva etapa ter sido concluída e persistida.
class CadastroProgress {
  const CadastroProgress({this.personal, this.vehicle, this.financial});

  const CadastroProgress.empty() : this();

  /// Progresso equivalente a um cadastro já completo (modo de edição).
  factory CadastroProgress.fromProfile(DriverProfile p) => CadastroProgress(
    personal: DriverPersonalData(
      nome: p.nome,
      uf: p.uf,
      cidade: p.cidade,
      raioAtendimentoKm: p.raioAtendimentoKm,
    ),
    vehicle: DriverVehicleData(
      marca: p.marcaVeiculo,
      modelo: p.modeloVeiculo,
      ano: p.anoVeiculo,
      cor: p.corVeiculo,
      placa: p.placaVeiculo,
    ),
    financial: DriverFinancialData(
      paymentMethods: p.paymentMethods,
      precoPorKm: p.precoPorKm,
    ),
  );

  final DriverPersonalData? personal;
  final DriverVehicleData? vehicle;
  final DriverFinancialData? financial;

  CadastroProgress copyWith({
    DriverPersonalData? personal,
    DriverVehicleData? vehicle,
    DriverFinancialData? financial,
  }) => CadastroProgress(
    personal: personal ?? this.personal,
    vehicle: vehicle ?? this.vehicle,
    financial: financial ?? this.financial,
  );

  bool get isComplete => nextStep == null;

  /// Índice (0, 1 ou 2) da primeira etapa ainda não salva, ou `null` se as
  /// três já foram — é onde o wizard retoma ao reabrir o aplicativo.
  int? get nextStep {
    if (personal == null) return 0;
    if (vehicle == null) return 1;
    if (financial == null) return 2;
    return null;
  }

  /// Cadastro completo, ou `null` se ainda falta alguma etapa.
  DriverProfile? toProfile() {
    final p = personal, v = vehicle, f = financial;
    if (p == null || v == null || f == null) return null;
    return DriverProfile(
      nome: p.nome,
      uf: p.uf,
      cidade: p.cidade,
      marcaVeiculo: v.marca,
      modeloVeiculo: v.modelo,
      corVeiculo: v.cor,
      placaVeiculo: v.placa,
      paymentMethods: f.paymentMethods,
      precoPorKm: f.precoPorKm,
      anoVeiculo: v.ano,
      raioAtendimentoKm: p.raioAtendimentoKm,
    );
  }
}
