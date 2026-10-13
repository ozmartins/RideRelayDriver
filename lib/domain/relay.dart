/// Estado de conexão de um relay.
enum RelayStatus {
  /// Tentativa de conexão em andamento.
  connecting,

  /// Conectado e apto a publicar e receber.
  connected,

  /// Indisponível: falhou, expirou ou perdeu a conexão.
  unavailable,
}

/// Um relay Nostr da lista do motorista.
///
/// Relays são independentes: o estado de um não afeta o de outro (FR-003).
class Relay {
  const Relay({
    required this.url,
    this.status = RelayStatus.connecting,
    this.lastError,
    this.isDefault = false,
  });

  /// Endereço do relay (`wss://` ou `ws://`). É a identidade da entidade.
  final String url;

  /// Estado atual da conexão.
  final RelayStatus status;

  /// Motivo resumido da indisponibilidade, para exibição ao usuário.
  final String? lastError;

  /// Verdadeiro quando o relay vem da lista padrão embutida.
  final bool isDefault;

  Relay copyWith({
    RelayStatus? status,
    String? lastError,
    bool clearError = false,
  }) {
    return Relay(
      url: url,
      status: status ?? this.status,
      lastError: clearError ? null : (lastError ?? this.lastError),
      isDefault: isDefault,
    );
  }

  /// Aceita apenas endereços WebSocket com host preenchido.
  ///
  /// Não exige ponto no host: um relay local de teste (`ws://localhost:7777`)
  /// é um endereço válido, e exigir domínio com ponto o rejeitaria sem motivo
  /// de segurança — a mesma regra do passageiro.
  static bool isValidUrl(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return false;
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return false;
    if (uri.scheme != 'wss' && uri.scheme != 'ws') return false;
    return uri.host.isNotEmpty;
  }

  /// Normaliza o endereço para comparação de duplicados.
  static String normalizeUrl(String raw) {
    var normalized = raw.trim();
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized.toLowerCase();
  }

  @override
  bool operator ==(Object other) =>
      other is Relay && normalizeUrl(other.url) == normalizeUrl(url);

  @override
  int get hashCode => normalizeUrl(url).hashCode;

  @override
  String toString() => 'Relay($url, $status)';
}
