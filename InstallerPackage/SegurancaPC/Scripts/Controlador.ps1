# Controlador.ps1 - Interface CLI interativa local para SegurancaPC
# Permite administrar o sistema sem depender do Telegram.
# Uso: powershell.exe -ExecutionPolicy Bypass -File "C:\SegurancaPC\Scripts\Controlador.ps1"

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'

$script:Version = '6.6'
Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -Force

$paths = Get-VigiaPaths
$basePath = $paths.Base
$configDir = $paths.ConfigDir
$scriptsDir = $paths.ScriptsDir
$settingsFile = $paths.SettingsFile
$monitorControlFile = Join-Path $configDir 'monitor_control.json'
$monitorStatusFile = Join-Path $configDir 'monitor_status.json'
$fetControlFile = Join-Path $configDir 'fet_control.json'
$fetStatusFile = Join-Path $configDir 'fet_status.json'
$accessLog = $paths.AccessLog
$debugLog = $paths.DebugLog

if (-not (Test-Path $settingsFile)) {
    Write-Host "ERRO: $settingsFile nao encontrado. Configure a instalacao primeiro." -ForegroundColor Red
    exit 1
}

$cfg = Get-VigiaConfig

function Pause-Continue {
    Write-Host ""
    Read-Host "Pressione ENTER para continuar"
}

function Write-Header($title) {
    Clear-Host
    Write-Host "=====================================================" -ForegroundColor Cyan
    Write-Host " VigiaPC - Controlador local (v$($script:Version))" -ForegroundColor Cyan
    Write-Host " PC: $($cfg.PCName)" -ForegroundColor DarkCyan
    Write-Host "=====================================================" -ForegroundColor Cyan
    if ($title) { Write-Host " $title" -ForegroundColor Yellow; Write-Host "" }
}

