param([string]$Destination)

$ErrorActionPreference = "SilentlyContinue"

function Write-Step($msg) { Write-Host "  >> $msg" -ForegroundColor Cyan }
function Write-OK($msg)   { Write-Host "  OK $msg" -ForegroundColor Green }
function Write-Skip($msg) { Write-Host "  -- $msg" -ForegroundColor Yellow }

$date = Get-Date -Format "yyyy-MM-dd_HH-mm"
$export = Join-Path $Destination "migratix_$date"
$rapport = @()

Write-Host ""
Write-Host "  Dossier de sauvegarde : $export" -ForegroundColor White
New-Item -ItemType Directory -Force -Path $export | Out-Null

# ── 1. Fichiers utilisateur ──────────────────────────────────────────────────
Write-Step "Copie des fichiers personnels..."

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
        Write-Step "  $($d.dst)..."
        robocopy $d.src $cible /E /COPY:DAT /R:1 /W:0 /NP /NFL /NDL /NJH /NJS | Out-Null
        Write-OK "$($d.dst) copie"
    } else {
        Write-Skip "$($d.src) introuvable, ignore"
    }
}

# ── 2. Navigateurs ───────────────────────────────────────────────────────────
Write-Step "Migration des navigateurs..."

$browsers = @(
    @{ nom = "Chrome";  profil = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default" },
    @{ nom = "Edge";    profil = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default" },
    @{ nom = "Brave";   profil = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default" }
)

foreach ($b in $browsers) {
    if (Test-Path $b.profil) {
        $dst = Join-Path $export "navigateurs\$($b.nom)"
        New-Item -ItemType Directory -Force -Path $dst | Out-Null

        # Marque-pages
        $bookmarks = Join-Path $b.profil "Bookmarks"
        if (Test-Path $bookmarks) {
            Copy-Item $bookmarks (Join-Path $dst "Bookmarks") -Force
            Write-OK "$($b.nom) — marque-pages copies"
        }

        # Liste des extensions
        $extPath = Join-Path $b.profil "Extensions"
        if (Test-Path $extPath) {
            $exts = Get-ChildItem $extPath -Directory | ForEach-Object {
                $manifest = Join-Path $_.FullName (Get-ChildItem $_.FullName -Directory | Select-Object -First 1).Name
                $manifest = Join-Path $manifest "manifest.json"
                $nom = $_.Name
                if (Test-Path $manifest) {
                    $json = Get-Content $manifest | ConvertFrom-Json -ErrorAction SilentlyContinue
                    if ($json.name) { $nom = $json.name }
                }
                [PSCustomObject]@{ ID = $_.Name; Nom = $nom }
            }
            $exts | Export-Csv (Join-Path $dst "extensions.csv") -NoTypeInformation -Encoding UTF8
            Write-OK "$($b.nom) — $($exts.Count) extensions listees"
        }

        # Mots de passe — impossible a copier (chiffres avec le compte Windows)
        $rapport += "NAVIGATEUR $($b.nom) : active la sync dans Parametres > Synchronisation pour recuperer tes mots de passe."
    }
}

# Firefox (profil complet)
$ffPath = "$env:APPDATA\Mozilla\Firefox\Profiles"
if (Test-Path $ffPath) {
    $dst = Join-Path $export "navigateurs\Firefox"
    robocopy $ffPath $dst /E /COPY:DAT /R:1 /W:0 /NP /NFL /NDL /NJH /NJS | Out-Null
    Write-OK "Firefox — profil complet copie"
}

# ── 3. Logiciels installés ───────────────────────────────────────────────────
Write-Step "Export de la liste des logiciels..."

try {
    New-Item -ItemType Directory -Force -Path (Join-Path $export "logiciels") | Out-Null
    winget export -o (Join-Path $export "logiciels\winget.json") --accept-source-agreements 2>$null
    Write-OK "Liste winget exportee"
} catch {
    Write-Skip "winget non disponible"
}

$logiciels = @()
$regPaths = @(
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
)
foreach ($path in $regPaths) {
    Get-ItemProperty $path | Where-Object { $_.DisplayName } | ForEach-Object {
        $logiciels += [PSCustomObject]@{
            Nom     = $_.DisplayName
            Version = $_.DisplayVersion
            Editeur = $_.Publisher
        }
    }
}
$logiciels | Sort-Object Nom -Unique | Export-Csv (Join-Path $export "logiciels\liste_complete.csv") -NoTypeInformation -Encoding UTF8
Write-OK "$($logiciels.Count) logiciels enregistres"

# ── 4. Variables d'environnement ─────────────────────────────────────────────
Write-Step "Export des variables d'environnement..."
$envVars = [System.Environment]::GetEnvironmentVariables("User")
$envVars | ConvertTo-Json | Out-File (Join-Path $export "env_variables.json") -Encoding UTF8
Write-OK "Variables exportees"

# ── 5. Licences ───────────────────────────────────────────────────────────────
Write-Step "Verification des licences..."
$appsLicences = @(
    @{ nom = "Microsoft Office"; cle = "HKLM:\SOFTWARE\Microsoft\Office" },
    @{ nom = "Adobe Creative Cloud"; cle = "HKLM:\SOFTWARE\Adobe" },
    @{ nom = "Autodesk"; cle = "HKLM:\SOFTWARE\Autodesk" }
)
foreach ($app in $appsLicences) {
    if (Test-Path $app.cle) {
        Write-Skip "$($app.nom) detecte — licence a gerer manuellement"
        $rapport += "LICENCE : $($app.nom) — connecte-toi avec ton compte sur le nouveau PC."
    }
}

# ── 6. Rapport ────────────────────────────────────────────────────────────────
$rapport += ""
$rapport += "=== MIGRATIX — RAPPORT ==="
$rapport += "Date : $date | Source : $env:COMPUTERNAME"
$rapport += ""
$rapport += "PROCHAINE ETAPE :"
$rapport += "  Option 1 (cle USB) : copie ce dossier sur ta cle, branche sur le nouveau PC, lance importer.bat"
$rapport += "  Option 2 (WiFi)    : lance transfert-wifi-serveur.bat sur cet ordi"
$rapport | Out-File (Join-Path $export "RAPPORT.txt") -Encoding UTF8

Write-Host ""
Write-Host "  ════════════════════════════════════════" -ForegroundColor Green
Write-Host "  EXPORTATION TERMINEE" -ForegroundColor Green
Write-Host "  $export" -ForegroundColor Green
Write-Host "  ════════════════════════════════════════" -ForegroundColor Green
Write-Host ""

return $export
