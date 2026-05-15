Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -Force

$ErrorActionPreference = 'SilentlyContinue'
$script:Version = '6.6'
$cfg = Get-VigiaConfig
$paths = Get-VigiaPaths
$chat = $cfg.UserId; $pc = $cfg.PCName
$controlFile = Join-Path $paths.ConfigDir 'monitor_control.json'
$statusFile = Join-Path $paths.ConfigDir 'monitor_status.json'
$debugLog = $paths.DebugLog
$warningMinutes = if ($cfg.WarningMin) { [int]$cfg.WarningMin } else { 1 }
$blockMinutes = if ($cfg.InactivityMin) { [int]$cfg.InactivityMin } else { 5 }

function Trim-DebugLog { Trim-VigiaLog -Path $debugLog }

function Send-Telegram($msg) {
    if (Send-TelegramMessage -ChatId $chat -Text $msg) {
        "$((Get-Date -Format 'HH:mm:ss')) - ENVIADO: $msg" | Out-File -Append $debugLog
    } else {
        "$((Get-Date -Format 'HH:mm:ss')) - ERRO: $msg" | Out-File -Append $debugLog
    }
}

function Capture-Screenshot {
    param(
        [bool]$AllScreens = $false
    )

    try {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing

        # Tornar o processo DPI-aware para capturar dimensoes corretas
        Add-Type @'
using System;
using System.Runtime.InteropServices;
public class DpiAwareness {
    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();
}
'@ -ErrorAction SilentlyContinue

        try {
            [DpiAwareness]::SetProcessDPIAware() | Out-Null
        } catch {}

        $screenshotDir = Join-Path $paths.Base 'Screenshots'
        if (-not (Test-Path $screenshotDir)) {
            New-Item -ItemType Directory -Path $screenshotDir -Force | Out-Null
        }

        $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"

        if ($AllScreens) {
            # Capturar todos os monitores (virtual screen)
            $filename = "screenshot_all_$timestamp.jpg"
            $filepath = Join-Path $screenshotDir $filename

            $left = [System.Windows.Forms.SystemInformation]::VirtualScreen.Left
            $top = [System.Windows.Forms.SystemInformation]::VirtualScreen.Top
            $width = [System.Windows.Forms.SystemInformation]::VirtualScreen.Width
            $height = [System.Windows.Forms.SystemInformation]::VirtualScreen.Height

            $bitmap = New-Object System.Drawing.Bitmap $width, $height
            $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
            $graphics.CopyFromScreen($left, $top, 0, 0, $bitmap.Size)

            "$((Get-Date -Format 'HH:mm:ss')) - Screenshot de todos os monitores: ${width}x${height}" | Out-File -Append $debugLog
        } else {
            # Capturar apenas monitor principal com correcao DPI
            $filename = "screenshot_$timestamp.jpg"
            $filepath = Join-Path $screenshotDir $filename

            $screen = [System.Windows.Forms.Screen]::PrimaryScreen
            $bounds = $screen.Bounds

            # Usar Working Area real do sistema
            $width = $bounds.Width
            $height = $bounds.Height
            $left = $bounds.Left
            $top = $bounds.Top

            $bitmap = New-Object System.Drawing.Bitmap $width, $height
            $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
            $graphics.CopyFromScreen($left, $top, 0, 0, [System.Drawing.Size]::new($width, $height))

            "$((Get-Date -Format 'HH:mm:ss')) - Screenshot do monitor principal: ${width}x${height}" | Out-File -Append $debugLog
        }

        # Salvar como JPEG com qualidade maxima (95%) - arquivo menor, qualidade otima
        $encoderParams = New-Object System.Drawing.Imaging.EncoderParameters(1)
        $encoderParams.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, 95L)
        $jpegCodec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
        $bitmap.Save($filepath, $jpegCodec, $encoderParams)

        $fileSize = [math]::Round((Get-Item $filepath).Length / 1MB, 2)
        "$((Get-Date -Format 'HH:mm:ss')) - Screenshot salvo: $filepath (${fileSize}MB)" | Out-File -Append $debugLog

        $graphics.Dispose()
        $bitmap.Dispose()

        return $filepath
    } catch {
        "$((Get-Date -Format 'HH:mm:ss')) - ERRO ao capturar screenshot: $($_.Exception.Message)" | Out-File -Append $debugLog
        return $null
    }
}

