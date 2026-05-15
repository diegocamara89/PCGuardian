# MonitorFET.ps1 - Monitor de Progresso do FET via OCR
# Versao 1.1 - usa Common.psm1

Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -Force

$ErrorActionPreference = 'SilentlyContinue'
$cfg = Get-VigiaConfig
$paths = Get-VigiaPaths
$chat = $cfg.UserId; $pc = $cfg.PCName
$controlFile = Join-Path $paths.ConfigDir 'fet_control.json'
$logFile = Join-Path $paths.ConfigDir 'fet_log.txt'
$statusFile = Join-Path $paths.ConfigDir 'fet_status.json'
$ocrDumpFile = Join-Path $paths.ConfigDir 'fet_ocr_last.txt'
$screenshotDir = Join-Path $paths.Base 'Screenshots\FET'
$script:lastOcrError = $null

# Intervalo de verificacao (padrao 5 minutos)
$checkIntervalSeconds = 300
if ($cfg.PSObject.Properties.Name -contains 'FetCheckIntervalSeconds' -and $cfg.FetCheckIntervalSeconds) {
    $checkIntervalSeconds = [int]$cfg.FetCheckIntervalSeconds
}

# Variaveis de estado
$maxAlcancado = 0
$ultimoTempo = 0
$ultimoProgresso = 0
$ultimoProgressoTime = $null
$concluido = $false

# ===== FUNCOES AUXILIARES =====

function Log-FET($msg) {
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    "$timestamp | $msg" | Out-File -Append $logFile -Encoding UTF8
}

function Send-Telegram($msg) {
    if (Send-TelegramMessage -ChatId $chat -Text $msg) {
        Log-FET "TELEGRAM: $msg"
    } else {
        Log-FET "ERRO TELEGRAM"
    }
}

function Get-FETControl {
    if (Test-Path $controlFile) {
        try {
            return Get-Content $controlFile -Raw | ConvertFrom-Json
        } catch {
            return @{ enabled = $false }
        }
    }
    return @{ enabled = $false }
}

function Write-FETStatus($data) {
    $data | ConvertTo-Json | Out-File $statusFile -Encoding UTF8
}

# ===== CAPTURA DE TELA COM DPI-AWARE =====

function Capture-Screen {
    param(
        [int]$MaxOcrDim = 800,
        [float[]]$Crop = $null
    )
    try {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing

        # DPI awareness
        Add-Type @'
using System;
using System.Runtime.InteropServices;
public class DpiAwarenessFET {
    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();
}
'@ -ErrorAction SilentlyContinue
        try { [DpiAwarenessFET]::SetProcessDPIAware() | Out-Null } catch {}

        if (-not (Test-Path $screenshotDir)) {
            New-Item -ItemType Directory -Path $screenshotDir -Force | Out-Null
        }

        $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
        $filename = "fet_$timestamp.png"
        $filepath = Join-Path $screenshotDir $filename

        # Capturar apenas monitor principal (OCR tem limite de dimensao)
        $screen = [System.Windows.Forms.Screen]::PrimaryScreen
        $bounds = $screen.Bounds
        $left = $bounds.Left
        $top = $bounds.Top
        $width = $bounds.Width
        $height = $bounds.Height

        $bitmap = New-Object System.Drawing.Bitmap $width, $height
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        $graphics.CopyFromScreen($left, $top, 0, 0, [System.Drawing.Size]::new($width, $height))
        $graphics.Dispose()

        if ($Crop -and $Crop.Count -eq 4) {
            $cropLeft = [int][Math]::Round($width * $Crop[0])
            $cropTop = [int][Math]::Round($height * $Crop[1])
            $cropWidth = [int][Math]::Round($width * $Crop[2])
            $cropHeight = [int][Math]::Round($height * $Crop[3])
            $cropRect = New-Object System.Drawing.Rectangle $cropLeft, $cropTop, $cropWidth, $cropHeight
            $cropped = $bitmap.Clone($cropRect, $bitmap.PixelFormat)
            $bitmap.Dispose()
            $bitmap = $cropped
            $width = $cropWidth
            $height = $cropHeight
            Log-FET "Screenshot recortado para $width x $height (OCR)"
        }

        # Reduzir imagem se exceder o limite do OCR (evita "Image dimensions are too large")
        $maxSide = [Math]::Max($width, $height)
        if ($maxSide -gt $MaxOcrDim) {
            $scale = $MaxOcrDim / $maxSide
            $newWidth = [int][Math]::Round($width * $scale)
            $newHeight = [int][Math]::Round($height * $scale)
            $resized = New-Object System.Drawing.Bitmap $newWidth, $newHeight
            $g2 = [System.Drawing.Graphics]::FromImage($resized)
            $g2.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $g2.DrawImage($bitmap, 0, 0, $newWidth, $newHeight)
            $g2.Dispose()
            $bitmap.Dispose()
            $bitmap = $resized
            Log-FET "Screenshot redimensionado para $newWidth x $newHeight (OCR)"
        }

        # PNG para melhor OCR (lossless)
        $bitmap.Save($filepath, [System.Drawing.Imaging.ImageFormat]::Png)
        $bitmap.Dispose()

        return $filepath
    } catch {
        Log-FET "ERRO captura: $($_.Exception.Message)"
        return $null
    }
}

