$ErrorActionPreference = "Continue"

function Write-Step($msg) { Write-Host "  >> $msg" -ForegroundColor Cyan }
function Write-OK($msg)   { Write-Host "  OK $msg" -ForegroundColor Green }
function Write-Fail($msg) { Write-Host "  !! $msg" -ForegroundColor Red }

Write-Host ""
Write-Host "  Connecte-toi au WiFi 'Miguation' avant de continuer." -ForegroundColor Yellow
Write-Host "  (Le mot de passe WiFi est affiché sur l'ancien PC)" -ForegroundColor Yellow
Write-Host ""
Read-Host "  Appuie sur Entree quand c'est fait"

$mdpPartage = Read-Host "  Entre le mot de passe du partage (affiché sur l'ancien PC)"

# IP fixe du hotspot Windows
$ip = "192.168.137.1"
$partage = "\\$ip\mgx-share"
$lecteur = "Z:"

Write-Step "Connexion au partage (peut prendre 10-15 secondes)..."

# Connexion avec timeout explicite
$job = Start-Job { param($p,$u,$pw) net use $p $pw /user:$u 2>&1 } -ArgumentList $partage,"mgx-tmp",$mdpPartage
$ok = Wait-Job $job -Timeout 20
Remove-Job $job -Force

if (-not $ok -or -not (Test-Path $partage)) {
    Write-Fail "Impossible de joindre l'ancien PC."
    Write-Host "  Vérifie que :" -ForegroundColor Yellow
    Write-Host "    - Tu es bien connecté au WiFi 'Miguation'" -ForegroundColor Yellow
    Write-Host "    - La fenêtre serveur est encore ouverte sur l'ancien PC" -ForegroundColor Yellow
    Write-Host "    - Le mot de passe du partage est correct" -ForegroundColor Yellow
    pause; exit 1
}

Write-OK "Connecté ! Lancement de l'importation..."
Write-Host ""

try {
    & "$PSScriptRoot\import.ps1" -Source $partage
} finally {
    net use $partage /delete 2>$null | Out-Null
    Write-Host "  Connexion au partage fermée." -ForegroundColor Gray
}
