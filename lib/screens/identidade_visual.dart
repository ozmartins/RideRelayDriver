import 'package:flutter/material.dart';

/// Tokens e componentes da identidade visual (seção "Identidade Visual e
/// Design" da constituição, v2.7.0) — fonte única no aplicativo: nenhuma tela
/// declara cor, raio ou tamanho próprio que conste da constituição.
class IdentidadeVisual {
  const IdentidadeVisual._();

  static const fundo = Color(0xFF24124F);
  static const fundoProfundo = Color(0xFF140A26);
  static const segmentoInativo = Color(0xFF382469);
  static const destaque = Color(0xFFC8F169);
  static const folha = Color(0xFFFAF8FF);
  static const campo = Color(0xFFF4F0FF);
  static const roxo = Color(0xFF6B3FE0);
  static const texto = Color(0xFF3D3358);
  static const textoSuave = Color(0xFF6E6789);
  static const desabilitado = Color(0xFFA6A1B8);

  /// Branco a 87% — subtítulo e título da barra sobre `fundo`.
  static const brancoSuave = Color(0xDEFFFFFF);

  /// Botão primário indisponível.
  static const botaoDesabilitadoFundo = Color(0xFFE7E1F7);
  static const botaoDesabilitadoTexto = Color(0xFF9C94B5);

  static const estiloValor = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: texto,
  );

  /// Ação primária: `roxo` com texto branco, [altura] 56 (tela) ou 48 (modal).
  static ButtonStyle estiloAcaoPrimaria({double altura = 56}) =>
      FilledButton.styleFrom(
        minimumSize: Size.fromHeight(altura),
        backgroundColor: roxo,
        foregroundColor: Colors.white,
        disabledBackgroundColor: botaoDesabilitadoFundo,
        disabledForegroundColor: botaoDesabilitadoTexto,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      );

  /// Ação secundária: texto `roxo`.
  static ButtonStyle get estiloAcaoSecundaria => TextButton.styleFrom(
    foregroundColor: roxo,
    textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
  );
}

/// Campo preenchido, com o rótulo sempre visível dentro do campo, acima do
/// valor.
InputDecoration decoracaoCampo({
  required String rotulo,
  String? dica,
  String? ajuda,
  String? erro,
  bool habilitado = true,
}) {
  return InputDecoration(
    labelText: rotulo,
    hintText: dica,
    helperText: ajuda,
    helperMaxLines: 2,
    errorText: erro,
    floatingLabelBehavior: FloatingLabelBehavior.always,
    labelStyle: TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      color: habilitado
          ? IdentidadeVisual.texto
          : IdentidadeVisual.desabilitado,
    ),
    hintStyle: const TextStyle(
      fontWeight: FontWeight.w600,
      color: IdentidadeVisual.textoSuave,
    ),
    helperStyle: const TextStyle(
      fontSize: 12,
      color: IdentidadeVisual.textoSuave,
    ),
    filled: true,
    fillColor: habilitado
        ? IdentidadeVisual.campo
        : IdentidadeVisual.campo.withValues(alpha: 0.6),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    // Sem traço (UnderlineInputBorder), para o rótulo flutuante ficar dentro
    // do campo e não sobre a borda.
    border: UnderlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide.none,
    ),
  );
}

/// Tela de conteúdo sem etapas: cabeçalho escuro (título da barra e título
/// grande) e folha clara de cantos superiores arredondados.
class TelaDeConteudo extends StatelessWidget {
  const TelaDeConteudo({
    super.key,
    required this.tituloBarra,
    required this.titulo,
    required this.child,
    this.acoes = const [],
    this.botaoFlutuante,
  });

  final String tituloBarra;
  final String titulo;
  final Widget child;

  /// Ícones de ação, alinhados à direita da linha do título da barra.
  final List<Widget> acoes;

  /// Botão flutuante estendido opcional (canto inferior direito).
  final Widget? botaoFlutuante;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: IdentidadeVisual.fundo,
      floatingActionButton: botaoFlutuante,
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: SizedBox(
              width: double.infinity,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    IconTheme.merge(
                      data: const IconThemeData(
                        color: IdentidadeVisual.brancoSuave,
                      ),
                      child: Row(
                        children: [
                          if (Navigator.of(context).canPop())
                            const BackButton(
                              color: IdentidadeVisual.brancoSuave,
                            ),
                          Expanded(
                            child: Text(
                              tituloBarra,
                              style: const TextStyle(
                                color: IdentidadeVisual.brancoSuave,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          ...acoes,
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      titulo,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: IdentidadeVisual.folha,
                borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
              ),
              child: SafeArea(top: false, child: child),
            ),
          ),
        ],
      ),
    );
  }
}

/// Modal da identidade: fundo `folha`, raio 24, título 20/800 e corpo 15.
class ModalTematizado extends StatelessWidget {
  const ModalTematizado({
    super.key,
    required this.titulo,
    required this.conteudo,
    required this.acoes,
  });

  final String titulo;
  final Widget conteudo;
  final List<Widget> acoes;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: IdentidadeVisual.folha,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text(
        titulo,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: IdentidadeVisual.texto,
        ),
      ),
      content: DefaultTextStyle.merge(
        style: const TextStyle(fontSize: 15, color: IdentidadeVisual.texto),
        child: conteudo,
      ),
      actions: acoes,
    );
  }
}
