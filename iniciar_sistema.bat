@echo off
setlocal EnableExtensions
set "BASE=%~dp0"
echo Iniciando PC Security a partir de %BASE%

if not exist "%BASE%Screenshots" mkdir "%BASE%Screenshots"
if not exist "%BASE%Screenshots\FET" mkdir "%BASE%Screenshots\FET"

echo Iniciando TelegramListener...
start /B powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "%BASE%Scripts\TelegramListener.ps1"

echo Aguardando 3 segundos...
timeout /T 3 /NOBREAK >nul

echo Iniciando MonitorInatividade...
start /B powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "%BASE%Scripts\MonitorInatividade.ps1"

echo Iniciando MonitorFET...
start /B powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "%BASE%Scripts\MonitorFET.ps1"

echo.
echo Sistema iniciado. Envie /help no Telegram para testar.
echo.
pause
endlocal
