# MonitorLogin.ps1 - Notifica login do usuário via Telegram e muta o áudio.
# Disparado por tarefa agendada no evento ON LOGON.

Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -Force

$cfg = Get-VigiaConfig
$paths = Get-VigiaPaths

Add-Type @'
using System;
using System.Runtime.InteropServices;
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

Start-Sleep -Seconds 5
[AudioMute]::Mute()

$user = $env:USERNAME
$time = Get-Date -Format "dd/MM/yyyy HH:mm:ss"
$message = "[PC DESBLOQUEADO]`nPC: $($cfg.PCName)`nUsuario: $user`nHorario: $time"

if (Send-TelegramMessage -ChatId $cfg.UserId -Text $message) {
    Write-VigiaLog -Path $paths.AccessLog -Message "[LOGIN] Usuario $user desbloqueou PC"
} else {
    Write-VigiaLog -Path $paths.DebugLog -Message "[LOGIN-ERRO] Falha ao enviar notificacao Telegram"
    Write-VigiaLog -Path $paths.AccessLog -Message "[LOGIN] Usuario $user desbloqueou PC (notificacao falhou)"
}
