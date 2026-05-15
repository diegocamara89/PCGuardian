# Changelog

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/).

## [Não lançado]

### Adicionado
- `Scripts/Common.psm1`: módulo compartilhado com `Send-TelegramMessage`, `Send-TelegramDocument`, `Get-VigiaConfig`, `Get-VigiaPaths`, `Write-VigiaLog` e `Trim-VigiaLog`. Elimina a duplicação que existia em três scripts e centraliza acesso à API do Telegram.
- `Scripts/Controlador.ps1`: menu CLI local para administrar o sistema sem depender do Telegram.
- `tools/sync_bundle.ps1`: copia `Scripts/*` e `*.bat` de root para o bundle do installer e valida sintaxe.
- `tools/legacy/`: scripts pessoais de manutenção pontual movidos para fora da publicação (ignorados pelo git).
- `Config/settings.example.json` versionado como template.
- `docs/superpowers/specs/` e `docs/superpowers/plans/`: spec e plano da publicação.
- `README.md`, `LICENSE` (MIT) e este `CHANGELOG.md`.
- `.gitignore` cobrindo segredos, runtime, screenshots, artefatos de build e `tools/legacy/`.

### Corrigido
- `installer_main.py`: `update_settings()` agora lê `settings.json` do bundle com `utf-8-sig`, tolerando templates salvos com BOM. Bug real encontrado durante validação end-to-end do `.exe` (`json.decoder.JSONDecodeError: Unexpected UTF-8 BOM`).
- `InstallerPackage/SegurancaPC/Config/settings.json` e `Config/settings.example.json`: re-salvos sem BOM (UTF-8 puro).
- `Scripts/*`: paths absolutos (`C:\SegurancaPC\...`) substituídos por `Get-VigiaPaths`/`$PSScriptRoot` — sistema agora roda de qualquer diretório.
- `MonitorInatividade.ps1`: 14 referências órfãs a `$configDir\debug.log` corrigidas durante o refactor para `$debugLog`.
- `installer_main.py`: trocados token e User ID reais que apareciam no help interativo por valores sintéticos.
- `TelegramListener.ps1`: comportamento do `default` no switch — passa a ignorar texto que não começa com `/`.
- `TelegramListener.ps1`: versão exibida em `/debug` corrigida para refletir a versão real do script.
- `TelegramListener.ps1`: substituídas chamadas legadas `Get-WmiObject` por `Get-CimInstance`.
- `MonitorInatividade.ps1`: removida notificação de start spam `"[PATCH v6.4]..."` que era enviada a cada reinício.
- `MonitorInatividade.ps1`: rotação básica de log (trunca `debug.log` quando passa de ~10 MB).
- `MonitorFET.ps1`: removido bloco de código morto em `Process-FETData`.
- `InstallerPackage/SegurancaPC_Installer.spec`: caminho do bundle convertido para relativo.
- `InstallerPackage/SegurancaPC/Scripts/`: sincronizado com a versão atual do `Scripts/`.
- Removidos do repositório: scripts pessoais de migração (`atualizar_*.bat`, `forcar_reinicio_telegram.bat`, `restart_telegram.ps1`, `verificar_versao.ps1`, `reiniciar_v66.ps1`, `check_*.ps1`, `reabilitar_bot.bat`) — eram artefatos de manutenção pontual.
- Apagado o arquivo `nul` criado por engano com `> nul` em PowerShell.

### Removido
- Artefatos `InstallerPackage/build/` e `InstallerPackage/dist/` (regeneráveis).
- Transcript pessoal do Claude Code (`2025-12-31-caveat-...txt`).
- Screenshots de teste em `Screenshots/`.
- Pergunta "Monitorar processos suspeitos?" do instalador — flag era documentada como não implementada mas vinha ligada por padrão (inconsistência).
- Variável `$basePath` não utilizada em `TelegramListener.ps1` após o refactor.

