import '../../../../tool/e2e/src/relogio.dart';

/// Relógio de teste: `dormir` avança o tempo virtual sem esperar de verdade.
class RelogioFalso implements Relogio {
  RelogioFalso([DateTime? inicio])
    : _agora = inicio ?? DateTime.utc(2026, 11, 1, 12);

  DateTime _agora;

  @override
  DateTime agora() => _agora;

  void avancar(Duration d) => _agora = _agora.add(d);

  @override
  Future<void> dormir(Duration duracao) async {
    _agora = _agora.add(duracao);
  }
}
