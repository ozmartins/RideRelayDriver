import 'dart:io';

import 'adb.dart';
import 'config.dart';
import 'relogio.dart';
import 'telas.dart';
import 'ui.dart';

/// Preparo da execução (FR-006, FR-007, FR-014): confere os emuladores, apaga
/// os dados dos apps, concede permissões, refaz os cadastros e lê as chaves
/// **públicas**. Nada aqui grava dump nem captura: as telas de cadastro,
/// relays e identidade são sensíveis (D10).

/// Pré-condição não atendida: nada foi executado nem apagado (saída 2).
class PreCondicaoFalha implements Exception {
  PreCondicaoFalha(this.mensagem);

  final String mensagem;

  @override
  String toString() => mensagem;
}

class AmbienteVerificado {
  const AmbienteVerificado({
    required this.serialMotorista,
    required this.serialPassageiro,
    required this.descricao,
  });

  final String serialMotorista;
  final String serialPassageiro;

  /// Metadados do relatório (FR-030): AVDs, API, ABI, seriais e relays.
  final Map<String, Object?> descricao;
}

const List<String> permissoesConcedidas = <String>[
  'android.permission.ACCESS_FINE_LOCATION',
  'android.permission.ACCESS_COARSE_LOCATION',
  'android.permission.POST_NOTIFICATIONS',
];

/// Dois emuladores online, com os AVDs esperados, API 34 e x86_64 (FR-006).
Future<AmbienteVerificado> verificarEmuladores(
  Adb adb, {
  String avdDoMotorista = avdMotorista,
  String avdDoPassageiro = avdPassageiro,
}) async {
  final List<String> seriais;
  try {
    seriais = await adb.dispositivos();
  } on AdbFalha catch (e) {
    throw PreCondicaoFalha('adb indisponível: ${e.mensagem}');
  }
  if (seriais.length < 2) {
    throw PreCondicaoFalha(
      'são necessários dois emuladores online; encontrados ${seriais.length}',
    );
  }
  final porAvd = <String, String>{};
  for (final s in seriais) {
    porAvd[await adb.nomeAvd(s)] = s;
  }
  final mot = porAvd[avdDoMotorista];
  final pax = porAvd[avdDoPassageiro];
  if (mot == null || pax == null) {
    throw PreCondicaoFalha(
      'AVDs esperados: $avdDoMotorista e $avdDoPassageiro; online: '
      '${porAvd.keys.join(', ')}',
    );
  }
  final descricao = <String, Object?>{
    'avd_motorista': avdDoMotorista,
    'avd_passageiro': avdDoPassageiro,
    'serial_motorista': mot,
    'serial_passageiro': pax,
    'relays': relaysDoRoteiro,
  };
  for (final (papel, serial) in [('motorista', mot), ('passageiro', pax)]) {
    final api = await adb.propriedade(serial, 'ro.build.version.sdk');
    final abi = await adb.propriedade(serial, 'ro.product.cpu.abi');
    final modelo = await adb.propriedade(serial, 'ro.product.model');
    if (api != '34') {
      throw PreCondicaoFalha('emulador do $papel com API $api (esperada: 34)');
    }
    if (abi != 'x86_64') {
      throw PreCondicaoFalha(
        'emulador do $papel com ABI $abi (esperada: x86_64)',
      );
    }
    descricao['api'] = api;
    descricao['abi'] = abi;
    descricao['modelo_$papel'] = modelo;
  }
  return AmbienteVerificado(
    serialMotorista: mot,
    serialPassageiro: pax,
    descricao: descricao,
  );
}

