import 'dart:convert';

import 'package:dart_nostr/dart_nostr.dart' as nostr;
import 'package:driver/services/default_relays.dart';
import 'package:driver/services/prototype_marker.dart';

import '../../../../tool/e2e/src/config.dart';
import '../../../../tool/e2e/src/observador.dart';
import '../../../support/fake_relay_transport.dart';
import '../../../support/signed_payload.dart';
import 'fake_adb.dart';
import 'relogio_falso.dart';

enum Fase {
  ocioso,
  solicitada,
  orcada,
  aceita,
  deslocando,
  chegou,
  emCorrida,
  avaliando,
}

const _resultadoDaBusca =
    'UFSC Campus Araranguá Unidade Mato Alto, Rua Pedro João Pereira, 150, '
    'Araranguá, Santa Catarina, Brasil';

/// Simula os dois apps, com as telas que se observaram nos emuladores: reage a
/// toques, digitação e posicionamento do roteiro trocando as telas do [FakeAdb]
/// e publicando eventos assinados nos relays falsos, para o observador. Só
/// serve ao teste do ciclo.
class SimuladorCorrida {
  SimuladorCorrida({
    required this.adb,
    required this.transporte,
    required this.serialMot,
    required this.serialPax,
    required this.motorista,
    required this.passageiro,
    required this.relogio,
  });

  final FakeAdb adb;
  final FakeRelayTransport transporte;
  final String serialMot;
  final String serialPax;
  final nostr.NostrKeyPairs motorista;
  final nostr.NostrKeyPairs passageiro;
  final RelogioFalso relogio;

  Fase fase = Fase.ocioso;

  /// Ações cujo efeito na tela do outro app não acontece (relay que não entrega).
  final Set<String> semEfeitoRemoto = {};

  /// Kinds que o "app" não publica.
  final Set<int> naoPublicar = {};

  /// A busca de endereço falha (o app mostra a mensagem do Photon).
  bool photonFalha = false;

  /// O app do motorista nunca chega a mostrar o botão de enviar orçamento.
  bool semBotaoDeOrcamento = false;

  /// O marcador "Destino da corrida" fica fora da tela do motorista (o destino
  /// está a vários quilômetros e o mapa segue o carro), como no app real.
  bool semMarcadorDeDestino = false;

  /// O motorista está offline (o roteiro precisa ligar o alternador).
  bool motoristaOffline = false;

  /// Contagem de vezes em que o motorista foi ligado pelo alternador.
  int ligadoPeloAlternador = 0;

  String _destinoTexto = '';
  bool _paxModalCaminho = false;
  bool _paxNoDestino = false;
  bool _driverNoDestino = false;
  final Set<String> _avaliou = {};
  final List<int> publicados = [];

  void iniciar() {
    _ocioso();
    adb.aoTocar = _aoTocar;
    adb.aoGeoFix = _aoGeoFix;
    adb.aoDigitar = _aoDigitar;
  }

  // ---- telas ---------------------------------------------------------------

  void _ocioso() {
    fase = Fase.ocioso;
    _avaliou.clear();
    _paxModalCaminho = false;
    _paxNoDestino = false;
    _driverNoDestino = false;
    _motIdle();
    _paxIdle();
  }

  void _motIdle() {
    adb.telas[serialMot] = [
      ElementoFake(motoristaOffline ? 'Você está offline' : 'Você está online'),
      ElementoFake(
        motoristaOffline
            ? 'Toque para receber solicitações'
            : 'Toque para parar de receber solicitações',
      ),
      const ElementoFake('', clicavel: true, classe: 'Switch'),
    ];
  }

  void _paxIdle() {
    adb.telas[serialPax] = [
      ElementoFake(_destinoTexto, clicavel: true, classe: 'EditText'),
      const ElementoFake('Dinheiro', clicavel: true),
      const ElementoFake('PIX', clicavel: true),
      const ElementoFake('Cartão', clicavel: true),
      const ElementoFake('Solicitar corrida', clicavel: true),
    ];
  }

