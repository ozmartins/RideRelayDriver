import 'relogio.dart';

/// Leitura do `uiautomator dump` e esperas por condição (FR-020, D3).

class Retangulo {
  const Retangulo(this.esquerda, this.topo, this.direita, this.base);

  final int esquerda;
  final int topo;
  final int direita;
  final int base;

  int get centroX => (esquerda + direita) ~/ 2;
  int get centroY => (topo + base) ~/ 2;
}

class No {
  No({
    required this.texto,
    required this.descricao,
    required this.limites,
    required this.clicavel,
    required this.habilitado,
    this.pai,
  });

  final String texto;
  final String descricao;
  final Retangulo limites;
  final bool clicavel;
  final bool habilitado;
  final No? pai;
  final List<No> filhos = [];

  bool contem(String rotulo) =>
      texto.contains(rotulo) || descricao.contains(rotulo);

  /// Igualdade exata com [rotulo] (para rótulos curtos como "OK").
  bool igual(String rotulo) => texto == rotulo || descricao == rotulo;

  bool get semRotulo => texto.isEmpty && descricao.isEmpty;

  Iterable<No> get descendentes sync* {
    for (final f in filhos) {
      yield f;
      yield* f.descendentes;
    }
  }
}

class Tela {
  Tela._(this.raiz, this.todos, this.xml);

  /// Lê o XML do `uiautomator dump`. XML sem nós produz uma tela vazia.
  factory Tela.parse(String xml) {
    final raiz = No(
      texto: '',
      descricao: '',
      limites: const Retangulo(0, 0, 0, 0),
      clicavel: false,
      habilitado: true,
    );
    final todos = <No>[];
    final pilha = <No>[raiz];
    final marca = RegExp(
      r'<(/?)node((?:\s+[\w:.-]+="[^"]*")*)\s*(/?)>',
      dotAll: true,
    );
    for (final m in marca.allMatches(xml)) {
      final fecha = m.group(1) == '/';
      final autoFecha = m.group(3) == '/';
      if (fecha) {
        if (pilha.length > 1) pilha.removeLast();
        continue;
      }
      final atributos = _atributos(m.group(2) ?? '');
      final no = No(
        texto: atributos['text'] ?? '',
        descricao: atributos['content-desc'] ?? '',
        limites: _limites(atributos['bounds'] ?? ''),
        clicavel: atributos['clickable'] == 'true',
        habilitado: atributos['enabled'] != 'false',
        pai: pilha.last,
      );
      pilha.last.filhos.add(no);
      todos.add(no);
      if (!autoFecha) pilha.add(no);
    }
    return Tela._(raiz, todos, xml);
  }

  final No raiz;
  final List<No> todos;

  /// XML original. Só vive em memória, salvo quando a política de evidências
  /// permite gravar (D10).
  final String xml;

  /// Algum nó com [rotulo] em `text` ou `content-desc`.
  bool tem(String rotulo) => todos.any((n) => n.contem(rotulo));

  /// Primeiro nó com [rotulo].
  No? achar(String rotulo) {
    for (final n in todos) {
      if (n.contem(rotulo)) return n;
    }
    return null;
  }

  /// O elemento a tocar para [rotulo]: o próprio nó se clicável, senão o
  /// ancestral clicável mais próximo, senão o nó. Com [habilitado], só devolve
  /// elementos habilitados.
  No? botao(String rotulo, {bool habilitado = true, bool exato = false}) {
    for (final n in todos) {
      if (exato ? !n.igual(rotulo) : !n.contem(rotulo)) continue;
      No? alvo = n;
      while (alvo != null && !alvo.clicavel) {
        alvo = alvo.pai;
      }
      alvo ??= n;
      if (alvo.pai == null) alvo = n;
      if (habilitado && !alvo.habilitado) continue;
      return alvo;
    }
    return null;
  }

  /// As estrelas da avaliação: clicáveis **sem rótulo** dentro do menor
  /// contêiner que contém [ancora] ("Avalie a corrida") e ao menos [minimo]
  /// deles, da esquerda para a direita (D3).
  List<No> estrelas(String ancora, {int minimo = 5}) {
    final no = achar(ancora);
    if (no == null) return const [];
    No? contenedor = no.pai;
    while (contenedor != null) {
      final candidatos = [
        for (final d in contenedor.descendentes)
          if (d.clicavel &&
              d.semRotulo &&
              d.descendentes.every((x) => x.semRotulo))
            d,
      ];
      if (candidatos.length >= minimo) {
        candidatos.sort((a, b) => a.limites.esquerda - b.limites.esquerda);
        return candidatos;
      }
      contenedor = contenedor.pai;
    }
    return const [];
  }

  /// Todo o texto visível, para checagens de política (nunca gravado).
  String get textoVisivel =>
      todos.map((n) => '${n.texto} ${n.descricao}').join('\n');

  static Map<String, String> _atributos(String s) {
    final mapa = <String, String>{};
    for (final m in RegExp(r'([\w:.-]+)="([^"]*)"').allMatches(s)) {
      mapa[m.group(1)!] = _desescapar(m.group(2)!);
    }
    return mapa;
  }

  static Retangulo _limites(String s) {
    final m = RegExp(r'\[(-?\d+),(-?\d+)\]\[(-?\d+),(-?\d+)\]').firstMatch(s);
    if (m == null) return const Retangulo(0, 0, 0, 0);
    return Retangulo(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
      int.parse(m.group(4)!),
    );
  }

  static String _desescapar(String s) => s
      .replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
        return String.fromCharCode(int.parse(m.group(1)!));
      })
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&');
}

/// Espera por condição (FR-020): chama [sonda] até devolver não nulo ou até
/// [timeout]. Estouro devolve `null`, nunca lança.
Future<T?> esperarCondicao<T>(
  Relogio relogio,
  Future<T?> Function() sonda, {
  required Duration timeout,
  Duration intervalo = const Duration(milliseconds: 700),
}) async {
  final fim = relogio.agora().add(timeout);
  while (true) {
    final valor = await sonda();
    if (valor != null) return valor;
    if (!relogio.agora().isBefore(fim)) return null;
    await relogio.dormir(intervalo);
  }
}