function Send-MonitorCommand($command, $value = $null) {
    $control = @{
        command = $command
        timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        processed = $false
    }
    if ($value) { $control.value = $value }
    try {
        $control | ConvertTo-Json | Out-File $monitorControlFile -Encoding UTF8
        return $true
    } catch {
        Write-Host "Falha ao escrever comando: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Get-MonitorProcesses {
    try {
        Get-CimInstance Win32_Process |
            Where-Object { $_.CommandLine -match 'SegurancaPC\\Scripts\\([A-Za-z]+)\.ps1' } |
            Select-Object ProcessId,
                @{N='Script';E={ if ($_.CommandLine -match '\\([^\\]+\.ps1)') { $Matches[1] } else { 'unknown' } }},
                @{N='Iniciado';E={ $_.CreationDate }}
    } catch { @() }
}

function Show-Status {
    Write-Header "Status do sistema"

    Write-Host "Processos ativos:" -ForegroundColor Yellow
    $procs = Get-MonitorProcesses
    if ($procs) {
        $procs | Format-Table -AutoSize
    } else {
        Write-Host "  Nenhum processo SegurancaPC esta rodando." -ForegroundColor Red
    }

    Write-Host "Monitor de inatividade:" -ForegroundColor Yellow
    if (Test-Path $monitorStatusFile) {
        try {
            $st = Get-Content $monitorStatusFile -Raw | ConvertFrom-Json
            Write-Host "  Status:           $($st.status)"
            Write-Host "  Ultima atividade: $($st.last_activity)"
            Write-Host "  Inatividade:      $($st.inactive_time)"
            Write-Host "  Monitorando:      $($st.monitoring)"
            Write-Host "  Tela bloqueada:   $($st.locked)"
            if ($st.pause_until) { Write-Host "  Pausa ate:        $($st.pause_until)" }
        } catch {
            Write-Host "  (arquivo de status corrompido)" -ForegroundColor Red
        }
    } else {
        Write-Host "  (sem status disponivel)" -ForegroundColor DarkGray
    }

    Write-Host ""
    Write-Host "Monitor FET (OCR):" -ForegroundColor Yellow
    if (Test-Path $fetStatusFile) {
        try {
            $fs = Get-Content $fetStatusFile -Raw | ConvertFrom-Json
            Write-Host "  Atividades:       $($fs.atual)/$($fs.total) (max $($fs.max))"
            Write-Host "  Tempo:            $($fs.tempo)"
            Write-Host "  Concluido:        $($fs.concluido)"
            Write-Host "  Ultima verif:     $($fs.last_check)"
        } catch {
            Write-Host "  (status indisponivel)" -ForegroundColor DarkGray
        }
    } else {
        Write-Host "  (monitor desligado ou sem dados)" -ForegroundColor DarkGray
    }

    Pause-Continue
}

function Action-LockPC {
    Write-Header "Bloquear PC"
    Write-Host "Mutando audio e bloqueando..." -ForegroundColor Yellow
    try {
        (New-Object -ComObject WScript.Shell).SendKeys([char]173) | Out-Null
    } catch {}
    rundll32.exe user32.dll,LockWorkStation
    Write-Host "[OK] Tela bloqueada." -ForegroundColor Green
    Pause-Continue
}

function Action-Screenshot($all) {
    Write-Header "Screenshot"
    $kind = if ($all) { "todos os monitores" } else { "monitor principal" }
    Write-Host "Solicitando captura ($kind)..." -ForegroundColor Yellow
    $val = if ($all) { "all" } else { $null }
    if (Send-MonitorCommand "screenshot" $val) {
        Write-Host "[OK] Comando enviado. O screenshot sera enviado via Telegram em segundos." -ForegroundColor Green
        Write-Host "Pasta local: $basePath\Screenshots" -ForegroundColor DarkGray
    } else {
        Write-Host "[ERRO] Falha ao enviar comando." -ForegroundColor Red
    }
    Pause-Continue
}

function Action-Pause {
    Write-Header "Pausar monitoramento"
    $minutos = Read-Host "Minutos para pausar (padrao 30)"
    if (-not $minutos) { $minutos = 30 }
    if (Send-MonitorCommand "pause" "$minutos") {
        Write-Host "[OK] Monitor pausado por $minutos minutos." -ForegroundColor Green
    }
    Pause-Continue
}

function Action-Resume {
    Write-Header "Retomar monitoramento"
    if (Send-MonitorCommand "resume") {
        Write-Host "[OK] Monitoramento retomado." -ForegroundColor Green
    }
    Pause-Continue
}

function Action-ToggleAudio {
    Write-Header "Alternar mute"
    try {
        (New-Object -ComObject WScript.Shell).SendKeys([char]173) | Out-Null
        Write-Host "[OK] Mute alternado." -ForegroundColor Green
    } catch {
        Write-Host "[ERRO] $($_.Exception.Message)" -ForegroundColor Red
    }
    Pause-Continue
}

function Action-ToggleFET {
    Write-Header "Ativar/desativar MonitorFET"
    $current = $false
    if (Test-Path $fetControlFile) {
        try { $current = (Get-Content $fetControlFile -Raw | ConvertFrom-Json).enabled } catch {}
    }
    Write-Host "Estado atual: $(if ($current) { 'ATIVO' } else { 'DESATIVADO' })" -ForegroundColor Yellow
    $resp = Read-Host "Inverter? (S/N)"
    if ($resp -match '^[Ss]') {
        try {
            @{ enabled = (-not $current); last_command = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss') } |
                ConvertTo-Json | Out-File $fetControlFile -Encoding UTF8
            Write-Host "[OK] FET agora $(if (-not $current) { 'ATIVADO' } else { 'DESATIVADO' })." -ForegroundColor Green
        } catch {
            Write-Host "[ERRO] $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    Pause-Continue
}

function Action-ShowLogs {
    Write-Header "Ultimos 20 eventos (access.log)"
    if (Test-Path $accessLog) {
        Get-Content $accessLog -Tail 20 -Encoding UTF8 | ForEach-Object { Write-Host $_ }
    } else {
        Write-Host "(sem log)" -ForegroundColor DarkGray
    }
    Pause-Continue
}

function Action-ShowDebug {
    Write-Header "Ultimas 30 linhas do debug.log"
    if (Test-Path $debugLog) {
        Get-Content $debugLog -Tail 30 -Encoding UTF8 | ForEach-Object { Write-Host $_ }
    } else {
        Write-Host "(sem log)" -ForegroundColor DarkGray
    }
    Pause-Continue
}

function Action-ListUSB {
    Write-Header "Dispositivos USB"
    $usb = Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DriveType -eq 2 }
    if ($usb) {
        $usb | Select-Object DeviceID,
            VolumeName,
            @{N='SizeGB';E={ [math]::Round($_.Size/1GB,2) }} |
            Format-Table -AutoSize
    } else {
        Write-Host "Nenhum dispositivo USB conectado." -ForegroundColor DarkGray
    }
    Pause-Continue
}

function Action-TopProcesses {
    Write-Header "Top 10 processos por CPU"
    Get-Process |
        Sort-Object CPU -Descending |
        Select-Object -First 10 Name,
            @{N='CPU';E={ if ($_.CPU) { [math]::Round($_.CPU,1) } else { 0 } }},
            @{N='MemMB';E={ [math]::Round($_.WorkingSet/1MB,1) }} |
        Format-Table -AutoSize
    Pause-Continue
}

function Action-Settings {
    Write-Header "Configuracao atual ($settingsFile)"
    Get-Content $settingsFile -Encoding UTF8 |
        ForEach-Object { if ($_ -match 'BotToken') { $_ -replace ':\s*"[^"]+"', ': "********"' } else { $_ } } |
        ForEach-Object { Write-Host $_ }
    Write-Host ""
    Write-Host "Para editar: abra $settingsFile no Notepad e reinicie os monitores." -ForegroundColor DarkGray
    Pause-Continue
}

function Action-Restart {
    Write-Header "Reiniciar monitores"
    Write-Host "Encerrando processos atuais..." -ForegroundColor Yellow
    Get-CimInstance Win32_Process |
        Where-Object { $_.CommandLine -match 'SegurancaPC\\Scripts\\(TelegramListener|MonitorInatividade|MonitorFET|MonitorLogin)\.ps1' } |
        ForEach-Object {
            Write-Host "  PID $($_.ProcessId) - $($_.Name)"
            Invoke-CimMethod -InputObject $_ -MethodName Terminate | Out-Null
        }

    Start-Sleep -Seconds 2

    Write-Host "Iniciando TelegramListener..." -ForegroundColor Yellow
    Start-Process powershell.exe -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptsDir\TelegramListener.ps1`"" -WindowStyle Hidden
    Start-Sleep -Seconds 2

    Write-Host "Iniciando MonitorInatividade..." -ForegroundColor Yellow
    Start-Process powershell.exe -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptsDir\MonitorInatividade.ps1`"" -WindowStyle Hidden
    Start-Sleep -Seconds 1

    Write-Host "Iniciando MonitorFET..." -ForegroundColor Yellow
    Start-Process powershell.exe -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptsDir\MonitorFET.ps1`"" -WindowStyle Hidden

    Start-Sleep -Seconds 2
    Write-Host "[OK] Monitores reiniciados." -ForegroundColor Green
    Pause-Continue
}

function Action-Stop {
    Write-Header "Encerrar todos os monitores"
    $resp = Read-Host "Confirma encerramento de TODOS os monitores? (S/N)"
    if ($resp -notmatch '^[Ss]') { Write-Host "Cancelado."; Pause-Continue; return }
    Get-CimInstance Win32_Process |
        Where-Object { $_.CommandLine -match 'SegurancaPC\\Scripts\\(TelegramListener|MonitorInatividade|MonitorFET|MonitorLogin)\.ps1' } |
        ForEach-Object {
            Write-Host "  Encerrando PID $($_.ProcessId)" -ForegroundColor DarkYellow
            Invoke-CimMethod -InputObject $_ -MethodName Terminate | Out-Null
        }
    Write-Host "[OK] Encerrado." -ForegroundColor Green
    Pause-Continue
}

function Show-Menu {
    Write-Header "Menu principal"
    @"
  [ 1] Status do sistema
  [ 2] Bloquear PC (mute + lock)
  [ 3] Capturar tela (monitor principal)
  [ 4] Capturar tela (todos os monitores)
  [ 5] Pausar monitoramento
  [ 6] Retomar monitoramento
  [ 7] Alternar mute (toggle)
  [ 8] Ativar/desativar MonitorFET
  [ 9] Ver ultimos eventos (access.log)
  [10] Ver debug.log (ultimas 30 linhas)
  [11] Listar dispositivos USB
  [12] Top processos
  [13] Mostrar configuracao
  [14] Reiniciar monitores
  [15] Encerrar todos os monitores
  [ 0] Sair
"@ | Write-Host
    Write-Host ""
    return (Read-Host "Escolha")
}

# Loop principal
while ($true) {
    $choice = Show-Menu
    switch ($choice) {
        '0'  { Clear-Host; Write-Host "Ate logo." -ForegroundColor Cyan; exit 0 }
        '1'  { Show-Status }
        '2'  { Action-LockPC }
        '3'  { Action-Screenshot $false }
        '4'  { Action-Screenshot $true }
        '5'  { Action-Pause }
        '6'  { Action-Resume }
        '7'  { Action-ToggleAudio }
        '8'  { Action-ToggleFET }
        '9'  { Action-ShowLogs }
        '10' { Action-ShowDebug }
        '11' { Action-ListUSB }
        '12' { Action-TopProcesses }
        '13' { Action-Settings }
        '14' { Action-Restart }
        '15' { Action-Stop }
        default { Write-Host "Opcao invalida." -ForegroundColor Red; Start-Sleep -Seconds 1 }
    }
}
