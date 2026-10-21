import 'reputation.dart';

/// Orçamento que o motorista está enviando (ou já enviou) para uma
/// [RideRequestReceived] — `data-model.md` da feature 007, ampliado pela
/// feature 009 com os dados do motorista/veículo e o tempo estimado.
class RideQuote {
  const RideQuote({
    required this.requestId,
    required this.passengerPubkey,
    required this.pricePerKm,
    required this.total,
    required this.driverName,
    required this.carBrand,
    required this.carModel,
    required this.carYear,
    this.etaMinutes,
    this.reputation,
  });

  /// Copiado de `RideRequestReceived.requestId` — vira a tag `["e", ...]`
  /// do evento publicado (FR-017 da feature 007).
  final String requestId;

  /// Copiado de `RideRequestReceived.passengerPubkey` — vira a tag
  /// `["p", ...]` e a chave pública com que o orçamento é cifrado (emenda 17).
  final String passengerPubkey;

  /// Preço usado nesta corrida — pode diferir do preço padrão do cadastro
  /// (FR-006, FR-007 da feature 007).
  final double pricePerKm;

  /// `pricePerKm` multiplicado pela distância entre origem e destino, em
  /// quilômetros — calculado por quem monta este `RideQuote`.
  final double total;

  /// Copiado de `DriverProfile.nome` no momento do envio (FR-001 da feature
  /// 009).
  final String driverName;

  /// Copiados de `DriverProfile.marcaVeiculo`/`modeloVeiculo` (FR-001).
  final String carBrand;
  final String carModel;

  /// Copiado de `DriverProfile.anoVeiculo` (feature 008; FR-001).
  final int carYear;

  /// Tempo estimado do trajeto motorista→origem, em minutos, derivado da
  /// duração devolvida pelo `RouteDistanceService.estimate` (FR-002 de
  /// `specs/009-detalhes-do-orcamento/spec.md`). `null` quando essa duração
  /// não estava disponível — nunca um valor inventado (FR-003).
  final int? etaMinutes;

  /// Reputação própria do motorista (emenda 25), declarada no orçamento.
  /// `null` — e a chave omitida do `content` — quando ele não tem recibos.
  final Reputation? reputation;

  @override
  String toString() =>
      'RideQuote($requestId, $driverName, $carBrand $carModel $carYear, '
      'R\$$pricePerKm/km, total: R\$$total, eta: ${etaMinutes ?? "—"}min)';
}