  void _motEmCorrida({required bool destino}) {
    adb.telas[serialMot] = [
      if (!destino) const ElementoFake('Ponto de embarque'),
      if (destino && !semMarcadorDeDestino)
        const ElementoFake('Destino da corrida'),
      const ElementoFake('Você está online'),
      const ElementoFake('', clicavel: true, classe: 'Switch'),
      const ElementoFake('CORRIDA EM ANDAMENTO'),
      const ElementoFake('Cancelar corrida', clicavel: true),
    ];
  }

  /// A tela do passageiro durante a corrida, sem o aviso "Motorista a caminho".
  void _paxBase() {
    final itens = <ElementoFake>[];
    if (fase == Fase.chegou) {
      itens
        ..add(const ElementoFake('Motorista chegou'))
        ..add(
          const ElementoFake(
            'Confirmo que encontrei o motorista',
            clicavel: true,
          ),
        );
    }
    if (fase == Fase.emCorrida && _paxNoDestino) {
      itens.add(
        const ElementoFake('Confirmar chegada ao destino', clicavel: true),
      );
    }
    itens.add(const ElementoFake('Cancelar corrida', clicavel: true));
    adb.telas[serialPax] = itens;
  }

  void _paxModal() {
    adb.telas[serialPax] = const [
      ElementoFake('Motorista a caminho'),
      ElementoFake('O motorista começou a se deslocar até você.'),
      ElementoFake('OK', clicavel: true),
    ];
  }

  void _avaliacao(String serial, {required bool confirmarHabilitado}) {
    adb.telas[serial] = [
      const ElementoFake('Avalie a corrida'),
      for (var i = 0; i < 5; i++)
        const ElementoFake('estrela', clicavel: true, rotuloVisivel: false),
      const ElementoFake('Pular', clicavel: true),
      ElementoFake(
        'Confirmar',
        clicavel: true,
        habilitado: confirmarHabilitado,
      ),
    ];
  }

  // ---- publicação ----------------------------------------------------------

  void _publicar(int kind, {required bool doMotorista, bool comP = true}) {
    if (naoPublicar.contains(kind)) return;
    publicados.add(kind);
    final de = doMotorista ? motorista : passageiro;
    final para = doMotorista ? passageiro : motorista;
    final payload = signedPayload(
      kind: kind,
      keyPairs: de,
      // Conteúdo único: dois eventos iguais no mesmo segundo teriam o mesmo id.
      content: 'SEGREDO-NAO-PODE-VAZAR-${publicados.length}',
      tags: [
        prototypeMarkerTag,
        if (comP) ['p', para.public],
      ],
    );
    for (final url in defaultRelayUrls) {
      transporte
          .lastSocket(url)
          .push(jsonEncode(['EVENT', Observador.idInscricao, payload]));
    }
  }

  // ---- reações -------------------------------------------------------------

  void _aoDigitar(String serial, String texto) {
    if (serial != serialPax) return;
    adb.telas[serialPax] = [
      const ElementoFake(destinoBusca, clicavel: true, classe: 'EditText'),
      if (photonFalha)
        const ElementoFake('Não foi possível buscar endereços no momento.')
      else
        const ElementoFake(_resultadoDaBusca, clicavel: true),
    ];
  }

  void _aoTocar(String serial, ElementoFake e, int indice) {
    final r = e.rotulo;
    if (r == 'Cancelar corrida' || r == 'Cancelar') {
      _publicar(
        serial == serialMot ? 20012 : 20013,
        doMotorista: serial == serialMot,
      );
      _ocioso();
      return;
    }
    if (serial == serialPax) {
      _aoTocarPax(r);
    } else {
      _aoTocarMot(e, r);
    }
  }

