import 'package:flutter/material.dart';

import '../domain/relay.dart';
import 'identidade_visual.dart';

/// Gestão da lista de relays: listar, adicionar, remover e restaurar o padrão.
///
/// Widget apresentacional: os callbacks devolvem mensagem de erro quando a
/// operação é recusada, e a tela apenas exibe.
class RelaysScreen extends StatefulWidget {
  const RelaysScreen({
    super.key,
    required this.relays,
    required this.onAdd,
    required this.onRemove,
    required this.onRestoreDefaults,
    required this.onReconnect,
  });

  final List<Relay> relays;

  /// Devolve `null` em caso de sucesso, ou a mensagem de recusa.
  final Future<String?> Function(String url) onAdd;
  final Future<void> Function(String url) onRemove;
  final Future<void> Function() onRestoreDefaults;

  /// Reconexão a pedido do usuário; a tela só reflete o estado dos relays.
  final Future<void> Function() onReconnect;

  @override
  State<RelaysScreen> createState() => _RelaysScreenState();
}

class _RelaysScreenState extends State<RelaysScreen> {
  final TextEditingController _url = TextEditingController();
  String? _erro;
  bool _reconectando = false;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final erro = await widget.onAdd(_url.text);
    if (!mounted) return;
    setState(() => _erro = erro);
    if (erro == null) _url.clear();
  }

  Future<void> _reconectar() async {
    // Desabilita o botão durante a chamada: toque duplo não sobrepõe rodadas.
    setState(() => _reconectando = true);
    try {
      await widget.onReconnect();
    } finally {
      if (mounted) setState(() => _reconectando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TelaDeConteudo(
      tituloBarra: 'Caronas Motorista',
      titulo: 'Relays',
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _url,
                    autocorrect: false,
                    style: IdentidadeVisual.estiloValor,
                    decoration: decoracaoCampo(
                      rotulo: 'Endereço do relay',
                      dica: 'wss://relay.exemplo.org',
                      erro: _erro,
                    ),
                    onSubmitted: (_) => _add(),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _add,
                  style: IdentidadeVisual.estiloAcaoPrimaria().copyWith(
                    minimumSize: const WidgetStatePropertyAll(Size(0, 56)),
                    padding: const WidgetStatePropertyAll(
                      EdgeInsets.symmetric(horizontal: 16),
                    ),
                  ),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Adicionar'),
                ),
              ],
            ),
          ),
          if (widget.relays.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const Key('botao-reconectar'),
                  onPressed: _reconectando ? null : _reconectar,
                  style: IdentidadeVisual.estiloAcaoPrimaria(),
                  icon: const Icon(Icons.sync, size: 18),
                  label: Text(_reconectando ? 'Reconectando…' : 'Reconectar'),
                ),
              ),
            ),
          Expanded(
            child: widget.relays.isEmpty
                ? _ListaVazia(onRestoreDefaults: widget.onRestoreDefaults)
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 8,
                    ),
                    itemCount: widget.relays.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final relay = widget.relays[index];
                      return Container(
                        decoration: BoxDecoration(
                          color: IdentidadeVisual.campo,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          leading: _StatusIcon(status: relay.status),
                          title: Text(
                            relay.url,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: IdentidadeVisual.texto,
                            ),
                          ),
                          subtitle: Text(
                            _descricao(relay),
                            style: const TextStyle(
                              fontSize: 12,
                              color: IdentidadeVisual.textoSuave,
                            ),
                          ),
                          trailing: IconButton(
                            tooltip: 'Remover',
                            color: IdentidadeVisual.roxo,
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => widget.onRemove(relay.url),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          if (widget.relays.isNotEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Text(
                'Relays da lista padrão podem ser removidos. Se a lista ficar '
                'vazia, é possível restaurá-la.',
                style: TextStyle(
                  fontSize: 12,
                  color: IdentidadeVisual.textoSuave,
                ),
              ),
            ),
        ],
      ),
    );
  }

  static String _descricao(Relay relay) {
    final estado = switch (relay.status) {
      RelayStatus.connecting => 'conectando',
      RelayStatus.connected => 'conectado',
      RelayStatus.unavailable => 'indisponível',
    };
    final origem = relay.isDefault ? 'lista padrão' : 'adicionado por você';
    final motivo = relay.lastError == null ? '' : ' — ${relay.lastError}';
    return '$estado · $origem$motivo';
  }
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.status});

  final RelayStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return switch (status) {
      RelayStatus.connecting => const Icon(
        Icons.sync,
        color: IdentidadeVisual.textoSuave,
      ),
      RelayStatus.connected => const Icon(
        Icons.check_circle,
        color: IdentidadeVisual.roxo,
      ),
      RelayStatus.unavailable => Icon(Icons.error_outline, color: scheme.error),
    };
  }
}

class _ListaVazia extends StatelessWidget {
  const _ListaVazia({required this.onRestoreDefaults});

  final Future<void> Function() onRestoreDefaults;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.cloud_off,
              size: 48,
              color: IdentidadeVisual.textoSuave,
            ),
            const SizedBox(height: 16),
            const Text(
              'Nenhum relay configurado. Sem relays o aplicativo não publica '
              'nem recebe eventos.',
              textAlign: TextAlign.center,
              style: TextStyle(color: IdentidadeVisual.texto),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              style: IdentidadeVisual.estiloAcaoPrimaria(),
              onPressed: onRestoreDefaults,
              icon: const Icon(Icons.restore),
              label: const Text('Restaurar lista padrão'),
            ),
          ],
        ),
      ),
    );
  }
}
