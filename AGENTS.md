# Repository Guidelines

## Project Structure & Module Organization

- `Scripts/` contains the core PowerShell services: `TelegramListener.ps1`, `MonitorInatividade.ps1`, `MonitorLogin.ps1`, `MonitorFET.ps1` (OCR progress monitor), and `Controlador.ps1` (local CLI).
- `Config/` holds runtime state and configuration, including `settings.json`, `monitor_control.json`, and `monitor_status.json`.
- `Screenshots/` stores auto-captured images (PNG/JPG).
- Root batch scripts like `iniciar_sistema.bat` orchestrate startup.
- `InstallerPackage/` contains the Python-based installer and PyInstaller spec.

## Build, Test, and Development Commands

- Build the installer:
  - `cd InstallerPackage`
  - `pyinstaller SegurancaPC_Installer.spec`
  - Output: `InstallerPackage/dist/SegurancaPC_Installer.exe`
- Run locally:
  - `iniciar_sistema.bat` (starts listener, then inactivity monitor)
  - `powershell.exe -ExecutionPolicy Bypass -File "C:\SegurancaPC\Scripts\TelegramListener.ps1"`
  - `powershell.exe -ExecutionPolicy Bypass -File "C:\SegurancaPC\Scripts\MonitorInatividade.ps1"`
- Inspect runtime status:
  - `type C:\SegurancaPC\Config\monitor_status.json`
  - `type C:\SegurancaPC\Config\debug.log`

## Coding Style & Naming Conventions

- PowerShell scripts use mixed Portuguese/English identifiers and Portuguese user-facing strings.
- Indentation is 2 spaces in JSON and typical PowerShell style in scripts; follow existing formatting in the file you touch.
- Batch files use snake_case naming (e.g., `iniciar_sistema.bat`).
- Keep messages and bot responses in Portuguese (BR).

## Testing Guidelines

- No automated test suite is present.
- Validate changes by running the relevant script and checking `Config/monitor_status.json`, `Config/debug.log`, and Telegram command behavior.
- Screenshot files should land in `Screenshots/` with timestamped names.

## Commit & Pull Request Guidelines

- No Git history is available in this workspace, so no commit message convention is enforced.
- If contributing via PR, include a brief description, steps to verify, and note any config changes (especially `Config/settings.json`).

## Security & Configuration Tips

- `Config/settings.json` contains the Telegram bot token and must not be committed or shared. It is listed in `.gitignore`.
- `Config/settings.example.json` is the versioned template with placeholder values.
- Use template or placeholder values when packaging or distributing configs. Never paste a real token into source, examples, error messages, or commit messages.
