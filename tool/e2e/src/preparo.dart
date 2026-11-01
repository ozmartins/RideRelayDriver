import 'dart:io';

import 'adb.dart';
import 'config.dart';
import 'relogio.dart';
import 'telas.dart';
import 'ui.dart';

/// Preparo de um período (FR-006, FR-007, FR-014): confere os emuladores, apaga
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

/// `pm clear` seguido da concessão das permissões (evita os diálogos).
Future<void> limparEConceder(Adb adb, String serial, String pacote) async {
  await adb.pmClear(serial, pacote);
  for (final p in permissoesConcedidas) {
    await adb.pmGrant(serial, pacote, p);
  }
}

const int _teclaVoltar = 4;

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
    final mais = tela.botao('Mais', exato: true);
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
  final tela = await _abrirEmMais(
    adb,
    relogio,
    serial,
    'Relays',
    'Servidores por onde o app se comunica',
  );
  final urls = <String>[
    for (final m in RegExp(r'wss://[^\s"<>]+').allMatches(tela.textoVisivel))
      m.group(0)!.replaceAll(RegExp(r'/+$'), ''),
  ];
  await adb.tecla(serial, _teclaVoltar);
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

Future<void> _preencher(
  Adb adb,
  Relogio relogio,
  String serial,
  String rotulo,
  String valor,
) async {
  await _tocarRotulo(adb, relogio, serial, rotulo);
  await adb.digitar(serial, valor);
  await adb.tecla(serial, _teclaVoltar); // fecha o teclado
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
  await _preencher(adb, relogio, serial, 'Nome ou apelido', 'Passageiro Teste');
  await _tocarRotulo(adb, relogio, serial, 'Continuar');
  final mapa = await esperarCondicao<Tela>(relogio, () async {
    final t = Tela.parse(await adb.dump(serial));
    return t.tem(Rotulos.campoDestino) ? t : null;
  }, timeout: const Duration(seconds: 30));
  if (mapa == null) throw PreCondicaoFalha('mapa do passageiro não abriu');
}

Future<void> cadastrarMotorista(Adb adb, Relogio relogio, String serial) async {
  await adb.iniciarApp(serial, pacoteMotorista);
  // Etapa 1: dados pessoais e raio (padrão 10 km).
  await _preencher(adb, relogio, serial, 'Nome', 'Motorista Teste');
  await _escolher(adb, relogio, serial, 'Selecione', 'Santa Catarina');
  await _escolher(adb, relogio, serial, 'Selecione', 'Ararangu');
  await _tocarRotulo(adb, relogio, serial, 'Salvar e continuar');
  // Etapa 2: veículo.
  await _preencher(adb, relogio, serial, 'Marca', 'Fiat');
  await _preencher(adb, relogio, serial, 'Modelo', 'Palio');
  await _preencher(adb, relogio, serial, 'Ano', '2018');
  await _preencher(adb, relogio, serial, 'Cor', 'Preto');
  await _preencher(adb, relogio, serial, 'Placa', 'ABC1D23');
  await _tocarRotulo(adb, relogio, serial, 'Salvar e continuar');
  // Etapa 3: financeiro.
  await _tocarRotulo(adb, relogio, serial, 'Pix');
  await _preencher(adb, relogio, serial, 'Preço por quilômetro', '2,50');
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
