$ErrorActionPreference = "Continue"

function Write-Step($msg) { Write-Host "  >> $msg" -ForegroundColor Cyan }
function Write-OK($msg)   { Write-Host "  OK $msg" -ForegroundColor Green }
function Write-Fail($msg) { Write-Host "  !! $msg" -ForegroundColor Red }

Write-Host ""
Write-Host "  Connecte-toi au WiFi 'Miguation' avant de continuer." -ForegroundColor Yellow
Write-Host "  (Le mot de passe WiFi est affiche sur l'ancien PC)" -ForegroundColor Yellow
Write-Host ""
Read-Host "  Appuie sur Entree quand c'est fait"

$mdpPartage = Read-Host "  Entre le mot de passe du partage (affiche sur l'ancien PC)"

# IP du hotspot Windows (ICS et Mobile Hotspot)
$ips = @("192.168.137.1", "192.168.173.1", "192.168.2.1")
$tempUser = "mgx-tmp"
$nomPartage = "mgx-share"

$ipOK = $null
Write-Step "Recherche de l'ancien PC sur le reseau..."
foreach ($ip in $ips) {
    if (Test-Connection -ComputerName $ip -Count 1 -Quiet -ErrorAction SilentlyContinue) {
        $ipOK = $ip
        Write-OK "Trouve a $ip"
        break
    }
}

if (-not $ipOK) {
    Write-Fail "Aucun PC trouve sur les IP habituelles du hotspot."
    Write-Host "  Verifie que :" -ForegroundColor Yellow
    Write-Host "    - Tu es bien connecte au WiFi 'Miguation'" -ForegroundColor Yellow
    Write-Host "    - La fenetre serveur est encore ouverte sur l'ancien PC" -ForegroundColor Yellow
    pause; exit 1
}

$partage = "\\$ipOK\$nomPartage"

Write-Step "Connexion au partage..."

# Nettoyage d'une eventuelle connexion existante
net use $partage /delete 2>$null | Out-Null

# Authentification directe (pas dans un job - sinon ca ne persiste pas)
$connexion = net use $partage $mdpPartage /user:$tempUser 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Fail "Authentification refusee."
    Write-Host "  Message : $connexion" -ForegroundColor Yellow
    Write-Host "  Verifie le mot de passe du partage (celui affiche sur l'ancien PC)." -ForegroundColor Yellow
    pause; exit 1
}

# Verifier que l'acces marche
if (-not (Test-Path $partage)) {
    Write-Fail "Partage authentifie mais inaccessible."
    net use $partage /delete 2>$null | Out-Null
    pause; exit 1
}

Write-OK "Connecte ! Lancement de l'importation..."
Write-Host ""

try {
    & "$PSScriptRoot\import.ps1" -Source $partage
} finally {
    net use $partage /delete 2>$null | Out-Null
    Write-Host "  Connexion au partage fermee." -ForegroundColor Gray
}
