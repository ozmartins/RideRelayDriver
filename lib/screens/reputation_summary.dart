import 'package:flutter/material.dart';

import '../domain/reputation_view.dart';
import 'identidade_visual.dart';

/// Reputação do passageiro na modal de solicitação (emenda 25 do contrato;
/// feature 026): a parte **verificada** (só recibos que conferem) em destaque e
/// a **declarada** em texto menor — nunca somadas numa nota única. Destaca
/// "inconsistente" e "N recibos não apresentados".
///
/// [view] nulo = passageiro sem histórico (reputação ausente ou malformada).
class ReputationSummary extends StatelessWidget {
  const ReputationSummary({super.key, required this.view});

  final ReputationView? view;

  @override
  Widget build(BuildContext context) {
    final v = view;
    if (v == null) {
      return const _Bloco(
        children: [
          Text(
            'Reputação do passageiro: sem histórico',
            key: Key('reputacao-sem-historico'),
            style: _estiloPrincipal,
          ),
        ],
      );
    }
    final erro = Theme.of(context).colorScheme.error;
    return _Bloco(
      children: [
        Text(
          'Reputação verificada: ${_verificada(v)}',
          key: const Key('reputacao-verificada'),
          style: _estiloPrincipal,
        ),
        Text(
          'Declarada pelo passageiro: ${_declarada(v.declared)}',
          key: const Key('reputacao-declarada'),
          style: _estiloSuave,
        ),
        if (v.inconsistent)
          Text(
            'Reputação inconsistente: os recibos não fecham com o que o '
            'passageiro declarou',
            key: const Key('reputacao-inconsistente'),
            style: TextStyle(color: erro, fontWeight: FontWeight.w700),
          ),
        if (v.gaps > 0)
          Text(
            '${v.gaps} ${v.gaps == 1 ? 'recibo não apresentado' : 'recibos não apresentados'}',
            key: const Key('reputacao-lacunas'),
            style: _estiloSuave,
          ),
        if (v.invalidDiscarded > 0)
          Text(
            '${v.invalidDiscarded} ${v.invalidDiscarded == 1 ? 'recibo descartado por ser inválido' : 'recibos descartados por serem inválidos'}',
            key: const Key('reputacao-descartados'),
            style: TextStyle(color: erro),
          ),
      ],
    );
  }

  static const _estiloPrincipal = TextStyle(
    fontWeight: FontWeight.w700,
    color: IdentidadeVisual.texto,
  );

  static const _estiloSuave = TextStyle(
    fontSize: 12,
    color: IdentidadeVisual.textoSuave,
  );

  static String _verificada(ReputationView v) {
    if (v.verifiedCount == 0) return 'nenhum recibo válido';
    final recibos =
        '${v.verifiedCount} ${v.verifiedCount == 1 ? 'recibo' : 'recibos'}';
    final media = v.verifiedAverage;
    return media == null
        ? 'sem notas em $recibos'
        : '${_nota(media)} ★ em $recibos';
  }

  static String _declarada(DeclaredReputation d) {
    final corridas =
        '${d.corridas} ${d.corridas == 1 ? 'corrida' : 'corridas'}';
    final media = d.media;
    return media == null || d.avaliacoes == 0
        ? '$corridas, sem avaliações'
        : '$corridas, média ${_nota(media)}';
  }

  static String _nota(double media) =>
      media.toStringAsFixed(2).replaceAll('.', ',');
}

class _Bloco extends StatelessWidget {
  const _Bloco({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    ),
  );
}
