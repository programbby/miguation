$ErrorActionPreference = "SilentlyContinue"

function Write-Step($msg) { Write-Host "  >> $msg" -ForegroundColor Cyan }
function Write-OK($msg)   { Write-Host "  OK $msg" -ForegroundColor Green }

Write-Host ""
Write-Host "  Assure-toi d'etre connecte au WiFi 'Migratix' avant de continuer." -ForegroundColor Yellow
Write-Host "  Appuie sur Entree quand c'est fait..."
Read-Host

# L'IP du hotspot Windows est toujours 192.168.137.1
$partage = "\\192.168.137.1\migratix-transfert"

Write-Step "Connexion a l'ancien PC..."

if (!(Test-Path $partage)) {
    Write-Host ""
    Write-Host "  ERREUR : impossible de joindre l'ancien PC." -ForegroundColor Red
    Write-Host "  Verifie que :" -ForegroundColor Yellow
    Write-Host "    - Tu es bien connecte au WiFi 'Migratix'" -ForegroundColor Yellow
    Write-Host "    - La fenetre serveur est encore ouverte sur l'ancien PC" -ForegroundColor Yellow
    exit 1
}

Write-OK "Connecte ! Lancement de l'importation..."
Write-Host ""

& "$PSScriptRoot\import.ps1" -Source $partage