function Send-Screenshot($filepath, $caption = "") {
    if (-not (Test-Path $filepath)) {
        "$((Get-Date -Format 'HH:mm:ss')) - ERRO: Arquivo nao encontrado: $filepath" | Out-File -Append $debugLog
        return $false
    }
    if (Send-TelegramDocument -ChatId $chat -FilePath $filepath -Caption $caption) {
        $sizeMB = [math]::Round((Get-Item $filepath).Length / 1MB, 2)
        "$((Get-Date -Format 'HH:mm:ss')) - Screenshot enviado (JPEG Q95, ${sizeMB}MB)" | Out-File -Append $debugLog
        return $true
    } else {
        "$((Get-Date -Format 'HH:mm:ss')) - ERRO ao enviar screenshot" | Out-File -Append $debugLog
        return $false
    }
}

function Get-USBDevices {
    try {
        $usbDevices = Get-WmiObject -Class Win32_LogicalDisk | Where-Object { $_.DriveType -eq 2 } | Select-Object DeviceID, VolumeName, Size
        return $usbDevices
    } catch {
        return @()
    }
}

function Compare-USBDevices($oldDevices, $newDevices) {
    $oldIds = @($oldDevices | ForEach-Object { $_.DeviceID })
    $newIds = @($newDevices | ForEach-Object { $_.DeviceID })

    $added = $newDevices | Where-Object { $oldIds -notcontains $_.DeviceID }
    $removed = $oldDevices | Where-Object { $newIds -notcontains $_.DeviceID }

    return @{
        Added = $added
        Removed = $removed
    }
}

function Is-PC-Locked {
    # Metodo 1: Verificar processo logonui (tela de login/bloqueio)
    if (Get-Process -Name "logonui" -ErrorAction SilentlyContinue) { return $true }

    # Metodo 2: Verificar sessao desconectada
    try {
        $session = quser $env:USERNAME 2>$null
        if ($session -match "Disc") { return $true }
    } catch {}

    # Metodo 3: Verificar se desktop de entrada esta acessivel (Win32 API)
    # Desktop inacessivel = PC bloqueado
    try {
        $signature = @'
[DllImport("user32.dll")]
public static extern IntPtr OpenInputDesktop(int dwFlags, bool fInherit, int dwDesiredAccess);
[DllImport("user32.dll")]
public static extern bool CloseDesktop(IntPtr hDesktop);
'@
        if (-not ([System.Management.Automation.PSTypeName]'Win32.Desktop').Type) {
            Add-Type -MemberDefinition $signature -Name Desktop -Namespace Win32
        }

        $desktop = [Win32.Desktop]::OpenInputDesktop(0, $false, 0)
        if ($desktop -eq [IntPtr]::Zero) {
            # Desktop inacessivel = PC bloqueado
            return $true
        }
        [Win32.Desktop]::CloseDesktop($desktop) | Out-Null
    } catch {}

    return $false
}

function Write-Status($idleMinutes, $pcLocked, $monitoringPaused, $pauseUntil) {
    $lastActivity = (Get-Date).AddMinutes(-1 * $idleMinutes)
    $status = @{
        status        = if ($monitoringPaused) { "paused" } else { "active" }
        last_activity = $lastActivity.ToString('yyyy-MM-dd HH:mm:ss')
        inactive_time = "$idleMinutes min"
        monitoring    = -not $monitoringPaused
        pause_until   = if ($pauseUntil) { $pauseUntil.ToString('yyyy-MM-dd HH:mm:ss') } else { $null }
        locked        = $pcLocked
    }
    try { $status | ConvertTo-Json | Out-File $statusFile -Encoding UTF8 } catch {}
}

