import 'package:flutter/material.dart';

import '../domain/cadastro_progress.dart';
import '../domain/driver_profile.dart';
import '../domain/municipio.dart';
import '../domain/payment_method.dart';
import '../domain/uf.dart';
import 'identidade_visual.dart';

/// Cadastro do motorista em três etapas ("wizard"): dados do motorista, dados
/// do veículo e financeiro.
///
/// Cada etapa é gravada assim que confirmada ("Salvar e continuar"), antes de
/// a seguinte ser exibida, para que fechar o aplicativo no meio retome na
/// etapa seguinte à última salva. Uma única tela para os dois modos de uso
/// (Princípio V): [initial] sem etapas salvas é o cadastro inicial e
/// bloqueante, exibido como `home:` sem rota para voltar; [initial] completo é
/// a edição, na aba "Cadastro".
class CadastroScreen extends StatefulWidget {
  const CadastroScreen({
    super.key,
    this.initial,
    required this.onSavePersonal,
    required this.onSaveVehicle,
    required this.onSaveFinancial,
  });

  /// O que já foi salvo, para pré-preencher e escolher a etapa em que o
  /// wizard abre ([CadastroProgress.nextStep], ou a primeira se completo).
  final CadastroProgress? initial;

  /// Cada callback grava a respectiva etapa, já normalizada. Devolve `null`
  /// em caso de sucesso, ou uma mensagem de erro a exibir sem perder o que
  /// foi digitado (FR-006, FR-007).
  final Future<String?> Function(DriverPersonalData data) onSavePersonal;
  final Future<String?> Function(DriverVehicleData data) onSaveVehicle;
  final Future<String?> Function(DriverFinancialData data) onSaveFinancial;

  @override
  State<CadastroScreen> createState() => _CadastroScreenState();
}

class _CadastroScreenState extends State<CadastroScreen> {
  late final TextEditingController _nome;
  late final TextEditingController _marca;
  late final TextEditingController _modelo;
  late final TextEditingController _cor;
  late final TextEditingController _placa;
  late final TextEditingController _precoPorKm;
  late final TextEditingController _ano;
  String? _uf;
  String? _cidade;

  /// Formas de pagamento aceitas (feature 005). Nenhuma vem pré-marcada por
  /// padrão no cadastro inicial — o motorista está declarando um fato sobre
  /// si mesmo, não escolhendo uma preferência para uma transação única
  /// (`data-model.md` da feature 005).
  late Set<PaymentMethod> _formasPagamento;
  int _etapa = 0;
  bool _enviando = false;
  String? _erroEnvio;

  @override
  void initState() {
    super.initState();
    final inicial = widget.initial;
    final pessoal = inicial?.personal;
    final veiculo = inicial?.vehicle;
    final financeiro = inicial?.financial;
    _etapa = inicial?.nextStep ?? 0;
    _nome = TextEditingController(text: pessoal?.nome ?? '');
    _marca = TextEditingController(text: veiculo?.marca ?? '');
    _modelo = TextEditingController(text: veiculo?.modelo ?? '');
    _cor = TextEditingController(text: veiculo?.cor ?? '');
    _placa = TextEditingController(text: veiculo?.placa ?? '');
    _precoPorKm = TextEditingController(
      text: financeiro == null
          ? ''
          : financeiro.precoPorKm.toStringAsFixed(2).replaceAll('.', ','),
    );
    _ano = TextEditingController(
      text: veiculo == null ? '' : veiculo.ano.toString(),
    );
    _uf = pessoal?.uf;
    _cidade = pessoal?.cidade;
    _formasPagamento = {...?financeiro?.paymentMethods};
    for (final controlador in [
      _nome,
      _marca,
      _modelo,
      _cor,
      _placa,
      _precoPorKm,
      _ano,
    ]) {
      controlador.addListener(_refresh);
    }
  }