# ===== OCR COM WINDOWS.MEDIA.OCR =====

function Invoke-OCR {
    param([string]$ImagePath)

    try {
        $script:lastOcrError = $null
        # Carregar assemblies UWP para OCR
        Add-Type -AssemblyName System.Runtime.WindowsRuntime -ErrorAction Stop

        # Metodo para converter Task em resultado sincrono
        $asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() |
            Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]

        function Wait-AsyncOperation($asyncOp, $resultType) {
            $asTask = $asTaskGeneric.MakeGenericMethod($resultType)
            $netTask = $asTask.Invoke($null, @($asyncOp))
            $netTask.Wait(-1) | Out-Null
            return $netTask.Result
        }

        # Carregar tipos UWP
        [Windows.Storage.StorageFile, Windows.Storage, ContentType=WindowsRuntime] | Out-Null
        [Windows.Graphics.Imaging.BitmapDecoder, Windows.Graphics.Imaging, ContentType=WindowsRuntime] | Out-Null
        [Windows.Media.Ocr.OcrEngine, Windows.Media.Ocr, ContentType=WindowsRuntime] | Out-Null

        # Abrir arquivo de imagem
        $asyncFile = [Windows.Storage.StorageFile]::GetFileFromPathAsync($ImagePath)
        $file = Wait-AsyncOperation $asyncFile ([Windows.Storage.StorageFile])

        # Abrir stream
        $asyncStream = $file.OpenAsync([Windows.Storage.FileAccessMode]::Read)
        $stream = Wait-AsyncOperation $asyncStream ([Windows.Storage.Streams.IRandomAccessStream])

        # Criar decoder
        $asyncDecoder = [Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)
        $decoder = Wait-AsyncOperation $asyncDecoder ([Windows.Graphics.Imaging.BitmapDecoder])

        # Obter bitmap
        $asyncBitmap = $decoder.GetSoftwareBitmapAsync()
        $bitmap = Wait-AsyncOperation $asyncBitmap ([Windows.Graphics.Imaging.SoftwareBitmap])

        # Criar OCR engine (tentar portugues, fallback para default)
        $ocrEngine = $null
        try {
            $lang = [Windows.Globalization.Language]::new("pt-BR")
            $ocrEngine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage($lang)
        } catch {}

        if (-not $ocrEngine) {
            $ocrEngine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
        }

        if (-not $ocrEngine) {
            Log-FET "ERRO: OCR engine nao disponivel"
            return $null
        }

        # Executar OCR
        $asyncResult = $ocrEngine.RecognizeAsync($bitmap)
        $result = Wait-AsyncOperation $asyncResult ([Windows.Media.Ocr.OcrResult])

        $stream.Dispose()

        return $result.Text
    } catch {
        $script:lastOcrError = $_.Exception.Message
        Log-FET "ERRO OCR: $($script:lastOcrError)"
        return $null
    }
}

# ===== PARSE DOS DADOS DO FET =====

