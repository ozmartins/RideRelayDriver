/// Marcador que identifica o tráfego deste protótipo na rede Nostr.
///
/// Definido na emenda 01 do contrato de eventos (16/09/2026). Sem ele, a
/// inscrição entregaria qualquer evento de terceiros que use os mesmos kinds.
///
/// **Não é mecanismo de segurança**: qualquer pessoa pode publicar com a mesma
/// tag. A confiança continua vindo da verificação de assinatura e da checagem
/// de autoria.
const String prototypeMarker = 'tcc-ufsc-caronas';

/// A tag como ela aparece no evento: `["t", "tcc-ufsc-caronas"]`.
const List<String> prototypeMarkerTag = <String>['t', prototypeMarker];

/// Verdadeiro se a lista de tags do evento traz o marcador do protótipo.
bool hasPrototypeMarker(List<dynamic>? tags) {
  if (tags == null) return false;
  for (final tag in tags) {
    if (tag is! List || tag.length < 2) continue;
    if (tag[0].toString() == 't' && tag[1].toString() == prototypeMarker) {
      return true;
    }
  }
  return false;
}
