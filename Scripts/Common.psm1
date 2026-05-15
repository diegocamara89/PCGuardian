# Common.psm1 - Módulo compartilhado VigiaPC/SegurancaPC
# Funções utilitárias usadas por TelegramListener, MonitorInatividade, MonitorFET, MonitorLogin, Controlador.

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$script:CachedConfig = $null
$script:CachedConfigMtime = $null

function Get-VigiaPaths {
    <#
    .SYNOPSIS
    Retorna paths padrão derivados de $PSScriptRoot (ou fallback C:\SegurancaPC).
    #>
    $base = if ($PSScriptRoot) {
        Split-Path $PSScriptRoot -Parent
    } else {
        'C:\SegurancaPC'
    }
    [ordered]@{
        Base          = $base
        ConfigDir     = Join-Path $base 'Config'
        ScriptsDir    = Join-Path $base 'Scripts'
        Screenshots   = Join-Path $base 'Screenshots'
        SettingsFile  = Join-Path $base 'Config\settings.json'
        DebugLog      = Join-Path $base 'Config\debug.log'
        AccessLog     = Join-Path $base 'Config\access.log'
    }
}

function Get-VigiaConfig {
    <#
    .SYNOPSIS
    Lê settings.json com cache invalidado por mtime.
    .PARAMETER Force
    Ignora cache e relê o arquivo.
    #>
    param([switch]$Force)
    $paths = Get-VigiaPaths
    if (-not (Test-Path $paths.SettingsFile)) {
        throw "settings.json não encontrado em $($paths.SettingsFile)"
    }
    $mtime = (Get-Item $paths.SettingsFile).LastWriteTime
    if (-not $Force -and $script:CachedConfig -and $script:CachedConfigMtime -eq $mtime) {
        return $script:CachedConfig
    }
    $script:CachedConfig = Get-Content $paths.SettingsFile -Raw | ConvertFrom-Json
    $script:CachedConfigMtime = $mtime
    return $script:CachedConfig
}

function Send-TelegramMessage {
    <#
    .SYNOPSIS
    Envia mensagem de texto via Telegram Bot API.
    .PARAMETER ChatId
    ID do chat destino (geralmente igual ao UserId).
    .PARAMETER Text
    Texto da mensagem.
    .PARAMETER ParseMode
    HTML, Markdown ou None (padrão None — texto puro).
    .PARAMETER Token
    Bot token. Se omitido, usa Get-VigiaConfig.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ChatId,
        [Parameter(Mandatory)][string]$Text,
        [ValidateSet('HTML','Markdown','None')][string]$ParseMode = 'None',
        [string]$Token
    )
    if (-not $Token) { $Token = (Get-VigiaConfig).BotToken }
    $body = @{ chat_id = $ChatId; text = $Text }
    if ($ParseMode -ne 'None') { $body.parse_mode = $ParseMode }
    try {
        Invoke-RestMethod -Uri "https://api.telegram.org/bot$Token/sendMessage" -Method Post -Body $body | Out-Null
        return $true
    } catch {
        return $false
    }
}

function Send-TelegramDocument {
    <#
    .SYNOPSIS
    Envia arquivo (foto/documento) via sendDocument (preserva qualidade).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ChatId,
        [Parameter(Mandatory)][string]$FilePath,
        [string]$Caption = '',
        [string]$Token
    )
    if (-not $Token) { $Token = (Get-VigiaConfig).BotToken }
    if (-not (Test-Path $FilePath)) { return $false }

    $fileBytes = [System.IO.File]::ReadAllBytes($FilePath)
    $fileEnc = [System.Text.Encoding]::GetEncoding('iso-8859-1').GetString($fileBytes)
    $filename = [System.IO.Path]::GetFileName($FilePath)
    $ext = [System.IO.Path]::GetExtension($FilePath).ToLower()
    $contentType = switch ($ext) {
        '.jpg'  { 'image/jpeg' }
        '.jpeg' { 'image/jpeg' }
        '.png'  { 'image/png' }
        default { 'application/octet-stream' }
    }
    $boundary = [System.Guid]::NewGuid().ToString()
    $LF = "`r`n"
    $body = (
        "--$boundary",
        "Content-Disposition: form-data; name=`"chat_id`"$LF",
        $ChatId,
        "--$boundary",
        "Content-Disposition: form-data; name=`"document`"; filename=`"$filename`"",
        "Content-Type: $contentType$LF",
        $fileEnc,
        "--$boundary",
        "Content-Disposition: form-data; name=`"caption`"$LF",
        $Caption,
        "--$boundary--$LF"
    ) -join $LF
    try {
        Invoke-RestMethod -Uri "https://api.telegram.org/bot$Token/sendDocument" -Method Post -ContentType "multipart/form-data; boundary=$boundary" -Body $body | Out-Null
        return $true
    } catch {
        return $false
    }
}

function Write-VigiaLog {
    <#
    .SYNOPSIS
    Escreve mensagem com timestamp no log indicado.
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Message
    )
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    "$ts - $Message" | Out-File -Append $Path -Encoding UTF8
}

function Trim-VigiaLog {
    <#
    .SYNOPSIS
    Trunca log mantendo últimas N linhas se exceder MaxBytes.
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [int]$MaxBytes = 10MB,
        [int]$KeepLines = 2000
    )
    try {
        if ((Test-Path $Path) -and (Get-Item $Path).Length -gt $MaxBytes) {
            $tail = Get-Content $Path -Tail $KeepLines -Encoding UTF8
            $tail | Out-File $Path -Encoding UTF8 -Force
        }
    } catch {}
}

Export-ModuleMember -Function Get-VigiaPaths, Get-VigiaConfig, Send-TelegramMessage, Send-TelegramDocument, Write-VigiaLog, Trim-VigiaLog