### Roadmap (apontado por code review, não bloqueia o release inicial)
- **PowerShell verb compliance**: vários comandos usam verbos fora da [lista aprovada](https://learn.microsoft.com/powershell/scripting/developer/cmdlet/approved-verbs-for-windows-powershell-commands) (`Toggle-`, `Log-`, `Capture-`, `Is-`, `Handle-`, `Parse-`, `Process-`, `Run-`, `Trim-`). Renomear é refactor invasivo. Candidatos: `Toggle-Audio-Mute → Switch-AudioMute`, `Log-Activity → Write-ActivityLog`, `Capture-Screenshot → New-Screenshot`, `Is-PC-Locked → Test-PCLocked`, etc.
- **Funções grandes**: `Capture-Screenshot` (~80 linhas) e `Handle-ControlCommand` (~75 linhas) em `MonitorInatividade.ps1`, e o `switch` gigante em `TelegramListener.ps1` (~300 linhas), poderiam ser decompostos em dispatch tables.
- **Duplicação de captura DPI-aware**: `MonitorInatividade.Capture-Screenshot` e `MonitorFET.Capture-Screen` reimplementam a mesma lógica de bitmap + crop + resize. Candidato a `New-VigiaScreenshot` em `Common.psm1`.
- **`Send-TelegramDocument` multipart manual** usa `iso-8859-1` para encodar binário — funciona, mas frágil. Em PS 7+, trocar por `Invoke-RestMethod -Form`; em PS 5.1, por `System.Net.Http.MultipartFormDataContent`.
- **`$ErrorActionPreference = 'SilentlyContinue'`** global nos monitores esconde causas de falha de IPC/WMI. Mudar para `Stop` seletivamente nos pontos críticos com logging explícito.
- **Telegram helpers retornam só `$false`** descartando a exceção. Estruturar retorno com causa para troubleshooting.
- **Token em texto plano** em `settings.json` — migrar para DPAPI/Credential Manager.
- **Endurecer ACL** do diretório de instalação no instalador (`icacls`).
- **IPC autenticado** entre listener/monitores (HMAC com chave gerada na instalação).

---

## [6.6] - 2026-01

### Adicionado
- `MonitorFET.ps1`: monitor especializado que captura a janela do FET, faz OCR
  (Windows.Media.Ocr) e alerta progresso, regressão (30+ atividades), travamento
  (30 min sem progresso) e conclusão.
- Comandos `/monitorfet_on`, `/monitorfet_off`, `/fetstatus` no listener.
- `iniciar_fet_monitor.bat` para subir só o monitor FET.

---

## [6.5] - 2025-12

### Adicionado
- Comando `/screenshotall`: captura **todos os monitores** (virtual screen) em uma imagem só.
- Lockfile (`Config/telegram_listener.lock`) garantindo instância única do listener.

### Modificado
- Screenshots passam a usar JPEG qualidade 95 (em vez de PNG) — arquivos ~70% menores, melhor para visualização no celular.

---

## [6.4] - 2025-10

### Adicionado
- Screenshot automático antes de bloquear por inatividade (`ScreenshotOnBlock`).
- Monitor de USB em tempo real via WMI `Win32_LogicalDisk`.
- `AutoBlockOnUSB`: bloqueio automático quando um USB desconhecido é conectado.
- Detecção de bloqueio do PC via `OpenInputDesktop` (Win32) para evitar
  notificações duplicadas quando a tela já está bloqueada.

---

## [6.2] - 2025-09

### Adicionado
- Sistema de confirmação dupla com janela de 30s para `/desligar`, `/reiniciar` e `/desativar`.
- Rate limit de 2s entre comandos do mesmo usuário.
- Persistência do `offset` do Telegram em arquivo para resistir a reinícios.

### Modificado
- Áudio via `keybd_event` Win32 (mais robusto que SendKeys) no monitor.

---

## [5.3] - 2025-09 (versão histórica)

- Primeira versão funcional do listener com controle remoto via Telegram.
