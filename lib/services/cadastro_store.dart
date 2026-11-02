import '../domain/cadastro_progress.dart';
import '../domain/driver_profile.dart';

/// Persistência do cadastro do motorista, em três etapas.
///
/// Abstração do projeto (Princípio III): a implementação real usa `sqflite`
/// (decisão D1 de `specs/003-cadastro-motorista/research.md`); os testes usam
/// um dublê em memória, seguindo o mesmo padrão de `KeyStore` e
/// `KeyValueStore` — nenhum teste toca SQLite real.
///
/// Cada etapa do wizard é gravada assim que concluída, em tabela própria,
/// para que fechar o aplicativo no meio retome na etapa seguinte.
abstract class CadastroStore {
  /// O que já foi salvo, etapa por etapa. Nenhuma gravação = progresso vazio.
  ///
  /// Lança [CorruptedDriverProfile] se alguma etapa salva não passar nas
  /// próprias regras. O chamador MUST tratar isso como progresso vazio — o
  /// cadastro não é segredo irrecuperável (FR-010).
  Future<CadastroProgress> loadProgress();

  Future<void> savePersonal(DriverPersonalData data);
  Future<void> saveVehicle(DriverVehicleData data);
  Future<void> saveFinancial(DriverFinancialData data);

  /// Cadastro completo, ou `null` se alguma etapa ainda não foi salva.
  /// Mesmas exceções de [loadProgress].
  Future<DriverProfile?> load() async => (await loadProgress()).toProfile();
}

/// Confere o progresso contra as regras de cada etapa presente, lançando
/// [CorruptedDriverProfile] se alguma não passar.
///
/// Único lugar que decide "isto está corrompido" — compartilhado por toda
/// implementação de [CadastroStore], real ou dublê, para que a decisão seja
/// testável sem depender de nenhum armazenamento real (Princípio II por
/// analogia: código que decide aceitar ou rejeitar um dado nasce com teste).
CadastroProgress ensureValid(CadastroProgress progress) {
  final personal = progress.personal;
  final vehicle = progress.vehicle;
  final financial = progress.financial;
  if ((personal != null && !personal.isValido) ||
      (vehicle != null && !vehicle.isValido) ||
      (financial != null && !financial.isValido)) {
    throw CorruptedDriverProfile(
      'etapa salva do cadastro não passa nas próprias regras de validação '
      '(UF, cidade ou campo obrigatório)',
    );
  }
  return progress;
}

/// Existe cadastro salvo, mas ele não é válido — UF fora da lista fixa,
/// cidade que não pertence àquela UF, ou campo obrigatório vazio.
///
/// Não é o mesmo caso de [CadastroStoreUnavailable]: aqui a leitura teve
/// sucesso, o dado é que está incoerente.
class CorruptedDriverProfile implements Exception {
  CorruptedDriverProfile(this.detail);
  final String detail;

  @override
  String toString() =>
      'Cadastro do motorista salvo em formato inválido: $detail';
}

/// O armazenamento local não está acessível (falha de leitura ou gravação).
class CadastroStoreUnavailable implements Exception {
  CadastroStoreUnavailable(this.cause);
  final Object cause;

  @override
  String toString() => 'Armazenamento do cadastro indisponível: $cause';
}
