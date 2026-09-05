param([string]$Destination)

$ErrorActionPreference = "Continue"
$LOG = $null

function Write-Step($msg) { Write-Host "  >> $msg" -ForegroundColor Cyan }
function Write-OK($msg)   { Write-Host "  OK $msg" -ForegroundColor Green }
function Write-Skip($msg) { Write-Host "  -- $msg" -ForegroundColor Yellow }
function Write-Fail($msg) { Write-Host "  !! $msg" -ForegroundColor Red }
function Log($msg)        { if ($LOG) { "$(Get-Date -f 'HH:mm:ss') $msg" | Out-File $LOG -Append -Encoding UTF8 } }

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole('Administrators')) {
    Write-Fail "Lance ce script en tant qu'Administrateur."
    pause; exit 1
}

$date = Get-Date -Format "yyyy-MM-dd_HH-mm"
$export = Join-Path $Destination "miguation_$date"
New-Item -ItemType Directory -Force -Path $export | Out-Null
$LOG = Join-Path $export "miguation.log"
Log "=== EXPORTATION DEMARREE ==="

# Navigateurs ouverts
$browsersOuverts = @("chrome","firefox","msedge","brave") | Where-Object { Get-Process $_ -ErrorAction SilentlyContinue }
if ($browsersOuverts) {
    Write-Host ""
    Write-Host "  ATTENTION : ces navigateurs sont ouverts :" -ForegroundColor Yellow
    $browsersOuverts | ForEach-Object { Write-Host "    - $_" -ForegroundColor Yellow }
    Write-Host "  Ferme-les pour une copie complete des marque-pages." -ForegroundColor Yellow
    $rep = Read-Host "  Continuer quand meme ? (o/n)"
    if ($rep -ne 'o') { exit 0 }
}

