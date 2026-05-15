import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

VALID_BOOL = {"y": True, "yes": True, "s": True, "sim": True,
              "n": False, "no": False, "nao": False, "na": False}

# Regex para validacao de token do Telegram (formato: 1234567890:ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefg)
TOKEN_PATTERN = re.compile(r'^\d{8,10}:[A-Za-z0-9_-]{35,}$')

# Regex para validacao de User ID do Telegram (apenas numeros)
USER_ID_PATTERN = re.compile(r'^\d{6,15}$')


def get_resource_path() -> Path:
    if getattr(sys, "frozen", False):
        base = Path(sys._MEIPASS)  # type: ignore[attr-defined]
    else:
        base = Path(__file__).resolve().parent
    return base / "SegurancaPC"


def prompt(text: str, default: str | None = None) -> str:
    suffix = f" [{default}]" if default else ""
    while True:
        raw = input(f"{text}{suffix}: ").strip()
        if raw:
            return raw
        if default is not None:
            return default
        print("Valor obrigatorio. Tente novamente.")


def prompt_bool(text: str, default: bool = True) -> bool:
    suffix = " [S/n]" if default else " [s/N]"
    while True:
        raw = input(f"{text}{suffix}: ").strip().lower()
        if not raw:
            return default
        if raw in VALID_BOOL:
            return VALID_BOOL[raw]
        print("Responda com s ou n.")


def prompt_bot_token(text: str) -> str:
    """Solicita e valida token do bot Telegram."""
    while True:
        token = input(f"{text}: ").strip()
        if not token:
            print("Token obrigatorio. Tente novamente.")
            continue
        if TOKEN_PATTERN.match(token):
            return token
        print("Token invalido. Formato esperado: 1234567890:ABCdef...")
        print("Exemplo: 1234567890:AAHwEXemploTokenSinteticoNaoUtilizavel0123")


def prompt_user_id(text: str) -> str:
    """Solicita e valida User ID do Telegram."""
    while True:
        user_id = input(f"{text}: ").strip()
        if not user_id:
            print("User ID obrigatorio. Tente novamente.")
            continue
        if USER_ID_PATTERN.match(user_id):
            return user_id
        print("User ID invalido. Deve conter apenas numeros (6-15 digitos).")
        print("Exemplo: 123456789")


def ensure_writable(path: Path) -> None:
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.touch(exist_ok=True)
    except PermissionError as exc:
        raise SystemExit(f"Permissao negada ao escrever em {path}. Execute como administrador.") from exc
    finally:
        if path.exists() and path.stat().st_size == 0:
            path.unlink()


def copy_template(template_dir: Path, target_dir: Path) -> None:
    if target_dir.exists() and any(target_dir.iterdir()):
        print(f"Diretorio {target_dir} ja possui arquivos.")
        overwrite = prompt_bool("Deseja atualizar os arquivos existentes?", True)
        if not overwrite:
            print("Mantendo arquivos existentes.")
            return
    print(f"Copiando arquivos para {target_dir}...")
    shutil.copytree(template_dir, target_dir, dirs_exist_ok=True)