  @override
  void dispose() {
    for (final controlador in [
      _nome,
      _marca,
      _modelo,
      _cor,
      _placa,
      _precoPorKm,
      _ano,
    ]) {
      controlador.dispose();
    }
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  bool get _nomeValido => DriverProfile.isTextoValido(_nome.text);
  bool get _marcaValida => DriverProfile.isTextoValido(_marca.text);
  bool get _modeloValido => DriverProfile.isTextoValido(_modelo.text);
  bool get _corValida => DriverProfile.isTextoValido(_cor.text);
  bool get _placaValida =>
      _placa.text.isNotEmpty && DriverProfile.isValidPlaca(_placa.text);
  bool get _ufValida => _uf != null && UF.isValida(_uf!);
  bool get _cidadeValida =>
      _uf != null &&
      _cidade != null &&
      Municipio.isValido(nome: _cidade!, uf: _uf!);
  double? get _precoPorKmValido =>
      DriverProfile.parsePrecoPorKm(_precoPorKm.text);
  int? get _anoValido => DriverProfile.parseAnoVeiculo(_ano.text);

  /// Cada etapa só habilita o envio quando **todos** os seus campos passam
  /// nas próprias regras (FR-002, FR-006 da feature 003; FR-002, FR-003 da
  /// feature 005).
  bool get _etapaValida => switch (_etapa) {
    0 => _nomeValido && _ufValida && _cidadeValida,
    1 =>
      _marcaValida &&
          _modeloValido &&
          _corValida &&
          _placaValida &&
          _anoValido != null,
    _ => _formasPagamento.isNotEmpty && _precoPorKmValido != null,
  };

  /// Trocar a UF limpa a cidade escolhida: nunca persistir uma combinação
  /// que não corresponda (FR-009).
  void _onUfChanged(String? novaUf) {
    setState(() {
      _uf = novaUf;
      _cidade = null;
    });
  }

  Future<void> _enviar() async {
    // Redundante com o botão desabilitado, mas garante que nenhum caminho
    // (tecla de atalho, teste automatizado) persista uma etapa inválida
    // (SC-003): a checagem vem antes de qualquer chamada de gravação.
    if (!_etapaValida || _enviando) return;
    final ultimaEtapa = _etapa == 2;

    setState(() {
      _enviando = true;
      _erroEnvio = null;
    });
    final erro = switch (_etapa) {
      0 => await widget.onSavePersonal(
        DriverPersonalData(
          nome: DriverProfile.normalizeTexto(_nome.text),
          uf: _uf!,
          cidade: _cidade!,
        ),
      ),
      1 => await widget.onSaveVehicle(
        DriverVehicleData(
          marca: DriverProfile.normalizeTexto(_marca.text),
          modelo: DriverProfile.normalizeTexto(_modelo.text),
          ano: _anoValido!,
          cor: DriverProfile.normalizeTexto(_cor.text),
          placa: DriverProfile.normalizePlaca(_placa.text),
        ),
      ),
      _ => await widget.onSaveFinancial(
        DriverFinancialData(
          paymentMethods: {..._formasPagamento},
          precoPorKm: _precoPorKmValido!,
        ),
      ),
    };
    if (!mounted) return;
    setState(() {
      _enviando = false;
      _erroEnvio = erro;
      if (erro == null && _etapa < 2) _etapa++;
    });
    // Na edição (aberta a partir de "Mais") a tela continua montada depois da
    // última etapa: confirma e volta a "Mais". No cadastro inicial ela é
    // substituída pela tela principal e nunca chega aqui montada.
    if (erro == null && ultimaEtapa && mounted) {
      _concluida();
    }
  }

  void _concluida() {
    if (widget.initial?.isComplete ?? false) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(const SnackBar(content: Text('Cadastro salvo')));
      final navigator = Navigator.of(context);
      // Sem rota para desempilhar (tela montada direto), volta à etapa 1.
      if (navigator.canPop()) {
        navigator.pop();
      } else {
        setState(() => _etapa = 0);
      }
    }
  }

  // Tokens da identidade visual, de [IdentidadeVisual] (constituição 2.7.0).
  static const _fundo = IdentidadeVisual.fundo;
  static const _segmentoInativo = IdentidadeVisual.segmentoInativo;
  static const _destaque = IdentidadeVisual.destaque;
  static const _folha = IdentidadeVisual.folha;
  static const _campo = IdentidadeVisual.campo;
  static const _roxo = IdentidadeVisual.roxo;
  static const _texto = IdentidadeVisual.texto;
  static const _textoSuave = IdentidadeVisual.textoSuave;
  static const _brancoSuave = IdentidadeVisual.brancoSuave;
  static const _estiloValor = IdentidadeVisual.estiloValor;
  static const _seta = Icon(
    Icons.arrow_drop_down,
    color: IdentidadeVisual.roxo,
  );

