$ErrorActionPreference = "SilentlyContinue"

function Write-Step($msg) { Write-Host "  >> $msg" -ForegroundColor Cyan }
function Write-OK($msg)   { Write-Host "  OK $msg" -ForegroundColor Green }
function Write-Fail($msg) { Write-Host "  !! $msg" -ForegroundColor Red }

# ── 1. Créer le hotspot ───────────────────────────────────────────────────────
$ssid = "Migratix"
$mdp  = "migratix" + (Get-Random -Minimum 1000 -Maximum 9999)

Write-Step "Creation du hotspot WiFi..."

netsh wlan set hostednetwork mode=allow ssid="$ssid" key="$mdp" 2>$null | Out-Null
$result = netsh wlan start hostednetwork 2>&1

if ($result -match "Le réseau hébergé a démarré|hosted network started") {
    Write-OK "Hotspot cree"
} else {
    Write-Fail "Impossible de creer le hotspot."
    Write-Host ""
    Write-Host "  Ton adaptateur WiFi ne supporte peut-etre pas cette fonction." -ForegroundColor Yellow
    Write-Host "  Utilise le mode WiFi normal a la place (transfert-wifi-serveur.bat)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Details : $result" -ForegroundColor DarkGray
    Read-Host "  Appuie sur Entree pour quitter"
    exit 1
}

# ── 2. Exporter ───────────────────────────────────────────────────────────────
Write-Step "Exportation en cours..."
$exportDossier = & "$PSScriptRoot\export.ps1" -Destination "$env:TEMP\migratix-wifi"

if (!$exportDossier -or !(Test-Path $exportDossier)) {
    $exportDossier = (Get-ChildItem "$env:TEMP\migratix-wifi" | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
}

# ── 3. Partager le dossier ────────────────────────────────────────────────────
$nomPartage = "migratix-transfert"
net share $nomPartage /delete 2>$null | Out-Null
net share "$nomPartage=$exportDossier" /GRANT:Everyone,READ | Out-Null

# ── 4. Instructions ───────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  ╔══════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "  ║  Sur le NOUVEAU PC :                             ║" -ForegroundColor Green
Write-Host "  ║                                                  ║" -ForegroundColor Green
Write-Host "  ║  1. Connecte-toi au WiFi :                       ║" -ForegroundColor Green
Write-Host "  ║     Nom      : $ssid" -ForegroundColor Yellow
Write-Host "  ║     Mot de passe : $mdp" -ForegroundColor Yellow
Write-Host "  ║                                                  ║" -ForegroundColor Green
Write-Host "  ║  2. Lance transfert-wifi-client.bat              ║" -ForegroundColor Green
Write-Host "  ║     (l'IP est automatique, pas besoin de la taper)║" -ForegroundColor Green
Write-Host "  ╚══════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "  Laisse cette fenetre ouverte pendant le transfert." -ForegroundColor White
Write-Host "  Appuie sur Entree quand le nouveau PC a termine." -ForegroundColor White
Read-Host

# ── 5. Nettoyage ──────────────────────────────────────────────────────────────
net share $nomPartage /delete 2>$null | Out-Null
netsh wlan stop hostednetwork 2>$null | Out-Null
Write-OK "Hotspot ferme. Transfert termine."