/// Um emulador online com o AVD [avd], API 34 e x86_64 (FR-006), para a máquina
/// que opera só o emulador do seu [papel] (`contracts/coordenacao.md`).
Future<({String serial, Map<String, Object?> descricao})> verificarEmulador(
  Adb adb, {
  required String avd,
  required String papel,
}) async {
  final List<String> seriais;
  try {
    seriais = await adb.dispositivos();
  } on AdbFalha catch (e) {
    throw PreCondicaoFalha('adb indisponível: ${e.mensagem}');
  }
  String? serial;
  final online = <String>[];
  for (final s in seriais) {
    final nome = await adb.nomeAvd(s);
    online.add(nome);
    if (nome == avd) serial = s;
  }
  if (serial == null) {
    throw PreCondicaoFalha(
      'AVD esperado: $avd; online: ${online.isEmpty ? 'nenhum' : online.join(', ')}',
    );
  }
  final api = await adb.propriedade(serial, 'ro.build.version.sdk');
  final abi = await adb.propriedade(serial, 'ro.product.cpu.abi');
  final modelo = await adb.propriedade(serial, 'ro.product.model');
  if (api != '34') {
    throw PreCondicaoFalha('emulador do $papel com API $api (esperada: 34)');
  }
  if (abi != 'x86_64') {
    throw PreCondicaoFalha(
      'emulador do $papel com ABI $abi (esperada: x86_64)',
    );
  }
  return (
    serial: serial,
    descricao: <String, Object?>{
      'avd_$papel': avd,
      'serial_$papel': serial,
      'api': api,
      'abi': abi,
      'modelo_$papel': modelo,
      'relays': relaysDoRoteiro,
    },
  );
}

/// `pm clear` seguido da concessão das permissões (evita os diálogos).
Future<void> limparEConceder(Adb adb, String serial, String pacote) async {
  await adb.pmClear(serial, pacote);
  for (final p in permissoesConcedidas) {
    await adb.pmGrant(serial, pacote, p);
  }
}

const int _teclaVoltar = 4;
const int _teclaEnter = 66;

/// Abre "Mais" e o item [item]; devolve a tela com [aguardar] visível.
Future<Tela> _abrirEmMais(
  Adb adb,
  Relogio relogio,
  String serial,
  String item,
  String aguardar,
) async {
  var tela = Tela.parse(await adb.dump(serial));
  if (!tela.tem(item)) {
    // No dump a aba é "Mais\nTab 2 of 2".
    final mais = tela.botao('Mais\nTab');
    if (mais == null) throw PreCondicaoFalha('aba "Mais" não encontrada');
    await adb.tocar(serial, mais.limites.centroX, mais.limites.centroY);
  }
  final comItem = await esperarCondicao<Tela>(relogio, () async {
    final t = Tela.parse(await adb.dump(serial));
    return t.botao(item) != null ? t : null;
  }, timeout: const Limites().elementoLocal);
  if (comItem == null) throw PreCondicaoFalha('"$item" não encontrado');
  final alvo = comItem.botao(item)!;
  await adb.tocar(serial, alvo.limites.centroX, alvo.limites.centroY);
  final destino = await esperarCondicao<Tela>(relogio, () async {
    final t = Tela.parse(await adb.dump(serial));
    return t.tem(aguardar) ? t : null;
  }, timeout: const Limites().elementoLocal);
  if (destino == null) throw PreCondicaoFalha('tela "$aguardar" não abriu');
  tela = destino;
  return tela;
}

/// Volta da aba "Mais" ao mapa (aba "Mapa").
Future<void> _voltarAoMapa(Adb adb, Relogio relogio, String serial) async {
  final tela = await esperarCondicao<Tela>(relogio, () async {
    final t = Tela.parse(await adb.dump(serial));
    return t.botao('Mapa\nTab') != null ? t : null;
  }, timeout: const Limites().elementoLocal);
  if (tela == null) throw PreCondicaoFalha('aba "Mapa" não encontrada');
  final b = tela.botao('Mapa\nTab')!;
  await adb.tocar(serial, b.limites.centroX, b.limites.centroY);
}

final _hex64 = RegExp(r'(?<![0-9a-fA-F])[0-9a-fA-F]{64}(?![0-9a-fA-F])');