# Espace disque
Write-Step "Verification de l'espace disque..."
$dossiersSources = @(
    "$env:USERPROFILE\Documents","$env:USERPROFILE\Desktop","$env:USERPROFILE\Pictures",
    "$env:USERPROFILE\Videos","$env:USERPROFILE\Music","$env:USERPROFILE\Downloads",
    "$env:USERPROFILE\projets","$env:USERPROFILE\.claude"
)
$tailleTotal = 0
foreach ($d in $dossiersSources) {
    if (Test-Path $d) {
        $tailleTotal += (Get-ChildItem $d -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
    }
}
$libre = (Get-PSDrive ($Destination.Substring(0,1)) -ErrorAction SilentlyContinue).Free
if ($libre -and $tailleTotal -gt $libre) {
    $manque = [math]::Round(($tailleTotal - $libre) / 1GB, 1)
    Write-Fail "Espace insuffisant sur la destination. Il manque environ $manque Go."
    Log "ERREUR espace disque insuffisant"
    pause; exit 1
}
Write-OK "Espace OK ($([math]::Round($tailleTotal/1GB,1)) Go a copier)"

# Fichiers utilisateur
Write-Step "Copie des fichiers personnels..."

$exclusions = @("node_modules",".venv","__pycache__",".cache",".git","dist","build",".next","vendor")

$dossiers = @(
    @{ src = "$env:USERPROFILE\Documents";  dst = "Documents" },
    @{ src = "$env:USERPROFILE\Desktop";    dst = "Bureau" },
    @{ src = "$env:USERPROFILE\Pictures";   dst = "Images" },
    @{ src = "$env:USERPROFILE\Videos";     dst = "Videos" },
    @{ src = "$env:USERPROFILE\Music";      dst = "Musique" },
    @{ src = "$env:USERPROFILE\Downloads";  dst = "Telechargements" },
    @{ src = "$env:USERPROFILE\projets";    dst = "projets" },
    @{ src = "$env:USERPROFILE\.claude";    dst = ".claude" }
)

foreach ($d in $dossiers) {
    if (Test-Path $d.src) {
        $cible = Join-Path $export "fichiers\$($d.dst)"
        New-Item -ItemType Directory -Force -Path $cible | Out-Null
        robocopy $d.src $cible /E /COPY:DAT /R:1 /W:0 /NP /NFL /NDL /NJH /NJS /XD $exclusions | Out-Null
        if ($LASTEXITCODE -gt 7) {
            Write-Fail "$($d.dst) - copie incomplete (code $LASTEXITCODE)"
            Log "ERREUR robocopy $($d.dst) code $LASTEXITCODE"
        } else {
            Write-OK "$($d.dst) copie"
            Log "OK $($d.dst)"
        }
    } else {
        Write-Skip "$($d.dst) introuvable"
    }
}

# Navigateurs
Write-Step "Migration des navigateurs..."

$browsers = @(
    @{ nom = "Chrome"; profil = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default" },
    @{ nom = "Edge";   profil = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default" },
    @{ nom = "Brave";  profil = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default" }
)

foreach ($b in $browsers) {
    if (Test-Path $b.profil) {
        $dst = Join-Path $export "navigateurs\$($b.nom)"
        New-Item -ItemType Directory -Force -Path $dst | Out-Null

        $bookmarks = Join-Path $b.profil "Bookmarks"
        if (Test-Path $bookmarks) {
            Copy-Item $bookmarks (Join-Path $dst "Bookmarks") -Force
            Write-OK "$($b.nom) - marque-pages copies"
            Log "OK $($b.nom) marque-pages"
        }

        $extPath = Join-Path $b.profil "Extensions"
        if (Test-Path $extPath) {
            $exts = Get-ChildItem $extPath -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                $extId = $_.Name
                $nom = $extId
                $versionDirs = Get-ChildItem $_.FullName -Directory -ErrorAction SilentlyContinue
                if ($versionDirs) {
                    $manifestPath = Join-Path $versionDirs[0].FullName "manifest.json"
                    if (Test-Path $manifestPath) {
                        try {
                            $json = Get-Content $manifestPath -Raw | ConvertFrom-Json -ErrorAction Stop
                            if ($json.name -and $json.name -notmatch '^__MSG_') { $nom = $json.name }
                        } catch {}
                    }
                }
                [PSCustomObject]@{ ID = $extId; Nom = $nom }
            }
            $exts | Export-Csv (Join-Path $dst "extensions.csv") -NoTypeInformation -Encoding UTF8
            Write-OK "$($b.nom) - $($exts.Count) extensions listees"
        }
    }
}

# Firefox
$ffBase = "$env:APPDATA\Mozilla\Firefox"
$ffProfiles = "$ffBase\Profiles"
if (Test-Path $ffProfiles) {
    $dst = Join-Path $export "navigateurs\Firefox"
    New-Item -ItemType Directory -Force -Path $dst | Out-Null
    robocopy $ffProfiles "$dst\Profiles" /E /COPY:DAT /R:1 /W:0 /NP /NFL /NDL /NJH /NJS | Out-Null
    $profilesIni = "$ffBase\profiles.ini"
    if (Test-Path $profilesIni) {
        Copy-Item $profilesIni "$dst\profiles.ini" -Force
    }
    Write-OK "Firefox - profil complet copie"
    Log "OK Firefox"
}

# Logiciels
Write-Step "Export de la liste des logiciels..."
New-Item -ItemType Directory -Force -Path (Join-Path $export "logiciels") | Out-Null

try {
    winget export -o (Join-Path $export "logiciels\winget.json") --accept-source-agreements 2>$null
    Write-OK "winget - liste exportee"
    Log "OK winget export"
} catch {
    Write-Skip "winget non disponible"
    Log "SKIP winget non disponible"
}

$logiciels = @()
"HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
"HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
"HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*" | ForEach-Object {
    Get-ItemProperty $_ -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName } | ForEach-Object {
        $logiciels += [PSCustomObject]@{ Nom = $_.DisplayName; Version = $_.DisplayVersion; Editeur = $_.Publisher }
    }
}
$logiciels | Sort-Object Nom -Unique | Export-Csv (Join-Path $export "logiciels\liste_complete.csv") -NoTypeInformation -Encoding UTF8
Write-OK "Registre - $($logiciels.Count) logiciels listes"

# Variables d'environnement
Write-Step "Export des variables d'environnement..."

$secretPattern = 'KEY|SECRET|TOKEN|PASSWORD|PASS|PASSWD|CREDENTIAL|API|AUTH|PRIVATE|OAUTH'
$vars = [System.Environment]::GetEnvironmentVariables("User")
$varsPropres = @{}
$secretsTrouves = @()

foreach ($key in $vars.Keys) {
    if ($key -match $secretPattern) {
        $secretsTrouves += $key
    } else {
        $varsPropres[$key] = $vars[$key]
    }
}

$varsPropres | ConvertTo-Json | Out-File (Join-Path $export "env_variables.json") -Encoding UTF8

if ($secretsTrouves.Count -gt 0) {
    Write-Host ""
    Write-Host "  SECRETS DETECTES - non copies (pour ta securite) :" -ForegroundColor Yellow
    $secretsTrouves | ForEach-Object { Write-Host "    - $_" -ForegroundColor Yellow }
    Write-Host "  Reentre-les manuellement sur le nouveau PC." -ForegroundColor Yellow
    Log "SECRETS IGNORES : $($secretsTrouves -join ', ')"
}
Write-OK "$($varsPropres.Count) variables exportees, $($secretsTrouves.Count) secrets ignores"

# Rapport
$rapport = @(
    "=== MIGUATION - RAPPORT ==="
    "Date : $date | Machine : $env:COMPUTERNAME"
    ""
)
if ($secretsTrouves.Count -gt 0) {
    $rapport += "SECRETS NON COPIES (a reentrer manuellement) :"
    $secretsTrouves | ForEach-Object { $rapport += "  - $_" }
    $rapport += ""
}
$rapport += "NAVIGATEURS : active la synchronisation dans Parametres > Synchronisation pour recuperer tes mots de passe."
$rapport += ""
$rapport += "PROCHAINE ETAPE :"
$rapport += "  Cle USB : copie ce dossier, lance importer.bat sur le nouveau PC."
$rapport += "  WiFi    : lance transfert-wifi-serveur.bat sur cet ordinateur."
$rapport | Out-File (Join-Path $export "RAPPORT.txt") -Encoding UTF8

Log "=== EXPORTATION TERMINEE ==="
Write-Host ""
Write-Host "  +========================================+" -ForegroundColor Green
Write-Host "  EXPORTATION TERMINEE" -ForegroundColor Green
Write-Host "  $export" -ForegroundColor Green
Write-Host "  +========================================+" -ForegroundColor Green
Write-Host ""

return $export
