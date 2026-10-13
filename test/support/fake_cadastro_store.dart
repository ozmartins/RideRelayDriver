import 'package:driver/domain/cadastro_progress.dart';
import 'package:driver/domain/driver_profile.dart';
import 'package:driver/services/cadastro_store.dart';

/// Dublê em memória de [CadastroStore]: nenhum teste toca SQLite real
/// (decisão D1 da feature 003, Princípio III). `loadProgress()` aplica
/// [ensureValid], igual à implementação real sobre `sqflite` — é a mesma
/// decisão de "isto está corrompido" nos dois lados.
class FakeCadastroStore implements CadastroStore {
  FakeCadastroStore([DriverProfile? perfil])
    : _progress = perfil == null
          ? const CadastroProgress.empty()
          : CadastroProgress.fromProfile(perfil);

  CadastroProgress _progress;

  /// Quantas etapas foram gravadas (uma por chamada a `save*`).
  int saveCount = 0;

  @override
  Future<CadastroProgress> loadProgress() async => ensureValid(_progress);

  @override
  Future<DriverProfile?> load() async => (await loadProgress()).toProfile();

  @override
  Future<void> savePersonal(DriverPersonalData data) async {
    saveCount++;
    _progress = _progress.copyWith(personal: data);
  }

  @override
  Future<void> saveVehicle(DriverVehicleData data) async {
    saveCount++;
    _progress = _progress.copyWith(vehicle: data);
  }

  @override
  Future<void> saveFinancial(DriverFinancialData data) async {
    saveCount++;
    _progress = _progress.copyWith(financial: data);
  }

  /// Só para teste: simula um progresso já persistido, inclusive corrompido,
  /// sem passar pela validação de gravação.
  void debugSetRaw(CadastroProgress progress) => _progress = progress;
}
