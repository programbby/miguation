param([string]$Destination)

$ErrorActionPreference = "SilentlyContinue"

function Write-Step($msg) { Write-Host "  >> $msg" -ForegroundColor Cyan }
function Write-OK($msg)   { Write-Host "  OK $msg" -ForegroundColor Green }
function Write-Skip($msg) { Write-Host "  -- $msg" -ForegroundColor Yellow }
function Write-Fail($msg) { Write-Host "  !! $msg" -ForegroundColor Red }

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
        Write-Step "  $($d.src)..."
        robocopy $d.src $cible /E /COPY:DAT /R:1 /W:0 /NP /NFL /NDL /NJH /NJS | Out-Null
        Write-OK "$($d.dst) copie"
    } else {
        Write-Skip "$($d.src) introuvable, ignore"
    }
}

# ── 2. Logiciels installés ───────────────────────────────────────────────────
Write-Step "Export de la liste des logiciels..."

$wingetOk = $false
try {
    winget export -o (Join-Path $export "logiciels\winget.json") --accept-source-agreements 2>$null
    $wingetOk = $true
    Write-OK "Liste winget exportee"
} catch {
    Write-Skip "winget non disponible"
}

# Liste complète via registre (backup si winget echoue)
$logiciels = @()
$regPaths = @(
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
)
foreach ($path in $regPaths) {
    Get-ItemProperty $path | Where-Object { $_.DisplayName } | ForEach-Object {
        $logiciels += [PSCustomObject]@{
            Nom      = $_.DisplayName
            Version  = $_.DisplayVersion
            Editeur  = $_.Publisher
            Licence  = if ($_.URLInfoAbout) { $_.URLInfoAbout } else { "Voir site editeur" }
        }
    }
}
New-Item -ItemType Directory -Force -Path (Join-Path $export "logiciels") | Out-Null
$logiciels | Sort-Object Nom -Unique | Export-Csv (Join-Path $export "logiciels\liste_complete.csv") -NoTypeInformation -Encoding UTF8
Write-OK "$($logiciels.Count) logiciels enregistres dans liste_complete.csv"

# ── 3. Variables d'environnement ─────────────────────────────────────────────
Write-Step "Export des variables d'environnement..."
$envVars = [System.Environment]::GetEnvironmentVariables("User")
$envVars | ConvertTo-Json | Out-File (Join-Path $export "env_variables.json") -Encoding UTF8
Write-OK "Variables exportees"

# ── 4. Licences — détection et instructions ───────────────────────────────────
Write-Step "Verification des licences..."
$licences = @()

$appsLicences = @(
    @{ nom = "Microsoft Office"; cle = "HKLM:\SOFTWARE\Microsoft\Office" },
    @{ nom = "Adobe Creative Cloud"; cle = "HKLM:\SOFTWARE\Adobe" },
    @{ nom = "Autodesk"; cle = "HKLM:\SOFTWARE\Autodesk" }
)

foreach ($app in $appsLicences) {
    if (Test-Path $app.cle) {
        $licences += $app.nom
        Write-Skip "$($app.nom) detecte — licence a gerer manuellement"
        $rapport += "LICENCE MANUELLE : $($app.nom) — connecte-toi avec ton compte sur le nouveau PC"
    }
}

# ── 5. Rapport final ──────────────────────────────────────────────────────────
$rapport += ""
$rapport += "=== MIGRATIX — RAPPORT D'EXPORTATION ==="
$rapport += "Date : $date"
$rapport += "Source : $env:COMPUTERNAME"
$rapport += ""
$rapport += "FICHIERS COPIES :"
foreach ($d in $dossiers) {
    if (Test-Path $d.src) { $rapport += "  OK  $($d.dst)" }
}
$rapport += ""
if ($licences.Count -gt 0) {
    $rapport += "LICENCES A GERER MANUELLEMENT (non copiables) :"
    foreach ($l in $licences) { $rapport += "  --  $l" }
    $rapport += ""
    $rapport += "Pour chaque licence : connecte-toi avec ton compte sur le nouveau PC."
} else {
    $rapport += "Aucune licence protegee detectee."
}
$rapport += ""
$rapport += "PROCHAINE ETAPE :"
$rapport += "  Branche ta cle USB / disque sur le nouveau PC"
$rapport += "  Double-clique sur importer.bat"

$rapport | Out-File (Join-Path $export "RAPPORT.txt") -Encoding UTF8

Write-Host ""
Write-Host "  ════════════════════════════════════════" -ForegroundColor Green
Write-Host "  EXPORTATION TERMINEE" -ForegroundColor Green
Write-Host "  Sauvegarde dans : $export" -ForegroundColor Green
Write-Host "  Lis RAPPORT.txt avant de passer au nouveau PC" -ForegroundColor Green
Write-Host "  ════════════════════════════════════════" -ForegroundColor Green
Write-Host ""
