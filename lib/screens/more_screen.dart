import 'package:flutter/material.dart';

import '../domain/cadastro_progress.dart';
import '../domain/identity.dart';
import '../domain/relay.dart';
import '../services/relay_connection.dart';
import 'cadastro_screen.dart';
import 'identidade_visual.dart';
import 'identity_screen.dart';
import 'relays_screen.dart';

/// Tela "Mais" do motorista: estado das conexões e o menu de acesso a
/// cadastro, relays e identidade — o mesmo desenho da tela "Mais" do
/// passageiro, que concentra o que antes ocupava a barra inferior.
///
/// As telas de destino são empilhadas (com botão de voltar), não embutidas:
/// a barra inferior fica só com "Mapa" e "Mais".
class MoreScreen extends StatelessWidget {
  const MoreScreen({
    required this.relayService,
    required this.identity,
    required this.progress,
    required this.onAddRelay,
    required this.onRemoveRelay,
    required this.onRestoreDefaults,
    required this.onSavePersonal,
    required this.onSaveVehicle,
    required this.onSaveFinancial,
    super.key,
  });

  final RelayConnection relayService;
  final Identity? identity;
  final CadastroProgress progress;
  final Future<String?> Function(String url) onAddRelay;
  final Future<void> Function(String url) onRemoveRelay;
  final Future<void> Function() onRestoreDefaults;
  final Future<String?> Function(DriverPersonalData data) onSavePersonal;
  final Future<String?> Function(DriverVehicleData data) onSaveVehicle;
  final Future<String?> Function(DriverFinancialData data) onSaveFinancial;

  void _abrir(BuildContext context, Widget tela) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => tela));
  }

  @override
  Widget build(BuildContext context) {
    return TelaDeConteudo(
      tituloBarra: 'Corridas Motorista',
      titulo: 'Mais',
      child: StreamBuilder<void>(
        stream: relayService.statusChanges,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              _FaixaConexao(relays: relayService.relays),
              _ItemDeMenu(
                tooltip: 'Cadastro',
                icone: Icons.badge_outlined,
                titulo: 'Cadastro',
                subtitulo: 'Seus dados, os do veículo e o financeiro',
                onTap: () => _abrir(
                  context,
                  CadastroScreen(
                    initial: progress,
                    onSavePersonal: onSavePersonal,
                    onSaveVehicle: onSaveVehicle,
                    onSaveFinancial: onSaveFinancial,
                  ),
                ),
              ),
              _ItemDeMenu(
                tooltip: 'Relays',
                icone: Icons.dns_outlined,
                titulo: 'Relays',
                subtitulo: 'Servidores por onde o app se comunica',
                // A tela de relays recebe a lista já pronta; reconstruí-la a
                // cada mudança de estado mantém a rota empilhada em dia.
                onTap: () => _abrir(
                  context,
                  StreamBuilder<void>(
                    stream: relayService.statusChanges,
                    builder: (_, _) => RelaysScreen(
                      relays: relayService.relays,
                      onAdd: onAddRelay,
                      onRemove: onRemoveRelay,
                      onRestoreDefaults: onRestoreDefaults,
                      onReconnect: relayService.reconnectNow,
                    ),
                  ),
                ),
              ),
              _ItemDeMenu(
                tooltip: 'Minha identidade',
                icone: Icons.vpn_key_outlined,
                titulo: 'Minha identidade',
                subtitulo: 'Sua chave pública na rede',
                onTap: () =>
                    _abrir(context, IdentityScreen(identity: identity)),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Cartão de menu: o "cartão de lista" da identidade, com seta à direita.
class _ItemDeMenu extends StatelessWidget {
  const _ItemDeMenu({
    required this.tooltip,
    required this.icone,
    required this.titulo,
    required this.subtitulo,
    required this.onTap,
  });

  final String tooltip;
  final IconData icone;
  final String titulo;
  final String subtitulo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: IdentidadeVisual.campo,
          borderRadius: BorderRadius.circular(16),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 4,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            leading: Icon(icone, color: IdentidadeVisual.roxo),
            title: Text(
              titulo,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: IdentidadeVisual.texto,
              ),
            ),
            subtitle: Text(
              subtitulo,
              style: const TextStyle(
                fontSize: 12,
                color: IdentidadeVisual.textoSuave,
              ),
            ),
            trailing: const Icon(
              Icons.chevron_right,
              color: IdentidadeVisual.roxo,
            ),
            onTap: onTap,
          ),
        ),
      ),
    );
  }
}

/// Resumo do estado das conexões no topo da tela.
class _FaixaConexao extends StatelessWidget {
  const _FaixaConexao({required this.relays});

  final List<Relay> relays;

  @override
  Widget build(BuildContext context) {
    if (relays.isEmpty) {
      return _faixa(
        context,
        alerta: true,
        icone: Icons.cloud_off,
        texto: 'Nenhum relay configurado. Acrescente um na tela de relays.',
      );
    }

    final conectados = relays
        .where((r) => r.status == RelayStatus.connected)
        .length;
    if (conectados > 0) {
      return _faixa(
        context,
        alerta: false,
        icone: Icons.cloud_done_outlined,
        texto: '$conectados de ${relays.length} relays conectados',
      );
    }

    final tentando = relays.any((r) => r.status == RelayStatus.connecting);
    return _faixa(
      context,
      alerta: true,
      icone: tentando ? Icons.wifi_find : Icons.wifi_off,
      texto: tentando
          ? 'Conectando aos relays…'
          : 'Sem conexão com nenhum relay. Verifique se o aparelho está '
                'conectado à internet e tente novamente.',
    );
  }

  Widget _faixa(
    BuildContext context, {
    required bool alerta,
    required IconData icone,
    required String texto,
  }) {
    final cor = alerta
        ? Theme.of(context).colorScheme.error
        : IdentidadeVisual.roxo;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      decoration: BoxDecoration(
        color: IdentidadeVisual.campo,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Icon(icone, color: cor, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              texto,
              style: TextStyle(
                fontSize: 13,
                color: alerta ? cor : IdentidadeVisual.texto,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
