[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
# PC SECURITY v6.6 - TelegramListener
# Sistema de Controle Remoto via Telegram (texto apenas)
# Funcionalidades: audio + screenshot + USB alerts + FET (OCR)

$script:Version = '6.6'

Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -Force

$paths = Get-VigiaPaths
$configPath = $paths.ConfigDir
$logFile = $paths.AccessLog
$monitorControlFile = Join-Path $configPath "monitor_control.json"
$monitorStatusFile = Join-Path $configPath "monitor_status.json"
$fetControlFile = Join-Path $configPath "fet_control.json"
$fetStatusFile = Join-Path $configPath "fet_status.json"
$offsetFile = Join-Path $configPath "telegram_offset.txt"
$lockFile = Join-Path $configPath "telegram_listener.lock"

# Constantes de configuracao
$confirmationTimeoutSeconds = 30
$pauseMinutes = 30
$rateLimitSeconds = 2
$apiTimeoutSeconds = 60
$errorSleepSeconds = 10
$normalSleepSeconds = 2

$cfg = Get-VigiaConfig
$bot = $cfg.BotToken
$authorizedUser = $cfg.UserId
$pc = $cfg.PCName

# Controle de confirmacao para comandos criticos
$pendingShutdown = @{}
$pendingRestart = @{}
$pendingDisable = @{}

# Rate limiting - previne spam de comandos
$userLastCommandTime = @{}

# Sinaliza para encerrar listener apos desativacao remota
$shouldExit = $false

# Funcao de controle de audio usando SendKeys (metodo robusto)
# NOTA: VK_VOLUME_MUTE ([char]173) sempre alterna (toggle) o estado de mute
# Portanto, Mute/Unmute/Toggle fazem a mesma coisa - alternar o estado atual
function Toggle-Audio-Mute {
    Log-Activity "[AUDIO-DEBUG] Alternando mute com SendKeys (VK_VOLUME_MUTE)"
    try {
        (New-Object -ComObject WScript.Shell).SendKeys([char]173)
        Start-Sleep -Milliseconds 100
        Log-Activity "[AUDIO-SUCCESS] Comando de toggle mute enviado com sucesso"
        return $true
    } catch {
        Log-Activity "[AUDIO-ERROR] Falha ao enviar comando de toggle mute: $($_.Exception.Message)"
        return $false
    }
}

function Send-Telegram($chatId, $message) {
    $ok = Send-TelegramMessage -ChatId $chatId -Text $message -ParseMode HTML -Token $bot
    if (-not $ok) { Log-Activity "[ERRO] Falha ao enviar mensagem Telegram" }
    return $ok
}

function Log-Activity($message) {
    Write-VigiaLog -Path $logFile -Message $message
}

# Garantir instancia unica do listener (lock file)
$lockStream = $null
try {
    $lockStream = [System.IO.File]::Open($lockFile, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
    Log-Activity "[STARTUP] Lock adquirido: $lockFile"
} catch {
    Log-Activity "[STARTUP] Outra instancia detectada (lock em uso). Encerrando esta."
    exit
}

function Send-Command-To-Monitor($command, $value = $null) {
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
        return $false
    }
}

function Disable-System {
    # Mata monitores em execucao (TEMPORARIO - volta apos reiniciar)
    # NOTA: NAO desabilita tarefas agendadas para permitir reinicio automatico

    try {
        Get-CimInstance Win32_Process |
            Where-Object { $_.Name -eq 'powershell.exe' -and $_.CommandLine -match 'C:\\SegurancaPC\\Scripts\\(MonitorInatividade|MonitorLogin)\\.ps1' } |
            ForEach-Object { Invoke-CimMethod -InputObject $_ -MethodName Terminate | Out-Null }
        Log-Activity "[DISABLE-TEMP] Monitores encerrados (temporario)"
    } catch {
        Log-Activity "[DISABLE-ERRO] Falha ao encerrar monitores: $($_.Exception.Message)"
    }

    # Solicita monitor parar graciosamente
    Send-Command-To-Monitor "stop" | Out-Null

    Log-Activity "[DISABLE-TEMP] Sistema desativado temporariamente. Tarefas agendadas permanecem ativas para reinicio automatico."
    return $true
}

# Inicializar sistema
$offset = 0
try {
    Invoke-RestMethod "https://api.telegram.org/bot$bot/deleteWebhook?drop_pending_updates=False" -ErrorAction Stop | Out-Null
    Log-Activity "[INIT] Webhook limpo com sucesso."
} catch {
    Log-Activity "[INIT-WARN] Falha ao limpar webhook: $($_.Exception.Message)"
}

if (Test-Path $offsetFile) {
    try {
        $savedOffset = Get-Content $offsetFile -ErrorAction Stop
        if ($savedOffset -match '^\d+$') {
            $offset = [int64]$savedOffset
            Log-Activity "[INIT] Offset restaurado: $offset"
        }
    } catch {
        Log-Activity "[INIT-ERROR] Offset invalido no arquivo, iniciando do zero."
    }
}
Log-Activity "[INICIADO] TelegramListener v6.6 - FET Monitor OCR"

while($true) {
    try {
        $updates = Invoke-RestMethod "https://api.telegram.org/bot$bot/getUpdates?offset=$offset&timeout=$apiTimeoutSeconds"

        foreach($update in $updates.result) {
            $offset = $update.update_id + 1
            try {
                "$offset" | Out-File $offsetFile -Encoding UTF8 -Force
            } catch {
                Log-Activity "[WARN] Falha ao salvar offset: $($_.Exception.Message)"
            }

            # PROCESSAR APENAS MENSAGENS DE TEXTO - NENHUM CALLBACK
            if($update.message -and $update.message.text) {
                $userId = $update.message.from.id
                $userName = if($update.message.from.first_name) { $update.message.from.first_name } else { "Usuario" }
                # Remover caracteres de controle invisiveis
                $command = ($update.message.text -replace '[\p{C}]+', '').Trim()

                if($userId -eq $authorizedUser) {
                    # Rate limiting - verificar se o comando nao esta sendo enviado muito rapidamente
                    $currentTime = Get-Date
                    if ($userLastCommandTime.ContainsKey($userId) -and ($currentTime - $userLastCommandTime[$userId]).TotalSeconds -lt $rateLimitSeconds) {
                        Send-Telegram $userId "RATE LIMIT`nAguarde $rateLimitSeconds segundos entre comandos"
                        continue
                    }
                    $userLastCommandTime[$userId] = $currentTime

                    Log-Activity "[COMANDO] $userName executou $command"

                    switch ($command) {
                        "/help" {
                            $helpText = "PC SECURITY v6.6 + FET MONITOR`nSistema: $pc`n`nCOMANDOS DISPONIVEIS:`n/help - Exibir este menu`n/bloquear - Bloquear PC + mute`n/screenshot - Capturar tela principal`n/screenshotall - Capturar TODOS os monitores`n/pausar - Pausar monitor (30min)`n/extender - +30min de pausa`n/retomar - Retomar monitoramento`n/desativar - Desativar bot TEMPORARIAMENTE (confirmacao dupla)`n`nFET MONITOR (OCR):`n/monitorfet_on - Ativar monitoramento FET`n/monitorfet_off - Desativar monitoramento FET`n/fetstatus - Status do FET`n`nAUDIO:`n/mute - Mutar som`n/unmute - Desmutar som`n/toggle - Alternar mute/unmute`n/audio - Status do audio`n`nENERGIA (confirmacao dupla):`n/desligar - Desligar PC`n/reiniciar - Reiniciar PC`n/cancelar - Cancelar operacao`n`nINFORMACOES:`n/status - Status do sistema`n/logs - Ultimos logs`n/debug - Info de debug`n/usb - Dispositivos USB`n/processos - Top processos`n`nSistema Online - v6.6 (FET OCR monitor)"
                            Send-Telegram $userId $helpText
                        }

                        "/bloquear" {
                            $time = Get-Date -Format "dd/MM/yyyy HH:mm:ss"
                            $muteStatus = if (Toggle-Audio-Mute) { "[OK] Som mutado" } else { "[ERRO] Falha ao mutar" }
                            Send-Telegram $userId "PC BLOQUEADO`nPC: $pc`nHora: $time`n$muteStatus"
                            Log-Activity "[BLOQUEIO] PC bloqueado remotamente com mute"
                            rundll32.exe user32.dll,LockWorkStation
                        }

                        "/screenshot" {
                            if(Send-Command-To-Monitor "screenshot") {
                                Send-Telegram $userId "CAPTURANDO SCREENSHOT (monitor principal)`nFormato: JPEG alta qualidade (95%)`nAguarde o envio..."
                                Log-Activity "[SCREENSHOT] Solicitado - monitor principal"
                            } else {
                                Send-Telegram $userId "ERRO`nFalha na comunicacao com monitor"
                            }
                        }

                        "/screenshotall" {
                            if(Send-Command-To-Monitor "screenshot" "all") {
                                Send-Telegram $userId "CAPTURANDO SCREENSHOT (todos os monitores)`nFormato: JPEG alta qualidade (95%)`nAguarde o envio..."
                                Log-Activity "[SCREENSHOT] Solicitado - todos os monitores"
                            } else {
                                Send-Telegram $userId "ERRO`nFalha na comunicacao com monitor"
                            }
                        }

                        "/monitorfet_on" {
                            try {
                                @{ enabled = $true; last_command = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss') } | ConvertTo-Json | Out-File $fetControlFile -Encoding UTF8
                                Send-Telegram $userId "FET MONITOR ATIVADO`nCaptura OCR a cada 5 min`nAlertas: regressao, travamento, conclusao`nPC: $pc"
                                Log-Activity "[FET] Monitoramento ativado"
                            } catch {
                                Send-Telegram $userId "ERRO`nFalha ao ativar monitoramento FET"
                            }
                        }

                        "/monitorfet_off" {
                            try {
                                @{ enabled = $false; last_command = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss') } | ConvertTo-Json | Out-File $fetControlFile -Encoding UTF8
                                Send-Telegram $userId "FET MONITOR DESATIVADO`nPC: $pc"
                                Log-Activity "[FET] Monitoramento desativado"
                            } catch {
                                Send-Telegram $userId "ERRO`nFalha ao desativar monitoramento FET"
                            }
                        }

                        "/fetstatus" {
                            try {
                                if (Test-Path $fetStatusFile) {
                                    $fetStatus = Get-Content $fetStatusFile -Raw | ConvertFrom-Json
                                    $statusMsg = "FET STATUS`n"
                                    $statusMsg += "Atividades: $($fetStatus.atual)/$($fetStatus.total)`n"
                                    $statusMsg += "Maximo: $($fetStatus.max)`n"
                                    $statusMsg += "Tempo: $($fetStatus.tempo)`n"
                                    $statusMsg += "Concluido: $(if ($fetStatus.concluido) { 'SIM' } else { 'NAO' })`n"
                                    $statusMsg += "Ultima verificacao: $($fetStatus.last_check)`n"
                                    $statusMsg += "PC: $pc"
                                    Send-Telegram $userId $statusMsg
                                } else {
                                    # Verificar se esta ativado
                                    $fetControl = if (Test-Path $fetControlFile) { Get-Content $fetControlFile -Raw | ConvertFrom-Json } else { @{ enabled = $false } }
                                    if ($fetControl.enabled) {
                                        Send-Telegram $userId "FET MONITOR`nAtivado, aguardando primeira leitura...`nPC: $pc"
                                    } else {
                                        Send-Telegram $userId "FET MONITOR`nDesativado`nUse /monitorfet_on para ativar`nPC: $pc"
                                    }
                                }
                                Log-Activity "[FET] Status consultado"
                            } catch {
                                Send-Telegram $userId "ERRO`nFalha ao obter status FET"
                            }
                        }

                        "/pausar" {
                            if(Send-Command-To-Monitor "pause" "30") {
                                Send-Telegram $userId "PAUSADO`nMonitoramento pausado por 30min`nUse /retomar para reativar"
                                Log-Activity "[PAUSE] Monitor pausado"
                            } else {
                                Send-Telegram $userId "ERRO`nFalha ao pausar"
                            }
                        }

                        "/extender" {
                            if(Send-Command-To-Monitor "extend" "30") {
                                Send-Telegram $userId "ESTENDIDO`nPausa estendida por +30min"
                                Log-Activity "[EXTEND] Pausa estendida"
                            } else {
                                Send-Telegram $userId "ERRO`nNao foi possivel estender"
                            }
                        }

                        "/retomar" {
                            if(Send-Command-To-Monitor "resume") {
                                Send-Telegram $userId "RETOMADO`nMonitoramento reativado"
                                Log-Activity "[RESUME] Monitor retomado"
                            } else {
                                Send-Telegram $userId "ERRO`nFalha ao retomar"
                            }
                        }

                        "/desligar" {
                            $confirmKey = "shutdown_$userId"
                            if ($pendingShutdown.ContainsKey($confirmKey)) {
                                $timeElapsed = ((Get-Date) - $pendingShutdown[$confirmKey]).TotalSeconds
                                if ($timeElapsed -le 30) {
                                    Send-Telegram $userId "DESLIGAMENTO CONFIRMADO`nDesligando em 30s...`nUse /cancelar para abortar"
                                    Log-Activity "[SHUTDOWN] Confirmado e executado"
                                    $pendingShutdown.Remove($confirmKey)
                                    Start-Process "shutdown.exe" -ArgumentList "/s /t 30" -WindowStyle Hidden
                                } else {
                                    $pendingShutdown[$confirmKey] = Get-Date
                                    Send-Telegram $userId "CONFIRMACAO NECESSARIA`nTempo expirou. Digite /desligar novamente em 30s"
                                }
                            } else {
                                $pendingShutdown[$confirmKey] = Get-Date
                                Send-Telegram $userId "CONFIRMACAO NECESSARIA`nDigite /desligar novamente em 30s para confirmar"
                            }
                        }

                        "/reiniciar" {
                            $confirmKey = "restart_$userId"
                            if ($pendingRestart.ContainsKey($confirmKey)) {
                                $timeElapsed = ((Get-Date) - $pendingRestart[$confirmKey]).TotalSeconds
                                if ($timeElapsed -le 30) {
                                    Send-Telegram $userId "REINICIO CONFIRMADO`nReiniciando em 30s...`nUse /cancelar para abortar"
                                    Log-Activity "[RESTART] Confirmado e executado"
                                    $pendingRestart.Remove($confirmKey)
                                    Start-Process "shutdown.exe" -ArgumentList "/r /t 30" -WindowStyle Hidden
                                } else {
                                    $pendingRestart[$confirmKey] = Get-Date
                                    Send-Telegram $userId "CONFIRMACAO NECESSARIA`nTempo expirou. Digite /reiniciar novamente em 30s"
                                }
                            } else {
                                $pendingRestart[$confirmKey] = Get-Date
                                Send-Telegram $userId "CONFIRMACAO NECESSARIA`nDigite /reiniciar novamente em 30s para confirmar"
                            }
                        }

                        "/cancelar" {
                            $cancelled = $false

                            if ($pendingShutdown.ContainsKey("shutdown_$userId")) {
                                $pendingShutdown.Remove("shutdown_$userId")
                                $cancelled = $true
                            }
                            if ($pendingRestart.ContainsKey("restart_$userId")) {
                                $pendingRestart.Remove("restart_$userId")
                                $cancelled = $true
                            }

                            try {
                                Start-Process "shutdown.exe" -ArgumentList "/a" -WindowStyle Hidden -ErrorAction SilentlyContinue
                            } catch {}

                            if ($cancelled) {
                                Send-Telegram $userId "CANCELADO`nOperacao de energia cancelada"
                                Log-Activity "[CANCEL] Operacao cancelada"
                            } else {
                                Send-Telegram $userId "INFO`nNenhuma operacao pendente"
                            }
                        }

                        "/desativar" {
                            $confirmKey = "disable_$userId"
                            if ($pendingDisable.ContainsKey($confirmKey)) {
                                $timeElapsed = ((Get-Date) - $pendingDisable[$confirmKey]).TotalSeconds
                                if ($timeElapsed -le 30) {
                                    if (Disable-System) {
                                        Send-Telegram $userId "DESATIVADO TEMPORARIAMENTE`nBot e monitores encerrados.`n`nNOTA: Apos reiniciar o PC, o sistema volta a funcionar automaticamente.`n`nListener sera encerrado agora."
                                        Log-Activity "[DISABLE-TEMP] Sistema desativado remotamente (temporario)"
                                        $pendingDisable.Remove($confirmKey)
                                        $shouldExit = $true
                                        break
                                    } else {
                                        Send-Telegram $userId "ERRO`nFalha ao desativar sistema"
                                    }
                                } else {
                                    $pendingDisable[$confirmKey] = Get-Date
                                    Send-Telegram $userId "CONFIRMACAO NECESSARIA`nTempo expirou. Digite /desativar novamente em 30s"
                                }
                            } else {
                                $pendingDisable[$confirmKey] = Get-Date
                                Send-Telegram $userId "CONFIRMACAO NECESSARIA`nDigite /desativar novamente em 30s para confirmar`n`nNOTA: Desativacao e temporaria. Sistema volta apos reiniciar PC."
                            }
                        }

                        "/status" {
                            if (Test-Path $monitorStatusFile) {
                                try {
                                    $status = Get-Content $monitorStatusFile | ConvertFrom-Json
                                    $statusText = "STATUS DO SISTEMA`nPC: $pc`nStatus: $($status.status)`nUltima atividade: $($status.last_activity)`nTempo inativo: $($status.inactive_time)`nMonitoramento: $($status.monitoring)"
                                } catch {
                                    $statusText = "STATUS`nPC: $pc`nStatus: Erro ao ler arquivo"
                                }
                            } else {
                                $statusText = "STATUS`nPC: $pc`nStatus: Monitor offline"
                            }
                            Send-Telegram $userId $statusText
                        }

                        "/logs" {
                            if (Test-Path $logFile) {
                                try {
                                    $logs = Get-Content $logFile -Tail 5 -Encoding UTF8 | Out-String
                                    Send-Telegram $userId "ULTIMOS LOGS:`n`n$logs"
                                } catch {
                                    Send-Telegram $userId "ERRO`nFalha ao ler logs"
                                }
                            } else {
                                Send-Telegram $userId "ERRO`nArquivo de logs nao encontrado"
                            }
                        }

                        "/debug" {
                            $time = Get-Date -Format "dd/MM/yyyy HH:mm:ss"
                            $debugText = "DEBUG INFO`nPC: $pc`nHora: $time`nListener: Ativo v$($script:Version)`nUser ID: $authorizedUser`nOffset: $offset"
                            Send-Telegram $userId $debugText
                        }

                        "/usb" {
                            try {
                                $usbDevices = Get-CimInstance -ClassName Win32_LogicalDisk | Where-Object { $_.DriveType -eq 2 }
                                if ($usbDevices) {
                                    $usbText = "DISPOSITIVOS USB:`n`n"
                                    foreach ($usb in $usbDevices) {
                                        $size = [math]::Round($usb.Size/1GB, 2)
                                        $usbText += "Drive: $($usb.DeviceID) - ${size}GB`n"
                                    }
                                } else {
                                    $usbText = "USB`nNenhum dispositivo detectado"
                                }
                            } catch {
                                $usbText = "ERRO`nFalha ao consultar USB"
                            }
                            Send-Telegram $userId $usbText
                        }

                        "/processos" {
                            try {
                                $processes = Get-Process | Sort-Object CPU -Descending | Select-Object -First 5 Name, CPU, WorkingSet
                                $procText = "TOP 5 PROCESSOS:`n`n"
                                foreach ($proc in $processes) {
                                    $cpu = if ($proc.CPU) { [math]::Round($proc.CPU, 1) } else { "0" }
                                    $mem = [math]::Round($proc.WorkingSet / 1MB, 1)
                                    $procText += "$($proc.Name) - CPU:${cpu}s RAM:${mem}MB`n"
                                }
                            } catch {
                                $procText = "ERRO`nFalha ao consultar processos"
                            }
                            Send-Telegram $userId $procText
                        }

                        "/mute" {
                            if (Toggle-Audio-Mute) {
                                Send-Telegram $userId "SOM ALTERNADO`n[OK] Comando mute enviado (toggle)`nNOTA: VK_VOLUME_MUTE sempre alterna o estado"
                                Log-Activity "[AUDIO] Mute toggle executado remotamente"
                            } else {
                                Send-Telegram $userId "ERRO`nFalha ao alternar o som"
                            }
                        }

                        "/unmute" {
                            if (Toggle-Audio-Mute) {
                                Send-Telegram $userId "SOM ALTERNADO`n[OK] Comando unmute enviado (toggle)`nNOTA: VK_VOLUME_MUTE sempre alterna o estado"
                                Log-Activity "[AUDIO] Unmute toggle executado remotamente"
                            } else {
                                Send-Telegram $userId "ERRO`nFalha ao alternar o som"
                            }
                        }

                        "/toggle" {
                            if (Toggle-Audio-Mute) {
                                Send-Telegram $userId "AUDIO ALTERNADO`n[OK] Estado de mute alternado com sucesso"
                                Log-Activity "[AUDIO] Toggle executado remotamente"
                            } else {
                                Send-Telegram $userId "ERRO`nFalha ao alternar o som"
                            }
                        }

                        "/audio" {
                            Send-Telegram $userId "STATUS DO AUDIO`nPC: $pc`n`nNOTA: Status em tempo real nao disponivel.`nSendKeys (VK_VOLUME_MUTE) apenas alterna o estado,`nnao e possivel consultar o estado atual.`n`nUse /toggle para alternar mute/unmute"
                        }

                        default {
                            # Ignora texto comum; responde apenas a comandos /
                            if ($command.StartsWith('/')) {
                                Send-Telegram $userId "COMANDO INVALIDO`nUse /help para ver comandos disponiveis"
                            }
                        }
                    }
                } else {
                    Log-Activity "[ACESSO NEGADO] $userName ($userId) tentou $command"
                }
            }
        }
        if ($shouldExit) { break }
    } catch {
        Log-Activity "[ERRO] Falha na comunicacao com API Telegram: $($_.Exception.Message)"
        Start-Sleep -Seconds $errorSleepSeconds
    }
    Start-Sleep -Seconds $normalSleepSeconds
}
