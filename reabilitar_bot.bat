@echo off
echo ====================================
echo Reabilitando tarefa agendada SegurancaPC
echo ====================================
echo.
echo Este script precisa de permissoes de Administrador.
echo Clique com botao direito e escolha "Executar como administrador".
echo.
pause

powershell.exe -NoProfile -Command "Enable-ScheduledTask -TaskName 'SegurancaPC_AutoStart' -ErrorAction Stop; Write-Host '[OK] SegurancaPC_AutoStart reabilitado' -ForegroundColor Green" 2>nul
if %errorlevel% neq 0 (
    echo [ERRO] Falha ao reabilitar a tarefa. Confira o nome:
    powershell.exe -NoProfile -Command "schtasks /Query | Select-String 'Seguranca'"
)

echo.
echo ====================================
echo Deseja iniciar o sistema agora?
echo ====================================
set /p choice="Digite S para sim ou N para nao: "

if /i "%choice%"=="S" (
    echo Iniciando sistema...
    start "" "C:\SegurancaPC\iniciar_sistema.bat"
) else (
    echo Sistema nao foi iniciado. Execute iniciar_sistema.bat manualmente.
)

echo.
pause
