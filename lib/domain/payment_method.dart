/// Forma de pagamento aceita pelo motorista (Key Entities do `spec.md` da
/// feature 005).
///
/// Não é mutuamente exclusiva: um motorista pode aceitar qualquer combinação
/// das três (FR-001, FR-002). Não tem contrapartida no enum equivalente do
/// app do passageiro — cada app tem o seu próprio tipo, como já é o padrão
/// deste protótipo (Assumptions do `spec.md`). O que os dois apps trocam é o
/// texto do campo `payment` do `kind: 20001` ([wireValue]), definido pelo
/// contrato de eventos.
enum PaymentMethod {
  cash('Dinheiro', 'cash', 'dinheiro'),
  pix('PIX', 'pix', 'pix'),
  card('Cartão', 'card', 'cartao');

  const PaymentMethod(this.label, this.storageValue, this.wireValue);

  /// Texto exibido ao motorista no formulário de cadastro.
  final String label;

  /// Valor gravado na coluna `payment_methods` (D2 de
  /// `specs/005-formas-pagamento/research.md`).
  final String storageValue;

  /// Valor do campo `payment` da solicitação de corrida (`kind: 20001`,
  /// emenda 04 do contrato de eventos).
  final String wireValue;

  /// A forma de pagamento que corresponde a [wire], ou `null` se o valor não
  /// é um dos três do contrato.
  static PaymentMethod? fromWire(String wire) {
    for (final metodo in values) {
      if (metodo.wireValue == wire) return metodo;
    }
    return null;
  }
}
