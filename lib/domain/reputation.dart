import 'receipt.dart';

/// Quantos recibos recentes (por `seq`) uma reputação apresenta (1.5 do
/// contrato, emenda 25).
const int kReputacaoJanela = 5;

/// Reputação que um usuário declara em `20001` (passageiro, em claro) ou
/// `20002` (motorista, cifrado) — emenda 25, seção 1.5.
///
/// Só [recibos] são verificáveis; [corridas], [avaliacoes] e [media] são
/// **declarados**. Ausente no `content` = usuário sem histórico.
class Reputation {
  const Reputation({
    required this.corridas,
    required this.avaliacoes,
    this.media,
    required this.seqProximo,
    this.head,
    required this.recibos,
  });

  /// Sem histórico: nenhum recibo, próximo `seq` é 0.
  const Reputation.empty()
    : corridas = 0,
      avaliacoes = 0,
      media = null,
      seqProximo = 0,
      head = null,
      recibos = const [];

  /// Decodificação estrita: [FormatException] para campo faltando, de tipo
  /// errado ou com mais de [kReputacaoJanela] recibos (limite do contrato; evita
  /// verificar listas arbitrariamente longas vindas de um relay). O conteúdo
  /// dos recibos é julgado depois, pelo verificador.
  factory Reputation.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      throw const FormatException('reputacao não é um objeto JSON');
    }
    final recibos = json['recibos'];
    if (recibos is! List || recibos.length > kReputacaoJanela) {
      throw const FormatException('reputacao.recibos ausente ou longo demais');
    }
    final media = json['media'];
    if (json.containsKey('media') && media is! num) {
      throw const FormatException('reputacao.media não numérica');
    }
    final head = json['head'];
    if (json.containsKey('head') &&
        (head is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(head))) {
      throw const FormatException('reputacao.head inválido');
    }
    return Reputation(
      corridas: _nonNegativeInt(json, 'corridas'),
      avaliacoes: _nonNegativeInt(json, 'avaliacoes'),
      media: json.containsKey('media') ? (media as num).toDouble() : null,
      seqProximo: _nonNegativeInt(json, 'seq_proximo'),
      head: json.containsKey('head') ? head as String : null,
      recibos: recibos.map(Receipt.fromJson).toList(growable: false),
    );
  }

  /// Nº de recibos guardados pelo declarante.
  final int corridas;

  /// Nº dos recibos que trazem nota.
  final int avaliacoes;

  /// Média das notas; `null` quando [avaliacoes] é 0.
  final double? media;

  /// Próximo `seq` a ser usado na cadeia do declarante.
  final int seqProximo;

  /// `idRecibo` do recibo `seqProximo − 1`; `null` quando [seqProximo] é 0.
  final String? head;

  /// Os mais recentes por `seq`, do mais novo ao mais antigo.
  final List<Receipt> recibos;

  /// JSON do contrato; `media` e `head` omitidos quando ausentes.
  Map<String, dynamic> toJson() => {
    'corridas': corridas,
    'avaliacoes': avaliacoes,
    'media': ?media,
    'seq_proximo': seqProximo,
    'head': ?head,
    'recibos': recibos.map((r) => r.toJson()).toList(),
  };

  @override
  bool operator ==(Object other) =>
      other is Reputation &&
      other.corridas == corridas &&
      other.avaliacoes == avaliacoes &&
      other.media == media &&
      other.seqProximo == seqProximo &&
      other.head == head &&
      _sameList(other.recibos, recibos);

  @override
  int get hashCode => Object.hash(
    corridas,
    avaliacoes,
    media,
    seqProximo,
    head,
    recibos.length,
  );

  @override
  String toString() =>
      'Reputation(corridas: $corridas, avaliacoes: $avaliacoes, '
      'seqProximo: $seqProximo, recibos: ${recibos.length})';

  static bool _sameList(List<Receipt> a, List<Receipt> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static int _nonNegativeInt(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! int || value < 0) {
      throw FormatException('campo "$key" ausente ou inválido');
    }
    return value;
  }
}
