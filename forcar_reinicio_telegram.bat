@echo off
echo ====================================
echo Reinicio seguro dos processos SegurancaPC
echo ====================================
echo.
echo Encerrando apenas processos SegurancaPC (nao mexe em outros PowerShells)...

powershell.exe -NoProfile -Command ^
  "Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match 'SegurancaPC\\\\Scripts\\\\(TelegramListener|MonitorInatividade|MonitorFET|MonitorLogin)\.ps1' } | ForEach-Object { Invoke-CimMethod -InputObject $_ -MethodName Terminate | Out-Null; Write-Output ('Encerrado PID ' + $_.ProcessId) }"

echo.
echo Aguardando 3 segundos...
timeout /T 3 /NOBREAK >nul

echo.
echo Iniciando TelegramListener...
start /B powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File "C:\SegurancaPC\Scripts\TelegramListener.ps1"

timeout /T 2 /NOBREAK >nul

echo Iniciando MonitorInatividade...
start /B powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File "C:\SegurancaPC\Scripts\MonitorInatividade.ps1"

timeout /T 1 /NOBREAK >nul

echo Iniciando MonitorFET...
start /B powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File "C:\SegurancaPC\Scripts\MonitorFET.ps1"

echo.
echo ====================================
echo PRONTO!
echo ====================================
echo Teste com /help no Telegram.
echo.
pause
