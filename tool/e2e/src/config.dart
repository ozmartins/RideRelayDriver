import 'package:driver/services/default_relays.dart';

/// Parâmetros fixos da avaliação (feature 029). Tudo aqui é o que o TCC afirma
/// ter sido usado: alterar um valor durante a execução exige registro em
/// `desvios.md` (FR-040).

/// Lista completa dos três relays públicos (FR-007). Nunca reduzida.
const List<String> relaysDoRoteiro = defaultRelayUrls;

/// Os três relays exigidos pelo spec.
const List<String> relaysEsperados = <String>[
  'wss://nos.lol',
  'wss://relay.primal.net',
  'wss://offchain.pub',
];

/// Verdadeiro só se [urls] for exatamente a lista completa exigida (FR-007).
bool verificarRelays(List<String> urls) =>
    urls.length == relaysEsperados.length &&
    {...urls}.containsAll(relaysEsperados);

const String pacoteMotorista = 'br.ufsc.tcc.corridas.driver';
const String pacotePassageiro = 'br.ufsc.tcc.corridas.passenger';

const String avdMotorista = 'Pixel_6_API34_1';
const String avdPassageiro = 'Pixel_6_API34_2';

class PontoGeo {
  const PontoGeo(this.lat, this.lon);

  final double lat;
  final double lon;
}

/// Coordenadas fixas (D14 do research). A partida do motorista fica a cerca de
/// 2 km da origem, dentro do raio de atendimento padrão (10 km); o destino fica
/// a mais de 1 km do ponto de encontro. A coordenada do destino precisa estar a
/// no máximo 1 km do ponto que o Photon devolve para [destinoBusca]: conferir
/// uma vez no ensaio e registrar em `desvios.md`.
const PontoGeo partidaDoMotorista = PontoGeo(-28.9150, -49.4900);
const PontoGeo pontoDeEncontro = PontoGeo(-28.9298, -49.4753);
const PontoGeo destinoDaCorrida = PontoGeo(-28.9503, -49.4967);

/// Texto digitado na busca de endereço (só ASCII, por causa do `input text`) e
/// trecho que o resultado escolhido deve conter.
const String destinoBusca = 'Universidade Federal de Santa Catarina Ararangua';
const String destinoResultadoContem = 'Ararangu';

/// Limites de tempo (D7): escolhidos, **não medidos**.
class Limites {
  const Limites();

  Duration get elementoLocal => const Duration(seconds: 15);
  Duration get buscaPhoton => const Duration(seconds: 30);
  Duration get efeitoRemoto => const Duration(seconds: 45);
  Duration get rota => const Duration(seconds: 45);
  Duration get posicionamento => const Duration(seconds: 30);
  Duration get etapa => const Duration(seconds: 60);

  /// Etapas que incluem a busca no Photon (E02) ou o cálculo de rota (E04):
  /// somam duas esperas e por isso têm teto maior que o geral (desvio D7).
  Duration get etapaComBusca => const Duration(seconds: 120);
  Duration get etapaComRota => const Duration(seconds: 90);
  Duration get voltaAoInicio => const Duration(seconds: 60);
  Duration get ciclo => const Duration(minutes: 5);
  Duration get periodo => const Duration(hours: 3);
}

const int metaValidosPorPeriodo = 30;
const int tetoPeriodo1 = 40;
const int tetoTotal = 80;

/// Teto de ciclos executados no período (FR-013): 40 no período 1; no período 2,
/// 80 menos os executados no 1.
int tetoDoPeriodo(int periodo, {int? executadosPeriodo1}) {
  if (periodo == 1) return tetoPeriodo1;
  final saldo = tetoTotal - (executadosPeriodo1 ?? tetoPeriodo1);
  return saldo < 0 ? 0 : saldo;
}

/// Margem do `since` do observador (F1 da análise): o `created_at` vem do relógio
/// do emulador, que pode estar atrasado em relação ao do hospedeiro.
const Duration margemSinceObservador = Duration(minutes: 10);
