import '../../../../tool/e2e/src/adb.dart';
import '../../../../tool/e2e/src/relogio.dart';
import 'relogio_falso.dart';

/// Elemento de tela do dublê: vira um `<node>` do `uiautomator dump`.
class ElementoFake {
  const ElementoFake(
    this.rotulo, {
    this.clicavel = false,
    this.habilitado = true,
    this.rotuloVisivel = true,
  });

  final String rotulo;
  final bool clicavel;
  final bool habilitado;

  /// Falso para ícones sem rótulo (as estrelas da avaliação).
  final bool rotuloVisivel;
}

/// `Adb` dublê: cada dispositivo tem uma lista de elementos; o `dump` os
/// transforma em XML e o `tocar` encontra o elemento pela coordenada.
class FakeAdb implements Adb {
  FakeAdb({this.relogio});

  final RelogioFalso? relogio;

  final Map<String, List<ElementoFake>> telas = {};
  final Map<String, String> avds = {};
  final Map<String, Map<String, String>> propriedades = {};
  final Map<String, int> epochs = {};
  final Map<String, bool> vivos = {};
  final Map<String, List<String>> logs = {};
  List<String> seriais = [];

  /// Registro de tudo que o roteiro fez, na ordem.
  final List<String> chamadas = [];
  final List<String> digitados = [];

  /// Chamado após cada toque em um elemento: (serial, rótulo, índice).
  void Function(String serial, ElementoFake elemento, int indice)? aoTocar;

  /// Chamado após cada `geo fix`.
  void Function(String serial, double lat, double lon)? aoGeoFix;

  /// Chamado após cada `digitar`.
  void Function(String serial, String texto)? aoDigitar;

  /// Se não nulo, todo comando lança [AdbFalha] com esta mensagem.
  String? falhaGeral;

  /// Não persiste capturas reais: devolve bytes fixos.
  List<int> pngFalso = [137, 80, 78, 71];

  static const int _altura = 100;

  void _verificar() {
    final f = falhaGeral;
    if (f != null) throw AdbFalha(f);
  }

  void _passar([int ms = 100]) => relogio?.avancar(Duration(milliseconds: ms));

  String xmlDe(String serial) {
    final itens = telas[serial] ?? const <ElementoFake>[];
    final b = StringBuffer('<?xml version="1.0"?><hierarchy rotation="0">');
    b.write(
      '<node text="" content-desc="" clickable="false" enabled="true" '
      'bounds="[0,0][1000,${(itens.length + 1) * _altura}]">',
    );
    for (var i = 0; i < itens.length; i++) {
      final e = itens[i];
      final rotulo = e.rotuloVisivel ? _esc(e.rotulo) : '';
      b.write(
        '<node text="$rotulo" content-desc="" '
        'clickable="${e.clicavel}" enabled="${e.habilitado}" '
        'bounds="[0,${i * _altura}][1000,${(i + 1) * _altura}]" />',
      );
    }
    b.write('</node></hierarchy>');
    return b.toString();
  }

  String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('"', '&quot;');

  @override
  Future<String> dump(String serial) async {
    _verificar();
    chamadas.add('dump:$serial');
    _passar(50);
    return xmlDe(serial);
  }

  @override
  Future<void> tocar(String serial, int x, int y) async {
    _verificar();
    final itens = telas[serial] ?? const <ElementoFake>[];
    final indice = y ~/ _altura;
    chamadas.add('tocar:$serial:$indice');
    _passar(100);
    if (indice >= 0 && indice < itens.length) {
      final e = itens[indice];
      chamadas.add('toque:$serial:${e.rotulo}');
      aoTocar?.call(serial, e, indice);
    }
  }

  @override
  Future<void> geoFix(String serial, double lat, double lon) async {
    _verificar();
    chamadas.add('geofix:$serial:$lat,$lon');
    _passar(50);
    aoGeoFix?.call(serial, lat, lon);
  }

  @override
  Future<void> digitar(String serial, String texto) async {
    _verificar();
    digitados.add(texto);
    chamadas.add('digitar:$serial');
    _passar(100);
    aoDigitar?.call(serial, texto);
  }

  @override
  Future<List<int>> captura(String serial) async {
    _verificar();
    chamadas.add('captura:$serial');
    return pngFalso;
  }

  @override
  Future<List<String>> logcat(String serial) async {
    _verificar();
    return logs[serial] ?? const [];
  }

  @override
  Future<void> limparLogcat(String serial) async {
    _verificar();
    chamadas.add('logcat-c:$serial');
    logs[serial] = [];
  }

  @override
  Future<List<String>> dispositivos() async {
    _verificar();
    return seriais;
  }

  @override
  Future<String> nomeAvd(String serial) async {
    _verificar();
    return avds[serial] ?? 'desconhecido';
  }

  @override
  Future<String> propriedade(String serial, String nome) async {
    _verificar();
    return propriedades[serial]?[nome] ?? '';
  }

  @override
  Future<int> epochEmulador(String serial) async {
    _verificar();
    return epochs[serial] ??
        (relogio ?? const _AgoraReal()).agora().millisecondsSinceEpoch ~/ 1000;
  }

  @override
  Future<void> iniciarApp(String serial, String pacote) async {
    _verificar();
    chamadas.add('iniciar:$serial:$pacote');
  }

  @override
  Future<bool> processoVivo(String serial, String pacote) async {
    _verificar();
    return vivos['$serial:$pacote'] ?? true;
  }

  @override
  Future<void> pmClear(String serial, String pacote) async {
    _verificar();
    chamadas.add('pm-clear:$serial:$pacote');
  }

  @override
  Future<void> pmGrant(String serial, String pacote, String permissao) async {
    _verificar();
    chamadas.add('pm-grant:$serial:$pacote:$permissao');
  }

  @override
  Future<void> tecla(String serial, int codigo) async {
    _verificar();
    chamadas.add('tecla:$serial:$codigo');
    aoTecla?.call(serial, codigo);
  }

  /// Chamado após cada tecla (o 4 é o botão voltar).
  void Function(String serial, int codigo)? aoTecla;

  @override
  Future<void> deslizar(
    String serial,
    int x1,
    int y1,
    int x2,
    int y2, {
    int duracaoMs = 300,
  }) async {
    _verificar();
    chamadas.add('deslizar:$serial');
    aoDeslizar?.call(serial);
  }

  /// Chamado após cada deslize.
  void Function(String serial)? aoDeslizar;
}

class _AgoraReal implements Relogio {
  const _AgoraReal();

  @override
  DateTime agora() => DateTime.now().toUtc();

  @override
  Future<void> dormir(Duration duracao) => Future<void>.delayed(duracao);
}
