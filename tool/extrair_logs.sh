#!/usr/bin/env bash
# Extrai do aparelho os logs do fluxo do app do motorista (build debug; veja LOGS.md).
# Uso: tool/extrair_logs.sh [DESTINO]    (padrão: logs-driver)
# Variáveis: SERIAL (aparelho, se houver mais de um), PACOTE (padrão: o do motorista).
set -euo pipefail

DESTINO="${1:-logs-driver}"
PACOTE="${PACOTE:-br.ufsc.tcc.corridas.driver}"

SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}}"
ADB="$SDK/platform-tools/adb"
[ -x "$ADB" ] || ADB="$(command -v adb)"

cd "$(dirname "$0")/.."

ADB_ARGS=()
if [ -n "${SERIAL:-}" ]; then
  ADB_ARGS=(-s "$SERIAL")
else
  N="$("$ADB" devices | awk 'NR>1 && $2=="device"' | wc -l)"
  if [ "$N" -eq 0 ]; then
    echo "Nenhum aparelho conectado (veja 'adb devices')." >&2
    exit 1
  elif [ "$N" -gt 1 ]; then
    echo "Há $N aparelhos conectados; informe SERIAL=<serial> (veja 'adb devices')." >&2
    exit 1
  fi
fi

mkdir -p "$DESTINO"
extraidos=0
for f in fluxo-ui.jsonl fluxo-servico.jsonl fluxo-ui.jsonl.1 fluxo-servico.jsonl.1; do
  saida="$DESTINO/$f"
  # run-as só funciona em build debug; arquivo inexistente faz o cat falhar.
  if "$ADB" "${ADB_ARGS[@]}" exec-out run-as "$PACOTE" cat "databases/logs/$f" \
      > "$saida" 2>/dev/null && [ -s "$saida" ]; then
    echo "$f: $(wc -l < "$saida") linhas"
    extraidos=$((extraidos + 1))
  else
    rm -f "$saida"
  fi
done

if [ "$extraidos" -eq 0 ]; then
  echo "Nenhum log extraído. O app é build debug e já rodou uma corrida? (pacote: $PACOTE)" >&2
  exit 1
fi
echo "Logs em $DESTINO/. Contêm dados de passageiros: anonimize antes de sair da máquina."