function Handle-ControlCommand([ref]$monitoringPaused, [ref]$pauseUntil, [ref]$stopRequested) {
    if (-not (Test-Path $controlFile)) { return }
    try {
        $control = Get-Content $controlFile | ConvertFrom-Json
    } catch {
        return
    }
    if (-not $control -or ($control.processed -eq $true)) { return }

    switch ($control.command) {
        'pause' {
            $minutes = if ($control.value) { [int]$control.value } else { 30 }
            # Limite defensivo: 1..720 minutos (12h). Valores fora da faixa caem para 30.
            if ($minutes -lt 1 -or $minutes -gt 720) { $minutes = 30 }
            $pauseUntil.Value = (Get-Date).AddMinutes($minutes)
            $monitoringPaused.Value = $true
        }
        'extend' {
            $minutes = if ($control.value) { [int]$control.value } else { 30 }
            if ($minutes -lt 1 -or $minutes -gt 720) { $minutes = 30 }
            if ($pauseUntil.Value) {
                $pauseUntil.Value = $pauseUntil.Value.AddMinutes($minutes)
            } else {
                $pauseUntil.Value = (Get-Date).AddMinutes($minutes)
            }
            $monitoringPaused.Value = $true
        }
        'resume' {
            $monitoringPaused.Value = $false
            $pauseUntil.Value = $null
        }
        'stop' {
            $stopRequested.Value = $true
        }
        'screenshot' {
            $allScreens = if ($control.value -eq "all") { $true } else { $false }
            $filepath = Capture-Screenshot -AllScreens $allScreens

            if ($filepath) {
                $screenType = if ($allScreens) { "Todos os monitores" } else { "Monitor principal" }
                $caption = "Screenshot - $screenType - $pc`n$(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')"
                if (Send-Screenshot $filepath $caption) {
                    "$((Get-Date -Format 'HH:mm:ss')) - Screenshot capturado e enviado ($screenType)" | Out-File -Append $debugLog
                } else {
                    Send-Telegram "[ERRO] Falha ao enviar screenshot - $pc"
                }
            } else {
                Send-Telegram "[ERRO] Falha ao capturar screenshot - $pc"
            }
        }
    }

    try {
        $control.processed = $true
        $control | ConvertTo-Json | Out-File $controlFile -Encoding UTF8
    } catch {}
}

