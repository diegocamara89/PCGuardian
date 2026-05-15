@echo off
setlocal EnableExtensions
set "BASE=%~dp0"
echo ====================================
echo Reiniciando PC Security (%BASE%)
echo ====================================
echo.

echo Encerrando apenas processos SegurancaPC...
powershell.exe -NoProfile -Command "Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match 'SegurancaPC\\\\Scripts\\\\(TelegramListener|MonitorInatividade|MonitorFET|MonitorLogin)\.ps1' } | ForEach-Object { Invoke-CimMethod -InputObject $_ -MethodName Terminate | Out-Null }" 2>nul

timeout /T 2 /NOBREAK >nul

if not exist "%BASE%Screenshots" mkdir "%BASE%Screenshots"
if not exist "%BASE%Screenshots\FET" mkdir "%BASE%Screenshots\FET"

echo Iniciando TelegramListener...
start /B powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "%BASE%Scripts\TelegramListener.ps1"
timeout /T 3 /NOBREAK >nul

echo Iniciando MonitorInatividade...
start /B powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "%BASE%Scripts\MonitorInatividade.ps1"
timeout /T 1 /NOBREAK >nul

echo Iniciando MonitorFET...
start /B powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "%BASE%Scripts\MonitorFET.ps1"

echo.
echo Pronto. Teste com /help ou /fetstatus no Telegram.
echo.
pause
endlocal
