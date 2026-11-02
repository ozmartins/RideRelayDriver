import 'dart:typed_data';

import '../domain/identity.dart';
import 'nip44.dart';

/// Texto cifrado nos kinds que não carregam dado próprio (`20003`, `20004`,
/// `20006`, `20007`, `20008`, `20009`, `20010`, `20012`): o NIP-44 rejeita
/// texto de entrada vazio, então o `content` vazio de antes vira este objeto
/// JSON vazio (emenda 17 do contrato, D2 de
/// `specs/019-mensagens-cifradas/research.md`).
const String emptyContentMarker = '{}';

/// Política de cifragem do contrato (emenda 17) sobre o [Nip44] puro.
///
/// Guarda, só em memória, a chave de conversa de cada par: o ECDH é o passo
/// caro e a localização sai a cada 5 s (D4). A chave de conversa nunca é
/// persistida, registrada em log nem exibida (Princípio I).
class MessageCipher {
  MessageCipher({this.maxCachedPeers = 64});

  /// Quantos pares mantêm a chave em cache; passado o limite, o mais antigo
  /// sai. Uma corrida ativa usa um par; o resto são orçamentos.
  final int maxCachedPeers;

  final Map<String, Uint8List> _cache = {};
  int _derivations = 0;

  /// Quantas vezes o ECDH foi calculado (para os testes verificarem o cache).
  int get derivationCount => _derivations;

  /// Cifra [plaintext] da [identity] para [peerPubkey]. Texto vazio vira
  /// [emptyContentMarker]. Lança [Nip44Exception] se não for possível cifrar
  /// — quem chama NUNCA publica em claro como alternativa (FR-004).
  String encryptFor(Identity identity, String peerPubkey, String plaintext) {
    final texto = plaintext.isEmpty ? emptyContentMarker : plaintext;
    return Nip44.encrypt(texto, _conversationKey(identity, peerPubkey));
  }

  /// Decifra [payload] vindo de [peerPubkey]. Devolve `null` em qualquer
  /// falha — chave inválida, MAC, padding, conteúdo em claro — sem lançar e
  /// sem registrar nada (FR-006, FR-009). Com [emptyMarker], o texto
  /// decifrado precisa ser exatamente [emptyContentMarker].
  String? decryptFrom(
    Identity identity,
    String peerPubkey,
    String payload, {
    bool emptyMarker = false,
  }) {
    try {
      final texto = Nip44.decrypt(
        payload,
        _conversationKey(identity, peerPubkey),
      );
      if (emptyMarker && texto != emptyContentMarker) return null;
      return texto;
    } on Object {
      return null;
    }
  }

  Uint8List _conversationKey(Identity identity, String peerPubkey) {
    final chave = '${identity.publicKey}:$peerPubkey';
    final existente = _cache[chave];
    if (existente != null) return existente;

    final nova = Nip44.conversationKey(identity.privateKey, peerPubkey);
    _derivations++;
    if (_cache.length >= maxCachedPeers) _cache.remove(_cache.keys.first);
    _cache[chave] = nova;
    return nova;
  }
}
