import 'dart:convert';

import 'package:dart_nostr/dart_nostr.dart' as nostr;
import 'package:latlong2/latlong.dart';

import '../domain/identity.dart';
import '../domain/nostr_event.dart';
import '../domain/ride_quote.dart';
import '../domain/ride_route_content.dart';
import 'key_store.dart';
import 'message_cipher.dart';
import 'prototype_marker.dart';

/// A chave guardada no armazenamento seguro não está no formato esperado.
///
/// Tratado como armazenamento corrompido em vez de motivo para gerar uma
/// identidade nova: substituir silenciosamente a identidade do motorista
/// apagaria sua presença na rede sem que ele soubesse.
class CorruptedIdentityStorage implements Exception {
  CorruptedIdentityStorage(this.detail);
  final String detail;

  @override
  String toString() => 'Identidade guardada em formato inválido: $detail';
}

/// Evento assinado, pronto para publicação.
class SignedEvent {
  const SignedEvent({required this.event, required this.payload});

  /// Representação de domínio, exibível na interface.
  final NostrEvent event;

  /// Payload serializado conforme o protocolo, com `id` e `sig`.
  final Map<String, dynamic> payload;
}

/// Cria, recupera e usa a identidade Nostr do motorista.
///
/// Único ponto do aplicativo que toca a chave privada. Recebe o armazenamento
/// por injeção (decisão D5), de modo que os testes rodam sem Keystore real.
class IdentityService {
  IdentityService(this._keyStore, {MessageCipher? cipher})
    : _cipher = cipher ?? MessageCipher();

  final KeyStore _keyStore;

  /// Cifra o `content` dos kinds com destinatário (emenda 17 do contrato).
  final MessageCipher _cipher;

  /// Chave de armazenamento da chave privada. Só a privada é guardada: a
  /// pública é derivada dela, evitando dois estados que podem divergir.
  static const String privateKeyStorageKey = 'nostr_private_key';

  /// Recupera a identidade existente ou cria uma na primeira execução (FR-004).
  ///
  /// Lança [CorruptedIdentityStorage] se o valor guardado estiver fora de
  /// formato e [KeyStoreUnavailable] se o armazenamento protegido falhar.
  Future<Identity> loadOrCreate() async {
    final stored = await _keyStore.read(privateKeyStorageKey);

    if (stored != null) {
      if (!Identity.isValidHexKey(stored)) {
        throw CorruptedIdentityStorage('${stored.length} caracteres');
      }
      return _fromPrivateKey(stored);
    }

    final generated = nostr.Nostr.instance.services.keys.generateKeyPair();
    await _keyStore.write(privateKeyStorageKey, generated.private);
    return Identity(publicKey: generated.public, privateKey: generated.private);
  }

  /// Assina um orçamento de carona (`kind: 20002`) em resposta à solicitação
  /// referenciada por [quote] (FR-011, FR-017 da feature 007; D4/D5 de
  /// `specs/007-receber-solicitacao-corrida/research.md`; campos do
  /// motorista e `etaMinutes` opcional, emenda 06, D2 de
  /// `specs/009-detalhes-do-orcamento/research.md`).
  ///
  /// Além da tag de marcador, inclui `["e", quote.requestId]`, referenciando
  /// o evento respondido — convenção padrão do NIP-01 para "responder a"
  /// outro evento (D5 de `specs/007-receber-solicitacao-corrida/research.md`).
  SignedEvent signRideQuote({
    required Identity identity,
    required RideQuote quote,
  }) {
    final keyPairs = nostr.NostrKeyPairs(private: identity.privateKey);
    final etaMinutes = quote.etaMinutes;
    final signed = nostr.NostrEvent.fromPartialData(
      kind: NostrEvent.kindRideQuote,
      // Emenda 17: só o autor da solicitação respondida lê o orçamento. Lança
      // `Nip44Exception` se não der para cifrar — nada é assinado em claro.
      content: _cipher.encryptFor(
        identity,
        quote.passengerPubkey,
        jsonEncode({
          'pricePerKm': quote.pricePerKm,
          'total': quote.total,
          'driverName': quote.driverName,
          'carBrand': quote.carBrand,
          'carModel': quote.carModel,
          'carYear': quote.carYear,
          // Chave omitida quando indisponível, nunca null/0 (D2 de
          // specs/009-detalhes-do-orcamento/research.md).
          'etaMinutes': ?etaMinutes,
        }),
      ),
      keyPairs: keyPairs,
      tags: [
        prototypeMarkerTag,
        ['e', quote.requestId],
        ['p', quote.passengerPubkey],
      ],
    );

    return SignedEvent(
      event: NostrEvent(
        id: signed.id!,
        authorPublicKey: signed.pubkey,
        createdAt: signed.createdAt!,
        kind: signed.kind!,
        content: signed.content!,
        isSignatureValid: signed.isVerified(),
      ),
      payload: {
        'id': signed.id,
        'pubkey': signed.pubkey,
        'created_at': signed.createdAt!.millisecondsSinceEpoch ~/ 1000,
        'kind': signed.kind,
        'tags': signed.tags ?? const <List<String>>[],
        'content': signed.content,
        'sig': signed.sig,
      },
    );
  }

