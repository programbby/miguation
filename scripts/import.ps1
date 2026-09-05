param([string]$Source)

$ErrorActionPreference = "Continue"

function Write-Step($msg) { Write-Host "  >> $msg" -ForegroundColor Cyan }
function Write-OK($msg)   { Write-Host "  OK $msg" -ForegroundColor Green }
function Write-Skip($msg) { Write-Host "  -- $msg" -ForegroundColor Yellow }
function Write-Fail($msg) { Write-Host "  !! $msg" -ForegroundColor Red }

# ── Vérification admin ───────────────────────────────────────────────────────
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole('Administrators')) {
    Write-Fail "Lance ce script en tant qu'Administrateur."
    pause; exit 1
}

Write-Host ""
Write-Host "  Source : $Source" -ForegroundColor White

if (!(Test-Path $Source)) {
    Write-Fail "Dossier introuvable : $Source"
    pause; exit 1
}

# ── Navigateurs ouverts ──────────────────────────────────────────────────────
$browsersOuverts = @("chrome","firefox","msedge","brave") | Where-Object { Get-Process $_ -ErrorAction SilentlyContinue }
if ($browsersOuverts) {
    Write-Host "  ATTENTION : ferme ces navigateurs avant de continuer :" -ForegroundColor Yellow
    $browsersOuverts | ForEach-Object { Write-Host "    - $_" -ForegroundColor Yellow }
    $rep = Read-Host "  Continuer quand même ? (o/n)"
    if ($rep -ne 'o') { exit 0 }
}

# ── Fichiers utilisateur ──────────────────────────────────────────────────────
Write-Step "Restauration des fichiers..."

$exclusions = @("node_modules",".venv","__pycache__",".cache",".git","dist","build",".next","vendor")

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
        robocopy $chemin $d.dst /E /COPY:DAT /R:1 /W:0 /NP /NFL /NDL /NJH /NJS /XD $exclusions | Out-Null
        if ($LASTEXITCODE -gt 7) {
            Write-Fail "$($d.src) - restauration incomplète (code $LASTEXITCODE)"
        } else {
            Write-OK "$($d.src) restauré"
        }
    } else {
        Write-Skip "$($d.src) absent de la sauvegarde"
    }
}

# ── Navigateurs ───────────────────────────────────────────────────────────────
Write-Step "Restauration des navigateurs..."

$browsers = @(
    @{ nom = "Chrome"; profil = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default" },
    @{ nom = "Edge";   profil = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default" },
    @{ nom = "Brave";  profil = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default" }
)

foreach ($b in $browsers) {
    $bk = Join-Path $Source "navigateurs\$($b.nom)\Bookmarks"
    if (Test-Path $bk) {
        if (Test-Path $b.profil) {
            Copy-Item $bk (Join-Path $b.profil "Bookmarks") -Force
            Write-OK "$($b.nom) - marque-pages restaurés (redémarre le navigateur)"
        } else {
            Write-Skip "$($b.nom) - pas installé sur ce PC"
        }
    }
    $extCsv = Join-Path $Source "navigateurs\$($b.nom)\extensions.csv"
    if (Test-Path $extCsv) {
        Write-Host ""
        Write-Host "  Extensions $($b.nom) à réinstaller :" -ForegroundColor Yellow
        Import-Csv $extCsv | ForEach-Object { Write-Host "    - $($_.Nom)" -ForegroundColor Yellow }
    }
}

# Firefox
$ffSrc = Join-Path $Source "navigateurs\Firefox\Profiles"
$ffIni = Join-Path $Source "navigateurs\Firefox\profiles.ini"
$ffDst = "$env:APPDATA\Mozilla\Firefox"
if (Test-Path $ffSrc) {
    New-Item -ItemType Directory -Force -Path "$ffDst\Profiles" | Out-Null
    robocopy $ffSrc "$ffDst\Profiles" /E /COPY:DAT /R:1 /W:0 /NP /NFL /NDL /NJH /NJS | Out-Null
    if (Test-Path $ffIni) {
        Copy-Item $ffIni "$ffDst\profiles.ini" -Force
    }
    Write-OK "Firefox - profil restauré"
}

# ── Logiciels ─────────────────────────────────────────────────────────────────
Write-Step "Réinstallation des logiciels..."

$wingetFile = Join-Path $Source "logiciels\winget.json"
if (Test-Path $wingetFile) {
    winget import -i $wingetFile --accept-package-agreements --accept-source-agreements --ignore-unavailable --ignore-versions 2>$null
    Write-OK "winget - logiciels réinstallés"
} else {
    Write-Skip "winget.json absent"
}

$csvFile = Join-Path $Source "logiciels\liste_complete.csv"
if (Test-Path $csvFile) {
    Write-Skip "Liste complète disponible : $csvFile"
}

# ── Variables d'environnement ─────────────────────────────────────────────────
Write-Step "Restauration des variables d'environnement..."

$protegees = @("PATH","PATHEXT","TEMP","TMP","USERPROFILE","APPDATA","LOCALAPPDATA",
               "PROGRAMFILES","PROGRAMFILES(X86)","WINDIR","SYSTEMROOT","COMSPEC","USERNAME")

$envFile = Join-Path $Source "env_variables.json"
if (Test-Path $envFile) {
    try {
        $vars = Get-Content $envFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        $count = 0
        $vars.PSObject.Properties | ForEach-Object {
            if ($protegees -notcontains $_.Name.ToUpper()) {
                [System.Environment]::SetEnvironmentVariable($_.Name, $_.Value, "User")
                $count++
            }
        }
        Write-OK "$count variables restaurées ($($protegees.Count) variables système protégées)"
    } catch {
        Write-Fail "Fichier de variables corrompu, ignoré."
    }
} else {
    Write-Skip "Fichier de variables absent"
}

# ── Rapport ───────────────────────────────────────────────────────────────────
$rapportFile = Join-Path $Source "RAPPORT.txt"
if (Test-Path $rapportFile) {
    Write-Host ""
    Write-Host "  ======== ACTIONS MANUELLES ========" -ForegroundColor Yellow
    Get-Content $rapportFile | Where-Object { $_ -match "SECRETS|NAVIGATEUR|LICENCE" } | ForEach-Object {
        Write-Host "  $_" -ForegroundColor Yellow
    }
    Write-Host "  ====================================" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "  ========================================" -ForegroundColor Green
Write-Host "  IMPORTATION TERMINEE" -ForegroundColor Green
Write-Host "  Redemarre ton PC pour que tout soit actif" -ForegroundColor Green
Write-Host "  ========================================" -ForegroundColor Green
Write-Host ""