function Parse-FETData($ocrText) {
    $data = @{
        Atual = 0
        Total = 0
        TempoMinutos = 0
        TempoSegundos = 0
        TempoTotalSeg = 0
        MaxAlcancado = 0
        Raw = $ocrText
    }

    if (-not $ocrText) { return $data }

    # Pattern: "1811 de um total de 1842 atividades alocadas"
    if ($ocrText -match '(\d+)\s+de\s+um\s+total\s+de\s+(\d+)\s+atividades') {
        $data.Atual = [int]$Matches[1]
        $data.Total = [int]$Matches[2]
    }

    # Pattern: "Tempo total: 34 min 14 s"
    if ($ocrText -match 'Tempo\s+total[:\s]+(\d+)\s*min\s+(\d+)\s*s') {
        $data.TempoMinutos = [int]$Matches[1]
        $data.TempoSegundos = [int]$Matches[2]
        $data.TempoTotalSeg = ($data.TempoMinutos * 60) + $data.TempoSegundos
    }

    # Pattern: "Máx atividades alocadas: 1817 (em 25 min 16 s)"
    if ($ocrText -match 'M[aá]x\s+atividades\s+alocadas[:\s]+(\d+)') {
        $data.MaxAlcancado = [int]$Matches[1]
    }

    return $data
}

# ===== LOGICA PRINCIPAL DE MONITORAMENTO =====

function Process-FETData($data) {
    $atual = $data.Atual
    $total = $data.Total
    $tempoAtual = $data.TempoTotalSeg

    # Ignorar se nao conseguiu extrair dados
    if ($atual -eq 0 -and $total -eq 0) {
        if ($data.Raw) {
            $data.Raw | Out-File $ocrDumpFile -Encoding UTF8
            $preview = ($data.Raw -replace '\s+', ' ').Trim()
            if ($preview.Length -gt 200) { $preview = $preview.Substring(0, 200) + "..." }
            Log-FET "OCR sem dados validos - ignorando. Trecho: $preview"
        } else {
            Log-FET "OCR sem dados validos - ignorando"
        }
        return
    }

    # ===== 1. DETECTAR NOVA EXECUCAO =====
    if ($tempoAtual -lt $script:ultimoTempo -and $script:ultimoTempo -gt 0) {
        Log-FET "NOVA EXECUCAO DETECTADA - Resetando (tempo $tempoAtual < $($script:ultimoTempo))"
        Send-Telegram "[FET] Nova execucao detectada!
Maximo anterior: $($script:maxAlcancado)
Iniciando novo monitoramento..."
        $script:maxAlcancado = 0
        $script:ultimoProgresso = 0
        $script:ultimoProgressoTime = Get-Date
        $script:concluido = $false
    }

    $script:ultimoTempo = $tempoAtual

    # ===== 2. DETECTAR CONCLUSAO =====
    if ($atual -eq $total -and $total -gt 0 -and -not $script:concluido) {
        $tempoFormatado = "{0}min {1}s" -f $data.TempoMinutos, $data.TempoSegundos
        Send-Telegram "[FET CONCLUIDO!]
Todas as $total atividades foram alocadas!
Tempo total: $tempoFormatado
PC: $pc"
        $script:concluido = $true
        Log-FET "CONCLUIDO: $atual/$total atividades em $tempoFormatado"
    }

    # ===== 3. ATUALIZAR MAXIMO =====
    if ($data.MaxAlcancado -gt $script:maxAlcancado) {
        $script:maxAlcancado = $data.MaxAlcancado
    } elseif ($atual -gt $script:maxAlcancado) {
        $script:maxAlcancado = $atual
    }

    # ===== 4. DETECTAR REGRESSAO (30+ atividades) =====
    $regressao = $script:maxAlcancado - $atual
    if ($regressao -ge 30) {
        $tempoFormatado = "{0}min {1}s" -f $data.TempoMinutos, $data.TempoSegundos
        Send-Telegram "[FET ALERTA] Regressao de $regressao atividades!
Maximo: $($script:maxAlcancado)
Atual: $atual/$total
Tempo: $tempoFormatado
PC: $pc"
        Log-FET "REGRESSAO: $regressao atividades (max $($script:maxAlcancado) -> atual $atual)"
    }

    # ===== 5. DETECTAR TRAVAMENTO (30 min sem progresso) =====
    if ($atual -gt $script:ultimoProgresso) {
        # Houve progresso
        $script:ultimoProgresso = $atual
        $script:ultimoProgressoTime = Get-Date
    } else {
        # Sem progresso - verificar tempo
        if ($script:ultimoProgressoTime) {
            $tempoParado = (Get-Date) - $script:ultimoProgressoTime
            if ($tempoParado.TotalMinutes -ge 30 -and -not $script:concluido) {
                Send-Telegram "[FET TRAVADO] Sem progresso ha 30 minutos!
Ultima atividade: $atual/$total
Parado desde: $($script:ultimoProgressoTime.ToString('HH:mm:ss'))
PC: $pc"
                Log-FET "TRAVADO: 30 min sem progresso em $atual/$total"
                # Reset para nao alertar novamente
                $script:ultimoProgressoTime = Get-Date
            }
        }
    }

    # ===== 6. ATUALIZAR STATUS =====
    $tempoFormatado = "{0}:{1:D2}" -f $data.TempoMinutos, $data.TempoSegundos
    Write-FETStatus @{
        enabled = $true
        atual = $atual
        total = $total
        max = $script:maxAlcancado
        tempo = $tempoFormatado
        last_check = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        concluido = $script:concluido
    }

    # Log normal
    Log-FET "Alocadas: $atual/$total | Max: $($script:maxAlcancado) | Tempo: $tempoFormatado"
}