  void _aoTocarPax(String r) {
    switch (r) {
      case _resultadoDaBusca:
        _destinoTexto = _resultadoDaBusca;
        _paxIdle();
      case 'Solicitar corrida':
        fase = Fase.solicitada;
        _publicar(20001, doMotorista: false, comP: false);
        adb.telas[serialPax] = const [
          ElementoFake('Orçamentos recebidos'),
          ElementoFake('Aguardando orçamentos…'),
          ElementoFake('Cancelar', clicavel: true),
        ];
        if (!semEfeitoRemoto.contains('solicitar')) {
          adb.telas[serialMot] = [
            const ElementoFake('Solicitação de corrida'),
            const ElementoFake('Origem: '),
            const ElementoFake('Recusar corrida', clicavel: true),
            if (!semBotaoDeOrcamento)
              const ElementoFake('Enviar orçamento', clicavel: true),
          ];
        }
      case 'Aceitar':
        fase = Fase.aceita;
        _publicar(20003, doMotorista: false);
        adb.telas[serialPax] = const [
          ElementoFake('Cancelar corrida', clicavel: true),
        ];
        if (!semEfeitoRemoto.contains('aceitar')) {
          adb.telas[serialMot] = const [
            ElementoFake('Orçamento aceito'),
            ElementoFake('Iniciar corrida', clicavel: true),
          ];
        }
      case 'OK':
        _paxModalCaminho = false;
        _paxBase();
      case 'Confirmo que encontrei o motorista':
        fase = Fase.emCorrida;
        _publicar(20008, doMotorista: false);
        // O aviso "Motorista a caminho" volta a cobrir a tela do passageiro.
        _paxModalCaminho = true;
        _paxModal();
        if (!semEfeitoRemoto.contains('confirmar-encontro')) {
          _motEmCorrida(destino: true);
        }
      case 'Confirmar chegada ao destino':
        fase = Fase.avaliando;
        _publicar(20010, doMotorista: false);
        _avaliacao(serialPax, confirmarHabilitado: false);
        if (!semEfeitoRemoto.contains('confirmar-destino')) {
          _avaliacao(serialMot, confirmarHabilitado: false);
        }
      case 'estrela':
        _avaliacao(serialPax, confirmarHabilitado: true);
      case 'Confirmar':
        _publicar(20014, doMotorista: false);
        _avaliou.add('pax');
        _paxIdle();
        _fimSeAvaliaram();
    }
  }

  void _aoTocarMot(ElementoFake e, String r) {
    switch (r) {
      case 'Enviar orçamento':
        fase = Fase.orcada;
        _publicar(20002, doMotorista: true);
        _motIdle();
        if (!semEfeitoRemoto.contains('orcamento')) {
          adb.telas[serialPax] = const [
            ElementoFake('Orçamentos recebidos'),
            ElementoFake('Motorista Teste — Fiat Palio 2018'),
            ElementoFake('Aceitar', clicavel: true),
            ElementoFake('Cancelar', clicavel: true),
          ];
        }
      case 'Iniciar corrida':
        fase = Fase.deslocando;
        _publicar(20005, doMotorista: true);
        _motEmCorrida(destino: false);
        _paxModalCaminho = true;
        _paxModal();
      case 'estrela':
        _avaliacao(serialMot, confirmarHabilitado: true);
      case 'Confirmar':
        _publicar(20014, doMotorista: true);
        _avaliou.add('mot');
        _motIdle();
        _fimSeAvaliaram();
      case '':
        // Alternador online/offline.
        if (e.classe == 'Switch') {
          motoristaOffline = !motoristaOffline;
          if (!motoristaOffline) ligadoPeloAlternador++;
          _motIdle();
        }
    }
  }

  void _fimSeAvaliaram() {
    if (_avaliou.length == 2) fase = Fase.ocioso;
  }

  bool _perto(PontoGeo p, double lat, double lon, double graus) =>
      (p.lat - lat).abs() < graus && (p.lon - lon).abs() < graus;

  void _aoGeoFix(String serial, double lat, double lon) {
    if (serial == serialPax) {
      if (_perto(destinoDaCorrida, lat, lon, 0.009)) {
        _paxNoDestino = true;
        if (fase == Fase.emCorrida && !_paxModalCaminho) _paxBase();
      } else {
        _paxNoDestino = false;
      }
      return;
    }
    if (fase == Fase.deslocando && _perto(pontoDeEncontro, lat, lon, 0.0002)) {
      fase = Fase.chegou;
      _publicar(20007, doMotorista: true);
      if (!semEfeitoRemoto.contains('chegada-origem')) {
        _paxModalCaminho = false;
        _paxBase();
      }
    } else if (fase == Fase.emCorrida &&
        !_driverNoDestino &&
        _perto(destinoDaCorrida, lat, lon, 0.009)) {
      _driverNoDestino = true;
      _publicar(20009, doMotorista: true);
    }
  }
}
