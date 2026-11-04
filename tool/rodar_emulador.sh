#!/usr/bin/env bash
# Sobe o emulador Pixel_6_API34_1 (se preciso), instala e roda o app do motorista nele.
# Uso: tool/rodar_emulador.sh [EXEC_ID]    (padrão: manual; veja LOGS.md)
set -euo pipefail

AVD="${AVD:-Pixel_6_API34_1}"
PORTA="${PORTA:-5554}"
SERIAL="emulator-$PORTA"
EXEC_ID="${1:-manual}"

SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}}"
EMULATOR="$SDK/emulator/emulator"
ADB="$SDK/platform-tools/adb"
[ -x "$EMULATOR" ] || EMULATOR="$(command -v emulator)"
[ -x "$ADB" ] || ADB="$(command -v adb)"

cd "$(dirname "$0")/.."

"$EMULATOR" -list-avds | grep -qx "$AVD" || { echo "AVD '$AVD' não existe." >&2; exit 1; }

if "$ADB" devices | grep -q "^$SERIAL[[:space:]]*device"; then
  echo "Emulador $SERIAL já está no ar."
else
  echo "Subindo $AVD em $SERIAL..."
  mkdir -p logs-emulador
  nohup "$EMULATOR" -avd "$AVD" -port "$PORTA" -no-snapshot-save \
    > "logs-emulador/$AVD.log" 2>&1 &
  "$ADB" -s "$SERIAL" wait-for-device
  echo "Aguardando o boot terminar..."
  until [ "$("$ADB" -s "$SERIAL" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; do
    sleep 2
  done
fi

flutter pub get
# 'flutter run' compila, instala e inicia o app; Ctrl+C encerra a sessão (o emulador continua).
exec flutter run -d "$SERIAL" --dart-define=EXEC_ID="$EXEC_ID"
