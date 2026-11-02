import 'package:flutter/material.dart';

import 'identidade_visual.dart';

/// Modal exibida quando o motorista recebe a aceitação de um orçamento que
/// ele enviou (feature 010, US1).
///
/// Widget apresentacional (como `RideRequestModal`): [onStartRide] é
/// responsabilidade de quem chama, incluindo fechar a modal (FR-002).
class QuoteAcceptedModal extends StatelessWidget {
  const QuoteAcceptedModal({super.key, required this.onStartRide});

  /// Chamado ao tocar em "Iniciar corrida" — transiciona o motorista para
  /// "Deslocando-se até o passageiro" e fecha a modal (FR-002, FR-003).
  final VoidCallback onStartRide;

  @override
  Widget build(BuildContext context) {
    return ModalTematizado(
      titulo: 'Orçamento aceito',
      conteudo: const Text(
        'O passageiro aceitou o seu orçamento. Toque em "Iniciar corrida" '
        'quando estiver a caminho dele.',
      ),
      acoes: [
        FilledButton(
          style: IdentidadeVisual.estiloAcaoPrimaria(altura: 48),
          onPressed: onStartRide,
          child: const Text('Iniciar corrida'),
        ),
      ],
    );
  }
}
