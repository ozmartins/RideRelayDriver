import 'package:flutter/material.dart';

import 'identidade_visual.dart';

/// Modal exibida quando o passageiro cancela a corrida (feature 020, FR-005).
///
/// Widget apresentacional (como `QuoteAcceptedModal`): [onClose] é
/// responsabilidade de quem chama, incluindo fechar a modal. A corrida já foi
/// encerrada no instante do recebimento do aviso; a modal só informa.
class RideCancelledByPassengerModal extends StatelessWidget {
  const RideCancelledByPassengerModal({super.key, required this.onClose});

  /// Chamado ao tocar em "OK" — apenas fecha a modal.
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return ModalTematizado(
      titulo: 'Corrida cancelada',
      conteudo: const Text('O passageiro cancelou a corrida.'),
      acoes: [
        FilledButton(
          style: IdentidadeVisual.estiloAcaoPrimaria(altura: 48),
          onPressed: onClose,
          child: const Text('OK'),
        ),
      ],
    );
  }
}
