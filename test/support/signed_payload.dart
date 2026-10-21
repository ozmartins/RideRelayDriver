import 'package:dart_nostr/dart_nostr.dart' as nostr;
import 'package:driver/domain/geohash.dart';
import 'package:driver/domain/nostr_event.dart' as domain;
import 'package:driver/services/prototype_marker.dart';

/// Evento **realmente assinado**, para que a verificação sob teste seja a
/// criptográfica de verdade, não um dublê que sempre aprova (Princípio II).
Map<String, dynamic> signedPayload({
  String content = 'evento de teste',
  int kind = domain.NostrEvent.kindRideRequest,
  nostr.NostrKeyPairs? keyPairs,
  List<List<String>>? tags,
  DateTime? createdAt,
}) {
  final keys = keyPairs ?? nostr.Nostr.instance.services.keys.generateKeyPair();
  final event = nostr.NostrEvent.fromPartialData(
    kind: kind,
    content: content,
    keyPairs: keys,
    tags: tags ?? [prototypeMarkerTag],
    createdAt: createdAt ?? DateTime.now().toUtc(),
  );
  return {
    'id': event.id,
    'pubkey': event.pubkey,
    'created_at': event.createdAt!.millisecondsSinceEpoch ~/ 1000,
    'kind': event.kind,
    'tags': event.tags,
    'content': event.content,
    'sig': event.sig,
  };
}

/// `content` válido de uma solicitação de corrida (emenda 04 do contrato).
String rideRequestContent({String payment = 'pix'}) =>
    '{"origin":{"lat":-28.9298,"lon":-49.4753},'
    '"destination":{"lat":-28.6721,"lon":-49.3671},'
    '"payment":"$payment"}';

/// As três tags `g` de uma solicitação de corrida com origem em ([lat], [lon]),
/// como o passageiro as publica (emenda 27 do contrato): o geohash da origem em
/// 5, 4 e 3 caracteres.
List<List<String>> tagsG(double lat, double lon) => [
  for (final p in kPrecisoesDaTag) ['g', Geohash.encode(lat, lon, p)],
];

/// Origem do [rideRequestContent] (Araranguá), e a mesma que as solicitações
/// de teste dos testes de tela usam por padrão.
const double origemDeTesteLat = -28.9298;
const double origemDeTesteLon = -49.4753;

/// Tags de uma solicitação de teste: marcador do protótipo e `g` da origem.
List<List<String>> tagsDeSolicitacao({
  double lat = origemDeTesteLat,
  double lon = origemDeTesteLon,
}) => [prototypeMarkerTag, ...tagsG(lat, lon)];