# ===== CICLO DE MONITORAMENTO =====

function Run-FETCycle {
    $ocrText = $null
    $passes = @(
        @{ label = 'center-native'; max = 2500; crop = @(0.25, 0.25, 0.5, 0.5) },
        @{ label = 'center-large'; max = 2500; crop = @(0.15, 0.15, 0.7, 0.7) },
        @{ label = 'full-high'; max = 2500; crop = $null }
    )

    foreach ($pass in $passes) {
        $imagePath = Capture-Screen -MaxOcrDim $pass.max -Crop $pass.crop
        if (-not $imagePath) { continue }
        $ocrText = Invoke-OCR -ImagePath $imagePath

        if (-not $ocrText -and $script:lastOcrError -and $script:lastOcrError -match 'Image dimensions are too large') {
            Log-FET "OCR falhou por dimensao na tentativa '$($pass.label)'."
            continue
        }

        if ($ocrText) {
            if ($ocrText -match '\d') {
                $ocrText | Out-File $ocrDumpFile -Encoding UTF8
                Log-FET "OCR OK na tentativa '$($pass.label)'."
                break
            }
        }
    }

    if ($ocrText) {
        $data = Parse-FETData $ocrText
        Process-FETData $data

        # Limpar screenshot apos processar (manter apenas ultimos 5)
        $oldFiles = Get-ChildItem $screenshotDir -Filter "fet_*.png" | Sort-Object CreationTime -Descending | Select-Object -Skip 5
        $oldFiles | Remove-Item -Force -ErrorAction SilentlyContinue
    } else {
        Log-FET "OCR falhou em todas as tentativas"
    }
}

# ===== LOOP PRINCIPAL =====

Log-FET "========================================="
Log-FET "MonitorFET iniciado - aguardando ativacao"
Log-FET "========================================="

$prevEnabled = $false
while ($true) {
    $control = Get-FETControl

    if ($control.enabled) {
        # Monitoramento ativo (disparar leitura imediata na primeira ativacao)
        if (-not $prevEnabled) {
            Log-FET "Monitoramento ativado - leitura imediata"
        }
        Run-FETCycle
    } else {
        # Monitoramento desativado - resetar variaveis
        if ($script:maxAlcancado -gt 0) {
            Log-FET "Monitoramento desativado - resetando estado"
            $script:maxAlcancado = 0
            $script:ultimoTempo = 0
            $script:ultimoProgresso = 0
            $script:ultimoProgressoTime = $null
            $script:concluido = $false
        }
    }

    $prevEnabled = $control.enabled
    Start-Sleep -Seconds $checkIntervalSeconds
}