/// Lê a chave **pública** da tela "Minha identidade", só em memória, e volta.
Future<String> lerChavePublica(Adb adb, Relogio relogio, String serial) async {
  final tela = await _abrirEmMais(
    adb,
    relogio,
    serial,
    'Minha identidade',
    'Chave pública',
  );
  final m = _hex64.firstMatch(tela.textoVisivel);
  await adb.tecla(serial, _teclaVoltar);
  await _voltarAoMapa(adb, relogio, serial);
  if (m == null) {
    throw PreCondicaoFalha(
      'chave pública não encontrada na tela de identidade',
    );
  }
  return m.group(0)!.toLowerCase();
}

/// Lê as URLs da tela de relays, só em memória, e volta. Sem barra final.
Future<List<String>> lerRelaysDoApp(
  Adb adb,
  Relogio relogio,
  String serial,
) async {
  final tela = await _abrirEmMais(adb, relogio, serial, 'Relays', 'Reconectar');
  final urls = <String>[
    for (final m in RegExp(r'wss://[^\s"<>]+').allMatches(tela.textoVisivel))
      m.group(0)!.replaceAll(RegExp(r'/+$'), ''),
  ];
  await adb.tecla(serial, _teclaVoltar);
  await _voltarAoMapa(adb, relogio, serial);
  return urls.toSet().toList();
}

/// Recusa se a lista do app não for exatamente a lista completa (FR-007).
Future<void> conferirRelays(Adb adb, Relogio relogio, String serial) async {
  final urls = await lerRelaysDoApp(adb, relogio, serial);
  if (!verificarRelays(urls)) {
    throw PreCondicaoFalha(
      'lista de relays do app ($serial) difere da exigida: ${urls.join(', ')}',
    );
  }
}

// ---- cadastros (valores ASCII fixos; ver desvios.md: mapeamento a confirmar) ---

Future<void> _tocarRotulo(
  Adb adb,
  Relogio relogio,
  String serial,
  String rotulo, {
  bool exato = false,
  Duration? timeout,
}) async {
  final tela = await esperarCondicao<Tela>(relogio, () async {
    final t = Tela.parse(await adb.dump(serial));
    return t.botao(rotulo, exato: exato) != null ? t : null;
  }, timeout: timeout ?? const Limites().elementoLocal);
  if (tela == null) {
    throw PreCondicaoFalha('"$rotulo" não encontrado ($serial)');
  }
  final b = tela.botao(rotulo, exato: exato)!;
  await adb.tocar(serial, b.limites.centroX, b.limites.centroY);
}

/// Preenche o campo de texto de ordem [indice] (de cima para baixo). Os rótulos
/// dos campos do Flutter não aparecem no dump, então a ordem é o único
/// identificador. O ENTER fecha o teclado: o BACK, com o app em foco, sai dele.
Future<void> _preencher(
  Adb adb,
  Relogio relogio,
  String serial,
  int indice,
  String valor,
) async {
  final tela = await esperarCondicao<Tela>(relogio, () async {
    final t = Tela.parse(await adb.dump(serial));
    return t.campos().length > indice ? t : null;
  }, timeout: const Limites().elementoLocal);
  if (tela == null) {
    throw PreCondicaoFalha('campo de texto $indice não encontrado ($serial)');
  }
  final campo = tela.campos()[indice];
  await adb.tocar(serial, campo.limites.centroX, campo.limites.centroY);
  await adb.digitar(serial, valor);
  await adb.tecla(serial, _teclaEnter);
}

/// Abre a lista suspensa que mostra [placeholder] e escolhe o item com [item],
/// rolando a lista se preciso.
Future<void> _escolher(
  Adb adb,
  Relogio relogio,
  String serial,
  String placeholder,
  String item,
) async {
  await _tocarRotulo(adb, relogio, serial, placeholder);
  for (var i = 0; i < 8; i++) {
    final t = Tela.parse(await adb.dump(serial));
    final b = t.botao(item);
    if (b != null) {
      await adb.tocar(serial, b.limites.centroX, b.limites.centroY);
      return;
    }
    await adb.deslizar(serial, 500, 1600, 500, 600);
  }
  throw PreCondicaoFalha('item "$item" não encontrado na lista ($serial)');
}

