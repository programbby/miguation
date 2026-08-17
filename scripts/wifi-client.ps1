$ErrorActionPreference = "SilentlyContinue"

function Write-Step($msg) { Write-Host "  >> $msg" -ForegroundColor Cyan }
function Write-OK($msg)   { Write-Host "  OK $msg" -ForegroundColor Green }

Write-Host ""
$ip = Read-Host "  Entre l'IP affichee sur l'ancien PC"
$partage = "\\$ip\migratix-transfert"

Write-Step "Connexion a $partage ..."

if (!(Test-Path $partage)) {
    Write-Host "  ERREUR : impossible de joindre l'ancien PC." -ForegroundColor Red
    Write-Host "  Verifie que les deux PCs sont sur le meme WiFi" -ForegroundColor Yellow
    Write-Host "  et que la fenetre serveur est encore ouverte." -ForegroundColor Yellow
    exit 1
}

Write-OK "Connecte ! Lancement de l'importation..."
Write-Host ""

& "$PSScriptRoot\import.ps1" -Source $partage
