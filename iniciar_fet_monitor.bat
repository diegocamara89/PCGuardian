@echo off
echo ====================================
echo Iniciando Monitor FET (OCR)
echo PC Security v6.6
echo ====================================
echo.
echo IMPORTANTE: Este monitor fica DESATIVADO por padrao.
echo Use /monitorfet_on no Telegram para ativar.
echo.
echo Alertas:
echo - Regressao de 30+ atividades
echo - Travamento (30min sem progresso)
echo - Conclusao (todas atividades alocadas)
echo - Nova execucao detectada
echo.
echo Iniciando em background...

start /B powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File "C:\SegurancaPC\Scripts\MonitorFET.ps1"

echo.
echo Monitor FET iniciado!
echo Use /fetstatus para ver o status atual.
echo.
pause
