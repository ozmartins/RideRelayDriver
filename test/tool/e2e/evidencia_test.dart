import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../tool/e2e/src/evidencia.dart';
import '../../../tool/e2e/src/ui.dart';
import 'support/fake_adb.dart';

void main() {
  late Directory pasta;
  late FakeAdb adb;
  late Evidencia evidencia;

  setUp(() {
    pasta = Directory.systemTemp.createTempSync('evid_');
    adb = FakeAdb();
    evidencia = Evidencia(adb: adb, pasta: Directory('${pasta.path}/capturas'));
  });

  tearDown(() => pasta.deleteSync(recursive: true));

  test('mapa comum: grava o PNG e, se pedido, o dump', () async {
    adb.telas['s'] = const [ElementoFake('Você está online')];
    final r = await evidencia.capturar(
      serial: 's',
      prefixo: 'c001-teste',
      comDump: true,
    );
    expect(r, ['capturas/c001-teste.png', 'capturas/c001-teste.xml']);
    expect(File('${pasta.path}/capturas/c001-teste.png').existsSync(), isTrue);
    expect(File('${pasta.path}/capturas/c001-teste.xml').existsSync(), isTrue);
  });

  for (final sensivel in const [
    'Minha identidade',
    'Chave pública',
    'Cadastro do motorista',
    'Servidores por onde o app se comunica',
    'Concluir cadastro',
    'Como podemos te chamar?',
  ]) {
    test('tela sensível "$sensivel": nada é gravado', () async {
      adb.telas['s'] = [ElementoFake(sensivel)];
      final r = await evidencia.capturar(
        serial: 's',
        prefixo: 'x',
        comDump: true,
      );
      expect(r.single, contains('omitida'));
      expect(Directory('${pasta.path}/capturas').existsSync(), isFalse);
      expect(adb.chamadas.where((c) => c.startsWith('captura')), isEmpty);
    });
  }

  test('falha do adb na captura não lança: devolve o motivo', () async {
    adb.falhaGeral = 'offline';
    final r = await evidencia.capturar(serial: 's', prefixo: 'x');
    expect(r.single, contains('não realizada'));
  });

  test('permitida usa a tela já lida', () {
    expect(Evidencia.permitida(Tela.parse(adb.xmlDe('vazio'))), isTrue);
  });
}
