param([string]$Source)

$ErrorActionPreference = "SilentlyContinue"

function Write-Step($msg) { Write-Host "  >> $msg" -ForegroundColor Cyan }
function Write-OK($msg)   { Write-Host "  OK $msg" -ForegroundColor Green }
function Write-Skip($msg) { Write-Host "  -- $msg" -ForegroundColor Yellow }

Write-Host ""
Write-Host "  Dossier source : $Source" -ForegroundColor White

if (!(Test-Path $Source)) {
    Write-Host "  ERREUR : dossier introuvable. Verifie le chemin." -ForegroundColor Red
    exit 1
}

# ── 1. Fichiers utilisateur ──────────────────────────────────────────────────
Write-Step "Restauration des fichiers personnels..."

$dossiers = @(
    @{ src = "Documents";      dst = "$env:USERPROFILE\Documents" },
    @{ src = "Bureau";         dst = "$env:USERPROFILE\Desktop" },
    @{ src = "Images";         dst = "$env:USERPROFILE\Pictures" },
    @{ src = "Videos";         dst = "$env:USERPROFILE\Videos" },
    @{ src = "Musique";        dst = "$env:USERPROFILE\Music" },
    @{ src = "Telechargements"; dst = "$env:USERPROFILE\Downloads" },
    @{ src = "projets";        dst = "$env:USERPROFILE\projets" },
    @{ src = ".claude";        dst = "$env:USERPROFILE\.claude" }
)

foreach ($d in $dossiers) {
    $chemin = Join-Path $Source "fichiers\$($d.src)"
    if (Test-Path $chemin) {
        Write-Step "  Restauration $($d.src)..."
        New-Item -ItemType Directory -Force -Path $d.dst | Out-Null
        robocopy $chemin $d.dst /E /COPY:DAT /R:1 /W:0 /NP /NFL /NDL /NJH /NJS | Out-Null
        Write-OK "$($d.src) restaure"
    } else {
        Write-Skip "$($d.src) absent de la sauvegarde, ignore"
    }
}

# ── 2. Logiciels ─────────────────────────────────────────────────────────────
Write-Step "Reinstallation des logiciels..."

$wingetFile = Join-Path $Source "logiciels\winget.json"
if (Test-Path $wingetFile) {
    Write-Step "  Installation via winget (peut prendre plusieurs minutes)..."
    winget import -i $wingetFile --accept-package-agreements --accept-source-agreements 2>$null
    Write-OK "Logiciels reinstalles via winget"
} else {
    Write-Skip "Fichier winget absent"
}

$csvFile = Join-Path $Source "logiciels\liste_complete.csv"
if (Test-Path $csvFile) {
    Write-OK "Liste complete disponible dans : $csvFile"
    Write-Skip "Installe manuellement ce qui manque en consultant ce fichier"
}

# ── 3. Variables d'environnement ─────────────────────────────────────────────
Write-Step "Restauration des variables d'environnement..."

$envFile = Join-Path $Source "env_variables.json"
if (Test-Path $envFile) {
    $vars = Get-Content $envFile | ConvertFrom-Json
    $vars.PSObject.Properties | ForEach-Object {
        [System.Environment]::SetEnvironmentVariable($_.Name, $_.Value, "User")
    }
    Write-OK "Variables restaurees"
} else {
    Write-Skip "Fichier de variables absent"
}

# ── 4. Rapport et licences ───────────────────────────────────────────────────
$rapportFile = Join-Path $Source "RAPPORT.txt"
if (Test-Path $rapportFile) {
    Write-Host ""
    Write-Host "  ════════ RAPPORT DE TON ANCIEN PC ════════" -ForegroundColor Yellow
    Get-Content $rapportFile | Where-Object { $_ -match "LICENCE|MANUEL" } | ForEach-Object {
        Write-Host "  $_" -ForegroundColor Yellow
    }
    Write-Host "  ══════════════════════════════════════════" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "  ════════════════════════════════════════" -ForegroundColor Green
Write-Host "  IMPORTATION TERMINEE" -ForegroundColor Green
Write-Host "  Redémarre ton PC pour que tout soit actif" -ForegroundColor Green
Write-Host "  Lis RAPPORT.txt pour les etapes manuelles" -ForegroundColor Green
Write-Host "  ════════════════════════════════════════" -ForegroundColor Green
Write-Host ""