def update_settings(config_dir: Path, pc_name: str, bot_token: str, user_id: str,
                    inactivity: int, warning: int, screenshot: bool,
                    usb_monitor: bool, process_monitor: bool, auto_block_usb: bool) -> None:
    settings_path = config_dir / "settings.json"
    if not settings_path.exists():
        raise SystemExit(f"Arquivo de configuracoes nao encontrado em {settings_path}.")
    with settings_path.open("r", encoding="utf-8") as fh:
        data = json.load(fh)
    data["PCName"] = pc_name
    data["BotToken"] = bot_token
    data["UserId"] = user_id
    data["InactivityMin"] = inactivity
    data["WarningMin"] = warning
    data["ScreenshotOnBlock"] = bool(screenshot)
    data["USBMonitoring"] = bool(usb_monitor)
    data["ProcessMonitoring"] = bool(process_monitor)
    data["AutoBlockOnUSB"] = bool(auto_block_usb)
    with settings_path.open("w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=2, ensure_ascii=False)
        fh.write("\n")


def register_startup_task(batch_path: Path) -> bool:
    task_name = "SegurancaPC_AutoStart"
    arguments = [
        "schtasks",
        "/Create",
        "/F",
        "/SC", "ONLOGON",
        "/RL", "HIGHEST",
        "/TN", task_name,
        "/TR", f'"{batch_path}"'
    ]
    result = subprocess.run(arguments, capture_output=True, text=True)
    if result.returncode == 0:
        print(f"Tarefa agendada '{task_name}' criada com sucesso.")
        return True
    print("Falha ao criar tarefa agendada. Saida:")
    print(result.stdout or result.stderr)
    print("Configure a inicializacao manualmente se necessario.")
    return False


def main() -> None:
    print("=== Instalador do PC Security ===")
    template_dir = get_resource_path()
    if not template_dir.exists():
        raise SystemExit("Nao foi possivel localizar os arquivos de instalacao internos.")

    default_install = Path("C:/SegurancaPC")
    install_dir = Path(prompt("Diretorio de instalacao", str(default_install)))
    ensure_writable(install_dir / "test.tmp")

    pc_name = prompt("Nome para identificacao do PC", install_dir.name.upper())
    bot_token = prompt_bot_token("Token do bot Telegram")
    user_id = prompt_user_id("ID autorizado do Telegram")

    def prompt_int(label: str, default: int, min_value: int, max_value: int) -> int:
        while True:
            raw = prompt(label, str(default))
            try:
                value = int(raw)
            except ValueError:
                print("Informe um numero valido.")
                continue
            if value < min_value or value > max_value:
                print(f"Valor deve estar entre {min_value} e {max_value}.")
                continue
            return value

    inactivity = prompt_int("Minutos para bloquear por inatividade", 5, 1, 120)
    warning = prompt_int("Minutos de aviso antes do bloqueio", 1, 1, inactivity)
    screenshot = prompt_bool("Enviar screenshot ao bloquear?", True)
    usb_monitor = prompt_bool("Monitorar dispositivos USB?", True)
    # ProcessMonitoring é flag legada — não está implementada (mantida como False para compat)
    process_monitor = False
    auto_block_usb = prompt_bool("Bloquear automaticamente ao detectar USB nao autorizado?", False)

    copy_template(template_dir, install_dir)

    # Garante pastas de saida (screenshots / screenshots FET)
    (install_dir / "Screenshots").mkdir(parents=True, exist_ok=True)
    (install_dir / "Screenshots" / "FET").mkdir(parents=True, exist_ok=True)

    config_dir = install_dir / "Config"
    update_settings(
        config_dir=config_dir,
        pc_name=pc_name,
        bot_token=bot_token,
        user_id=user_id,
        inactivity=inactivity,
        warning=warning,
        screenshot=screenshot,
        usb_monitor=usb_monitor,
        process_monitor=process_monitor,
        auto_block_usb=auto_block_usb,
    )

    task_choice = prompt_bool("Criar tarefa para iniciar automaticamente?", True)
    autostart_ok = True
    if task_choice:
        batch_path = install_dir / "iniciar_sistema.bat"
        autostart_ok = register_startup_task(batch_path)

    start_now = prompt_bool("Deseja iniciar agora o monitoramento?", False)
    if start_now:
        batch_path = install_dir / "iniciar_sistema.bat"
        subprocess.Popen(["cmd.exe", "/c", str(batch_path)], creationflags=subprocess.CREATE_NEW_CONSOLE)
        print("Script iniciado em segundo plano.")

    print("\nInstalacao concluida.")
    print(f"Configuracoes salvas em {config_dir / 'settings.json'}")
    if not autostart_ok:
        print("AVISO: a tarefa de inicializacao automatica NAO foi criada.")
        print("       Inicie manualmente com 'iniciar_sistema.bat' ou crie a tarefa via schtasks.")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nInstalacao cancelada pelo usuario.")
