/// Lista padrão de relays embutida no aplicativo (decisão D10).
///
/// **MUST ser idêntica à lista da app do passageiro**
/// (`Prototipo/passenger/lib/shared/default_relays.dart`). É o relay em comum
/// que permite o passageiro receber o que o motorista publica — não existe
/// canal direto entre as duas apps. Alterar aqui exige alterar lá na mesma
/// mudança.
///
/// Verificados em 16/09/2026 publicando um evento assinado e recuperando-o por
/// uma conexão separada — não apenas por documento NIP-11, que só prova que o
/// relay responde HTTP e não que aceita publicação. Os três completaram a ida e
/// volta abaixo de 1,4 s.
///
/// `wss://relay.damus.io` foi **removido** nessa verificação: apesar de ser o
/// relay mais difundido do ecossistema, falhou a conexão em 1 de 3 tentativas
/// consecutivas. A instabilidade apareceria como ruído nas medições de SC-001 e
/// SC-009. Reserva já verificada, caso algum dos três caia: `wss://nostr.mom`.
///
/// A lista é volátil por natureza — relays saem do ar —, por isso o aplicativo
/// trata `unavailable` como estado normal.
const List<String> defaultRelayUrls = <String>[
  'wss://nos.lol',
  'wss://relay.primal.net',
  'wss://offchain.pub',
];