Future<void> cadastrarPassageiro(
  Adb adb,
  Relogio relogio,
  String serial,
) async {
  await adb.iniciarApp(serial, pacotePassageiro);
  await _preencher(adb, relogio, serial, 0, 'Passageiro Teste');
  // O ENTER já grava o nome; se a tela de nome ainda estiver aberta, o botão
  // "Continuar" conclui.
  final mapa = await esperarCondicao<Tela>(relogio, () async {
    final t = Tela.parse(await adb.dump(serial));
    if (t.botao('Continuar') != null) {
      final b = t.botao('Continuar')!;
      await adb.tocar(serial, b.limites.centroX, b.limites.centroY);
      return null;
    }
    return t.botao(Rotulos.solicitar) != null ? t : null;
  }, timeout: const Duration(seconds: 30));
  if (mapa == null) throw PreCondicaoFalha('mapa do passageiro não abriu');
}

Future<void> cadastrarMotorista(Adb adb, Relogio relogio, String serial) async {
  await adb.iniciarApp(serial, pacoteMotorista);
  // Etapa 1: nome, UF, cidade; o raio fica no padrão (10 km).
  await _preencher(adb, relogio, serial, 0, 'Motorista Teste');
  await _escolher(adb, relogio, serial, 'Selecione', 'Santa Catarina');
  await _escolher(adb, relogio, serial, 'Selecione', 'Ararangu');
  await _tocarRotulo(adb, relogio, serial, 'Salvar e continuar');
  // Etapa 2: marca, modelo, ano, cor e placa, nesta ordem.
  for (final (i, v) in [
    (0, 'Fiat'),
    (1, 'Palio'),
    (2, '2018'),
    (3, 'Preto'),
    (4, 'ABC1D23'),
  ]) {
    await _preencher(adb, relogio, serial, i, v);
  }
  await _tocarRotulo(adb, relogio, serial, 'Salvar e continuar');
  // Etapa 3: forma de pagamento (a mesma que o passageiro escolhe) e preço.
  await _tocarRotulo(adb, relogio, serial, Rotulos.pix);
  await _preencher(adb, relogio, serial, 0, '2,50');
  await _tocarRotulo(adb, relogio, serial, 'Concluir cadastro');
  final mapa = await esperarCondicao<Tela>(relogio, () async {
    final t = Tela.parse(await adb.dump(serial));
    return t.tem(Rotulos.motoristaOnline) || t.tem(Rotulos.motoristaOffline)
        ? t
        : null;
  }, timeout: const Duration(seconds: 30));
  if (mapa == null) throw PreCondicaoFalha('mapa do motorista não abriu');
}

// ---- versões (FR-030) --------------------------------------------------------

/// Commit do repositório em [diretorio] e se há alterações não commitadas.
Future<Map<String, Object?>> lerVersao(String diretorio) async {
  try {
    final hash = await Process.run('git', [
      '-C',
      diretorio,
      'rev-parse',
      'HEAD',
    ]);
    final sujo = await Process.run('git', [
      '-C',
      diretorio,
      'status',
      '--porcelain',
    ]);
    if (hash.exitCode != 0) {
      return {
        'commit': null,
        'alteracoes_locais': null,
        'erro': 'git sem resposta',
      };
    }
    return {
      'commit': (hash.stdout as String).trim(),
      'alteracoes_locais': (sujo.stdout as String).trim().isNotEmpty,
    };
  } on ProcessException {
    return {
      'commit': null,
      'alteracoes_locais': null,
      'erro': 'git indisponível',
    };
  }
}
