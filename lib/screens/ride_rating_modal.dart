import 'package:flutter/material.dart';

import 'identidade_visual.dart';

/// Modal de avaliação da corrida, exibida ao final dela (feature 013, US1).
///
/// Widget apresentacional (como `QuoteAcceptedModal`): fechar a modal é
/// responsabilidade de quem chama [onConfirm]/[onSkip], não deste widget.
class RideRatingModal extends StatefulWidget {
  const RideRatingModal({
    super.key,
    required this.onConfirm,
    required this.onSkip,
  });

  /// Chamado com a nota escolhida (1 a 5) ao tocar "Confirmar".
  final void Function(int stars) onConfirm;

  /// Chamado ao tocar em fechar/pular sem selecionar nenhuma nota (FR-008).
  final VoidCallback onSkip;

  @override
  State<RideRatingModal> createState() => _RideRatingModalState();
}

class _RideRatingModalState extends State<RideRatingModal> {
  int? _notaSelecionada;

  @override
  Widget build(BuildContext context) {
    return ModalTematizado(
      titulo: 'Avalie a corrida',
      conteudo: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(5, (indice) {
          final posicao = indice + 1;
          final selecionada =
              _notaSelecionada != null && posicao <= _notaSelecionada!;
          return IconButton(
            onPressed: () => setState(() => _notaSelecionada = posicao),
            icon: Icon(
              selecionada ? Icons.star : Icons.star_border,
              color: selecionada
                  ? IdentidadeVisual.roxo
                  : IdentidadeVisual.desabilitado,
            ),
          );
        }),
      ),
      acoes: [
        TextButton(
          style: IdentidadeVisual.estiloAcaoSecundaria,
          onPressed: widget.onSkip,
          child: const Text('Pular'),
        ),
        FilledButton(
          style: IdentidadeVisual.estiloAcaoPrimaria(altura: 48)
              .copyWith(minimumSize: const WidgetStatePropertyAll(Size(0, 48))),
          onPressed: _notaSelecionada == null
              ? null
              : () => widget.onConfirm(_notaSelecionada!),
          child: const Text('Confirmar'),
        ),
      ],
    );
  }
}
