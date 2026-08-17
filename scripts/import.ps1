param([string]$Source)

$ErrorActionPreference = "SilentlyContinue"

function Write-Step($msg) { Write-Host "  >> $msg" -ForegroundColor Cyan }
function Write-OK($msg)   { Write-Host "  OK $msg" -ForegroundColor Green }
function Write-Skip($msg) { Write-Host "  -- $msg" -ForegroundColor Yellow }

Write-Host ""
Write-Host "  Source : $Source" -ForegroundColor White

if (!(Test-Path $Source)) {
    Write-Host "  ERREUR : dossier introuvable." -ForegroundColor Red
    exit 1
}

# ── 1. Fichiers utilisateur ──────────────────────────────────────────────────
Write-Step "Restauration des fichiers..."

$dossiers = @(
    @{ src = "Documents";       dst = "$env:USERPROFILE\Documents" },
    @{ src = "Bureau";          dst = "$env:USERPROFILE\Desktop" },
    @{ src = "Images";          dst = "$env:USERPROFILE\Pictures" },
    @{ src = "Videos";          dst = "$env:USERPROFILE\Videos" },
    @{ src = "Musique";         dst = "$env:USERPROFILE\Music" },
    @{ src = "Telechargements"; dst = "$env:USERPROFILE\Downloads" },
    @{ src = "projets";         dst = "$env:USERPROFILE\projets" },
    @{ src = ".claude";         dst = "$env:USERPROFILE\.claude" }
)

foreach ($d in $dossiers) {
    $chemin = Join-Path $Source "fichiers\$($d.src)"
    if (Test-Path $chemin) {
        New-Item -ItemType Directory -Force -Path $d.dst | Out-Null
        robocopy $chemin $d.dst /E /COPY:DAT /R:1 /W:0 /NP /NFL /NDL /NJH /NJS | Out-Null
        Write-OK "$($d.src) restaure"
    } else {
        Write-Skip "$($d.src) absent, ignore"
    }
}

# ── 2. Navigateurs ───────────────────────────────────────────────────────────
Write-Step "Restauration des navigateurs..."

$browsers = @(
    @{ nom = "Chrome"; profil = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default" },
    @{ nom = "Edge";   profil = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default" },
    @{ nom = "Brave";  profil = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default" }
)

foreach ($b in $browsers) {
    $src = Join-Path $Source "navigateurs\$($b.nom)\Bookmarks"
    if (Test-Path $src) {
        if (Test-Path $b.profil) {
            Copy-Item $src (Join-Path $b.profil "Bookmarks") -Force
            Write-OK "$($b.nom) — marque-pages restaures (redemarrer le navigateur)"
        } else {
            Write-Skip "$($b.nom) pas installe sur ce PC — installe-le d'abord"
        }
    }
    # Afficher la liste des extensions
    $extCsv = Join-Path $Source "navigateurs\$($b.nom)\extensions.csv"
    if (Test-Path $extCsv) {
        Write-Host ""
        Write-Host "  Extensions $($b.nom) a reinstaller manuellement :" -ForegroundColor Yellow
        Import-Csv $extCsv | ForEach-Object { Write-Host "    - $($_.Nom)" -ForegroundColor Yellow }
    }
}

# Firefox
$ffSrc = Join-Path $Source "navigateurs\Firefox"
$ffDst = "$env:APPDATA\Mozilla\Firefox\Profiles"
if (Test-Path $ffSrc) {
    New-Item -ItemType Directory -Force -Path $ffDst | Out-Null
    robocopy $ffSrc $ffDst /E /COPY:DAT /R:1 /W:0 /NP /NFL /NDL /NJH /NJS | Out-Null
    Write-OK "Firefox — profil restaure"
}

# ── 3. Logiciels ─────────────────────────────────────────────────────────────
Write-Step "Reinstallation des logiciels..."

$wingetFile = Join-Path $Source "logiciels\winget.json"
if (Test-Path $wingetFile) {
    winget import -i $wingetFile --accept-package-agreements --accept-source-agreements 2>$null
    Write-OK "Logiciels reinstalles via winget"
} else {
    Write-Skip "winget.json absent"
}

$csvFile = Join-Path $Source "logiciels\liste_complete.csv"
if (Test-Path $csvFile) {
    Write-Skip "Liste complete : $csvFile — installe manuellement ce qui manque"
}

# ── 4. Variables d'environnement ─────────────────────────────────────────────
Write-Step "Restauration des variables d'environnement..."
$envFile = Join-Path $Source "env_variables.json"
if (Test-Path $envFile) {
    $vars = Get-Content $envFile | ConvertFrom-Json
    $vars.PSObject.Properties | ForEach-Object {
        [System.Environment]::SetEnvironmentVariable($_.Name, $_.Value, "User")
    }
    Write-OK "Variables restaurees"
}

# ── 5. Rapport ────────────────────────────────────────────────────────────────
$rapportFile = Join-Path $Source "RAPPORT.txt"
if (Test-Path $rapportFile) {
    Write-Host ""
    Write-Host "  ════════ ACTIONS MANUELLES REQUISES ════════" -ForegroundColor Yellow
    Get-Content $rapportFile | Where-Object { $_ -match "LICENCE|NAVIGATEUR" } | ForEach-Object {
        Write-Host "  $_" -ForegroundColor Yellow
    }
    Write-Host "  ════════════════════════════════════════════" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "  ════════════════════════════════════════" -ForegroundColor Green
Write-Host "  IMPORTATION TERMINEE" -ForegroundColor Green
Write-Host "  Redémarre ton PC pour que tout soit actif" -ForegroundColor Green
Write-Host "  ════════════════════════════════════════" -ForegroundColor Green
Write-Host ""
