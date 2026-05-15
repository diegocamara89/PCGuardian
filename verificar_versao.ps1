# Diagnostico do estado dos processos SegurancaPC
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "Verificando estado do PC Security" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host ""

# Listar processos via CIM (CommandLine indisponivel em Get-Process no PS 5.1)
$procs = Get-CimInstance Win32_Process |
    Where-Object { $_.CommandLine -match 'SegurancaPC\\Scripts\\([A-Za-z]+)\.ps1' } |
    Select-Object ProcessId,
        @{N='Script';E={ if ($_.CommandLine -match '\\([^\\]+\.ps1)') { $Matches[1] } else { 'unknown' } }},
        CreationDate

Write-Host "Processos em execucao:" -ForegroundColor Yellow
if ($procs) {
    $procs | Format-Table -AutoSize
} else {
    Write-Host "  [AVISO] Nenhum processo SegurancaPC esta rodando" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "Verificando versoes dos arquivos:" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan

foreach ($file in @(
    'C:\SegurancaPC\Scripts\TelegramListener.ps1',
    'C:\SegurancaPC\Scripts\MonitorInatividade.ps1',
    'C:\SegurancaPC\Scripts\MonitorFET.ps1',
    'C:\SegurancaPC\Scripts\MonitorLogin.ps1',
    'C:\SegurancaPC\Scripts\Controlador.ps1',
    'C:\SegurancaPC\Scripts\Common.psm1'
)) {
    if (-not (Test-Path $file)) {
        Write-Host "  [FALTA] $file" -ForegroundColor Red
        continue
    }
    $content = Get-Content $file -Raw
    if ($content -match '\$script:Version\s*=\s*[''"]([\d.]+)[''"]') {
        Write-Host "  [OK]   $([System.IO.Path]::GetFileName($file)) -> v$($Matches[1])" -ForegroundColor Green
    } elseif ($content -match 'v(\d+\.\d+)') {
        Write-Host "  [INFO] $([System.IO.Path]::GetFileName($file)) -> referencia v$($Matches[1]) no comentario" -ForegroundColor Gray
    } else {
        Write-Host "  [?]    $([System.IO.Path]::GetFileName($file)) -> versao nao identificada" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "Se algum processo estiver desatualizado, reinicie com:" -ForegroundColor Yellow
Write-Host "  C:\SegurancaPC\reiniciar_sistema.bat" -ForegroundColor Cyan
