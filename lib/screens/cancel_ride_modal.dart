import 'package:flutter/material.dart';

import 'identidade_visual.dart';

/// Modal de confirmação do cancelamento da corrida (feature 018, FR-002).
///
/// Widget apresentacional (como `QuoteAcceptedModal`): [onConfirm] e
/// [onBack] são responsabilidade de quem chama, incluindo fechar a modal.
class CancelRideModal extends StatelessWidget {
  const CancelRideModal({
    super.key,
    required this.onConfirm,
    required this.onBack,
  });

  /// Chamado ao tocar em "Cancelar corrida" — efetiva o cancelamento.
  final VoidCallback onConfirm;

  /// Chamado ao tocar em "Voltar" — desiste sem nenhum efeito.
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return ModalTematizado(
      titulo: 'Cancelar corrida?',
      conteudo: const Text(
        'O passageiro será avisado de que você cancelou a corrida.',
      ),
      acoes: [
        TextButton(
          style: IdentidadeVisual.estiloAcaoSecundaria,
          onPressed: onBack,
          child: const Text('Voltar'),
        ),
        FilledButton(
          style: IdentidadeVisual.estiloAcaoPrimaria(altura: 48)
              .copyWith(minimumSize: const WidgetStatePropertyAll(Size(0, 48))),
          onPressed: onConfirm,
          child: const Text('Cancelar corrida'),
        ),
      ],
    );
  }
}
