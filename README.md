# VigiaPC (SegurancaPC)

> Sistema de controle parental e monitoramento remoto para Windows, operado por bot do Telegram.
> Inclui bloqueio automático por inatividade, captura de tela sob demanda, monitoramento de USB,
> notificação de login e monitor especializado de progresso via OCR.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform: Windows](https://img.shields.io/badge/Plataforma-Windows%2010%2F11-blue)]()
[![PowerShell 5.1+](https://img.shields.io/badge/PowerShell-5.1%2B-blue)]()

> **Nota sobre o nome:** internamente o projeto se chama `SegurancaPC` / `PC Security`
> (em todos os caminhos `C:\SegurancaPC`, nas tarefas agendadas e no próprio
> instalador). O nome "VigiaPC" é apenas o nome amigável de divulgação. Os dois
> termos se referem ao mesmo software.

---

## ⚡ Quick start (TL;DR)

Para quem tem pressa — instalação completa em ~5 min:

1. **Crie um bot no Telegram:** abra [@BotFather](https://t.me/BotFather), envie `/newbot`, escolha nome e username (deve terminar em `bot`). Anote o **token**.
2. **Descubra seu User ID:** abra [@userinfobot](https://t.me/userinfobot) e envie qualquer mensagem. Anote o **número** que ele responde.
3. **Baixe** `SegurancaPC_Installer.exe` na [aba Releases](https://github.com/diegocamara89/PCGuardian/releases).
4. **Execute como Administrador** (botão direito → "Executar como administrador"). Se o Windows mostrar "SmartScreen protegeu seu PC", clique em **Mais informações → Executar mesmo assim** (ver [seção dedicada](#se-o-windows-bloquear-o-instalador)).
5. **Responda às perguntas** do instalador (token, user id, nome do PC).
6. **Teste:** envie `/help` ao seu bot. Você deve receber o menu de comandos.

Pronto. Detalhes nas seções abaixo.

---

## ⚠️ Aviso de uso responsável

Este software permite **bloquear remotamente um PC, capturar a tela, ser
notificado de logins e monitorar dispositivos USB**. Esses são poderes
significativos. Use apenas em equipamentos que você possui ou para os quais
tem **autorização explícita do usuário** (por exemplo, controle parental).

Monitorar uma máquina sem consentimento do usuário **pode violar a LGPD,
o Código Penal (art. 154-A — invasão de dispositivo informático) e leis
trabalhistas/estatutárias**, dependendo do contexto. **A responsabilidade é
inteiramente do operador.**

---

## Visão geral

Quatro componentes em execução simultânea no PC monitorado:

| Componente | Função |
|---|---|
| `TelegramListener.ps1` | Polling do bot, despachador de ~20 comandos, confirmação dupla para ações críticas, rate-limit |
| `MonitorInatividade.ps1` | Detecta inatividade (Win32 `GetLastInputInfo`), bloqueia, captura tela, monitora USB |
| `MonitorLogin.ps1` | Disparado em logon do usuário; muta áudio e notifica via Telegram |
| `MonitorFET.ps1` (opcional) | Monitora janela do FET via OCR (Windows.Media.Ocr) e alerta progresso/travamento/conclusão |

Os componentes conversam por arquivos JSON em `Config/` (canal de comandos
e de status). O bot Telegram é a interface principal; um **Controlador CLI
local** (`Scripts/Controlador.ps1`) está disponível para administrar offline.

---

## Requisitos

- **Sistema operacional:** Windows 10 ou 11 (testado em Windows 11 Home).
- **PowerShell:** 5.1 (vem com o Windows) ou 7+.
- **.NET Framework:** 4.7.2+ (geralmente já instalado).
- **OCR UWP** (opcional, só para o `MonitorFET`): pacote de idioma português
  instalado pelo Windows (`Configurações → Hora e idioma → Idioma → Português → Opções → Reconhecimento de fala/OCR`).
- **Python 3.10+** (apenas se você for **rebuildar** o instalador).
- **Bot do Telegram:** veja a seção [Criando o bot no Telegram](#criando-o-bot-no-telegram) abaixo.

---

## Criando o bot no Telegram

Você precisa de duas coisas antes de instalar: o **token do bot** e o seu **User ID numérico**.

### Passo 1 — Criar o bot

1. Abra o Telegram e procure por **[@BotFather](https://t.me/BotFather)** (é o bot oficial para criar bots).
2. Envie `/start` e depois `/newbot`.
3. O BotFather pergunta o **nome** do bot (qualquer texto, ex.: "Vigia do PC do Joãozinho").
4. Pergunta o **username** — deve ser único no Telegram e **terminar em `bot`** (ex.: `vigia_joaozinho_bot`).
5. Resposta final inclui uma linha tipo:
   ```
   Use this token to access the HTTP API:
   1234567890:AAHwEXemploTokenSinteticoNaoUtilizavel0123
   ```
   Esse é o seu **token**. Guarde — ele é segredo (quem tem o token controla o bot).

### Passo 2 — Descobrir seu User ID

1. Procure por **[@userinfobot](https://t.me/userinfobot)** no Telegram.
2. Envie `/start`.
3. Ele responde com seus dados, incluindo:
   ```
   Id: 1697670772
   ```
   Esse número é o seu **User ID**. Só você (com esse ID) poderá controlar o bot.

### Passo 3 — Iniciar conversa com o seu novo bot

Antes do bot conseguir te mandar mensagens, **você precisa enviar `/start` para o seu próprio bot** pelo menos uma vez. Sem isso, o Telegram bloqueia mensagens automáticas.

Pronto — você tem o token e o User ID. Use no instalador.

---

## Instalação

### Opção A — Instalador empacotado (recomendada)

1. Baixe `SegurancaPC_Installer.exe` na seção *Releases* deste repositório.
2. Execute **como Administrador** (botão direito → Executar como administrador).
3. Responda às perguntas:
   - Diretório (padrão `C:\SegurancaPC`).
   - Nome do PC para identificar nas notificações.
   - Token do bot Telegram.
   - User ID autorizado.
   - Minutos de inatividade para bloquear (padrão 5).
   - Funcionalidades opcionais (screenshot, USB, auto-bloqueio USB).
4. Ao final, o instalador cria a tarefa agendada `SegurancaPC_AutoStart`
   (privilégio elevado, gatilho ON LOGON).

### Opção B — Instalação manual a partir do código-fonte

```powershell
# 1. Clonar
git clone https://github.com/diegocamara89/PCGuardian.git C:\SegurancaPC
cd C:\SegurancaPC

# 2. Copiar template de configuração e preencher
Copy-Item Config\settings.example.json Config\settings.json
notepad Config\settings.json   # preencher BotToken, UserId, PCName

# 3. Iniciar manualmente
.\iniciar_sistema.bat

# 4. (opcional) Criar tarefa agendada para iniciar no logon
schtasks /Create /F /SC ONLOGON /RL HIGHEST /TN SegurancaPC_AutoStart `
  /TR '"C:\SegurancaPC\iniciar_sistema.bat"'
```

### Opção C — Rebuildar o instalador

```powershell
cd C:\SegurancaPC\InstallerPackage
pip install pyinstaller
pyinstaller SegurancaPC_Installer.spec
# saída: dist\SegurancaPC_Installer.exe
```

---

## Se o Windows bloquear o instalador

O `SegurancaPC_Installer.exe` é gerado pelo PyInstaller e **não tem certificado
de assinatura de código** (assinatura custa centenas de dólares por ano).
Isso é normal em software open source e leva o Windows e alguns antivírus a
exibir alertas. Não é vírus — você pode verificar tudo lendo o código-fonte
neste repositório.

### "O Windows protegeu seu PC" (SmartScreen)

Ao executar o `.exe`, você vai ver uma tela azul:

> Windows protegeu seu PC
> O Microsoft Defender SmartScreen impediu a inicialização de um aplicativo
> não reconhecido.

**Como prosseguir:**

1. Clique em **"Mais informações"** (texto pequeno).
2. Aparece um botão **"Executar mesmo assim"** — clique nele.
3. Em seguida o UAC vai pedir confirmação de Administrador — confirme.

### Antivírus marcou como "trojan" ou "PUA"

Falso positivo comum com binários PyInstaller. Caminhos:

- **Windows Defender:** abra "Segurança do Windows" → "Proteção contra vírus e ameaças" → "Histórico de proteção" → encontre o item → "Permitir".
- **Outros antivírus:** adicione `C:\SegurancaPC\` à lista de exclusões.

Se você não confia no `.exe`, use a **Opção B (instalação manual)** acima —
ela só usa PowerShell, sem binário compilado.

---

## Verificando a instalação

Após o instalador terminar (ou rodar `iniciar_sistema.bat`), confirme passo a passo:

### 1. Os processos estão rodando

```powershell
Get-CimInstance Win32_Process | Where-Object {
  $_.CommandLine -match 'SegurancaPC\\Scripts\\(TelegramListener|MonitorInatividade|MonitorFET)\.ps1'
} | Select-Object ProcessId, @{N='Script';E={if($_.CommandLine -match '\\([^\\]+\.ps1)'){$Matches[1]}}}
```

Você deve ver **3 linhas** — uma para cada script. Se aparecer 0, abra um
terminal PowerShell **como Administrador** e rode `C:\SegurancaPC\iniciar_sistema.bat`.

### 2. O bot responde

No Telegram, com sua conta autorizada, envie `/help` para o seu bot. Resposta esperada (resumida):

```
PC SECURITY v6.6 + FET MONITOR
Sistema: <PCName>

COMANDOS DISPONIVEIS:
/help - Exibir este menu
/bloquear - Bloquear PC + mute
...
```

Se não chegar resposta em ~10s:

- **Você enviou `/start` ao seu próprio bot pelo menos uma vez?** (passo 3 acima)
- **O `UserId` em `Config/settings.json` bate com o seu real?** (use `@userinfobot` de novo)
- **O `BotToken` está correto?** Verifique no `@BotFather` → `/mybots`.

### 3. Status em tempo real

Envie `/status` ao bot. Resposta esperada:

```
STATUS DO SISTEMA
PC: <PCName>
Status: active
Ultima atividade: <horario>
Tempo inativo: 0 min
Monitoramento: True
```

### 4. Controlador CLI local (sem Telegram)

Em qualquer momento, rode `controlador.bat` na pasta de instalação. Aparece
um menu numérico com 15 ações (status, screenshot, mute, pausar, etc.). Útil
para diagnóstico quando o Telegram não está disponível.

### 5. Verificar tarefa agendada

```powershell
schtasks /Query /TN SegurancaPC_AutoStart /V /FO LIST
```

Deve mostrar "Estado: Pronto" e "Logon Type: Interactive Token".

---

## Comandos do bot

Envie as mensagens abaixo para o seu bot privado, com a conta autorizada.

### Controle imediato
| Comando | Ação |
|---|---|
| `/help` | Lista todos os comandos |
| `/bloquear` | Bloqueia o PC e muta o áudio |
| `/screenshot` | Captura o monitor principal e envia (JPEG Q95) |
| `/screenshotall` | Captura **todos** os monitores e envia |
| `/status` | Resumo do estado (inatividade, pausa, bloqueio) |
| `/logs` | Últimas 5 entradas do log de comandos |
| `/debug` | Diagnóstico do listener (versão, offset, etc.) |
| `/usb` | Lista dispositivos USB conectados |
| `/processos` | Top 5 processos por CPU |

### Pausar e retomar
| Comando | Ação |
|---|---|
| `/pausar` | Suspende o bloqueio por inatividade por 30 min |
| `/extender` | +30 min na pausa atual |
| `/retomar` | Reativa o monitoramento |

### Áudio
| Comando | Ação |
|---|---|
| `/mute`, `/unmute`, `/toggle` | Alternam o estado de mute (Windows usa apenas toggle) |
| `/audio` | Status (informativo; não é possível ler o estado real) |

### Monitor FET (OCR)
| Comando | Ação |
|---|---|
| `/monitorfet_on` / `/monitorfet_off` | Ativa/desativa |
| `/fetstatus` | Progresso atual |

### Comandos críticos (exigem confirmação dupla em 30s)
| Comando | Ação |
|---|---|
| `/desligar` | Desliga o PC após 30s (use `/cancelar` para abortar) |
| `/reiniciar` | Reinicia após 30s |
| `/desativar` | Encerra os processos do bot **temporariamente** (volta após reboot) |
| `/cancelar` | Aborta qualquer desligamento/reinício pendente |

---

## Estrutura do repositório

```
SegurancaPC/
├── Scripts/
│   ├── TelegramListener.ps1     # Bot principal
│   ├── MonitorInatividade.ps1   # Inatividade + screenshot + USB
│   ├── MonitorLogin.ps1         # Notificação de logon
│   ├── MonitorFET.ps1           # Monitor OCR (opcional)
│   └── Controlador.ps1          # Menu CLI local
├── Config/
│   ├── settings.example.json    # Template (versionado)
│   ├── settings.json            # Real (NÃO versionado)
│   └── suspicious_processes.json
├── Screenshots/                 # Saída (vazio no repo, .gitkeep)
├── InstallerPackage/
│   ├── installer_main.py
│   ├── SegurancaPC_Installer.spec
│   └── SegurancaPC/             # Template bundled no .exe
├── iniciar_sistema.bat
├── reiniciar_sistema.bat
├── README.md
├── LICENSE
├── CHANGELOG.md
└── .gitignore
```

---

## Configuração (`Config/settings.json`)

| Chave | Tipo | Padrão | Descrição |
|---|---|---|---|
| `BotToken` | string | — | Token do bot Telegram |
| `UserId` | string (numérico) | — | ID Telegram do único usuário autorizado |
| `PCName` | string | — | Identificador exibido nas notificações |
| `InactivityMin` | int | 5 | Minutos de inatividade até bloquear |
| `WarningMin` | int | 1 | Minutos de antecedência do aviso |
| `ScreenshotOnBlock` | bool | true | Captura tela antes de bloquear por inatividade |
| `USBMonitoring` | bool | true | Alerta quando USB é conectado |
| `AutoBlockOnUSB` | bool | false | Bloqueia automaticamente em novo USB |
| `ProcessMonitoring` | bool | false | **Não implementado** — flag legada |
| `FetCheckIntervalSeconds` | int | 300 | Intervalo do MonitorFET |

---

## Troubleshooting

| Sintoma | Diagnóstico |
|---|---|
| Bot não responde | Veja se há processo do `TelegramListener.ps1` rodando: `Get-CimInstance Win32_Process \| Where-Object { $_.CommandLine -match 'TelegramListener' }` |
| "Outra instância detectada (lock em uso)" no log | Mate o processo antigo ou apague `Config/telegram_listener.lock` se o listener morreu sem liberar |
| Token inválido | Use [@BotFather](https://t.me/BotFather) e o comando `/mybots` para checar o token |
| Comando enviado por outra pessoa | O `UserId` em `settings.json` precisa bater com o seu numérico |
| Logs gigantescos em `Config/debug.log` | Rotação ainda não é automática (issue aberta); apague manualmente quando passar de ~50 MB |
| OCR do FET não funciona | Confirme o idioma instalado: `Get-WinUserLanguageList` deve incluir `pt-BR` |

---

## Segurança

### Garantias atuais
- O token do bot fica em `settings.json` em **texto plano** — esse arquivo
  está no `.gitignore` e nunca deve ser commitado nem compartilhado.
- O sistema verifica o `UserId` de cada mensagem; comandos de qualquer outro
  remetente são apenas logados e ignorados.
- Comandos de impacto irreversível (`/desligar`, `/reiniciar`, `/desativar`)
  exigem confirmação dupla em até 30s.
- Há rate-limit de 2s entre comandos do mesmo usuário.

### Limitações conhecidas (hardening recomendado em produção)
- **Permissões do diretório de instalação**: como a tarefa agendada roda com
  `/RL HIGHEST` (privilégio elevado no logon), qualquer processo local que
  consiga sobrescrever os `.ps1` em `Scripts/` ganha execução elevada na
  próxima inicialização. **Recomendação**: restrinja a ACL de
  `C:\SegurancaPC\Scripts` para somente leitura por `Users` e gravação só
  por `Administrators` (use `icacls` ou a aba "Segurança" do Explorer).
- **IPC local sem autenticação**: os arquivos em `Config/` (`monitor_control.json`,
  `fet_control.json`) são lidos sem assinatura. Um processo local que
  consiga escrever em `Config/` pode pausar, parar ou disparar screenshots.
  Mitigação: restringir ACL de `Config/` à conta que roda os monitores.
- **Token em texto plano**: o token fica em `settings.json` sem proteção
  DPAPI/Credential Manager. Quem tem leitura do arquivo tem o token. ACL
  restrita em `Config/settings.json` é a contramedida imediata.

Esses três itens estão no roadmap (`docs/` do projeto).

---

## Roadmap

- [ ] Rotação automática de logs (truncar quando passar do limite).
- [ ] Suporte a múltiplos usuários autorizados (lista de IDs).
- [ ] Armazenar token via Windows Credential Manager / DPAPI em vez de texto plano.
- [ ] Testes Pester para os scripts PowerShell.
- [ ] GitHub Actions com PSScriptAnalyzer.
- [ ] Documentação ampliada em `docs/`.

---

## Contribuindo

Pull requests bem-vindos. Antes de abrir:

1. Rode `PSScriptAnalyzer` nos `.ps1` que tocar.
2. Atualize o `CHANGELOG.md` na seção "Não lançado".
3. Não inclua arquivos de `Config/` (exceto `settings.example.json`),
   `Screenshots/`, `InstallerPackage/build/` ou `InstallerPackage/dist/`.
4. Não cole tokens reais nem User IDs reais em commits, exemplos ou issues.

---

## Licença

MIT — veja [LICENSE](LICENSE).
