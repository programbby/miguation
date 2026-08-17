$ErrorActionPreference = "SilentlyContinue"

function Write-Step($msg) { Write-Host "  >> $msg" -ForegroundColor Cyan }
function Write-OK($msg)   { Write-Host "  OK $msg" -ForegroundColor Green }

# 1. Exporter d'abord
Write-Step "Exportation en cours..."
$exportDossier = & "$PSScriptRoot\export.ps1" -Destination "$env:TEMP\migratix-wifi"

if (!$exportDossier -or !(Test-Path $exportDossier)) {
    $exportDossier = (Get-ChildItem "$env:TEMP\migratix-wifi" | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
}

# 2. Créer le partage réseau
$nomPartage = "migratix-transfert"
net share $nomPartage /delete 2>$null | Out-Null
net share "$nomPartage=$exportDossier" /GRANT:Everyone,READ | Out-Null
Write-OK "Dossier partage sur le reseau"

# 3. Afficher l'IP locale
$ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notlike "*Loopback*" -and $_.IPAddress -notlike "169.*" } | Select-Object -First 1).IPAddress

Write-Host ""
Write-Host "  ╔══════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "  ║  Sur le NOUVEAU PC, lance :                  ║" -ForegroundColor Green
Write-Host "  ║  transfert-wifi-client.bat                   ║" -ForegroundColor Green
Write-Host "  ║                                              ║" -ForegroundColor Green
Write-Host "  ║  Quand il demande l'IP, entre :              ║" -ForegroundColor Green
Write-Host "  ║  $ip" -ForegroundColor Yellow
Write-Host "  ╚══════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "  Laisse cette fenetre ouverte pendant le transfert." -ForegroundColor White
Write-Host "  Appuie sur Entree quand le nouveau PC a termine." -ForegroundColor White
Read-Host

# 4. Supprimer le partage
net share $nomPartage /delete 2>$null | Out-Null
Write-OK "Partage ferme. Transfert termine."
