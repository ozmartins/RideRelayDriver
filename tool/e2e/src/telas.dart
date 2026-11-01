/// Catálogo de rótulos dos dois apps usados pelo roteiro (feature 029) e das
/// telas sensíveis. Os rótulos vêm do código dos apps; qualquer divergência
/// encontrada no ensaio atualiza este arquivo e é registrada em `desvios.md`.
class Rotulos {
  const Rotulos._();

  // Passageiro
  static const campoDestino = 'Para onde você quer ir?';
  static const solicitar = 'Solicitar corrida';
  static const aguardandoOrcamentos = 'Aguardando orçamentos…';
  static const orcamentosRecebidos = 'Orçamentos recebidos';
  static const aceitar = 'Aceitar';
  static const motoristaACaminho = 'Motorista a caminho';
  static const ok = 'OK';
  static const motoristaChegou = 'Motorista chegou';
  static const confirmarEncontro = 'Confirmo que encontrei o motorista';
  static const confirmarDestino = 'Confirmar chegada ao destino';
  static const cancelarPassageiro = 'Cancelar corrida';
  static const calculandoDistancia = 'Calculando distância…';

  // Motorista
  static const motoristaOnline = 'Você está online';
  static const motoristaOffline = 'Você está offline';
  static const ficarOnline = 'Toque para receber solicitações';
  static const solicitacaoDeCorrida = 'Solicitação de corrida';
  static const enviarOrcamento = 'Enviar orçamento';
  static const orcamentoAceito = 'Orçamento aceito';
  static const iniciarCorrida = 'Iniciar corrida';
  static const corridaEmAndamento = 'CORRIDA EM ANDAMENTO';
  static const cancelarMotorista = 'Cancelar corrida';

  // Os dois
  static const avalieACorrida = 'Avalie a corrida';
  static const confirmar = 'Confirmar';
}

/// Mensagens dos apps que atribuem uma falha a um serviço externo (D9, FR-021a).
class SinaisDeInterface {
  const SinaisDeInterface._();

  static const photon = 'Não foi possível buscar endereços no momento';
  static const rotaOrs1 = 'Não foi possível calcular a distância';
  static const rotaOrs2 = 'Não foi possível traçar a rota';
}

/// Trechos que denunciam uma tela sensível (D10): nunca se grava captura nem
/// dump delas. Comparação por substring no texto visível.
const List<String> marcadoresDeTelaSensivel = <String>[
  'Cadastro do motorista',
  'Dados do motorista',
  'Dados do veículo',
  'Concluir cadastro',
  'Salvar e continuar',
  'Editar cadastro',
  'Cadastro salvo',
  'Servidores por onde o app se comunica',
  'Minha identidade',
  'Chave pública',
  'Copiar chave pública',
  'chave privada',
  'Chave privada',
  'backup',
  'Backup',
  'Como podemos te chamar?',
  'Alterar nome',
];
