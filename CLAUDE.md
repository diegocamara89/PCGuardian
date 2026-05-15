# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

PC Security (SegurancaPC), also distributed under the friendly name **VigiaPC**, is a Windows-based parental control and remote monitoring system that provides inactivity monitoring, remote PC locking, USB monitoring, and Telegram-based remote control. The system consists of PowerShell monitoring scripts, a Python installer, an interactive local CLI controller, and uses Telegram Bot API for remote administration.

Current version: **v6.6** — adds `MonitorFET.ps1` with OCR-based progress tracking.

## Architecture

### Core Components

1. **TelegramListener.ps1** - Main remote control interface
   - Polls Telegram Bot API for commands
   - Handles 20+ commands (/bloquear, /screenshot, /pausar, /audio, etc.)
   - Implements double-confirmation for critical operations (shutdown, restart, disable)
   - Rate limiting to prevent command spam
   - Communicates with MonitorInatividade via JSON control files

2. **MonitorInatividade.ps1** - Inactivity monitor
   - Uses Win32 API (GetLastInputInfo) to track user idle time
   - Auto-blocks PC after configurable inactivity period
   - Sends warning before blocking
   - Mutes audio when blocking (using keybd_event)
   - Supports remote pause/resume via monitor_control.json
   - Writes status to monitor_status.json for TelegramListener queries
   - **Screenshot functionality**: Captures screen using System.Drawing and sends via Telegram
     - Responds to `/screenshot` command from TelegramListener
     - Auto-captures on block if `ScreenshotOnBlock` is enabled
   - **USB Monitoring**: Detects new USB devices in real-time
     - Alerts via Telegram when USB is connected/removed
     - Auto-blocks PC if `AutoBlockOnUSB` is enabled

3. **MonitorLogin.ps1** - Login notification
   - Triggers on user login (via scheduled task)
   - Mutes audio at login
   - Sends Telegram notification with user and timestamp

4. **MonitorFET.ps1** - OCR-based progress monitor (optional, v6.6+)
   - Captures screen, OCRs via `Windows.Media.Ocr` (UWP)
   - Parses FET (timetabling software) status text and tracks: current/total activities, max reached, elapsed time
   - Alerts on regression (30+ activity drop), stall (30 min no progress), completion, and new execution
   - Controlled via `Config/fet_control.json` (`enabled: true|false`)
   - Status surfaced in `Config/fet_status.json`

5. **Controlador.ps1** - Local interactive CLI (numeric menu)
   - Lets the operator perform the same actions as the bot directly on the host without depending on Telegram
   - Useful when network is down, when debugging, or when the listener is hung

6. **installer_main.py** - Interactive installer
   - Prompts for configuration (PC name, bot token, user ID, thresholds)
   - Copies template files from bundled resources
   - Writes settings.json configuration
   - Creates Windows scheduled task for autostart
   - Optionally starts monitoring immediately

### Inter-Process Communication

The scripts communicate via JSON files in the Config directory:

- **monitor_control.json** - Commands from TelegramListener to MonitorInatividade
  - Commands: pause, extend, resume, stop, screenshot
  - Has `processed` flag to prevent duplicate execution

- **monitor_status.json** - Status from MonitorInatividade to TelegramListener
  - Contains: status, last_activity, inactive_time, monitoring state, pause_until

- **settings.json** - Central configuration (gitignored)
  - Bot credentials (BotToken, UserId)
  - Timing thresholds (InactivityMin, WarningMin)
  - Feature flags (ScreenshotOnBlock, USBMonitoring, ProcessMonitoring, AutoBlockOnUSB)
  - Optional `FetCheckIntervalSeconds` for the FET monitor

- **settings.example.json** - Template with placeholder values, versioned in the repo.

- **fet_control.json / fet_status.json** - Control/status channel for MonitorFET.

### File Structure

```
C:\SegurancaPC\
├── Scripts\
│   ├── TelegramListener.ps1    # Main bot listener
│   ├── MonitorInatividade.ps1  # Inactivity monitor + USB + screenshot
│   ├── MonitorLogin.ps1         # Login notification
│   ├── MonitorFET.ps1           # OCR progress monitor (v6.6+)
│   └── Controlador.ps1          # Local interactive CLI
├── Config\
│   ├── settings.example.json    # Template (versioned)
│   ├── settings.json            # Real config (gitignored)
│   ├── monitor_control.json     # Command channel (runtime)
│   ├── monitor_status.json      # Status channel (runtime)
│   ├── fet_control.json         # FET on/off (runtime)
│   ├── fet_status.json          # FET progress (runtime)
│   ├── telegram_offset.txt      # Last seen update_id
│   ├── telegram_listener.lock   # Single-instance lock
│   ├── access.log               # Command/login events
│   └── debug.log                # Monitor debug logs
├── Screenshots\                 # Auto-captured screenshots (gitignored)
├── iniciar_sistema.bat          # Startup script
├── reiniciar_sistema.bat        # Restart helper
└── InstallerPackage\
    ├── installer_main.py        # Installer logic
    ├── SegurancaPC_Installer.spec  # PyInstaller spec
    └── SegurancaPC\             # Bundled template files
```

## Common Commands

### Building the Installer

```bash
# Build the installer executable using PyInstaller
cd InstallerPackage
pyinstaller SegurancaPC_Installer.spec

# Output: dist/SegurancaPC_Installer.exe
```

The spec file bundles the entire `InstallerPackage/SegurancaPC` directory as data files, which are extracted at runtime via `get_resource_path()`.