  InputDecoration _decoracaoCampo({
    required String rotulo,
    String? dica,
    String? ajuda,
    String? erro,
    bool habilitado = true,
  }) => decoracaoCampo(
    rotulo: rotulo,
    dica: dica,
    ajuda: ajuda,
    erro: erro,
    habilitado: habilitado,
  );

  List<Widget> _camposEtapa1() {
    final municipios = _uf == null
        ? const <Municipio>[]
        : Municipio.doEstado(_uf!);
    const estiloValor = _estiloValor;
    const seta = _seta;
    return [
      TextField(
        controller: _nome,
        textCapitalization: TextCapitalization.words,
        style: estiloValor,
        decoration: _decoracaoCampo(
          rotulo: 'Nome',
          dica: 'Seu nome completo',
          erro: _nome.text.isEmpty || _nomeValido ? null : 'Informe um nome',
        ),
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        initialValue: _uf,
        icon: seta,
        style: estiloValor,
        borderRadius: BorderRadius.circular(16),
        hint: const Text(
          'Selecione',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: _textoSuave,
          ),
        ),
        decoration: _decoracaoCampo(rotulo: 'UF'),
        items: [
          for (final uf in brazilianStates)
            DropdownMenuItem(
              value: uf.sigla,
              child: Text('${uf.sigla} — ${uf.nome}'),
            ),
        ],
        onChanged: _onUfChanged,
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        key: ValueKey('cidade-$_uf'),
        initialValue: _cidade,
        icon: seta,
        style: estiloValor,
        borderRadius: BorderRadius.circular(16),
        hint: Text(
          _uf == null ? '—' : 'Selecione',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: _textoSuave,
          ),
        ),
        decoration: _decoracaoCampo(
          rotulo: 'Cidade',
          ajuda: _uf == null ? 'Escolha a UF primeiro' : null,
          habilitado: _uf != null,
        ),
        items: [
          for (final municipio in municipios)
            DropdownMenuItem(
              value: municipio.nome,
              child: Text(municipio.nome),
            ),
        ],
        onChanged: _uf == null
            ? null
            : (cidade) => setState(() => _cidade = cidade),
      ),
    ];
  }

  List<Widget> _camposEtapa2() {
    return [
      TextField(
        controller: _marca,
        style: _estiloValor,
        decoration: _decoracaoCampo(
          rotulo: 'Marca',
          dica: 'Ex.: Fiat',
          erro: _marca.text.isEmpty || _marcaValida ? null : 'Informe a marca',
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _modelo,
        style: _estiloValor,
        decoration: _decoracaoCampo(
          rotulo: 'Modelo',
          dica: 'Ex.: Palio',
          erro: _modelo.text.isEmpty || _modeloValido
              ? null
              : 'Informe o modelo',
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _ano,
        keyboardType: TextInputType.number,
        maxLength: 4,
        style: _estiloValor,
        decoration: _decoracaoCampo(
          rotulo: 'Ano',
          dica: 'Ex.: 2018',
          erro: _ano.text.isEmpty || _anoValido != null
              ? null
              : 'Informe um ano válido de 4 dígitos',
        ).copyWith(counterText: ''),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _cor,
        style: _estiloValor,
        decoration: _decoracaoCampo(
          rotulo: 'Cor',
          dica: 'Ex.: Preto',
          erro: _cor.text.isEmpty || _corValida ? null : 'Informe a cor',
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _placa,
        textCapitalization: TextCapitalization.characters,
        style: _estiloValor,
        decoration: _decoracaoCampo(
          rotulo: 'Placa',
          dica: 'ABC1234 ou ABC1D23',
          erro: _placa.text.isEmpty || _placaValida
              ? null
              : 'Placa fora do formato antigo ou Mercosul',
        ),
      ),
    ];
  }

  List<Widget> _camposEtapa3() {
    return [
      const Padding(
        padding: EdgeInsets.only(left: 4, bottom: 8),
        child: Text(
          'Formas de pagamento aceitas',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: _texto,
          ),
        ),
      ),
      for (final forma in PaymentMethod.values)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: _campo,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: CheckboxListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              controlAffinity: ListTileControlAffinity.leading,
              activeColor: _roxo,
              side: const BorderSide(color: _roxo, width: 2),
              checkboxShape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
              title: Text(forma.label, style: _estiloValor),
              value: _formasPagamento.contains(forma),
              onChanged: (marcado) => setState(() {
                if (marcado ?? false) {
                  _formasPagamento.add(forma);
                } else {
                  _formasPagamento.remove(forma);
                }
              }),
            ),
          ),
        ),
      if (_formasPagamento.isEmpty)
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 4),
          child: Text(
            'Marque ao menos uma forma de pagamento',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        ),
      const SizedBox(height: 12),
      TextField(
        controller: _precoPorKm,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: _estiloValor,
        decoration: _decoracaoCampo(
          rotulo: 'Preço por quilômetro',
          dica: 'Ex.: 2,50',
          ajuda:
              'Valor sugerido — você pode alterá-lo em cada corrida '
              'que decidir aceitar.',
          erro: _precoPorKm.text.isEmpty || _precoPorKmValido != null
              ? null
              : 'Informe um preço válido, maior que zero',
        ),
      ),
    ];
  }

  /// Esqueleto visual da identidade (constituição 2.5.1): cabeçalho escuro
  /// com barra de progresso, folha clara com os [campos] e ação primária
  /// fixa no rodapé. Usado pelas etapas 1 e 2.
  Widget _buildEtapaTematizada(
    BuildContext context,
    bool editando, {
    required String titulo,
    required List<Widget> campos,
  }) {
    final etapa = _etapa;
    return Scaffold(
      backgroundColor: _fundo,
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // Empilhada a partir de "Mais" tem para onde voltar; no
                      // cadastro inicial (tela raiz) não há.
                      if (Navigator.of(context).canPop())
                        const BackButton(color: _brancoSuave),
                      Expanded(
                        child: Text(
                          editando
                              ? 'Editar cadastro'
                              : 'Cadastro do motorista',
                          style: const TextStyle(
                            color: _brancoSuave,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Etapa ${etapa + 1} de 3',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      for (var i = 0; i < 3; i++) ...[
                        if (i > 0) const SizedBox(width: 4),
                        Expanded(
                          child: Container(
                            height: 3,
                            decoration: BoxDecoration(
                              color: i <= etapa ? _destaque : _segmentoInativo,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    titulo,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (!editando && etapa == 0) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'Antes de usar o aplicativo, precisamos dos seus dados '
                      'e os do seu veículo.',
                      style: TextStyle(color: _brancoSuave, fontSize: 15),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: _folha,
                borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              ...campos,
                              if (_erroEnvio != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: Text(
                                    _erroEnvio!,
                                    style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .error,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _etapaValida && !_enviando ? _enviar : null,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(56),
                          backgroundColor: _roxo,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: const Color(0xFFE7E1F7),
                          disabledForegroundColor: const Color(0xFF9C94B5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        icon: _enviando
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(
                                etapa == 2 ? Icons.check : Icons.arrow_forward,
                                size: 18,
                              ),
                        label: Text(
                          etapa == 2
                              ? 'Concluir cadastro'
                              : 'Salvar e continuar',
                        ),
                      ),
                      if (etapa > 0)
                        TextButton(
                          onPressed: _enviando
                              ? null
                              : () => setState(() => _etapa--),
                          style: TextButton.styleFrom(foregroundColor: _roxo),
                          child: const Text('Voltar'),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editando = widget.initial?.isComplete ?? false;
    if (_etapa == 0) {
      return _buildEtapaTematizada(
        context,
        editando,
        titulo: 'Dados do motorista',
        campos: _camposEtapa1(),
      );
    }
    if (_etapa == 1) {
      return _buildEtapaTematizada(
        context,
        editando,
        titulo: 'Dados do veículo',
        campos: _camposEtapa2(),
      );
    }
    return _buildEtapaTematizada(
      context,
      editando,
      titulo: 'Financeiro',
      campos: _camposEtapa3(),
    );
  }
}
