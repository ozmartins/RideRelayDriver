import 'package:flutter_test/flutter_test.dart';

import '../../../tool/e2e/src/classificacao.dart';

void main() {
  group('classificar', () {
    test('ambiente: adb indisponível', () {
      final c = classificar(const Evidencias(adbIndisponivel: true));
      expect(c.origem, OrigemFalha.ambienteTeste);
      expect(c.origemBruta, 'ambiente_teste');
    });

    test('ambiente: observador sem nenhum relay', () {
      final c = classificar(const Evidencias(observadorSemRelays: true));
      expect(c.origem, OrigemFalha.ambienteTeste);
    });

    test('ambiente vence serviço externo (menor número)', () {
      final c = classificar(
        const Evidencias(
          adbIndisponivel: true,
          sinalExterno: SinalExterno(fonte: 'ui', servico: 'Photon'),
        ),
      );
      expect(c.origem, OrigemFalha.ambienteTeste);
    });

    test('serviço externo: sinal de UI do Photon', () {
      final c = classificar(
        const Evidencias(
          sinalExterno: SinalExterno(fonte: 'ui', servico: 'Photon'),
        ),
      );
      expect(c.origem, OrigemFalha.servicoExterno);
      expect(c.servicoExterno, 'Photon');
      expect(c.sinal!.fonte, 'ui');
    });

    test('serviço externo vence relays', () {
      final c = classificar(
        const Evidencias(
          sinalExterno: SinalExterno(
            fonte: 'logcat',
            servico: 'OpenRouteService',
            http: 429,
          ),
          acaoExecutada: true,
          eventoEsperado: true,
          eventoObservado: true,
          efeitoRemotoAusente: true,
        ),
      );
      expect(c.origem, OrigemFalha.servicoExterno);
      expect(c.sinal!.http, 429);
    });

    test('sem sinal nunca é externo', () {
      final c = classificar(const Evidencias());
      expect(c.origem, OrigemFalha.aplicativo);
      expect(c.servicoExterno, isNull);
    });

    test('relays: evento visto em algum relay e o app não avançou', () {
      final c = classificar(
        const Evidencias(
          acaoExecutada: true,
          eventoEsperado: true,
          eventoObservado: true,
          efeitoRemotoAusente: true,
        ),
      );
      expect(c.origem, OrigemFalha.relays);
      expect(c.origemBruta, 'relays');
    });

    test('aplicativo: elemento ausente sem ação executada', () {
      final c = classificar(const Evidencias(eventoEsperado: true));
      expect(c.origem, OrigemFalha.aplicativo);
      expect(c.origemBruta, 'aplicativo');
    });

    test('aplicativo: processo ausente', () {
      final c = classificar(
        const Evidencias(
          acaoExecutada: true,
          eventoEsperado: true,
          processoAppAusente: true,
        ),
      );
      expect(c.origem, OrigemFalha.aplicativo);
      expect(c.origemBruta, 'aplicativo');
    });

    test('indeterminada: ação feita, evento em nenhum relay → aplicativo', () {
      final c = classificar(
        const Evidencias(acaoExecutada: true, eventoEsperado: true),
      );
      expect(c.origem, OrigemFalha.aplicativo);
      expect(c.origemBruta, 'indeterminada');
    });
  });

  group('detectarSinalExterno', () {
    test('mensagem do Photon na tela', () {
      final s = detectarSinalExterno(
        textoTela:
            'Não foi possível buscar endereços no momento. Verifique sua',
      );
      expect(s!.servico, 'Photon');
      expect(s.fonte, 'ui');
    });

    test('mensagem de rota na tela → OpenRouteService', () {
      expect(
        detectarSinalExterno(
          textoTela: 'Não foi possível traçar a rota agora.',
        )!.servico,
        'OpenRouteService',
      );
      expect(
        detectarSinalExterno(
          textoTela:
              'Não foi possível calcular a distância até o destino agora.',
        )!.servico,
        'OpenRouteService',
      );
    });

    test('logcat de distância com HTTP 429', () {
      final s = detectarSinalExterno(
        linhasLogcat: [
          'I/flutter ( 1): outra coisa',
          'I/flutter ( 1): Distância motorista→origem falhou: status 429',
        ],
      );
      expect(s!.servico, 'OpenRouteService');
      expect(s.http, 429);
      expect(limiteDiarioOrsEsgotado(s), isTrue);
    });

    test('logcat de distância sem 429 não é limite diário', () {
      final s = detectarSinalExterno(
        linhasLogcat: [
          'I/flutter ( 1): Distância origem→destino falhou: timeout',
        ],
      );
      expect(s!.servico, 'OpenRouteService');
      expect(limiteDiarioOrsEsgotado(s), isFalse);
    });

    test('logcat de endereço → Photon; de tiles → OpenFreeMap', () {
      expect(
        detectarSinalExterno(
          linhasLogcat: ['I/flutter ( 1): Endereço do destino falhou: x'],
        )!.servico,
        'Photon',
      );
      expect(
        detectarSinalExterno(
          linhasLogcat: ['I/flutter ( 1): tile request failed for openfreemap'],
        )!.servico,
        'OpenFreeMap',
      );
    });

    test('nada reconhecível → null', () {
      expect(
        detectarSinalExterno(
          textoTela: 'Você está online',
          linhasLogcat: ['I/flutter ( 1): tudo bem'],
        ),
        isNull,
      );
    });
  });
}
