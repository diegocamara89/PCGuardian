# sync_bundle.ps1 - Copia Scripts/* e arquivos de root para InstallerPackage/SegurancaPC/
# Uso: powershell.exe -ExecutionPolicy Bypass -File tools\sync_bundle.ps1

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$src = Join-Path $repoRoot 'Scripts'
$dst = Join-Path $repoRoot 'InstallerPackage\SegurancaPC\Scripts'
$rootSrc = $repoRoot
$rootDst = Join-Path $repoRoot 'InstallerPackage\SegurancaPC'

# Scripts a copiar
$psFiles = @(
    'TelegramListener.ps1',
    'MonitorInatividade.ps1',
    'MonitorLogin.ps1',
    'MonitorFET.ps1',
    'Controlador.ps1',
    'Common.psm1'
)

$rootFiles = @(
    'iniciar_sistema.bat',
    'controlador.bat'
)

if (-not (Test-Path $dst)) { New-Item -ItemType Directory -Path $dst -Force | Out-Null }

Write-Host "=== Sincronizando bundle do installer ===" -ForegroundColor Cyan

foreach ($f in $psFiles) {
    $s = Join-Path $src $f
    $d = Join-Path $dst $f
    if (-not (Test-Path $s)) { Write-Host "[FALTA] $s" -ForegroundColor Red; continue }
    Copy-Item $s $d -Force
    Write-Host "[OK] $f" -ForegroundColor Green
}

foreach ($f in $rootFiles) {
    $s = Join-Path $rootSrc $f
    $d = Join-Path $rootDst $f
    if (-not (Test-Path $s)) { Write-Host "[FALTA] $s" -ForegroundColor Red; continue }
    Copy-Item $s $d -Force
    Write-Host "[OK] $f (root)" -ForegroundColor Green
}

Write-Host ""
Write-Host "=== Validando sintaxe ===" -ForegroundColor Cyan
$hasError = $false
foreach ($f in $psFiles) {
    $path = Join-Path $dst $f
    if (-not (Test-Path $path)) { continue }
    $errs = $null
    [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$errs) | Out-Null
    if ($errs.Count -eq 0) {
        Write-Host "[OK] $f" -ForegroundColor Green
    } else {
        Write-Host "[ERRO] $f - $($errs.Count) erros" -ForegroundColor Red
        $hasError = $true
    }
}

if ($hasError) { exit 1 }
Write-Host ""
Write-Host "Bundle sincronizado em: $dst" -ForegroundColor Cyan
Write-Host "Para rebuildar o .exe:" -ForegroundColor Yellow
Write-Host "  cd InstallerPackage; pyinstaller SegurancaPC_Installer.spec" -ForegroundColor Cyan