### Running the System

```bash
# Start both monitoring scripts
iniciar_sistema.bat

# Manually start individual components
powershell.exe -ExecutionPolicy Bypass -File "C:\SegurancaPC\Scripts\TelegramListener.ps1"
powershell.exe -ExecutionPolicy Bypass -File "C:\SegurancaPC\Scripts\MonitorInatividade.ps1"
```

The batch file starts TelegramListener first, waits 3 seconds, then starts MonitorInatividade.

### Testing Configuration

```bash
# View current settings
type C:\SegurancaPC\Config\settings.json

# Check monitor status
type C:\SegurancaPC\Config\monitor_status.json

# View recent logs
type C:\SegurancaPC\Config\access.log
type C:\SegurancaPC\Config\debug.log
```

### Telegram Bot Commands

Send these commands to the configured Telegram bot:

- `/help` - List all commands
- `/bloquear` - Lock PC immediately
- `/pausar` - Pause monitoring for 30 minutes
- `/status` - Get current system status
- `/mute` / `/unmute` / `/toggle` - Audio control

Critical commands require double-confirmation within 30 seconds:
- `/desligar` - Shutdown PC
- `/reiniciar` - Restart PC
- `/desativar` - Disable monitoring system

## Development Notes

### Sensitive Data Handling

**CRITICAL**: The settings.json file contains the Telegram bot token and should NEVER be committed to version control. Always use template files with placeholder values for distribution.

### PowerShell Execution

All scripts use `$ErrorActionPreference = 'SilentlyContinue'` or `-ErrorAction SilentlyContinue` to prevent error dialogs. When debugging, temporarily change to `'Continue'` to see errors.

### Audio Muting Implementation

The system uses TWO methods to mute audio:
1. **SendKeys** (char 173 = VK_VOLUME_MUTE) in TelegramListener
2. **keybd_event** Win32 API in MonitorInatividade and MonitorLogin

Both methods toggle mute state. The keybd_event approach is more reliable but requires Add-Type C# compilation.

### Scheduled Tasks

The installer creates the task `SegurancaPC_AutoStart` with `/RL HIGHEST` (admin privileges) and `/SC ONLOGON` trigger. View with:

```bash
schtasks /Query /TN SegurancaPC_AutoStart /V /FO LIST
```

### Windows API Usage

MonitorInatividade.ps1 uses inline C# code (Add-Type) to access:
- `GetLastInputInfo` - Tracks keyboard/mouse idle time
- `keybd_event` - Simulates mute key press

This code is compiled into PowerShell session memory at runtime.

## Configuration Variables

Key settings in `Config/settings.json`:

- `BotToken` - Telegram bot API token
- `UserId` - Authorized Telegram user ID (numeric)
- `PCName` - Identifier for this PC in notifications
- `InactivityMin` - Minutes of inactivity before auto-block (default: 5)
- `WarningMin` - Minutes before block to send warning (default: 1)
- `ScreenshotOnBlock` - **[FUNCTIONAL]** Captures and sends screenshot automatically when PC is blocked by inactivity
- `USBMonitoring` - **[FUNCTIONAL]** Monitors USB devices in real-time and alerts when new devices are connected
- `ProcessMonitoring` - **[NOT IMPLEMENTED]** Suspicious process monitoring (intentionally disabled)
- `AutoBlockOnUSB` - **[FUNCTIONAL]** Auto-blocks PC when unauthorized USB is detected (requires `USBMonitoring: true`)

## Implemented Features (v6.6)

### FET Progress Monitor (OCR)
- **Optional** — disabled by default. Activate with `/monitorfet_on`.
- Captures the primary screen every 5 minutes (configurable via `FetCheckIntervalSeconds`).
- OCR via `Windows.Media.Ocr` (requires the pt-BR language pack with OCR engine).
- Parses lines such as `"1811 de um total de 1842 atividades alocadas"`, `"Tempo total: 34 min 14 s"`, `"Máx atividades alocadas: 1817"`.
- Telegram alerts on regression (30+ activity drop), stall (30 min without progress), completion, and new run detection.
- Keeps only the last 5 screenshots in `Screenshots/FET/` to save disk.

### Screenshot Functionality
- **Command `/screenshot`**: Captures current screen and sends via Telegram on demand
- **Auto-screenshot on block**: When `ScreenshotOnBlock: true`, automatically captures screen before blocking PC due to inactivity
- **Implementation**: Uses .NET System.Drawing.Bitmap to capture primary screen, saves to Screenshots folder, sends via Telegram sendPhoto API
- **File format**: PNG images named `screenshot_YYYY-MM-DD_HH-mm-ss.png`

### USB Monitoring
- **Real-time detection**: Monitors USB devices using WMI Win32_LogicalDisk (DriveType = 2)
- **Change tracking**: Compares current devices with known devices list to detect additions/removals
- **Telegram alerts**: Sends notification with device ID, volume name, and size when USB is connected
- **Auto-block**: If `AutoBlockOnUSB: true`, automatically locks PC when unknown USB is detected
- **Logging**: All USB events are logged to debug.log

### Disabled Features
- **ProcessMonitoring**: Intentionally not implemented (was causing false positives and user frustration)
- File `suspicious_processes.json` exists but is not used by the code

## Language and Localization

All user-facing messages are in Portuguese (BR). Error messages, logs, and Telegram responses use Portuguese strings. Variable names and code comments are mixed Portuguese/English.