  /// Assina a localização atual do motorista (`kind: 20005`), publicada
  /// enquanto ele estiver "Deslocando-se até o passageiro" (FR-007 a
  /// FR-009; emenda 08 do contrato, D2/D4 de `specs/010-iniciar-corrida/research.md`).
  ///
  /// [quoteId] e [passengerPubkey] vêm da `ActiveRide` corrente — a mesma
  /// convenção de tags `["e", ...]` + `["p", ...]` já usada pelos kinds
  /// 20003/20004.
  SignedEvent signDriverLocation({
    required Identity identity,
    required String quoteId,
    required String passengerPubkey,
    required double lat,
    required double lon,
  }) {
    return _signCorrelatedEvent(
      identity: identity,
      kind: NostrEvent.kindDriverLocation,
      quoteId: quoteId,
      passengerPubkey: passengerPubkey,
      content: jsonEncode({'lat': lat, 'lon': lon}),
    );
  }

  /// Assina o aviso de que uma corrida não pode mais ser atendida (`kind:
  /// 20006`), publicado quando uma segunda aceitação chega enquanto o
  /// motorista já está "Deslocando-se até o passageiro" (FR-010; emenda 08
  /// do contrato).
  SignedEvent signRideNoLongerAvailable({
    required Identity identity,
    required String quoteId,
    required String passengerPubkey,
  }) {
    return _signCorrelatedEvent(
      identity: identity,
      kind: NostrEvent.kindRideNoLongerAvailable,
      quoteId: quoteId,
      passengerPubkey: passengerPubkey,
      content: '',
    );
  }

  /// Assina o aviso de chegada do motorista (`kind: 20007`), publicado uma
  /// única vez por corrida quando a posição do motorista entra no raio de
  /// chegada do ponto de origem (FR-002; emenda 09 do contrato, feature
  /// 011).
  SignedEvent signArrivalNotice({
    required Identity identity,
    required String quoteId,
    required String passengerPubkey,
  }) {
    return _signCorrelatedEvent(
      identity: identity,
      kind: NostrEvent.kindArrivalNotice,
      quoteId: quoteId,
      passengerPubkey: passengerPubkey,
      content: '',
    );
  }

  /// Assina o aviso de chegada ao destino (`kind: 20009`), publicado uma
  /// única vez por corrida quando a posição do motorista entra no raio de
  /// 1 km do destino, durante "Em corrida" (FR-004; emenda 11 do contrato,
  /// feature 012).
  SignedEvent signDestinationArrival({
    required Identity identity,
    required String quoteId,
    required String passengerPubkey,
  }) {
    return _signCorrelatedEvent(
      identity: identity,
      kind: NostrEvent.kindDestinationArrival,
      quoteId: quoteId,
      passengerPubkey: passengerPubkey,
      content: '',
    );
  }

