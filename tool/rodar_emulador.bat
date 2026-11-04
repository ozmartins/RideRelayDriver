@echo off
rem Sobe o emulador Pixel_6_API34_1 (se preciso), instala e roda o app do motorista nele.
rem Uso: tool\rodar_emulador.bat [EXEC_ID]    (padrao: manual; veja LOGS.md)
rem Variaveis opcionais: AVD, PORTA, ANDROID_HOME / ANDROID_SDK_ROOT.
setlocal EnableExtensions

if not defined AVD set "AVD=Pixel_6_API34_1"
if not defined PORTA set "PORTA=5554"
set "SERIAL=emulator-%PORTA%"
set "EXEC_ID=%~1"
if not defined EXEC_ID set "EXEC_ID=manual"

if defined ANDROID_HOME (
  set "SDK=%ANDROID_HOME%"
) else if defined ANDROID_SDK_ROOT (
  set "SDK=%ANDROID_SDK_ROOT%"
) else (
  set "SDK=%LOCALAPPDATA%\Android\Sdk"
)
set "EMULATOR=%SDK%\emulator\emulator.exe"
set "ADB=%SDK%\platform-tools\adb.exe"
if not exist "%EMULATOR%" set "EMULATOR=emulator"
if not exist "%ADB%" set "ADB=adb"

cd /d "%~dp0.."

"%EMULATOR%" -list-avds | findstr /x /c:"%AVD%" >nul
if errorlevel 1 (
  echo AVD '%AVD%' nao existe. 1>&2
  exit /b 1
)

"%ADB%" devices | findstr /r /c:"^%SERIAL%[ 	]*device" >nul
if not errorlevel 1 (
  echo Emulador %SERIAL% ja esta no ar.
  goto rodar
)

echo Subindo %AVD% em %SERIAL%...
if not exist logs-emulador mkdir logs-emulador
start "" /b "%EMULATOR%" -avd %AVD% -port %PORTA% -no-snapshot-save > "logs-emulador\%AVD%.log" 2>&1
"%ADB%" -s %SERIAL% wait-for-device
echo Aguardando o boot terminar...
:boot
set "BOOT="
for /f "delims=" %%i in ('"%ADB%" -s %SERIAL% shell getprop sys.boot_completed 2^>nul') do set "BOOT=%%i"
if "%BOOT%"=="1" goto rodar
timeout /t 2 /nobreak >nul
goto boot

:rodar
call flutter pub get || exit /b %errorlevel%
rem 'flutter run' compila, instala e inicia o app; Ctrl+C encerra a sessao (o emulador continua).
call flutter run -d %SERIAL% --dart-define=EXEC_ID=%EXEC_ID%
exit /b %errorlevel%