Add-Type @'
using System;
using System.Runtime.InteropServices;
public class IdleTime {
    [DllImport("user32.dll")]
    static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);
    struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }
    public static int GetIdleMinutes() {
        LASTINPUTINFO info = new LASTINPUTINFO();
        info.cbSize = 8;
        GetLastInputInfo(ref info);
        return (Environment.TickCount - (int)info.dwTime) / 60000;
    }
}
public class AudioMute {
    [DllImport("user32.dll")]
    public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
    public static void Mute() {
        const byte VK_VOLUME_MUTE = 0xAD;
        const uint KEYEVENTF_KEYUP = 0x0002;
        keybd_event(VK_VOLUME_MUTE, 0, 0, UIntPtr.Zero);
        System.Threading.Thread.Sleep(50);
        keybd_event(VK_VOLUME_MUTE, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
    }
}
'@

$warned = $false; $blocked = $false; $isLocked = $false
$monitoringPaused = $false; $pauseUntil = $null; $stopRequested = $false

# Monitoramento USB - inicializar lista de dispositivos conhecidos
$knownUSBDevices = @()
if ($cfg.USBMonitoring) {
    $knownUSBDevices = Get-USBDevices
    "$((Get-Date -Format 'HH:mm:ss')) - USB Monitoring ativado. Dispositivos conhecidos: $($knownUSBDevices.Count)" | Out-File -Append $debugLog
}

# Log de inicializacao (sem notificar Telegram a cada restart)
"$((Get-Date -Format 'HH:mm:ss')) - Monitor iniciado v$($script:Version) - $pc" | Out-File -Append $debugLog -Encoding UTF8

$logTrimCounter = 0
while($true) {
    Handle-ControlCommand ([ref]$monitoringPaused) ([ref]$pauseUntil) ([ref]$stopRequested)

    # Rotaciona log periodicamente (a cada ~10 min de loop)
    $logTrimCounter++
    if ($logTrimCounter -ge 60) { Trim-DebugLog; $logTrimCounter = 0 }

    if ($stopRequested) {
        "$((Get-Date -Format 'HH:mm:ss')) - STOP solicitado - encerrando monitor" | Out-File -Append $debugLog
        break
    }

    if ($pauseUntil -and (Get-Date) -ge $pauseUntil) {
        $monitoringPaused = $false
        $pauseUntil = $null
    }

    $idle = [IdleTime]::GetIdleMinutes()
    $pcLocked = Is-PC-Locked
    "$((Get-Date -Format 'HH:mm:ss')) - Idle:$idle Lock:$pcLocked Warn:$warned Block:$blocked Pause:$monitoringPaused" | Out-File -Append $debugLog
    Write-Status -idleMinutes $idle -pcLocked $pcLocked -monitoringPaused $monitoringPaused -pauseUntil $pauseUntil

    if ($monitoringPaused) {
        Start-Sleep -Seconds 10
        continue
    }

    if ($pcLocked) {
        if (-not $isLocked) {
            "$((Get-Date -Format 'HH:mm:ss')) - PC BLOQUEADO - Modo silencioso" | Out-File -Append $debugLog
            $isLocked = $true
        }
        Start-Sleep -Seconds 30
        continue
    }

    if ($isLocked -and -not $pcLocked) {
        "$((Get-Date -Format 'HH:mm:ss')) - PC DESBLOQUEADO - Reset completo" | Out-File -Append $debugLog
        $isLocked = $false; $warned = $false; $blocked = $false
    }

    if ($idle -lt ($blockMinutes - $warningMinutes)) { $warned = $false; $blocked = $false }

    # Monitoramento USB - verificar novos dispositivos
    if ($cfg.USBMonitoring -and -not $pcLocked) {
        $currentUSBDevices = Get-USBDevices
        $changes = Compare-USBDevices $knownUSBDevices $currentUSBDevices

        foreach ($device in $changes.Added) {
            $size = if ($device.Size) { [math]::Round($device.Size/1GB, 2) } else { "?" }
            $name = if ($device.VolumeName) { $device.VolumeName } else { "Sem nome" }
            $alert = "[USB DETECTADO]`nDispositivo: $($device.DeviceID)`nNome: $name`nTamanho: ${size}GB`nPC: $pc`n$(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')"
            Send-Telegram $alert
            "$((Get-Date -Format 'HH:mm:ss')) - USB detectado: $($device.DeviceID)" | Out-File -Append $debugLog

            # Auto-bloquear se configurado
            if ($cfg.AutoBlockOnUSB) {
                [AudioMute]::Mute()
                Send-Telegram "[AUTO-BLOQUEIO USB] PC bloqueado por USB nao autorizado - $pc"
                rundll32.exe user32.dll,LockWorkStation
                "$((Get-Date -Format 'HH:mm:ss')) - PC bloqueado automaticamente por USB" | Out-File -Append $debugLog
            }
        }

        foreach ($device in $changes.Removed) {
            "$((Get-Date -Format 'HH:mm:ss')) - USB removido: $($device.DeviceID)" | Out-File -Append $debugLog
        }

        $knownUSBDevices = $currentUSBDevices
    }

    if ($idle -ge ($blockMinutes - $warningMinutes) -and -not $warned -and -not $blocked) {
        Send-Telegram "[AVISO] Bloqueio em $warningMinutes minuto(s) - $pc"
        $warned = $true
    }

    if ($idle -ge $blockMinutes -and -not $blocked) {
        [AudioMute]::Mute()

        # Screenshot automatico antes de bloquear (se habilitado)
        if ($cfg.ScreenshotOnBlock) {
            $filepath = Capture-Screenshot
            if ($filepath) {
                $caption = "[AUTO-BLOQUEIO] PC bloqueado por inatividade - $pc`n$(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')"
                Send-Screenshot $filepath $caption | Out-Null
                "$((Get-Date -Format 'HH:mm:ss')) - Screenshot automatico capturado ao bloquear" | Out-File -Append $debugLog
            }
        }

        Send-Telegram "[BLOQUEADO] PC bloqueado por inatividade (som mutado) - $pc"
        rundll32.exe user32.dll,LockWorkStation
        $blocked = $true; $warned = $false
        Start-Sleep -Seconds 30
    }

    Start-Sleep -Seconds 10
}
