import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/identity.dart';
import 'identidade_visual.dart';

/// Exibe a identidade Nostr do motorista.
///
/// A chave privada **não** é exibida (FR-005, Princípio I): a tela mostra
/// apenas a chave pública, que é o que identifica o motorista na rede.
class IdentityScreen extends StatelessWidget {
  const IdentityScreen({super.key, required this.identity});

  final Identity? identity;

  @override
  Widget build(BuildContext context) {
    final current = identity;

    return TelaDeConteudo(
      tituloBarra: 'Caronas Motorista',
      titulo: 'Minha identidade',
      child: current == null
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Identidade ainda não carregada.',
                  style: TextStyle(color: IdentidadeVisual.texto),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
              children: [
                const Padding(
                  padding: EdgeInsets.only(left: 4, bottom: 8),
                  child: Text(
                    'Chave pública',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: IdentidadeVisual.texto,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: IdentidadeVisual.campo,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: SelectableText(
                    current.publicKey,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 14,
                      color: IdentidadeVisual.texto,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  style: IdentidadeVisual.estiloAcaoPrimaria(),
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: current.publicKey),
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Chave pública copiada.')),
                      );
                    }
                  },
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Copiar chave pública'),
                ),
                const SizedBox(height: 24),
                const Text(
                  'A chave privada fica guardada no armazenamento protegido do '
                  'aparelho e não é exibida nem enviada a nenhum relay.',
                  style: TextStyle(
                    fontSize: 12,
                    color: IdentidadeVisual.textoSuave,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Desinstalar o aplicativo apaga a chave privada de forma '
                  'irreversível: a identidade é perdida e uma nova será criada '
                  'na próxima instalação.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
            ),
    );
  }
}
