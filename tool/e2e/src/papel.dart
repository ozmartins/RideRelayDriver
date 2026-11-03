import 'coordenacao.dart';
import 'preparo.dart';
import 'relogio.dart';

/// Troca das identidades entre as duas máquinas (`contracts/coordenacao.md`):
/// cada lado entrega a própria chave **pública** do app e a versão do código, e
/// recebe as do outro. A chave privada nunca sai do aparelho.

class IdentidadeDoOutro {
  const IdentidadeDoOutro({required this.pub, required this.versao});

  final String pub;
  final Map<String, Object?> versao;
}

final RegExp _hex64 = RegExp(r'^[0-9a-f]{64}$');

/// Só `commit` (texto) e `alteracoes_locais` (booleano) atravessam a rede.
Map<String, Object?> _versaoSegura(Object? v) {
  if (v is! Map) return const {'commit': null, 'alteracoes_locais': null};
  final commit = v['commit'];
  final alteracoes = v['alteracoes_locais'];
  return {
    'commit': commit is String && commit.length <= 64 ? commit : null,
    'alteracoes_locais': alteracoes is bool ? alteracoes : null,
  };
}

/// Usa a barreira `inicio-ciclo` do ciclo 0, que o laço nunca usa (os ciclos
/// começam em 1). Repete enquanto o outro lado não aparece, até [prazo].
Future<IdentidadeDoOutro> trocarIdentidades(
  Coordenacao coordenacao, {
  required String minhaPub,
  required Map<String, Object?> minhaVersao,
  required Relogio relogio,
  Duration prazo = const Duration(minutes: 10),
  Duration intervalo = const Duration(seconds: 5),
  void Function(String)? log,
}) async {
  final fim = relogio.agora().add(prazo);
  while (true) {
    try {
      final r = await coordenacao.barreira(
        'inicio-ciclo',
        0,
        dados: {'pub': minhaPub, 'versao': _versaoSegura(minhaVersao)},
      );
      switch (r.resultado) {
        case ResultadoBarreira.abortado:
          throw PreCondicaoFalha('o outro lado abortou antes de começar');
        case ResultadoBarreira.liberada:
          final pub = r.outro?['pub'];
          if (pub is! String || !_hex64.hasMatch(pub)) {
            throw PreCondicaoFalha(
              'o outro lado enviou uma chave pública inválida',
            );
          }
          if (pub == minhaPub) {
            throw PreCondicaoFalha(
              'os dois lados têm a mesma chave pública: dois apps iguais?',
            );
          }
          return IdentidadeDoOutro(
            pub: pub,
            versao: _versaoSegura(r.outro?['versao']),
          );
        case ResultadoBarreira.expirada:
          log?.call('o outro lado ainda não chegou; esperando');
      }
    } on CoordenadorInalcancavel catch (e) {
      log?.call('$e; tentando de novo');
    }
    if (!relogio.agora().isBefore(fim)) {
      throw PreCondicaoFalha(
        'o outro lado não apareceu em ${prazo.inMinutes} min',
      );
    }
    await relogio.dormir(intervalo);
  }
}
