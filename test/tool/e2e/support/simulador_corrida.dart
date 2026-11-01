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
  noDestino,
  avaliando,
}

/// Simula os dois apps: reage a toques, digitação e posicionamento do roteiro
/// trocando as telas do [FakeAdb] e publicando eventos assinados nos relays
/// falsos, para o observador. Só serve ao teste do ciclo.
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
    adb.telas[serialMot] = const [
      ElementoFake(RotulosSim.motoristaOnline),
      ElementoFake('Toque para parar de receber solicitações', clicavel: true),
    ];
    adb.telas[serialPax] = const [
      ElementoFake(RotulosSim.campoDestino, clicavel: true),
    ];
  }

  void _mot(List<ElementoFake> itens) => adb.telas[serialMot] = itens;
  void _pax(List<ElementoFake> itens) => adb.telas[serialPax] = itens;

  List<ElementoFake> _avaliacao({required bool confirmarHabilitado}) => [
    const ElementoFake(RotulosSim.avalie),
    for (var i = 0; i < 5; i++)
      const ElementoFake('estrela', clicavel: true, rotuloVisivel: false),
    const ElementoFake('Pular', clicavel: true),
    ElementoFake('Confirmar', clicavel: true, habilitado: confirmarHabilitado),
  ];

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
    if (photonFalha) {
      _pax(const [
        ElementoFake(destinoBusca, clicavel: true),
        ElementoFake('Não foi possível buscar endereços no momento.'),
      ]);
      return;
    }
    _pax(const [
      ElementoFake(destinoBusca, clicavel: true),
      ElementoFake(
        'Universidade Federal de Santa Catarina, Araranguá, SC',
        clicavel: true,
      ),
    ]);
  }

  void _aoTocar(String serial, ElementoFake e, int indice) {
    final r = e.rotulo;
    if (r == 'Cancelar corrida') {
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
      _aoTocarMot(r);
    }
  }

  void _aoTocarPax(String r) {
    switch (r) {
      case 'Universidade Federal de Santa Catarina, Araranguá, SC':
        _pax(const [
          ElementoFake(destinoBusca),
          ElementoFake('Solicitar corrida', clicavel: true),
        ]);
      case 'Solicitar corrida':
        fase = Fase.solicitada;
        _publicar(20001, doMotorista: false, comP: false);
        _pax(const [
          ElementoFake('Aguardando orçamentos…'),
          ElementoFake('Cancelar corrida', clicavel: true),
        ]);
        if (!semEfeitoRemoto.contains('solicitar')) {
          _mot([
            const ElementoFake('Solicitação de corrida'),
            if (!semBotaoDeOrcamento)
              const ElementoFake('Enviar orçamento', clicavel: true),
          ]);
        }
      case 'Aceitar':
        fase = Fase.aceita;
        _publicar(20003, doMotorista: false);
        _pax(const [
          ElementoFake('Aguardando motorista'),
          ElementoFake('Cancelar corrida', clicavel: true),
        ]);
        if (!semEfeitoRemoto.contains('aceitar')) {
          _mot(const [
            ElementoFake('Orçamento aceito'),
            ElementoFake('Iniciar corrida', clicavel: true),
            ElementoFake('Cancelar corrida', clicavel: true),
          ]);
        }
      case 'OK':
        _pax(const [
          ElementoFake('Motorista a caminho'),
          ElementoFake('Cancelar corrida', clicavel: true),
        ]);
      case 'Confirmo que encontrei o motorista':
        fase = Fase.emCorrida;
        _publicar(20008, doMotorista: false);
        _pax(const [
          ElementoFake('Corrida em andamento'),
          ElementoFake('Cancelar corrida', clicavel: true),
        ]);
        if (!semEfeitoRemoto.contains('confirmar-encontro')) {
          _mot(const [
            ElementoFake('CORRIDA EM ANDAMENTO'),
            ElementoFake('Cancelar corrida', clicavel: true),
          ]);
        }
      case 'Confirmar chegada ao destino':
        fase = Fase.avaliando;
        _publicar(20010, doMotorista: false);
        _pax(_avaliacao(confirmarHabilitado: false));
        if (!semEfeitoRemoto.contains('confirmar-destino')) {
          _mot(_avaliacao(confirmarHabilitado: false));
        }
      case 'estrela':
        _pax(_avaliacao(confirmarHabilitado: true));
      case 'Confirmar':
        _publicar(20014, doMotorista: false);
        _avaliou.add('pax');
        _pax(const [ElementoFake(RotulosSim.campoDestino, clicavel: true)]);
        _fimSeAvaliaram();
    }
  }

  void _aoTocarMot(String r) {
    switch (r) {
      case 'Enviar orçamento':
        fase = Fase.orcada;
        _publicar(20002, doMotorista: true);
        _mot(const [
          ElementoFake(RotulosSim.motoristaOnline),
          ElementoFake(
            'Toque para parar de receber solicitações',
            clicavel: true,
          ),
        ]);
        if (!semEfeitoRemoto.contains('orcamento')) {
          _pax(const [
            ElementoFake('Orçamentos recebidos'),
            ElementoFake('Aceitar', clicavel: true),
            ElementoFake('Cancelar corrida', clicavel: true),
          ]);
        }
      case 'Iniciar corrida':
        fase = Fase.deslocando;
        _publicar(20005, doMotorista: true);
        _mot(const [
          ElementoFake('Deslocando-se até o passageiro'),
          ElementoFake('Cancelar corrida', clicavel: true),
        ]);
        _pax(const [
          ElementoFake('Motorista a caminho'),
          ElementoFake('O motorista começou a se deslocar até você.'),
          ElementoFake('OK', clicavel: true),
        ]);
      case 'estrela':
        _mot(_avaliacao(confirmarHabilitado: true));
      case 'Confirmar':
        _publicar(20014, doMotorista: true);
        _avaliou.add('mot');
        _mot(const [
          ElementoFake(RotulosSim.motoristaOnline),
          ElementoFake(
            'Toque para parar de receber solicitações',
            clicavel: true,
          ),
        ]);
        _fimSeAvaliaram();
      case 'Toque para receber solicitações':
        _mot(const [
          ElementoFake(RotulosSim.motoristaOnline),
          ElementoFake(
            'Toque para parar de receber solicitações',
            clicavel: true,
          ),
        ]);
    }
  }

  void _fimSeAvaliaram() {
    if (_avaliou.length == 2) fase = Fase.ocioso;
  }

  void _aoGeoFix(String serial, double lat, double lon) {
    if (serial != serialMot) return;
    bool perto(PontoGeo p, double graus) =>
        (p.lat - lat).abs() < graus && (p.lon - lon).abs() < graus;
    if (fase == Fase.deslocando && perto(pontoDeEncontro, 0.0002)) {
      fase = Fase.chegou;
      _publicar(20007, doMotorista: true);
      if (!semEfeitoRemoto.contains('chegada-origem')) {
        _pax(const [
          ElementoFake('Motorista chegou'),
          ElementoFake('Confirmo que encontrei o motorista', clicavel: true),
        ]);
      }
    } else if (fase == Fase.emCorrida && perto(destinoDaCorrida, 0.009)) {
      fase = Fase.noDestino;
      _publicar(20009, doMotorista: true);
      if (!semEfeitoRemoto.contains('chegada-destino')) {
        _pax(const [
          ElementoFake('Corrida em andamento'),
          ElementoFake('Confirmar chegada ao destino', clicavel: true),
        ]);
      }
    }
  }
}

/// Rótulos usados nas telas do simulador (iguais aos de `telas.dart`; copiados
/// para o teste não depender do que ele verifica).
class RotulosSim {
  const RotulosSim._();

  static const motoristaOnline = 'Você está online';
  static const campoDestino = 'Para onde você quer ir?';
  static const avalie = 'Avalie a corrida';
}