  /// Assina a rota da corrida (`kind: 20011`), publicada a cada trajeto até o
  /// destino calculado com sucesso durante "Em corrida" (emenda 13 do
  /// contrato, feature 017).
  ///
  /// [points] é codificado (e reduzido ao teto do contrato) por
  /// `RideRouteContent`; lança [ArgumentError] com menos de 2 pontos.
  SignedEvent signRideRoute({
    required Identity identity,
    required String quoteId,
    required String passengerPubkey,
    required List<LatLng> points,
  }) {
    return _signCorrelatedEvent(
      identity: identity,
      kind: NostrEvent.kindRideRoute,
      quoteId: quoteId,
      passengerPubkey: passengerPubkey,
      content: RideRouteContent.encode(points),
    );
  }

  /// Assina o cancelamento da corrida (`kind: 20012`), publicado uma única vez
  /// quando o motorista cancela a corrida ativa (emenda 14 do contrato,
  /// feature 018). `content` vazio: não há motivo nem posição.
  SignedEvent signRideCancelled({
    required Identity identity,
    required String quoteId,
    required String passengerPubkey,
  }) {
    return _signCorrelatedEvent(
      identity: identity,
      kind: NostrEvent.kindRideCancelled,
      quoteId: quoteId,
      passengerPubkey: passengerPubkey,
      content: '',
    );
  }

  /// Decifra o `content` de um [event] recebido (emenda 17, regra de recepção
  /// 7), **depois** de a assinatura ter sido verificada pelo `EventFeed`.
  ///
  /// Devolve `null` — e o chamador descarta o evento em silêncio, sem efeito —
  /// se a tag `p` não for a chave desta [identity], se o conteúdo estiver em
  /// claro, adulterado ou cifrado a outra chave, ou, com [emptyMarker] (os
  /// kinds sem dado próprio: `20003`, `20008`, `20010`), se o texto decifrado
  /// não for exatamente `{}`. Nunca lança nem registra chave ou texto.
  String? decryptContent({
    required Identity identity,
    required NostrEvent event,
    bool emptyMarker = false,
  }) {
    if (event.recipientPublicKey != identity.publicKey) return null;
    return _cipher.decryptFrom(
      identity,
      event.authorPublicKey,
      event.content,
      emptyMarker: emptyMarker,
    );
  }

  /// Assina um evento no formato comum aos kinds 20005/20006/20007/20009/20011/20012:
  /// marcador do protótipo + `["e", quoteId]` + `["p", passengerPubkey]`, com o
  /// `content` cifrado ao passageiro (emenda 17).
  SignedEvent _signCorrelatedEvent({
    required Identity identity,
    required int kind,
    required String quoteId,
    required String passengerPubkey,
    required String content,
  }) {
    final keyPairs = nostr.NostrKeyPairs(private: identity.privateKey);
    final signed = nostr.NostrEvent.fromPartialData(
      kind: kind,
      // Emenda 17: cifrado ao passageiro (texto vazio vira `{}`); lança
      // `Nip44Exception` se não der — nada é assinado em claro (FR-004).
      content: _cipher.encryptFor(identity, passengerPubkey, content),
      keyPairs: keyPairs,
      tags: [
        prototypeMarkerTag,
        ['e', quoteId],
        ['p', passengerPubkey],
      ],
    );

    return SignedEvent(
      event: NostrEvent(
        id: signed.id!,
        authorPublicKey: signed.pubkey,
        createdAt: signed.createdAt!,
        kind: signed.kind!,
        content: signed.content!,
        isSignatureValid: signed.isVerified(),
        tags: (signed.tags ?? const [])
            .map((t) => t.map((e) => e.toString()).toList())
            .toList(),
      ),
      payload: {
        'id': signed.id,
        'pubkey': signed.pubkey,
        'created_at': signed.createdAt!.millisecondsSinceEpoch ~/ 1000,
        'kind': signed.kind,
        'tags': signed.tags ?? const <List<String>>[],
        'content': signed.content,
        'sig': signed.sig,
      },
    );
  }

  Identity _fromPrivateKey(String privateKey) {
    final publicKey = nostr.Nostr.instance.services.keys.derivePublicKey(
      privateKey: privateKey,
    );
    return Identity(publicKey: publicKey, privateKey: privateKey);
  }
}
